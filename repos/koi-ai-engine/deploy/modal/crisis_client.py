"""Internal crisis scoring boundary used by the chat service."""
import asyncio
from typing import Any, Awaitable, Callable


ScoreCallable = Callable[..., Any]


class CrisisClient:
    def __init__(self, scorer: ScoreCallable | None = None):
        self._scorer = scorer

    async def score_async(self, *, text: str | None, audio_bytes: bytes | None,
                          video_bytes: bytes | None, language: str | None,
                          turn_id: str | None, uid: str) -> dict[str, Any]:
        if self._scorer is None:
            return {"status": "unavailable"}
        try:
            result = self._scorer(
                text=text, audio_bytes=audio_bytes, video_bytes=video_bytes,
                language=language, turn_id=turn_id, uid=uid,
            )
            if asyncio.iscoroutine(result) or isinstance(result, Awaitable):
                result = await result
            return result if isinstance(result, dict) else {"status": "unavailable"}
        except Exception:
            return {"status": "unavailable"}


class FakeCrisisClient(CrisisClient):
    def __init__(self, result: dict[str, Any] | None = None, delay: float = 0):
        self.result = result or {"status": "unavailable"}
        self.delay = delay

    async def score_async(self, **kwargs: Any) -> dict[str, Any]:
        if self.delay:
            await asyncio.sleep(self.delay)
        return dict(self.result)
