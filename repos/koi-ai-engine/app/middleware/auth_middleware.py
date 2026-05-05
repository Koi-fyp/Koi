from typing import Any, Awaitable, Callable, Dict

from fastapi import HTTPException, Request, status
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import Response

from app.core.security import initialize_firebase
from firebase_admin import auth as firebase_auth


class FirebaseAuthMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, exempt_paths: set[str] | None = None):
        super().__init__(app)
        self.exempt_paths = exempt_paths or {'/health', '/ai/warmup', '/', '/docs', '/openapi.json'}

    async def dispatch(self, request: Request, call_next: Callable[[Request], Awaitable[Response]]) -> Response:
        if request.url.path in self.exempt_paths:
            return await call_next(request)

        if request.url.path.startswith('/ai'):
            authorization = request.headers.get('authorization', '')
            if not authorization.startswith('Bearer '):
                return Response(status_code=status.HTTP_401_UNAUTHORIZED)

            token = authorization.removeprefix('Bearer ').strip()
            if not token:
                return Response(status_code=status.HTTP_401_UNAUTHORIZED)

            initialize_firebase()
            try:
                decoded = firebase_auth.verify_id_token(token)
                request.state.user = decoded
            except Exception:
                return Response(status_code=status.HTTP_401_UNAUTHORIZED)

        return await call_next(request)
