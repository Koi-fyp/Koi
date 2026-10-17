import os, json, urllib.request, urllib.error
KEY = os.environ.get("KOI_OAI_API_KEY", "")
BASE = os.environ.get("KOI_OAI_BASE_URL", "https://api.groq.com/openai/v1")
MODEL = os.environ.get("PROBE_MODEL", "openai/gpt-oss-120b")
body = {"model": MODEL, "messages": [{"role": "user", "content": "Say hi in one word."}], "max_tokens": 64}
for ua in [None, "koi-companion/1.0", "curl/8.4.0"]:
    h = {"Authorization": "Bearer " + KEY, "Content-Type": "application/json"}
    if ua:
        h["User-Agent"] = ua
    req = urllib.request.Request(BASE + "/chat/completions", data=json.dumps(body).encode(), method="POST", headers=h)
    try:
        r = urllib.request.urlopen(req, timeout=60)
        print("UA=%s -> 200" % ua)
    except urllib.error.HTTPError as e:
        print("UA=%s -> %d body=%r" % (ua, e.code, e.read().decode("utf-8", "replace")[:80]))
    except Exception as e:
        print("UA=%s -> exception %s" % (ua, type(e).__name__))