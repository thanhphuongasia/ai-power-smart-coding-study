"""Đăng nhập email + mật khẩu, token bearer, phân quyền.

- Mật khẩu: argon2id (`argon2-cffi`). Không bao giờ lưu hay log mật khẩu thô.
- Token: `secrets.token_urlsafe(32)` trả cho client MỘT lần; DB chỉ lưu sha256 của nó (`user_sessions`).
- Login sai 5 lần / 15 phút theo (IP, email) → 429; mỗi IP tối đa 30 lần thử sai / 15 phút trên mọi
  email (chặn dò nhiều email và giữ RAM có giới hạn theo số IP). Đổi mật khẩu sai cũng bị đếm. Đếm
  trong RAM: mất khi restart, chỉ đúng với 1 process uvicorn (đúng cấu hình hiện tại).
- `current_user` / `require_admin` là dependency cho mọi API cần đăng nhập. Phân quyền kiểm ở server,
  UI ẩn nút chỉ là phụ.
"""

from __future__ import annotations

import hashlib
import secrets
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError, VerifyMismatchError
from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.db import SessionLocal, get_session
from app.tables import User, UserSession

router = APIRouter(prefix="/api")

ROLES = frozenset({"learner", "admin"})
SESSION_TTL = timedelta(days=30)
MIN_PASSWORD_LENGTH = 10
MAX_FAILURES = 5
MAX_FAILURES_PER_IP = 30
# Quá số khoá này thì quét bỏ khoá đã hết hạn (khoá chỉ tự dọn khi chính nó được chạm lại).
SWEEP_AT_KEYS = 10_000
FAILURE_WINDOW_SECONDS = 15 * 60

_hasher = PasswordHasher()
# Băm sẵn để email không tồn tại vẫn tốn thời gian verify như email có thật (không lộ email nào có).
_DUMMY_HASH = _hasher.hash(secrets.token_urlsafe(16))


def hash_password(password: str) -> str:
    return _hasher.hash(password)


def verify_password(password_hash: str, password: str) -> bool:
    try:
        return _hasher.verify(password_hash, password)
    except (VerifyMismatchError, VerificationError, InvalidHashError):
        return False


def token_digest(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def normalize_email(email: str) -> str:
    return email.strip().lower()


def _now() -> datetime:
    return datetime.now(timezone.utc)


class LoginThrottle:
    """Đếm login sai theo khoá (IP, email) trong cửa sổ trượt."""

    def __init__(self, max_failures: int = MAX_FAILURES, window: float = FAILURE_WINDOW_SECONDS):
        self.max_failures = max_failures
        self.window = window
        self._failures: dict[tuple[str, str], list[float]] = {}
        self._lock = threading.Lock()

    def _recent(self, key: tuple[str, str], now: float) -> list[float]:
        recent = [t for t in self._failures.get(key, []) if now - t < self.window]
        if recent:
            self._failures[key] = recent
        else:
            self._failures.pop(key, None)
        return recent

    def attempt(self, key: tuple[str, str]) -> bool:
        """Giữ chỗ một lần thử TRƯỚC khi verify (tính như thất bại). Hết lượt → False.

        Check-rồi-ghi trong cùng một lock: N request song song không cùng lọt qua trước khi ai kịp
        ghi thất bại. Thử đúng thì gọi `reset`/`release` để trả lại chỗ.
        """
        with self._lock:
            now = time.monotonic()
            recent = self._recent(key, now)
            if len(recent) >= self.max_failures:
                return False
            self._failures[key] = [*recent, now]
            if len(self._failures) > SWEEP_AT_KEYS:
                for k in list(self._failures):
                    self._recent(k, now)
            return True

    def release(self, key: tuple[str, str]) -> None:
        """Trả lại chỗ của lần thử gần nhất (thử đúng)."""
        with self._lock:
            times = self._failures.get(key)
            if times:
                times.pop()
                if not times:
                    self._failures.pop(key, None)

    def reset(self, key: tuple[str, str]) -> None:
        with self._lock:
            self._failures.pop(key, None)


throttle = LoginThrottle()
ip_throttle = LoginThrottle(max_failures=MAX_FAILURES_PER_IP)


@dataclass(frozen=True)
class CurrentUser:
    id: int
    email: str
    roles: tuple[str, ...]
    session_id: int

    @property
    def is_admin(self) -> bool:
        return "admin" in self.roles


def _bearer(request: Request) -> str | None:
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token.strip():
        return None
    return token.strip()


def user_for_token(session: Session, token: str) -> CurrentUser | None:
    row = session.execute(
        select(UserSession.id, User.id, User.email, User.roles)
        .join(User, User.id == UserSession.user_id)
        .where(UserSession.token_hash == token_digest(token), UserSession.expires_at > _now())
    ).first()
    if row is None:
        return None
    session_id, user_id, email, roles = row
    return CurrentUser(id=user_id, email=email, roles=tuple(roles), session_id=session_id)


def _unauthorized() -> HTTPException:
    # Mỗi lần một instance mới: raise lại một instance dùng chung làm traceback của nó dài mãi.
    return HTTPException(status_code=401, detail="not_authenticated", headers={"WWW-Authenticate": "Bearer"})


def current_user(request: Request, session: Session = Depends(get_session)) -> CurrentUser:
    token = _bearer(request)
    user = user_for_token(session, token) if token else None
    if user is None:
        raise _unauthorized()
    return user


def require_admin(user: CurrentUser = Depends(current_user)) -> CurrentUser:
    if not user.is_admin:
        raise HTTPException(status_code=403, detail="admin_required")
    return user


UserLookup = Callable[[str], "CurrentUser | None"]


def get_user_lookup() -> UserLookup:
    """Cho `/run`: tra user bằng session DB ngắn, trả kết nối ngay (không giữ trong lúc chờ máy chấm)."""

    def lookup(token: str) -> CurrentUser | None:
        with SessionLocal() as session:
            return user_for_token(session, token)

    return lookup


def optional_bearer(request: Request) -> str | None:
    return _bearer(request)


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=254)
    password: str = Field(min_length=1, max_length=256)


class UserOut(BaseModel):
    email: str
    roles: list[str]


class LoginResponse(BaseModel):
    token: str
    user: UserOut


class PasswordChange(BaseModel):
    current_password: str = Field(min_length=1, max_length=256)
    new_password: str = Field(min_length=1, max_length=256)


def _client_ip(request: Request) -> str:
    # uvicorn chạy --proxy-headers sau nginx: request.client là IP thật của người dùng.
    return request.client.host if request.client else "unknown"


def create_session(session: Session, user_id: int) -> str:
    token = secrets.token_urlsafe(32)
    session.add(UserSession(token_hash=token_digest(token), user_id=user_id, expires_at=_now() + SESSION_TTL))
    return token


@router.post("/auth/login", response_model=LoginResponse)
def login(body: LoginRequest, request: Request, session: Session = Depends(get_session)) -> LoginResponse:
    email = normalize_email(body.email)
    ip = _client_ip(request)
    key, ip_key = (ip, email), (ip, "*")
    if not ip_throttle.attempt(ip_key):
        raise HTTPException(status_code=429, detail="too_many_attempts")
    if not throttle.attempt(key):
        ip_throttle.release(ip_key)
        raise HTTPException(status_code=429, detail="too_many_attempts")
    # FOR UPDATE: đổi mật khẩu đồng thời phải xong trước (hoặc chờ login này xong) — không để login
    # bằng mật khẩu cũ tạo phiên mới SAU khi đổi mật khẩu đã thu hồi các phiên.
    user = session.scalar(select(User).where(User.email == email).with_for_update())
    ok = verify_password(user.password_hash if user else _DUMMY_HASH, body.password)
    if user is None or not ok:
        raise HTTPException(status_code=401, detail="invalid_credentials")
    throttle.reset(key)
    ip_throttle.release(ip_key)
    if _hasher.check_needs_rehash(user.password_hash):
        user.password_hash = hash_password(body.password)
    session.execute(delete(UserSession).where(UserSession.user_id == user.id, UserSession.expires_at <= _now()))
    token = create_session(session, user.id)
    session.commit()
    return LoginResponse(token=token, user=UserOut(email=user.email, roles=list(user.roles)))


@router.post("/auth/logout", status_code=204)
def logout(user: CurrentUser = Depends(current_user), session: Session = Depends(get_session)) -> Response:
    session.execute(delete(UserSession).where(UserSession.id == user.session_id))
    session.commit()
    return Response(status_code=204)


@router.get("/me", response_model=UserOut)
def me(user: CurrentUser = Depends(current_user)) -> UserOut:
    return UserOut(email=user.email, roles=list(user.roles))


@router.post("/auth/password", status_code=204)
def change_password(
    body: PasswordChange,
    request: Request,
    user: CurrentUser = Depends(current_user),
    session: Session = Depends(get_session),
) -> Response:
    # Token lọt (vd XSS) không được thành công cụ dò mật khẩu không giới hạn.
    key = (_client_ip(request), f"pw:{user.id}")
    if not throttle.attempt(key):
        raise HTTPException(status_code=429, detail="too_many_attempts")
    row = session.get(User, user.id, with_for_update=True)
    if row is None or not verify_password(row.password_hash, body.current_password):
        raise HTTPException(status_code=401, detail="wrong_password")
    throttle.reset(key)
    if len(body.new_password) < MIN_PASSWORD_LENGTH:
        raise HTTPException(status_code=400, detail="weak_password")
    row.password_hash = hash_password(body.new_password)
    # Đổi mật khẩu thì đăng xuất mọi thiết bị khác, giữ phiên hiện tại.
    session.execute(delete(UserSession).where(UserSession.user_id == user.id, UserSession.id != user.session_id))
    session.commit()
    return Response(status_code=204)
