import json
from typing import Any, Dict

import firebase_admin
from firebase_admin import auth as firebase_auth, credentials
from fastapi import Depends, HTTPException, Request, status
from jose import JWTError

from app.core.config import settings


def initialize_firebase() -> None:
    if firebase_admin._apps:
        return
    if not settings.firebase_admin_sdk:
        return

    try:
        credential_info = json.loads(settings.firebase_admin_sdk)
        firebase_admin.initialize_app(credentials.Certificate(credential_info))
    except Exception as exc:
        raise RuntimeError(f'Unable to initialize Firebase Admin SDK: {exc}') from exc


async def verify_firebase_token(request: Request) -> Dict[str, Any]:
    authorization = request.headers.get('authorization', '')
    if not authorization.startswith('Bearer '):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Authorization header missing or invalid',
        )

    token = authorization.removeprefix('Bearer ').strip()
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Authorization token missing',
        )

    initialize_firebase()
    try:
        decoded = firebase_auth.verify_id_token(token)
        return decoded
    except (firebase_auth.InvalidIdTokenError, firebase_auth.ExpiredIdTokenError, JWTError):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail='Invalid or expired Firebase token',
        )
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f'Unable to validate Firebase token: {exc}',
        )
