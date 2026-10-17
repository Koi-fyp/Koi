"""ONE video multipart turn against POST /api/v1/chat (stdlib only). Ahmad runs it; it calls a deployed service.

Usage (koivenv, cmd):
  python -B agent_tasks\\acceptance\\video_smoke.py <CHAT_URL> <MP4_PATH>                     text+video
  python -B agent_tasks\\acceptance\\video_smoke.py <CHAT_URL> <MP4_PATH> --with-audio <WAV>  audio+video
  options: [--message TEXT] (text+video only; default a synthetic line) [--language ur|en]

Request (rules quoted in _media_common.py from chat_core.py:141-177): multipart/form-data with
  payload = {"message"?, "session_history": [], "exercise_state": null, "client_event": "none" [, "language"]}
  video   = the MP4 (video/mp4, seekable), at most 80 MiB; the crisis service uses only its first 60 s, 8 frames
  audio   = (audio+video only) the WAV, at most 25 MiB, first 30 s. text+audio+video is NOT allowed (422).
[CODE] With typed text, the video's own sound track is ignored (crisis_app.py:310-311).
Token: env KOI_TOKEN only; never printed. Redirects followed by hand (303 -> GET), silently.
Prints ONLY: HTTP status, time to first SSE event, event names, transcript length + language, risk status +
category, risk.modalities_used, risk.confidence_reasons, done.full_text length, reply_backend,
reply_fallback_reason; on 4xx the error class only. Oversize files are not sent. Exit 0 always.
"""
import os
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import _media_common as M  # noqa: E402

DEFAULT_MESSAGE = "I had a long day at work today."


def _opt(argv, name):
    return argv[argv.index(name) + 1] if name in argv and argv.index(name) + 1 < len(argv) else None


def main(argv):
    if len(argv) < 2 or argv[0].startswith("-"):
        print(__doc__)
        return 0
    url, mp4 = argv[0], argv[1]
    wav, language = _opt(argv, "--with-audio"), _opt(argv, "--language")
    token = os.environ.get("KOI_TOKEN", "").strip()
    if not token:
        print("KOI_TOKEN is not set; nothing sent")
        return 0
    video, vsize, vbig = M.read_file(mp4, M.VIDEO_MAX)
    if vbig:
        print("not sent: video is %d bytes > 80 MiB limit (chat_core.py:156)" % vsize)
        return 0
    files = [("video", os.path.basename(mp4), "video/mp4", video)]
    payload = {"session_history": [], "exercise_state": None, "client_event": "none"}
    if wav:
        audio, asize, abig = M.read_file(wav, M.AUDIO_MAX)
        if abig:
            print("not sent: audio is %d bytes > 25 MiB limit (chat_core.py:156)" % asize)
            return 0
        files.insert(0, ("audio", os.path.basename(wav), "audio/wav", audio))   # audio+video: no message
    else:
        payload["message"] = _opt(argv, "--message") or DEFAULT_MESSAGE         # text+video
    if language:
        payload["language"] = language
    print("mode: %s" % ("audio+video" if wav else "text+video"))
    r = M.run_turn(url, payload, files, token)
    token = files = None
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
    print("risk.modalities_used: %s" % r["modalities_used"])
    print("risk.confidence_reasons: %s" % r["confidence_reasons"])
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
