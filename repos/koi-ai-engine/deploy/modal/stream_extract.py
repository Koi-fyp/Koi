"""Small, dependency-free extractor for the structured chat response."""
import json
from typing import Any


class StreamExtractor:
    def __init__(self) -> None:
        self._buffer = ""
        self._done = False
        self._state_emitted = False

    def feed(self, chunk: str) -> list[tuple[str, Any]]:
        if self._done:
            return []
        self._buffer += chunk
        events: list[tuple[str, Any]] = []
        source = self._buffer.lstrip()
        if not self._state_emitted:
            marker = '"companion_state"'
            start = source.find(marker)
            if start >= 0:
                colon = source.find(":", start + len(marker))
                if colon >= 0:
                    try:
                        state, _ = json.JSONDecoder().raw_decode(source[colon + 1:].lstrip())
                    except json.JSONDecodeError:
                        state = None
                    if isinstance(state, dict):
                        events.append(("companion_state", state))
                        self._state_emitted = True
        try:
            value, end = json.JSONDecoder().raw_decode(source)
        except json.JSONDecodeError:
            return events
        if not isinstance(value, dict) or not isinstance(value.get("reply"), str):
            raise ValueError("structured response must contain a string reply")
        self._done = True
        if not self._state_emitted and isinstance(value.get("companion_state"), dict):
            events.append(("companion_state", value["companion_state"]))
        events.append(("reply", value["reply"]))
        self._buffer = source[end:]
        return events

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
