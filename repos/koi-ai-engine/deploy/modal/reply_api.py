"""Optional hosted-LLM reply backend for the ordinary chat path (flag KOI_REPLY_BACKEND=api; default OFF).

Config comes ONLY from the environment; there are no defaults for provider, model, base URL or key:
    KOI_LLM_PROVIDER   "gemini" | "openai_compat"
    KOI_LLM_MODEL      provider model id
    KOI_LLM_API_KEY    sent only in a header (gemini: x-goog-api-key; openai_compat: Authorization: Bearer)
    KOI_LLM_BASE_URL   openai_compat only, e.g. https://host/v1 (POST {base}/chat/completions)
    KOI_LLM_TIMEOUT_S  default 20
    KOI_LLM_REASONING_EFFORT  openai_compat only; sent as `reasoning_effort` when set (use the model's lowest
                       value); unset/empty = parameter not sent
Missing or invalid config -> config() returns None (API disabled).

Sent: system prompt + the last HISTORY_TURNS history turns + the new message. Nothing else (no uid, token, risk,
exercise_state, audio or video). Every failure raises ReplyAPIError(reason) with an enum reason; logs carry only
that reason, never the prompt, reply, key or response body.

Request shapes are written from documentation knowledge and are UNVERIFIED live: validate with
agent_tasks/bench_replies.py --smoke before enabling the flag.
"""
import json
import logging
import os
import re
import socket
import urllib.error
import urllib.request

log = logging.getLogger("koi.reply_api")

HISTORY_TURNS = 16
OAI_MAX_TOKENS = 2048   # room for hidden reasoning tokens so they cannot exhaust the reply budget
USER_AGENT = "koi-companion/1.0"   # openai_compat only: some gateways (Groq) answer 403 / 1010 to Python's default UA
PROVIDERS = ("gemini", "openai_compat")
GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent"
GEMINI_BLOCKED = {"SAFETY", "RECITATION", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "IMAGE_SAFETY", "OTHER"}
JSON_ONLY = (" Respond ONLY with one JSON object, keys in this order: \"companion_state\" "
             "(object with \"emotion\" and \"intensity\") then \"reply\" (string). No markdown, no other text.")
REASONS = ("not_configured", "timeout", "http_4xx", "http_5xx", "network", "invalid_json", "empty", "blocked",
           "bad_emotion", "bad_shape", "internal_error")
_FENCE = re.compile(r"^\s*```(?:json)?\s*(.*?)\s*```\s*$", re.S | re.I)


class ReplyAPIError(Exception):
    def __init__(self, reason):
        super().__init__(reason)
        self.reason = reason if reason in REASONS else "internal_error"


def config(env=None):
    """dict or None. Never logs or returns anything derived from the key except the key itself for the request."""
    env = os.environ if env is None else env
    provider = (env.get("KOI_LLM_PROVIDER") or "").strip()
    model = (env.get("KOI_LLM_MODEL") or "").strip()
    key = (env.get("KOI_LLM_API_KEY") or "").strip()
    base = (env.get("KOI_LLM_BASE_URL") or "").strip().rstrip("/")
    try:
        timeout = float(env.get("KOI_LLM_TIMEOUT_S") or 20)
    except ValueError:
        return None
    if provider not in PROVIDERS or not model or not key or timeout <= 0:
        return None
    if provider == "openai_compat" and not base.startswith(("https://", "http://")):
        return None
    effort = (env.get("KOI_LLM_REASONING_EFFORT") or "").strip() or None
    return {"provider": provider, "model": model, "key": key, "base_url": base, "timeout": timeout,
            "reasoning_effort": effort}


def _http_fetch(url, headers, body, timeout):
    """POST JSON; returns (status, body_bytes). Raises ReplyAPIError on transport failures."""
    req = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, b""
    except (socket.timeout, TimeoutError):
        raise ReplyAPIError("timeout") from None
    except urllib.error.URLError as e:
        raise ReplyAPIError("timeout" if isinstance(e.reason, (socket.timeout, TimeoutError)) else "network") from None


def _gemini_schema(schema):
    """CHAT_JSON_SCHEMA -> Gemini responseSchema (OpenAPI subset: upper-case types, propertyOrdering)."""
    out = {"type": schema["type"].upper()}
    for k in ("enum", "minimum", "maximum", "required"):
        if k in schema:
            out[k] = schema[k]
    if "properties" in schema:
        out["properties"] = {k: _gemini_schema(v) for k, v in schema["properties"].items()}
        out["propertyOrdering"] = list(schema["properties"])
    return out


def gemini_request(cfg, system, history, message, schema):
    """(url, headers, body). Key only in the x-goog-api-key header. No thinking/reasoning option is set."""
    contents = [{"role": "model" if t["role"] == "assistant" else "user", "parts": [{"text": t["content"]}]}
                for t in history]
    contents.append({"role": "user", "parts": [{"text": message}]})
    body = {"systemInstruction": {"parts": [{"text": system}]}, "contents": contents,
            "generationConfig": {"responseMimeType": "application/json", "responseSchema": _gemini_schema(schema)}}
    headers = {"Content-Type": "application/json", "x-goog-api-key": cfg["key"]}
    return GEMINI_URL % cfg["model"], headers, json.dumps(body).encode("utf-8")


def gemini_text(data):
    if (data.get("promptFeedback") or {}).get("blockReason"):
        raise ReplyAPIError("blocked")
    candidates = data.get("candidates") or []
    if not candidates:
        raise ReplyAPIError("empty")
    first = candidates[0]
    if first.get("finishReason") in GEMINI_BLOCKED:
        raise ReplyAPIError("blocked")
    parts = (first.get("content") or {}).get("parts") or []
    return "".join(p.get("text", "") for p in parts if isinstance(p, dict) and not p.get("thought"))


def openai_compat_request(cfg, system, history, message, schema):
    """(url, headers, body). JSON mode (`json_object`, widely supported) + JSON-only instruction in the system prompt."""
    messages = [{"role": "system", "content": system + JSON_ONLY}]
    messages += [{"role": t["role"], "content": t["content"]} for t in history]
    messages.append({"role": "user", "content": message})
    body = {"model": cfg["model"], "messages": messages, "response_format": {"type": "json_object"},
            "max_tokens": OAI_MAX_TOKENS}
    if cfg.get("reasoning_effort"):
        body["reasoning_effort"] = cfg["reasoning_effort"]
    headers = {"Content-Type": "application/json", "Authorization": "Bearer " + cfg["key"], "User-Agent": USER_AGENT}
    return cfg["base_url"] + "/chat/completions", headers, json.dumps(body).encode("utf-8")


def openai_compat_text(data):
    choices = data.get("choices") or []
    if not choices:
        raise ReplyAPIError("empty")
    first = choices[0]
    msg = first.get("message") or {}
    if first.get("finish_reason") == "content_filter" or msg.get("refusal"):
        raise ReplyAPIError("blocked")
    # Only `content` is used; reasoning fields (reasoning_content / reasoning) are ignored and never logged.
    return msg.get("content") or ""


BUILDERS = {"gemini": (gemini_request, gemini_text), "openai_compat": (openai_compat_request, openai_compat_text)}


def parse_reply(text, schema, clamp):
    """Strip fences, parse, validate. Returns (companion_state, reply)."""
    text = (text or "").strip()
    if not text:
        raise ReplyAPIError("empty")
    m = _FENCE.match(text)
    if m:
        text = m.group(1)
    try:
        value = json.loads(text)
    except ValueError:
        raise ReplyAPIError("invalid_json") from None
    if not isinstance(value, dict) or not isinstance(value.get("companion_state"), dict):
        raise ReplyAPIError("bad_shape")
    allowed = schema["properties"]["companion_state"]["properties"]["emotion"]["enum"]
    if value["companion_state"].get("emotion") not in allowed:
        raise ReplyAPIError("bad_emotion")
    reply = value.get("reply")
    if not isinstance(reply, str) or not reply.strip():
        raise ReplyAPIError("empty")
    return clamp(value["companion_state"]), reply.strip()


def generate(cfg, system, history, message, schema, clamp, fetch=None):
    """One non-streaming call. history: [{"role": "user"|"assistant", "content"}]. Raises ReplyAPIError."""
    if not cfg:
        raise ReplyAPIError("not_configured")
    try:
        build, extract = BUILDERS[cfg["provider"]]
        turns = [{"role": t["role"], "content": t["content"]} for t in history if t.get("role") in ("user", "assistant")]
        url, headers, body = build(cfg, system, turns[-HISTORY_TURNS:], message, schema)
        status, raw = (fetch or _http_fetch)(url, headers, body, cfg["timeout"])
        if status >= 500:
            raise ReplyAPIError("http_5xx")
        if status >= 400:
            raise ReplyAPIError("http_4xx")
        try:
            data = json.loads(raw.decode("utf-8") if isinstance(raw, bytes) else raw)
        except ValueError:
            raise ReplyAPIError("invalid_json") from None
        if not isinstance(data, dict):
            raise ReplyAPIError("bad_shape")
        return parse_reply(extract(data), schema, clamp)
    except ReplyAPIError as exc:
        log.warning("reply_api failed: %s", exc.reason)
        raise
    except Exception as exc:  # anything unexpected: class name only
        log.warning("reply_api failed: internal_error (%s)", type(exc).__name__)
        raise ReplyAPIError("internal_error") from None
