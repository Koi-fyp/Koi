from functools import lru_cache
from typing import List

from pydantic import Field, HttpUrl
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file='.env', env_file_encoding='utf-8', extra='ignore')

    host: str = Field(default='0.0.0.0', alias='HOST')
    port: int = Field(default=8000, alias='PORT')
    debug: bool = Field(default=False, alias='DEBUG')

    firebase_project_id: str = Field(default='', alias='FIREBASE_PROJECT_ID')
    firebase_admin_sdk: str = Field(default='', alias='FIREBASE_ADMIN_SDK')

    next_js_origin: str = Field(default='http://localhost:3000', alias='NEXT_JS_ORIGIN')
    flutter_origin: str = Field(default='http://localhost:8080', alias='FLUTTER_ORIGIN')

    google_ai_studio_key: str = Field(default='', alias='GOOGLE_AI_STUDIO_KEY')
    huggingface_api_key: str = Field(default='', alias='HUGGINGFACE_API_KEY')

    model_name: str = Field(default='distilbert-base-uncased', alias='MODEL_NAME')
    inference_timeout: int = Field(default=30, alias='INFERENCE_TIMEOUT')
    max_batch_size: int = Field(default=32, alias='MAX_BATCH_SIZE')

    @property
    def allowed_origins(self) -> List[str]:
        return [self.next_js_origin, self.flutter_origin]


@lru_cache

def get_settings() -> Settings:
    return Settings()


settings = get_settings()
