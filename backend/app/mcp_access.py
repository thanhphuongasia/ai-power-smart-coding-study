"""Cấp/thu hồi quyền sửa nội dung qua `/mcp` cho một tài khoản identity-service (`sub` của JWT).

Dùng chung cho CLI (module này) và admin API. Kiểm quyền lúc gọi tool nằm ở `mcp_auth.authorize_sub`.

    python -m app.mcp_access list
    python -m app.mcp_access allow <sub> --as <email-admin> [--label <text>]
    python -m app.mcp_access revoke <sub>
"""

from __future__ import annotations

import argparse
import sys
from datetime import datetime, timezone

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.auth import normalize_email
from app.tables import McpAccess, User

MAX_SUB_LENGTH = 100
MAX_LABEL_LENGTH = 200


def _iso(value: datetime | None) -> str | None:
    return value.isoformat() if value is not None else None


def _item(row: McpAccess, email: str) -> dict:
    return {
        "sub": row.sub,
        "email": email,
        "label": row.label,
        "created_at": _iso(row.created_at),
        "revoked_at": _iso(row.revoked_at),
    }


def list_access(session: Session) -> list[dict]:
    rows = session.execute(
        select(McpAccess, User.email)
        .join(User, User.id == McpAccess.user_id)
        .order_by(McpAccess.created_at, McpAccess.sub)
    ).all()
    return [_item(row, email) for row, email in rows]


def allow(session: Session, sub: str, email: str, label: str = "") -> dict:
    """Cấp (hoặc cấp lại) quyền cho `sub`, hành động thay mặt admin `email`. Không commit.

    `ValueError` (thông điệp tiếng Việt, hiện được cho người dùng) nếu sub/label sai hoặc email
    không phải admin đang tồn tại.
    """
    sub = sub.strip() if isinstance(sub, str) else ""
    if not sub or len(sub) > MAX_SUB_LENGTH:
        raise ValueError(f"sub phải dài 1..{MAX_SUB_LENGTH} ký tự")
    if any(ch.isspace() for ch in sub):
        raise ValueError("sub không được chứa khoảng trắng")
    label = (label or "").strip()
    if len(label) > MAX_LABEL_LENGTH:
        raise ValueError(f"label tối đa {MAX_LABEL_LENGTH} ký tự")
    user = session.scalar(select(User).where(User.email == normalize_email(email)))
    if user is None:
        raise ValueError("không có user với email này")
    if "admin" not in user.roles:
        raise ValueError("user này không phải admin — chỉ admin mới được cấp quyền MCP")
    row = session.get(McpAccess, sub)
    if row is None:
        row = McpAccess(sub=sub, user_id=user.id, label=label)
        session.add(row)
    else:
        row.user_id = user.id
        row.label = label
        row.revoked_at = None
    session.flush()
    session.refresh(row)  # lấy created_at do DB đặt
    return _item(row, user.email)


def revoke(session: Session, sub: str) -> bool:
    """Thu hồi nếu đang hiệu lực; False nếu không có / đã thu hồi. Không commit."""
    row = session.get(McpAccess, sub.strip()) if isinstance(sub, str) else None
    if row is None or row.revoked_at is not None:
        return False
    row.revoked_at = datetime.now(timezone.utc)
    session.flush()
    return True


def _line(item: dict) -> str:
    state = f"đã thu hồi {item['revoked_at']}" if item["revoked_at"] else "hiệu lực"
    label = f" [{item['label']}]" if item["label"] else ""
    return f"{item['sub']} -> {item['email']}{label} ({state})"


def main(argv: list[str]) -> int:
    """`argv` không gồm tên chương trình. Trả exit code."""
    from app import db  # tra cứu lúc gọi để test thay được SessionLocal

    parser = argparse.ArgumentParser(prog="python -m app.mcp_access")
    sub_parsers = parser.add_subparsers(dest="cmd", required=True)
    sub_parsers.add_parser("list")
    p_allow = sub_parsers.add_parser("allow")
    p_allow.add_argument("sub")
    p_allow.add_argument("--as", dest="email", required=True)
    p_allow.add_argument("--label", default="")
    p_revoke = sub_parsers.add_parser("revoke")
    p_revoke.add_argument("sub")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:  # argparse tự in usage ra stderr
        return exc.code if isinstance(exc.code, int) else 2

    with db.SessionLocal() as session:
        if args.cmd == "list":
            for item in list_access(session):
                print(_line(item))
            return 0
        if args.cmd == "allow":
            try:
                item = allow(session, args.sub, args.email, args.label)
            except ValueError as exc:
                print(str(exc), file=sys.stderr)
                return 1
            session.commit()
            print("đã cấp: " + _line(item))
            return 0
        if not revoke(session, args.sub):
            print("không có quyền đang hiệu lực cho sub này", file=sys.stderr)
            return 1
        session.commit()
        print(f"đã thu hồi: {args.sub.strip()}")
        return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
