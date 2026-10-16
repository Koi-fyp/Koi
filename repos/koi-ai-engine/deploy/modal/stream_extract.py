"""Small, dependency-free extractor for the structured chat response."""
import difflib
import json
import re
from typing import Any

_KEY_OBJECT = re.compile(r'"([A-Za-z_]{4,40})"\s*:\s*\{')
_REPLY_STRING = re.compile(r'"([A-Za-z_]{3,20})"\s*:\s*"')
_JSONISH = re.compile(r'(^\s*(\{|\[|```))|(\{\s*"[A-Za-z_]+"\s*:)')


def key_matches(key: Any, target: str, threshold: float = 0.8) -> bool:
    """True for the key itself or a near-miss spelling (e.g. "cocompaniion_state")."""
    if not isinstance(key, str):
        return False
    norm = key.strip().lower()
    return norm == target or difflib.SequenceMatcher(None, norm, target).ratio() >= threshold


def near_get(value: Any, target: str) -> Any:
    if not isinstance(value, dict):
        return None
    if target in value:
        return value[target]
    for key, item in value.items():
        if key_matches(key, target):
            return item
    return None


def looks_like_json(text: str) -> bool:
    return bool(_JSONISH.search(text or ""))


def _strip_fence(source: str) -> str:
    source = source.lstrip()
    if source.startswith("```"):
        newline = source.find("\n")
        if newline < 0:
            return ""
        source = source[newline + 1:].lstrip()
        if source.rstrip().endswith("```"):
            source = source.rstrip()[:-3].rstrip()
    return source


def _clean_reply(value: Any, depth: int = 0) -> tuple[str | None, Any]:
    """Return (reply text or None, nested companion_state or None); never JSON-looking text."""
    if not isinstance(value, str):
        return None, None
    text = value.strip()
    if not looks_like_json(text):
        return (text or None), None
    if depth >= 2:
        return None, None
    try:
        nested, _ = json.JSONDecoder().raw_decode(_strip_fence(text))
    except json.JSONDecodeError:
        return None, None
    if isinstance(nested, str):
        return _clean_reply(nested, depth + 1)
    state = near_get(nested, "companion_state")
    reply, inner_state = _clean_reply(near_get(nested, "reply"), depth + 1)
    return reply, state if isinstance(state, dict) else inner_state


class StreamExtractor:
    def __init__(self) -> None:
        self._buffer = ""
        self._done = False
        self._state_emitted = False

    def update(self, full_text: str) -> list[tuple[str, Any]]:
        """Parse the cumulative model text; safe when it is not prefix-stable."""
        if self._done:
            return []
        self._buffer = full_text
        return self._parse()

    def feed(self, chunk: str) -> list[tuple[str, Any]]:
        if self._done:
            return []
        self._buffer += chunk
        return self._parse()

    def _state_event(self, state: Any) -> list[tuple[str, Any]]:
        if self._state_emitted or not isinstance(state, dict):
            return []
        self._state_emitted = True
        return [("companion_state", state)]

    def _parse(self) -> list[tuple[str, Any]]:
        events: list[tuple[str, Any]] = []
        source = _strip_fence(self._buffer)
        if not self._state_emitted:
            for match in _KEY_OBJECT.finditer(source):
                if not key_matches(match.group(1), "companion_state"):
                    continue
                try:
                    state, _ = json.JSONDecoder().raw_decode(source[match.end() - 1:])
                except json.JSONDecodeError:
                    break
                events += self._state_event(state)
                break
        try:
            value, end = json.JSONDecoder().raw_decode(source)
        except json.JSONDecodeError:
            return events
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except json.JSONDecodeError:
                value = {"reply": value}
        self._done = True
        events += self._state_event(near_get(value, "companion_state"))
        reply, nested_state = _clean_reply(near_get(value, "reply"))
        events += self._state_event(nested_state)
        if reply:
            events.append(("reply", reply))
        self._buffer = source[end:]
        return events

    def salvage(self) -> list[tuple[str, Any]]:
        """Best effort after generation ends without a complete JSON object."""
        if self._done:
            return []
        self._done = True
        source = _strip_fence(self._buffer)
        if not source:
            return []
        if not looks_like_json(source):
            return [("reply", source.strip())]
        for match in _REPLY_STRING.finditer(source):
            if not key_matches(match.group(1), "reply"):
                continue
            raw = source[match.end():]
            out, i = [], 0
            while i < len(raw) and raw[i] != '"':
                out.append(raw[i:i + 2] if raw[i] == "\\" else raw[i])
                i += 2 if raw[i] == "\\" else 1
            body, text = "".join(out), None
            for cut in range(7):  # drop a truncated trailing escape such as "\u06"
                try:
                    text = json.loads('"' + body[:len(body) - cut] + '"')
                    break
                except json.JSONDecodeError:
                    continue
            if text is None:
                return []
            reply, _ = _clean_reply(text.replace("�", ""))
            return [("reply", reply)] if reply else []
        return []

    def finish(self) -> list[tuple[str, Any]]:
        if not self._done:
            raise ValueError("incomplete structured response")
        return []


def extract(chunks: list[str] | tuple[str, ...]) -> list[tuple[str, Any]]:
    parser = StreamExtractor()
    out: list[tuple[str, Any]] = []
    for chunk in chunks:
        out.extend(parser.feed(chunk))
    parser.finish()
    return out
