"""Shared helpers for audio_smoke.py / video_smoke.py (stdlib only). Prints nothing by itself.

Multipart rules are copied from deploy/modal/chat_core.py (c172d35), not imported, so the smokes run anywhere:
  - content-type must START WITH "multipart/form-data" (chat_core.py:141-142), else the body is parsed as JSON
  - form field "payload" = JSON string of the v1 fields + optional "language", "turn_id"; "message" optional with
    audio (chat_core.py:147-155, :101-110)
  - file fields "audio" and "video"; limits audio 25 MiB, video 80 MiB, larger -> 413 (chat_core.py:156-165)
  - allowed: text | audio | text+video | audio+video; anything else -> 422 (chat_core.py:167-177)
  - the crisis service decodes only the first 30 s of audio and the first 60 s / 8 frames of video
    (crisis_app.py:241-244, :251-261); MP4 must be seekable (crisis_app.py:37)
"""
import http.client
import json
import os
import time
import urllib.parse
import uuid
import wave

AUDIO_MAX = 25 * 1024 * 1024
VIDEO_MAX = 80 * 1024 * 1024
AUDIO_DECODED_S = 30
VIDEO_DECODED_S = 60
HOP_TIMEOUT_S = 200
MAX_HOPS = 20


def wav_seconds(path):
    """Duration of a PCM WAV, or None if the file is not a readable WAV."""
    try:
        with wave.open(path, "rb") as w:
            return w.getnframes() / float(w.getframerate())
    except Exception:  # noqa: BLE001
        return None


def multipart(payload, files):
    """payload: dict -> 'payload' field; files: [(field, filename, content_type, bytes)]. Returns (body, ctype)."""
    boundary = "koi-" + uuid.uuid4().hex
    parts = [("--%s\r\nContent-Disposition: form-data; name=\"payload\"\r\n"
              "Content-Type: application/json\r\n\r\n" % boundary).encode() + json.dumps(payload).encode() + b"\r\n"]
    for field, filename, ctype, data in files:
        parts.append(("--%s\r\nContent-Disposition: form-data; name=\"%s\"; filename=\"%s\"\r\n"
                      "Content-Type: %s\r\n\r\n" % (boundary, field, filename, ctype)).encode() + data + b"\r\n")
    parts.append(("--%s--\r\n" % boundary).encode())
    return b"".join(parts), "multipart/form-data; boundary=" + boundary


def _conn(url):
    p = urllib.parse.urlsplit(url)
    cls = http.client.HTTPSConnection if p.scheme == "https" else http.client.HTTPConnection
    return cls(p.netloc, timeout=HOP_TIMEOUT_S), (p.path or "/") + ("?" + p.query if p.query else ""), p.hostname


def post_following(url, body, headers):
    """POST, then follow redirects by hand (303 -> GET, as Modal's poll redirect requires). Silent.
    The Authorization header is sent only to the original host. Returns (response, conn, t0)."""
    t0 = time.monotonic()
    origin = urllib.parse.urlsplit(url).hostname
    method = "POST"
    for _ in range(MAX_HOPS):
        conn, path, host = _conn(url)
        h = dict(headers)
        if host != origin:
            h.pop("Authorization", None)
        if method == "GET":
            h.pop("Content-Type", None)
        conn.request(method, path, body=body if method == "POST" else None, headers=h)
        resp = conn.getresponse()
        loc = resp.getheader("Location")
        if resp.status in (301, 302, 303, 307, 308) and loc:
            resp.read()
            conn.close()
            url = urllib.parse.urljoin(url, loc)
            if resp.status in (301, 302, 303):
                method = "GET"
            continue
        return resp, conn, t0
    raise RuntimeError("too many redirects")


def sse(resp):
    event, data = None, []
    while True:
        raw = resp.readline()
        if not raw:
            return
        line = raw.decode("utf-8", "replace").rstrip("\r\n")
        if not line:
            if event is not None:
                try:
                    yield event, json.loads("\n".join(data)) if data else None
                except ValueError:
                    yield event, None
            event, data = None, []
        elif line.startswith("event:"):
            event = line[6:].strip()
        elif line.startswith("data:"):
            data.append(line[5:].lstrip())


# Fixed labels for pre-stream errors; the server's detail text is never printed (chat_core.py:146-177, :200-206, :364)
_CLASSES = (("too large", "too_large"), ("allowed modalities", "modality_combination"),
            ("transcript", "no_transcript"), ("payload", "bad_payload"), ("invalid json", "bad_payload"),
            ("token", "auth"), ("authorization", "auth"), ("role", "bad_role"), ("director secret", "misconfigured"))


def error_class(status, body):
    try:
        detail = json.loads(body.decode("utf-8", "replace")).get("detail")
    except Exception:  # noqa: BLE001
        detail = None
    text = json.dumps(detail).lower() if detail is not None else ""
    if isinstance(detail, list):
        return "validation"
    for needle, label in _CLASSES:
        if needle in text:
            return label
    return "http_%d" % status


def run_turn(chat_url, payload, files, token):
    """One multipart chat turn. Returns a summary dict with ONLY the fields the smokes may print."""
    body, ctype = multipart(payload, files)
    out = {"http_status": None}
    try:
        resp, conn, t0 = post_following(chat_url.rstrip("/") + "/api/v1/chat", body,
                                        {"Authorization": "Bearer " + token, "Content-Type": ctype,
                                         "Accept": "text/event-stream"})
    except Exception as exc:  # noqa: BLE001
        out["transport_error"] = type(exc).__name__
        return out
    out["http_status"] = resp.status
    if resp.status != 200:
        out["error_class"] = error_class(resp.status, resp.read(4096))
        conn.close()
        return out
    names, first_s, deltas = [], None, []
    transcript = risk = done = None
    try:
        for name, data in sse(resp):
            if first_s is None:
                first_s = time.monotonic() - t0
            names.append(name)
            if name == "transcript" and isinstance(data, dict):
                transcript = data
            elif name == "risk" and isinstance(data, dict):
                risk = data
            elif name == "delta" and isinstance(data, dict):
                deltas.append(data.get("text", ""))
            elif name == "done" and isinstance(data, dict):
                done = data
    except Exception as exc:  # noqa: BLE001
        out["stream_error"] = type(exc).__name__
    conn.close()
    out.update({
        "first_event_s": round(first_s, 2) if first_s is not None else None,
        "events": names,
        "transcript_len": len(transcript.get("text") or "") if transcript else None,
        "transcript_language": transcript.get("language") if transcript else None,
        "risk_status": (risk or {}).get("status"), "risk_category": (risk or {}).get("risk_category"),
        "modalities_used": (risk or {}).get("modalities_used"),
        "confidence_reasons": (risk or {}).get("confidence_reasons"),
        "full_text_len": len(done.get("full_text") or "") if done else None,
        "reply_backend": (done or {}).get("reply_backend"),
        "reply_fallback_reason": (done or {}).get("reply_fallback_reason"),
    })
    return out


def read_file(path, limit):
    size = os.path.getsize(path)
    with open(path, "rb") as f:
        return f.read(), size, size > limit
