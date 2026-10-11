"""Xác thực cho `/mcp`: claude.ai đăng nhập qua identity-service (OAuth 2.1 + PKCE, GitHub), backend này
chỉ là resource server — verify JWT, không giữ secret, không phát token.

- Discovery (RFC 9728): `/.well-known/oauth-protected-resource[/mcp]` chỉ claude.ai tới identity-service.
- Token: JWT RS256 do identity-service ký; kiểm chữ ký (JWKS), `iss`, `aud` == `<PUBLIC_BASE_URL>/mcp`
  (RFC 8707 — token phát cho app/resource khác bị từ chối), `exp`.
- Quyền: JWT hợp lệ mới chỉ chứng minh "ai đó có tài khoản GitHub". Được sửa nội dung hay không do bảng
  `mcp_access` quyết (`authorize_sub`), kiểm ở MỖI tool call nên thu hồi có hiệu lực ngay dù JWT còn hạn.
- Không bao giờ dùng `AUTH_OPEN_AS` hay token `user_sessions` của app: đây là đường xác thực riêng.

Env (đọc lúc gọi): `PUBLIC_BASE_URL` (vd https://codewithphuong.jacons-corp.com — thiếu thì MCP tắt),
`IDENTITY_ISSUER` (mặc định https://identity.jacons-corp.com).
"""

from __future__ import annotations

import os
import threading
import time
from collections.abc import Callable
from typing import Any

import httpx
import jwt
from fastapi import APIRouter, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import CurrentUser
from app.tables import McpAccess, User

DEFAULT_ISSUER = "https://identity.jacons-corp.com"
MCP_PATH = "/mcp"
SCOPES = ["content"]
LEEWAY_SECONDS = 30
# Phiên "ảo" của MCP trong CurrentUser: không có dòng user_sessions nào (khác OPEN_SESSION_ID = 0).
MCP_SESSION_ID = -1

router = APIRouter()


class InvalidToken(Exception):
    """Token thiếu/sai/hết hạn/không dành cho resource này → 401."""


class JwksUnavailable(Exception):
    """Không lấy được khoá công khai của identity-service → 503 (không phải lỗi của token)."""


def public_base_url() -> str | None:
    base = os.environ.get("PUBLIC_BASE_URL", "").strip().rstrip("/")
    return base or None


def issuer() -> str:
    return os.environ.get("IDENTITY_ISSUER", "").strip().rstrip("/") or DEFAULT_ISSUER


def mcp_resource(base: str) -> str:
    return base + MCP_PATH


def resource_metadata_url(base: str) -> str:
    return f"{base}/.well-known/oauth-protected-resource{MCP_PATH}"


def www_authenticate(base: str, invalid: bool) -> str:
    """Header của 401: claude.ai chỉ bắt đầu đăng nhập khi thấy `resource_metadata` trên một 401."""
    error = 'error="invalid_token", ' if invalid else ""
    return f'Bearer {error}resource_metadata="{resource_metadata_url(base)}", scope="{" ".join(SCOPES)}"'


def _http_get_json(url: str) -> Any:
    response = httpx.get(url, timeout=5.0, follow_redirects=False)
    response.raise_for_status()
    return response.json()


class JwksCache:
    """Khoá công khai của identity-service, theo `kid`.

    Không dùng thẳng `PyJWKClient`: nó tải lại JWKS mỗi lần gặp `kid` lạ, nên ai cũng gửi được token
    `kid` ngẫu nhiên để bắt server gọi identity-service liên tục. Ở đây `kid` lạ chỉ được tải lại tối đa
    một lần mỗi `min_refresh` giây; khoá cũ giữ tối đa `max_age` giây (xoay khoá vẫn nhận ra).
    """

    def __init__(
        self,
        url: str,
        fetch: Callable[[str], Any] = _http_get_json,
        min_refresh: float = 60.0,
        max_age: float = 3600.0,
        clock: Callable[[], float] = time.monotonic,
    ):
        self.url = url
        self._fetch = fetch
        self._min_refresh = min_refresh
        self._max_age = max_age
        self._clock = clock
        self._keys: dict[str, Any] = {}
        self._fetched_at: float | None = None
        self._lock = threading.Lock()

    def _refresh(self, now: float) -> None:
        self._fetched_at = now  # kể cả khi lỗi: identity-service chết thì không dội request vào nó
        try:
            data = self._fetch(self.url)
            jwks = jwt.PyJWKSet.from_dict(data)
        except (httpx.HTTPError, ValueError, jwt.PyJWTError) as exc:
            raise JwksUnavailable(type(exc).__name__) from None
        self._keys = {k.key_id: k.key for k in jwks.keys if k.key_id and k.key_type == "RSA"}

    def key_for(self, kid: str) -> Any:
        with self._lock:
            now = self._clock()
            age = None if self._fetched_at is None else now - self._fetched_at
            stale = age is None or age >= self._max_age
            may_refresh = age is None or age >= self._min_refresh
            if stale or (kid not in self._keys and may_refresh):
                try:
                    self._refresh(now)
                except JwksUnavailable:
                    if not self._keys:
                        raise
            key = self._keys.get(kid)
        if key is None:
            raise InvalidToken("unknown kid")
        return key


_caches: dict[str, JwksCache] = {}
_caches_lock = threading.Lock()


def jwks_for(iss: str) -> JwksCache:
    with _caches_lock:
        cache = _caches.get(iss)
        if cache is None:
            cache = _caches[iss] = JwksCache(f"{iss}/.well-known/jwks.json")
        return cache


def verify_token(token: str, *, audience: str, iss: str, keys: JwksCache) -> dict:
    """Claims của JWT nếu hợp lệ cho đúng resource này; ngược lại `InvalidToken`."""
    try:
        header = jwt.get_unverified_header(token)
    except jwt.PyJWTError:
        raise InvalidToken("malformed") from None
    # Chỉ RS256: chặn `alg=none` và nhầm khoá công khai thành secret HMAC (HS256).
    if header.get("alg") != "RS256" or not isinstance(header.get("kid"), str):
        raise InvalidToken("alg")
    key = keys.key_for(header["kid"])
    try:
        claims = jwt.decode(
            token,
            key,
            algorithms=["RS256"],
            audience=audience,
            issuer=iss,
            leeway=LEEWAY_SECONDS,
            options={"require": ["exp", "iss", "aud", "sub"]},
        )
    except jwt.PyJWTError:
        raise InvalidToken("claims") from None
    if not isinstance(claims.get("sub"), str) or not claims["sub"].strip():
        raise InvalidToken("sub")
    return claims


def verify_bearer(authorization: str | None, base: str) -> dict:
    """Header `Authorization` → claims. Blocking (có thể tải JWKS): gọi trong threadpool."""
    scheme, _, token = (authorization or "").partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        raise InvalidToken("missing")
    iss = issuer()
    return verify_token(token.strip(), audience=mcp_resource(base), iss=iss, keys=jwks_for(iss))


def authorize_sub(session: Session, sub: str) -> CurrentUser | None:
    """Admin mà tài khoản identity `sub` được phép hành động thay; None nếu chưa cấp / đã thu hồi /
    user đích không còn là admin. Gọi ở MỖI tool call."""
    row = session.execute(
        select(User.id, User.email, User.roles)
        .join(McpAccess, McpAccess.user_id == User.id)
        .where(McpAccess.sub == sub, McpAccess.revoked_at.is_(None))
    ).first()
    if row is None:
        return None
    user_id, email, roles = row
    if "admin" not in roles:
        return None
    return CurrentUser(id=user_id, email=email, roles=tuple(roles), session_id=MCP_SESSION_ID)


def protected_resource_metadata(base: str) -> dict:
    return {
        "resource": mcp_resource(base),
        "authorization_servers": [issuer()],
        "scopes_supported": SCOPES,
        "bearer_methods_supported": ["header"],
    }


@router.get("/.well-known/oauth-protected-resource")
@router.get("/.well-known/oauth-protected-resource/mcp")
def get_protected_resource_metadata() -> dict:
    base = public_base_url()
    if base is None:
        raise HTTPException(status_code=404, detail="mcp_not_configured")
    return protected_resource_metadata(base)
