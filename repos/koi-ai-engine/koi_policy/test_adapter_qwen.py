"""In-process adapter test; the real model is never loaded."""

import adapter_qwen as A
import compose as K


class _StubInferenceService:
    def __init__(self, result="Thank you for telling me.", error=None):
        self.calls = []
        self.result = result
        self.error = error

    def generate_text(self, message, *, system_instruction, max_new_tokens):
        self.calls.append((message, system_instruction, max_new_tokens))
        if self.error:
            raise self.error
        return self.result


def test_phrase_fn_uses_in_process_plain_text_generation(monkeypatch):
    stub = _StubInferenceService()
    monkeypatch.setattr(A, "inference_service", stub)
    direction = {
        "goal": "acknowledge the user's feeling",
        "lang": "en",
        "user_text": "I feel overwhelmed.",
        "next_line": "Let us take this one step at a time.",
        "exercise": "grounding",
        "max_words": 25,
    }

    state, tokens = A.phrase_fn(direction)

    assert state is None
    assert list(tokens) == ["Thank you for telling me."]
    assert stub.calls == [
        (
            "I feel overwhelmed.",
            A.K.direction_prompt(direction),
            96,
        )
    ]


def _direction(lang="en"):
    return K.direction(
        "acknowledge the user's feeling",
        lang,
        "I feel overwhelmed.",
        "Let us take this one step at a time.",
        "grounding",
    )


def _fallbacks():
    return ["Reviewed fallback."]


def test_acknowledge_model_error_uses_fallback(monkeypatch):
    stub = _StubInferenceService(error=RuntimeError("model unavailable"))
    monkeypatch.setattr(A, "inference_service", stub)

    state, sentences, source, notes = K.acknowledge(
        A.phrase_fn, _direction(), _fallbacks(), 0
    )

    assert source == "fallback"
    assert sentences == ["Reviewed fallback."]
    assert notes
    assert stub.calls[0][2] == 96


def test_acknowledge_releases_good_sentences_before_question(monkeypatch):
    stub = _StubInferenceService(
        result="I hear you. Thank you for sharing. Are you okay?"
    )
    monkeypatch.setattr(A, "inference_service", stub)

    state, sentences, source, notes = K.acknowledge(
        A.phrase_fn, _direction(), _fallbacks(), 0
    )

    assert source == "generated"
    assert sentences == ["I hear you.", "Thank you for sharing."]
    assert notes == ["attempt 1: kept 2 sentence(s), cut at: asks a question (the fixed line asks)"]
    assert stub.calls[0][2] == 96


def test_acknowledge_rejects_urdu_script_for_english(monkeypatch):
    stub = _StubInferenceService(result="میں آپ کی بات سمجھتا ہوں۔")
    monkeypatch.setattr(A, "inference_service", stub)

    state, sentences, source, notes = K.acknowledge(
        A.phrase_fn, _direction("en"), _fallbacks(), 0
    )

    assert source == "fallback"
    assert sentences == ["Reviewed fallback."]
    assert len(stub.calls) == 2
    assert all(call[2] == 96 for call in stub.calls)
