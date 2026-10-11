"""Đặt lại mật khẩu cho một user (việc của người vận hành, chạy trên server). Mật khẩu gõ qua prompt ẩn
— không nằm trong argv, lịch sử shell hay log.

    python -m app.set_password <email>

Đặt xong thì thu hồi mọi phiên đăng nhập cũ của user đó. Ngắn hơn MIN_PASSWORD_LENGTH vẫn cho đặt
(người vận hành tự chọn, vd tài khoản test) nhưng in cảnh báo; màn Đổi mật khẩu trong app vẫn bắt ≥ 10.
"""

from __future__ import annotations

import getpass
import sys

from sqlalchemy import delete, select
from sqlalchemy.orm import Session

from app.auth import MIN_PASSWORD_LENGTH, hash_password, normalize_email
from app.tables import User, UserSession


def set_password(session: Session, email: str, password: str) -> bool:
    """Đổi hash + xoá mọi phiên của user. False nếu không có user. Không commit."""
    user = session.scalar(select(User).where(User.email == normalize_email(email)))
    if user is None:
        return False
    user.password_hash = hash_password(password)
    session.execute(delete(UserSession).where(UserSession.user_id == user.id))
    return True


def main(argv: list[str]) -> int:
    from app.db import SessionLocal

    if len(argv) != 2:
        print("usage: python -m app.set_password <email>", file=sys.stderr)
        return 2
    password = getpass.getpass("Mật khẩu mới: ")
    if not password or password != getpass.getpass("Nhập lại: "):
        print("không khớp hoặc rỗng — không đổi gì", file=sys.stderr)
        return 1
    if len(password) < MIN_PASSWORD_LENGTH:
        print(f"cảnh báo: mật khẩu ngắn hơn {MIN_PASSWORD_LENGTH} ký tự", file=sys.stderr)
    with SessionLocal() as session:
        if not set_password(session, argv[1], password):
            print("không có user này", file=sys.stderr)
            return 1
        session.commit()
    print(f"đã đặt mật khẩu cho {normalize_email(argv[1])} (đã đăng xuất mọi phiên cũ)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
