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
    `kid` ngẫu nhiên để bắt server gọi identity-service liên tục. Ở đây mọi lần tải (thành công hay lỗi)
    cách nhau ít nhất `min_refresh` giây.

    - Khoá hợp lệ `max_age` giây kể từ lần tải THÀNH CÔNG gần nhất; quá hạn thì tải lại.
    - Tải lại lỗi: dùng tiếp khoá cũ thêm tối đa `grace` giây rồi thôi (khoá đã bị thu hồi ở identity
      không được sống mãi chỉ vì identity chết).
    - Lần tải gần nhất lỗi mà không có khoá dùng được → `JwksUnavailable` (503) cho MỌI request trong
      lúc đó, không lẫn thành 401 — claude.ai coi 401 là token hỏng và bắt đăng nhập lại.

    Giữ khoá suốt lần tải (≤5s, tối đa một lần mỗi `min_refresh`): request khác chờ chứ không bắn thêm.
    """

    def __init__(
        self,
        url: str,
        fetch: Callable[[str], Any] = _http_get_json,
        min_refresh: float = 60.0,
        max_age: float = 3600.0,
        grace: float = 3600.0,
        clock: Callable[[], float] = time.monotonic,
    ):
        self.url = url
        self._fetch = fetch
        self._min_refresh = min_refresh
        self._max_age = max_age
        self._grace = grace
        self._clock = clock
        self._keys: dict[str, Any] = {}
        self._last_success: float | None = None
        self._last_attempt: float | None = None
        self._last_failed = False
        self._lock = threading.Lock()

    def _load(self) -> dict[str, Any]:
        try:
            data = self._fetch(self.url)
            if not isinstance(data, dict) or not isinstance(data.get("keys"), list):
                raise ValueError("jwks shape")
            jwks = jwt.PyJWKSet.from_dict(data)
        except (httpx.HTTPError, ValueError, TypeError, AttributeError, KeyError, jwt.PyJWTError) as exc:
            raise JwksUnavailable(type(exc).__name__) from None
        keys = {k.key_id: k.key for k in jwks.keys if k.key_id and k.key_type == "RSA"}
        if not keys:
            raise JwksUnavailable("no RSA keys")  # không xoá khoá đang dùng được
        return keys

    def _try_refresh(self, now: float) -> None:
        self._last_attempt = now
        try:
            keys = self._load()
        except JwksUnavailable:
            self._last_failed = True
            return
        self._keys, self._last_success, self._last_failed = keys, now, False

    def key_for(self, kid: str) -> Any:
        with self._lock:
            now = self._clock()
            age = None if self._last_success is None else now - self._last_success
            want = age is None or age >= self._max_age or kid not in self._keys
            may = self._last_attempt is None or now - self._last_attempt >= self._min_refresh
            if want and may:
                self._try_refresh(now)
                age = None if self._last_success is None else now - self._last_success
            usable = age is not None and age < self._max_age + self._grace
            key = self._keys.get(kid) if usable else None
            failed = self._last_failed
        if key is not None:
            return key
        if failed or not usable:
            raise JwksUnavailable("jwks")
        raise InvalidToken("unknown kid")


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
