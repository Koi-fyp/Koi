from fastapi import APIRouter, Depends

from app.core.security import verify_firebase_token
from app.models.schemas import HealthStatus, InferenceRequest, InferenceResponse, WarmupResponse
from app.services.inference_service import InferenceService

router = APIRouter()
service = InferenceService()


@router.get('/api/health', response_model=HealthStatus, tags=['system'])
async def api_health_check():
    from main import health_check as root_health_check

    return await root_health_check()


@router.get('/api/ai/warmup', response_model=WarmupResponse, tags=['system'])
async def api_warmup_model():
    from main import warmup_model as root_warmup_model

    return await root_warmup_model()


@router.post('/api/ai/inference', response_model=InferenceResponse, tags=['inference'])
async def api_run_inference(payload: InferenceRequest, current_user=Depends(verify_firebase_token)):
    result = service.generate(payload.model_dump(), current_user.get('uid'))
    return InferenceResponse(
        user_id=current_user.get('uid'),
        message='Inference processed successfully',
        result=result,
    )
