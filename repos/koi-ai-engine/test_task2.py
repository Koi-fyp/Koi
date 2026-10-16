import json
import sys
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

sys.path.insert(0, str(Path(__file__).resolve().parent / "koi_policy"))

from app.api import routes
import adapter_qwen
import state_token as T
from app.models.schemas import ChatResponse, CompanionState
from main import app


def _model_reply(message, session_history):
    return ChatResponse(
        companion_state=CompanionState(emotion="neutral", intensity=0.4),
        reply=f"normal: {message}",
        latency_ms=7,
    )


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.setenv("KOI_DIRECTOR_SECRET", "test-secret")
    app.dependency_overrides[routes.verify_firebase_token] = lambda: {"uid": "test"}
    monkeypatch.setattr(routes.inference_service, "generate_reply", _model_reply)
    monkeypatch.setattr(adapter_qwen, "phrase_fn", lambda direction: (None, iter(())))
    with TestClient(app) as value:
        yield value
    app.dependency_overrides.clear()


def _post(client, message, **extra):
    return client.post("/api/v1/chat", json={"message": message, **extra})


def test_flag_off_is_ordinary_chat_and_never_calls_director(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "0")
    monkeypatch.delenv("KOI_DIRECTOR_SECRET", raising=False)
    app.dependency_overrides[routes.verify_firebase_token] = lambda: {"uid": "test"}
    monkeypatch.setattr(routes.inference_service, "generate_reply", _model_reply)
    monkeypatch.setattr(routes, "_director_turn", lambda *_: (_ for _ in ()).throw(AssertionError))
    with TestClient(app) as client:
        response = _post(client, "hello")
    app.dependency_overrides.clear()
    assert response.status_code == 200
    assert response.json() == {
        "companion_state": {"emotion": "neutral", "intensity": 0.4},
        "reply": "normal: hello",
        "latency_ms": 7,
    }
    print("normal chat:", json.dumps(response.json()))


def test_risk_unavailable_does_not_start_exercise(client):
    response = _post(client, "hello")
    assert response.status_code == 200
    assert response.json()["reply"] == "normal: hello"
    assert response.json()["handoff"] == "companion"


def test_idle_low_risk_does_not_start_exercise(client, monkeypatch):
    monkeypatch.setattr(routes.risk_provider, "get_risk", lambda text: ("LOW", 0.1, []))
    response = _post(client, "hello")
    assert response.status_code == 200
    assert response.json()["reply"] == "normal: hello"
    assert response.json()["handoff"] == "companion"


def test_demo_lexicon_breathing_offer_and_accept(client, monkeypatch):
    monkeypatch.setenv("KOI_RISK_SOURCE", "demo_lexicon")
    offer = _post(client, "please help")
    assert offer.status_code == 200
    assert offer.json()["handoff"] == "companion"
    print("exercise offer:", json.dumps(offer.json()))

    accepted = _post(client, "start", client_event="start_breathing")
    assert accepted.status_code == 200
    body = accepted.json()
    assert body["ui_action"]["name"] == "start_breathing"
    assert "handoff" not in body
    print("breathing ui_action:", json.dumps(body))


def test_high_risk_at_each_waiting_step_returns_ordinary_reply(client, monkeypatch):
    monkeypatch.setenv("KOI_RISK_SOURCE", "demo_lexicon")
    calls = []
    monkeypatch.setattr(
        routes.inference_service,
        "generate_reply",
        lambda *a: calls.append(a) or _model_reply(*a),
    )
    started = _post(client, "start", client_event="start_breathing")
    token = started.json()["exercise_state"]
    for message in ("I will hurt myself", "I will hurt myself"):
        response = _post(client, message, exercise_state=token)
        assert response.status_code == 200
        body = response.json()
        assert body["handoff"] == "crisis"
        assert body["reply"] == f"normal: {message}"
        token = body["exercise_state"]
    assert len(calls) == 2
    print("crisis handoff:", json.dumps(body))


def test_distress_mid_exercise_returns_ordinary_reply_and_stops_exercise(client, monkeypatch):
    monkeypatch.setenv("KOI_RISK_SOURCE", "demo_lexicon")
    calls = []
    monkeypatch.setattr(
        routes.inference_service,
        "generate_reply",
        lambda *a: calls.append(a) or _model_reply(*a),
    )
    started = _post(client, "start", client_event="start_breathing")
    response = _post(
        client,
        "I want to kill myself",
        exercise_state=started.json()["exercise_state"],
    )
    assert response.status_code == 200
    body = response.json()
    assert body["handoff"] == "crisis"
    assert body["reply"] == "normal: I want to kill myself"
    assert len(calls) == 1


def test_idle_distress_returns_ordinary_reply_and_crisis_handoff(client, monkeypatch):
    monkeypatch.setenv("KOI_RISK_SOURCE", "demo_lexicon")
    calls = []
    monkeypatch.setattr(
        routes.inference_service,
        "generate_reply",
        lambda *a: calls.append(a) or _model_reply(*a),
    )
    response = _post(client, "I want to kill myself")
    assert response.status_code == 200
    body = response.json()
    assert body["handoff"] == "crisis"
    assert body["reply"] == "normal: I want to kill myself"
    assert len(calls) == 1


def _risk_queue(monkeypatch, values):
    queued = iter(values)
    monkeypatch.setattr(routes.risk_provider, "get_risk", lambda text: next(queued))


def _build_waiting_tokens(client, monkeypatch):
    scripts = {
        "breathing": [
            ("everything is a lot", None, ("MODERATE", 0.5, [])),
            ("what's that?", None, ("LOW", 0.1, [])),
            ("ok let's try", None, ("LOW", 0.1, [])),
            (None, "playback_done", ("LOW", 0.1, [])),
            ("a bit better actually", None, ("LOW", 0.1, [])),
        ],
        "breathing_pause": [
            ("everything is a lot", None, ("MODERATE", 0.5, [])),
            ("ok let's try", None, ("LOW", 0.1, [])),
            ("hold on", None, ("LOW", 0.1, [])),
        ],
        "breathing_decline": [
            ("everything is a lot", None, ("MODERATE", 0.5, [])),
            ("no", None, ("LOW", 0.1, [])),
            ("not my thing really", None, ("LOW", 0.1, [])),
        ],
        "grounding": [
            ("can we do a grounding exercise", None, ("LOW", 0.1, [])),
            ("sad", None, ("LOW", 0.1, [])),
            ("done", None, ("LOW", 0.1, [])),
            ("a lamp", None, ("LOW", 0.1, [])),
            ("birds", None, ("LOW", 0.1, [])),
            ("better", None, ("LOW", 0.1, [])),
            ("yes", None, ("LOW", 0.1, [])),
        ],
        "plan": [
            ("let's make a plan", None, ("LOW", 0.1, [])),
            ("walk", None, ("LOW", 0.1, [])),
            ("evening", None, ("LOW", 0.1, [])),
            ("3", None, ("LOW", 0.1, [])),
        ],
    }
    tokens = {}
    for name, script in scripts.items():
        _risk_queue(monkeypatch, [risk for _, _, risk in script])
        current_token = None
        for text, event, _ in script:
            extra = {"client_event": event} if event else {}
            if current_token:
                extra["exercise_state"] = current_token
            response = _post(client, text or "playback", **extra)
            assert response.status_code == 200
            state_token = response.json().get("exercise_state")
            if not state_token:
                continue
            current_token = state_token
            state = T.verify(state_token, "test-secret")
            ex = state.get("ex")
            if ex:
                tokens[f"{ex['j']}.{ex['step']}"] = state_token
    # Complete grounding once so its go_to value is present in a client token.
    grounding_post_check = tokens["grounding.post_check"]
    _risk_queue(monkeypatch, [("LOW", 0.1, [])])
    response = _post(client, "better", exercise_state=grounding_post_check)
    grounding_go_to = response.json()["exercise_state"]
    _risk_queue(monkeypatch, [("LOW", 0.1, [])])
    response = _post(client, "yes", exercise_state=grounding_go_to)
    grounding_seed = response.json()["exercise_state"]

    # With go_to=grounding, a declined CBT offer reaches grounding.offer.
    current_token = grounding_seed
    for _ in range(3):
        _risk_queue(monkeypatch, [("MODERATE", 0.6, [])])
        response = _post(
            client,
            "I keep thinking nobody wants me around",
            exercise_state=current_token,
        )
        current_token = response.json()["exercise_state"]
    cbt_offer_state = T.verify(current_token, "test-secret")
    assert cbt_offer_state["ex"]["step"] == "offer"
    tokens["cbt.offer"] = current_token

    _risk_queue(monkeypatch, [("LOW", 0.1, [])])
    response = _post(client, "what is it", exercise_state=current_token)
    state_token = response.json()["exercise_state"]
    state = T.verify(state_token, "test-secret")
    tokens["cbt.explain"] = state_token
    assert state["ex"]["step"] == "explain"

    _risk_queue(monkeypatch, [("LOW", 0.1, [])])
    response = _post(client, "no thanks", exercise_state=current_token)
    state_token = response.json()["exercise_state"]
    state = T.verify(state_token, "test-secret")
    tokens["grounding.offer"] = state_token
    assert state["ex"]["j"] == "grounding" and state["ex"]["step"] == "offer"

    # Branches from the grounding offer reach its explanation, why-not, and alternative waits.
    grounding_offer = tokens["grounding.offer"]
    for text, label in (
        ("what is it", "grounding.explain"),
        ("no", "grounding.why_not"),
    ):
        _risk_queue(monkeypatch, [("LOW", 0.1, [])])
        response = _post(client, text, exercise_state=grounding_offer)
        state_token = response.json()["exercise_state"]
        state = T.verify(state_token, "test-secret")
        tokens[label] = state_token
        assert state["ex"]["step"] == label.split(".", 1)[1]
    _risk_queue(monkeypatch, [("LOW", 0.1, [])])
    response = _post(client, "not my thing", exercise_state=tokens["grounding.why_not"])
    state_token = response.json()["exercise_state"]
    state = T.verify(state_token, "test-secret")
    tokens["grounding.alt_offer"] = state_token
    assert state["ex"]["step"] == "alt_offer"

    return tokens


def test_high_tier_reaches_every_waiting_state_over_http(client, monkeypatch):
    tokens = _build_waiting_tokens(client, monkeypatch)
    expected = {
        "breathing.offer", "breathing.explain", "breathing.playing", "breathing.paused",
        "breathing.why_not", "breathing.alt_offer", "breathing.post_check", "breathing.go_to",
        "grounding.offer", "grounding.explain", "grounding.g1", "grounding.g2", "grounding.g3",
        "grounding.g4", "grounding.g5", "grounding.why_not", "grounding.alt_offer",
        "grounding.post_check", "grounding.go_to",
        "plan.t1", "plan.t2", "plan.t3", "plan.t3b",
        "cbt.offer", "cbt.explain",
    }
    assert set(tokens) == expected

    for state_name, token in tokens.items():
        calls = []
        monkeypatch.setattr(
            routes.risk_provider,
            "get_risk",
            lambda text: ("HIGH", 0.95, []),
        )
        monkeypatch.setattr(
            routes.inference_service,
            "generate_reply",
            lambda *args: calls.append(args) or _model_reply(*args),
        )
        response = _post(client, "still here", exercise_state=token)
        body = response.json()
        assert body["handoff"] == "crisis"
        assert body["reply"] == "normal: still here"
        assert len(calls) == 1
        returned_ui = body.get("ui_action")
        print(
            f"HIGH fork {state_name}: handoff={body['handoff']} "
            f"ui_action={returned_ui!r}"
        )


def test_distress_word_forks_report_stop_ui_action(client, monkeypatch):
    tokens = _build_waiting_tokens(client, monkeypatch)
    for state_name, token in tokens.items():
        monkeypatch.setattr(
            routes.risk_provider,
            "get_risk",
            lambda text: ("HIGH", 0.95, ["demo_distress"]),
        )
        calls = []
        monkeypatch.setattr(
            routes.inference_service,
            "generate_reply",
            lambda *args: calls.append(args) or _model_reply(*args),
        )
        response = _post(client, "I will hurt myself", exercise_state=token)
        body = response.json()
        assert body["handoff"] == "crisis"
        assert body["reply"] == "normal: I will hurt myself"
        assert len(calls) == 1
        emitted_stop = state_name.endswith(".playing")
        returned_stop = body.get("ui_action", {}).get("name") == "stop_breathing"
        print(
            f"distress fork {state_name}: emitted_stop={emitted_stop} "
            f"returned_stop={returned_stop}"
        )


def test_demo_lexicon_text_breathing_start_is_reported(client, monkeypatch):
    monkeypatch.setenv("KOI_RISK_SOURCE", "demo_lexicon")
    response = _post(client, "can we do a breathing exercise")
    body = response.json()
    started = bool(body.get("exercise_state"))
    print(f"text start breathing: exercise_started={started} body={json.dumps(body)}")
    assert response.status_code == 200


def test_tampered_state_behaves_as_director(client):
    response = _post(client, "hello", exercise_state="tampered")
    assert response.status_code == 200
    assert response.json()["reply"] == "normal: hello"
    assert response.json()["exercise_state"]


def test_missing_secret_refuses_start(monkeypatch):
    monkeypatch.setenv("KOI_EXERCISES", "1")
    monkeypatch.delenv("KOI_DIRECTOR_SECRET", raising=False)
    app.dependency_overrides[routes.verify_firebase_token] = lambda: {"uid": "test"}
    with pytest.raises(RuntimeError, match="KOI_DIRECTOR_SECRET"):
        with TestClient(app):
            pass
    app.dependency_overrides.clear()


def test_response_field_order(client):
    response = _post(client, "hello")
    assert list(response.json())[:3] == ["companion_state", "reply", "latency_ms"]
