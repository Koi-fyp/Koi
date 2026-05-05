from typing import Any, Dict, Optional

from pydantic import BaseModel, Field


class HealthStatus(BaseModel):
    status: str
    service: str = 'koi-ai-engine'
    version: str = '0.1.0'
    cpu_percent: float
    memory_percent: float
    memory_available_mb: int


class WarmupResponse(BaseModel):
    status: str = 'ready'
    message: str = 'AI engine warmed up'
    timestamp: str


class InferenceRequest(BaseModel):
    prompt: str = Field(min_length=1)
    metadata: Dict[str, Any] = Field(default_factory=dict)
    model: Optional[str] = None


class InferenceResponse(BaseModel):
    status: str = 'success'
    user_id: Optional[str] = None
    message: str
    result: Dict[str, Any] = Field(default_factory=dict)
