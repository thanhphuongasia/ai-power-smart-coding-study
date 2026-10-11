"""seed_users: idempotent, mật khẩu chỉ ở file 600 (INV-03), không bao giờ ra stdout."""

from __future__ import annotations

import stat

from sqlalchemy import select

from app import seed_users as seed_module
from app.auth import verify_password
from app.seed_users import seed_users
from app.tables import User


def _lines(path):
    return [ln.split("\t") for ln in path.read_text(encoding="utf-8").splitlines()]


def test_creates_both_users_with_roles_and_private_file(db_session, tmp_path):
    path = tmp_path / "secret" / "initial-passwords"
    assert seed_users(db_session, path) == 2
    users = {u.email: u for u in db_session.scalars(select(User))}
    assert users["test@gmail.com"].roles == ["learner", "admin"]
    assert users["phuongtt.tech1508@gmail.com"].roles == ["learner", "admin"]
    assert stat.S_IMODE(path.stat().st_mode) == 0o600
    assert stat.S_IMODE(path.parent.stat().st_mode) == 0o700
    rows = _lines(path)
    assert [r[1] for r in rows] == ["test@gmail.com", "phuongtt.tech1508@gmail.com"]
    for _, email, password in rows:
        assert len(password) >= 10
        assert password not in users[email].password_hash
        assert verify_password(users[email].password_hash, password)


def test_rerun_creates_nothing_and_keeps_passwords(db_session, tmp_path):
    path = tmp_path / "pw"
    seed_users(db_session, path)
    before = {u.email: u.password_hash for u in db_session.scalars(select(User))}
    assert seed_users(db_session, path) == 0
    after = {u.email: u.password_hash for u in db_session.scalars(select(User))}
    assert before == after
    assert len(_lines(path)) == 2  # không append thêm


def test_existing_user_gets_missing_role_not_new_password(db_session, tmp_path):
    db_session.add(User(email="phuongtt.tech1508@gmail.com", password_hash="$argon2id$x", roles=["learner"]))
    db_session.flush()
    assert seed_users(db_session, tmp_path / "pw") == 1  # chỉ test@gmail.com mới
    u = db_session.scalar(select(User).where(User.email == "phuongtt.tech1508@gmail.com"))
    assert u.roles == ["learner", "admin"] and u.password_hash == "$argon2id$x"


def test_loose_permissions_on_existing_file_are_tightened(db_session, tmp_path):
    path = tmp_path / "pw"
    path.write_text("")
    path.chmod(0o644)
    seed_users(db_session, path)
    assert stat.S_IMODE(path.stat().st_mode) == 0o600


def test_main_prints_count_never_password(db_session, tmp_path, monkeypatch, capsys):
    path = tmp_path / "pw"
    monkeypatch.setenv("INITIAL_PASSWORDS_FILE", str(path))

    class _Ctx:
        def __enter__(self):
            return db_session

        def __exit__(self, *exc):
            return False

    monkeypatch.setattr("app.db.SessionLocal", lambda: _Ctx())
    monkeypatch.setattr(db_session, "commit", lambda: None)
    assert seed_module.main() == 0
    out = capsys.readouterr()
    assert "created 2 user(s)" in out.out
    for _, _, password in _lines(path):
        assert password not in out.out and password not in out.err


def test_password_file_write_failure_means_no_commit(db_session, tmp_path, monkeypatch):
    """Ghi file lỗi → main() ném lỗi TRƯỚC commit: không có tài khoản nào mà không ai biết mật khẩu."""
    monkeypatch.setenv("INITIAL_PASSWORDS_FILE", str(tmp_path / "pw"))
    commits = []

    class _Ctx:
        def __enter__(self):
            return db_session

        def __exit__(self, *exc):
            return False

    def boom(path, lines):
        raise OSError("disk full")

    monkeypatch.setattr("app.db.SessionLocal", lambda: _Ctx())
    monkeypatch.setattr(db_session, "commit", lambda: commits.append(1))
    monkeypatch.setattr(seed_module, "_append_private", boom)
    import pytest

    with pytest.raises(OSError):
        seed_module.main()
    assert commits == []


def test_symlinked_password_file_is_refused(db_session, tmp_path):
    target = tmp_path / "elsewhere"
    target.write_text("")
    link = tmp_path / "pw"
    link.symlink_to(target)
    import pytest

    with pytest.raises(OSError):
        seed_users(db_session, link)
    assert target.read_text() == ""


def test_set_password_changes_hash_and_revokes_sessions(db_session, tmp_path):
    from app.auth import create_session, user_for_token
    from app.set_password import set_password

    seed_users(db_session, tmp_path / "pw")
    user = db_session.scalar(select(User).where(User.email == "test@gmail.com"))
    token = create_session(db_session, user.id)
    db_session.flush()
    assert set_password(db_session, " Test@Gmail.com ", "new-pass-123") is True
    db_session.flush()
    assert verify_password(user.password_hash, "new-pass-123")
    assert user_for_token(db_session, token) is None
    assert set_password(db_session, "nobody@x.com", "x") is False


def test_set_password_cli_never_takes_password_in_argv(capsys):
    from app.set_password import main

    assert main(["set_password"]) == 2
    assert main(["set_password", "a@b.c", "secret"]) == 2
