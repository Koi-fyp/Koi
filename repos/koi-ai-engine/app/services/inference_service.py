from typing import Any, Dict

from app.core.config import settings


class InferenceService:
    def warmup(self) -> Dict[str, Any]:
        return {
            'model': settings.model_name,
            'status': 'ready',
        }

    def generate(self, payload: Dict[str, Any], user_id: str | None = None) -> Dict[str, Any]:
        prompt = payload.get('prompt', '')
        return {
            'analysis': 'placeholder-response',
            'prompt_length': len(prompt),
            'user_id': user_id,
            'model': payload.get('model') or settings.model_name,
        }
