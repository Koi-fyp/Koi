"""
Signed, client-carried director state (keeps the FastAPI engine stateless; Blueprint §4.1).

token = base64url(JSON payload) + "." + hex HMAC-SHA256(secret, base64 part). Standard library only.

What it guarantees: the client cannot EDIT the state (cooldowns, offer cap, current step) without detection.
What it does NOT guarantee (disclosed): a client can REPLAY an older valid token; a stateless server cannot tell.
The current-turn risk check runs every turn regardless of the token, so a replay can at worst replay an offer
cooldown, never skip a crisis rule.
"""
import base64
import hashlib
import hmac
import json
import os

VERSION = 1


class TokenError(ValueError):
    pass


def _secret(secret):
    s = secret if secret is not None else os.environ.get("KOI_DIRECTOR_SECRET")
    if not s:
        raise TokenError("no signing secret (pass secret= or set KOI_DIRECTOR_SECRET)")
    return s.encode() if isinstance(s, str) else s


def sign(payload, secret=None):
    body = base64.urlsafe_b64encode(json.dumps({**payload, "v": VERSION}, ensure_ascii=False,
                                               separators=(",", ":"), sort_keys=True).encode()).decode().rstrip("=")
    mac = hmac.new(_secret(secret), body.encode(), hashlib.sha256).hexdigest()
    return body + "." + mac


def verify(token, secret=None):
    if not isinstance(token, str) or token.count(".") != 1:
        raise TokenError("malformed token")
    body, mac = token.split(".")
    good = hmac.new(_secret(secret), body.encode(), hashlib.sha256).hexdigest()
    if not hmac.compare_digest(mac, good):
        raise TokenError("bad signature")
    try:
        payload = json.loads(base64.urlsafe_b64decode(body + "=" * (-len(body) % 4)))
    except Exception as e:  # noqa: BLE001
        raise TokenError(f"undecodable payload: {e}") from None
    if payload.get("v") != VERSION:
        raise TokenError(f"unsupported token version {payload.get('v')!r}")
    return payload
