"""In-process adapter for exercise acknowledgements from the Companion LLM."""

import sys
from pathlib import Path

import compose as K

ENGINE_ROOT = Path(__file__).resolve().parent.parent
if str(ENGINE_ROOT) not in sys.path:
    sys.path.insert(0, str(ENGINE_ROOT))

from app.services.inference_service import inference_service


def phrase_fn(direction):
    """Return ``(None, token_iterator)`` for one exercise acknowledgement."""
    prompt = K.direction_prompt(direction)
    reply = inference_service.generate_text(
        direction["user_text"],
        system_instruction=prompt,
        max_new_tokens=96,
    )
    return None, iter((reply,))
