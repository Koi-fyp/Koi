"""ONE audio-only multipart turn against POST /api/v1/chat (stdlib only). Ahmad runs it; it calls a deployed service.

Usage (koivenv, cmd):  python -B agent_tasks\\acceptance\\audio_smoke.py <CHAT_URL> <WAV_PATH> [--language ur|en]

Request (rules quoted in _media_common.py from chat_core.py:141-177): multipart/form-data with
  payload = {"session_history": [], "exercise_state": null, "client_event": "none" [, "language"]}  (no "message")
  audio   = the WAV file (audio/wav), at most 25 MiB; the crisis service scores only its first 30 s.
Token: env KOI_TOKEN only; never printed. Redirects followed by hand (303 -> GET), silently.
Prints ONLY: HTTP status, time to first SSE event, event names in order, transcript text length + language,
risk status + category, done.full_text length, reply_backend, reply_fallback_reason; on 4xx the error class only.
Does not send a file over 25 MiB (prints that and exits). Exit 0 always.

[CODE] An audio turn waits at most 3 s for the crisis result (chat_core.py:348-352) and takes its message from the
ASR transcript in that result (chat_core.py:361-364). A slower result, or no speech, gives HTTP 422 with error class
"no_transcript" (see g0b_repro.py case a5).
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _media_common as M  # noqa: E402


def main(argv):
    if len(argv) < 2 or argv[0].startswith("-"):
        print(__doc__)
        return 0
    url, path = argv[0], argv[1]
    language = argv[argv.index("--language") + 1] if "--language" in argv and argv.index("--language") + 1 < len(argv) else None
    token = os.environ.get("KOI_TOKEN", "").strip()
    if not token:
        print("KOI_TOKEN is not set; nothing sent")
        return 0
    data, size, too_big = M.read_file(path, M.AUDIO_MAX)
    if too_big:
        print("not sent: audio is %d bytes > 25 MiB limit (chat_core.py:156)" % size)
        return 0
    payload = {"session_history": [], "exercise_state": None, "client_event": "none"}
    if language:
        payload["language"] = language
    r = M.run_turn(url, payload, [("audio", os.path.basename(path), "audio/wav", data)], token)
    token = data = None
    print("HTTP status: %s" % r.get("http_status"))
    if r.get("transport_error"):
        print("transport error: %s" % r["transport_error"])
        return 0
    if r.get("http_status") != 200:
        print("error class: %s" % r.get("error_class"))
        return 0
    print("time to first SSE event: %s s" % r["first_event_s"])
    print("events: %s" % " ".join(r["events"]))
    print("transcript: length=%s language=%s" % (r["transcript_len"], r["transcript_language"]))
    print("risk: status=%s category=%s" % (r["risk_status"], r["risk_category"]))
    print("done.full_text length: %s" % r["full_text_len"])
    print("reply_backend: %s" % r["reply_backend"])
    print("reply_fallback_reason: %s" % r["reply_fallback_reason"])
    if r.get("stream_error"):
        print("stream error: %s" % r["stream_error"])
    return 0


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    finally:
        sys.exit(0)
