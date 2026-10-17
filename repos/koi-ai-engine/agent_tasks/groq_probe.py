import os, json, urllib.request, urllib.error
KEY = os.environ.get("KOI_OAI_API_KEY", "")
BASE = os.environ.get("KOI_OAI_BASE_URL", "https://api.groq.com/openai/v1")
MODEL = os.environ.get("PROBE_MODEL", "openai/gpt-oss-120b")
msgs = [{"role": "system", "content": "Reply with JSON only."},
        {"role": "user", "content": "Return JSON like {\"reply\": \"hello\"}"}]
variants = [
    ("A minimal", {}),
    ("B max_tokens 2048", {"max_tokens": 2048}),
    ("C response_format json_object", {"response_format": {"type": "json_object"}}),
    ("D reasoning_effort low", {"reasoning_effort": "low"}),
    ("E reasoning_effort medium", {"reasoning_effort": "medium"}),
    ("F max_completion_tokens 2048", {"max_completion_tokens": 2048}),
    ("G all four: mt+rf+low", {"max_tokens": 2048, "response_format": {"type": "json_object"}, "reasoning_effort": "low"}),
]
for name, extra in variants:
    body = {"model": MODEL, "messages": msgs}
    body.update(extra)
    req = urllib.request.Request(BASE + "/chat/completions", data=json.dumps(body).encode(), method="POST",
                                 headers={"Authorization": "Bearer " + KEY, "Content-Type": "application/json"})
    try:
        r = urllib.request.urlopen(req, timeout=60)
        d = json.loads(r.read().decode("utf-8"))
        c = (d.get("choices") or [{}])[0].get("message", {}).get("content")
        print(name, "-> 200 content_len=%s" % (len(c) if isinstance(c, str) else None))
    except urllib.error.HTTPError as e:
        raw = e.read().decode("utf-8", "replace")
        try:
            err = json.loads(raw).get("error", {})
            print(name, "-> %d %s | %s" % (e.code, err.get("type"), str(err.get("message"))[:160]))
        except ValueError:
            print(name, "-> %d non-JSON body (len %d)" % (e.code, len(raw)))
    except Exception as e:
        print(name, "-> exception", type(e).__name__)