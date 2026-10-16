import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import crisis_app


def _crisis():
    return crisis_app.Crisis()


def test_score_surface_rejects_disallowed_combinations():
    service = _crisis()
    with pytest.raises(ValueError, match="text\\+audio"):
        service.score("typed", b"audio")
    with pytest.raises(ValueError, match="video requires"):
        service.score(None, None, b"video")


def test_score_surface_accepts_allowed_combination_contract():
    result = _crisis().score("typed", None, b"video", "en", "turn-1", "uid-1")
    assert result["status"] == "unavailable"
    assert result["turn_id"] == "turn-1"
