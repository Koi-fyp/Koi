import os
import sys
import threading

import numpy as np
import pytest

sys.path.insert(0, os.path.dirname(__file__))
import crisis_app
import koi_crisis_core as core


def _crisis():
    return crisis_app.Crisis._get_user_cls()()


def test_score_surface_rejects_disallowed_combinations():
    service = _crisis()
    with pytest.raises(ValueError, match="text\\+audio"):
        service.score_turn("typed", b"audio")
    with pytest.raises(ValueError, match="video requires"):
        service.score_turn(None, None, b"video")


def test_score_surface_uninitialized_is_unavailable():
    result = _crisis().score_turn("typed", None, b"video", "en", "turn-1", "uid-1")
    assert result["status"] == "unavailable"
    assert result["turn_id"] == "turn-1"


def test_score_is_a_remote_modal_method():
    assert hasattr(crisis_app.Crisis().score, "remote")


class _Seg:
    text = " hello from audio "


class _Asr:
    def transcribe(self, wav, **kwargs):
        return [_Seg()], type("Info", (), {"language": "en"})()


def _loaded(asr=True):
    """A Crisis instance with deterministic fake encoders (no torch, ffmpeg or GPU)."""
    inst = _crisis()
    inst.core = core
    inst.cal = dict(core.UNCALIBRATED, max_category="HIGH")
    inst.calibrated = False
    inst.heads = [object()]
    inst.lock = threading.Lock()
    inst.asr = _Asr() if asr else None
    inst.rag = None
    inst.helpline = {"name": "test", "number": "0", "verified": False}
    inst.auth_disabled = True
    inst._text = lambda text: (None, np.array([0.0, 0.0, 3.0, 0.0, 0.0, 0.0, 0.0]))
    inst._audio = lambda wav: "audio-embedding"
    inst._video = lambda frames: "video-embedding"
    inst._heads = lambda t, a, v, combo: [0.5, 1.5, 2.5]
    inst._decode_audio = lambda path: np.zeros(16000, dtype=np.float32)
    inst._decode_video = lambda path: np.zeros((8, 224, 224, 3), dtype=np.uint8)
    return inst


def _web_json(inst, data, files):
    from fastapi.testclient import TestClient
    api = crisis_app.Crisis._get_user_cls().__dict__["web"]._get_raw_f()(inst)
    response = TestClient(api).post("/api/v1/crisis", data=data, files=files or None)
    assert response.status_code == 200, response.text
    return response.json()


def _strip(result):
    return {k: v for k, v in result.items() if k != "timing_ms"}


@pytest.mark.parametrize("text,audio,video", [
    ("I feel low", None, None),
    (None, b"wav-bytes", None),
    ("I feel low", None, b"mp4-bytes"),
    (None, b"wav-bytes", b"mp4-bytes"),
])
def test_score_turn_matches_web_json(text, audio, video):
    inst = _loaded()
    direct = inst.score_turn(text, audio, video, "en", "turn-9", "uid-1")
    data = {"language": "en", "turn_id": "turn-9", **({"text": text} if text else {})}
    files = {k: (k, v) for k, v in (("audio", audio), ("video", video)) if v}
    assert _strip(direct) == _strip(_web_json(inst, data, files))
    assert direct["risk_category"] in {"LOW", "MODERATE", "HIGH"}
    if audio:
        assert direct["transcript"] == "hello from audio"


def test_score_turn_failures_are_unavailable():
    inst = _loaded(asr=False)
    assert inst.score_turn(None, b"wav-bytes")["status"] == "unavailable"
    inst = _loaded()
    inst._text = lambda text: (_ for _ in ()).throw(RuntimeError("cuda"))
    assert inst.score_turn("hello")["status"] == "unavailable"
