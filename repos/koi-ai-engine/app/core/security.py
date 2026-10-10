"""
🆕 [PHASE 2 REBUILD] CARRIED OVER, functionally unchanged from the
previous version of this file — this was the one piece of the old
`koi-ai-engine` codebase confirmed correct against locked canon during
the pre-rebuild audit:

  - Uses `firebase_admin.auth.verify_id_token()` — real JWKS verification
    via the vetted `firebase-admin` SDK, not a hand-rolled signature
    check. Satisfies the CRITICAL requirement in
    TRACK_AI_BACKEND_FINAL_v4_13.md line 98 / Blueprint §4.1's
    "SECURITY RULE."
  - Identity is read only from the verified token's decoded claims
    (`current_user.get('uid')` at call sites) — never from a
    client-supplied JSON field. `ChatRequest` (see schemas.py) has no
    user-identity field at all, by design, matching "Reject JSON
    user_id payloads."

No changes made here beyond this header comment.
"""

import json
from typing import Any, Dict

import firebase_admin
from firebase_admin import auth as firebase_auth, credentials
from fastapi import HTTPException, Request, status
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
