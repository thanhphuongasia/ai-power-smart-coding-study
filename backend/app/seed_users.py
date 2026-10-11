"""Tạo tài khoản ban đầu (idempotent). Mật khẩu ngẫu nhiên, KHÔNG BAO GIỜ in ra stdout/log.

    INITIAL_PASSWORDS_FILE=/etc/smart-coding-study/initial-passwords python -m app.seed_users

- User chưa có → tạo với mật khẩu ngẫu nhiên; dòng `<thời điểm>\\t<email>\\t<mật khẩu>` được APPEND
  vào INITIAL_PASSWORDS_FILE (quyền 600, thư mục 700). Người dùng tự đọc file đó rồi đổi mật khẩu.
- User đã có → không đổi mật khẩu; chỉ thêm role còn thiếu.
- Ghi file TRƯỚC khi commit: commit lỗi thì file thừa vài dòng vô hại; ngược lại (commit xong mà ghi file
  lỗi) sẽ ra tài khoản không ai biết mật khẩu.
- Mặc định (máy dev): `backend/.initial-passwords` — đã gitignore, deploy không rsync file này.
"""

from __future__ import annotations

import os
import secrets
import sys
from datetime import datetime, timezone
from pathlib import Path

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import hash_password, normalize_email
from app.tables import User

SEED_USERS: list[tuple[str, tuple[str, ...]]] = [
    ("test@gmail.com", ("learner",)),
    ("phuongtt.tech1508@gmail.com", ("learner", "admin")),
]
DEFAULT_FILE = Path(__file__).resolve().parent.parent / ".initial-passwords"


def _append_private(path: Path, lines: list[str]) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    try:
        os.fchmod(fd, 0o600)  # file có sẵn với quyền rộng hơn → siết lại
        os.write(fd, "".join(lines).encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)


def seed_users(session: Session, path: Path, users=SEED_USERS) -> int:
    """Tạo user còn thiếu. Trả số user mới tạo. Không commit — caller commit sau khi hàm trả về."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    lines: list[str] = []
    for raw_email, roles in users:
        email = normalize_email(raw_email)
        user = session.scalar(select(User).where(User.email == email))
        if user is None:
            password = secrets.token_urlsafe(12)  # 16 ký tự ≥ MIN_PASSWORD_LENGTH
            session.add(User(email=email, password_hash=hash_password(password), roles=list(roles)))
            lines.append(f"{now}\t{email}\t{password}\n")
        else:
            missing = [r for r in roles if r not in user.roles]
            if missing:
                user.roles = [*user.roles, *missing]
    session.flush()
    if lines:
        _append_private(path, lines)
    return len(lines)


def main() -> int:
    from app.db import SessionLocal

    path = Path(os.environ.get("INITIAL_PASSWORDS_FILE") or DEFAULT_FILE)
    with SessionLocal() as session:
        created = seed_users(session, path)
        session.commit()
    # Chỉ in số lượng + chỗ lấy mật khẩu; không in mật khẩu.
    print(f"created {created} user(s)" + (f"; initial passwords appended to {path}" if created else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
