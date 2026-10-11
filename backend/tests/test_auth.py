"""Đăng nhập, token, phân quyền, và `/run` ghi passed cho user đã đăng nhập."""

from __future__ import annotations

import copy
import subprocess
import sys
from datetime import datetime, timedelta, timezone

import pytest
from fastapi import Depends, FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import select

from app import auth
from app.auth import CurrentUser, LoginThrottle, hash_password, require_admin, token_digest, user_for_token
from app.content_api import get_judge_lookup, read_judge
from app.db import get_session
from app.load_content import load_content
from app.main import app, get_runner
from app.progress import get_pass_recorder, record_pass
from app.runner import Execution
from app.tables import User, UserProgress, UserSession

PASSWORD = "correct-horse-battery"


class LocalRunner:
    async def run(self, source: str, stdin: str) -> Execution:
        proc = subprocess.run([sys.executable, "-c", source], input=stdin, capture_output=True, text=True, timeout=5)
        return Execution("ok" if proc.returncode == 0 else "error", proc.stdout, proc.stderr)


@pytest.fixture(autouse=True)
def fresh_throttle(monkeypatch):
    monkeypatch.setattr(auth, "throttle", LoginThrottle())


@pytest.fixture()
def client_for():
    def make(session) -> TestClient:
        app.dependency_overrides[get_session] = lambda: session
        app.dependency_overrides[get_judge_lookup] = lambda: (lambda i: read_judge(session, i))
        app.dependency_overrides[get_runner] = lambda: LocalRunner()
        app.dependency_overrides[auth.get_user_lookup] = lambda: (lambda t: user_for_token(session, t))
        app.dependency_overrides[get_pass_recorder] = lambda: (lambda uid, ex: record_pass(session, uid, ex))
        return TestClient(app)

    yield make
    app.dependency_overrides.clear()


def add_user(session, email="test@gmail.com", roles=("learner",), password=PASSWORD) -> User:
    user = User(email=email, password_hash=hash_password(password), roles=list(roles))
    session.add(user)
    session.flush()
    return user


def login(client, email="test@gmail.com", password=PASSWORD):
    return client.post("/api/auth/login", json={"email": email, "password": password})


def bearer(token: str) -> dict:
    return {"Authorization": f"Bearer {token}"}


def test_password_stored_hashed_and_token_stored_as_digest(db_session, client_for):
    user = add_user(db_session)
    assert PASSWORD not in user.password_hash and user.password_hash.startswith("$argon2id$")
    r = login(client_for(db_session))
    assert r.status_code == 200
    token = r.json()["token"]
    stored = db_session.scalars(select(UserSession.token_hash).where(UserSession.user_id == user.id)).all()
    assert stored == [token_digest(token)] and token not in stored


def test_login_ok_returns_token_and_roles_email_case_insensitive(db_session, client_for):
    add_user(db_session, email="phuongtt.tech1508@gmail.com", roles=("learner", "admin"))
    r = login(client_for(db_session), email="  PhuongTT.Tech1508@Gmail.com ")
    assert r.status_code == 200
    assert r.json()["user"] == {"email": "phuongtt.tech1508@gmail.com", "roles": ["learner", "admin"]}


@pytest.mark.parametrize("email,password", [("test@gmail.com", "wrong-password"), ("nobody@gmail.com", PASSWORD)])
def test_login_wrong_password_or_unknown_email_same_401(db_session, client_for, email, password):
    add_user(db_session)
    r = login(client_for(db_session), email=email, password=password)
    assert r.status_code == 401 and r.json() == {"detail": "invalid_credentials"}


def test_login_throttled_after_5_failures_even_with_right_password(db_session, client_for):
    add_user(db_session)
    client = client_for(db_session)
    for _ in range(5):
        assert login(client, password="nope").status_code == 401
    r = login(client)
    assert r.status_code == 429 and r.json() == {"detail": "too_many_attempts"}


def test_me_requires_valid_token(db_session, client_for):
    add_user(db_session)
    client = client_for(db_session)
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/me", headers=bearer("forged")).status_code == 401
    assert client.get("/api/me", headers={"Authorization": "Basic abc"}).status_code == 401
    token = login(client).json()["token"]
    assert client.get("/api/me", headers=bearer(token)).json() == {"email": "test@gmail.com", "roles": ["learner"]}


def test_expired_session_is_401(db_session, client_for):
    add_user(db_session)
    client = client_for(db_session)
    token = login(client).json()["token"]
    row = db_session.scalar(select(UserSession).where(UserSession.token_hash == token_digest(token)))
    row.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
    db_session.flush()
    assert client.get("/api/me", headers=bearer(token)).status_code == 401


def test_logout_revokes_only_that_token(db_session, client_for):
    add_user(db_session)
    client = client_for(db_session)
    t1 = login(client).json()["token"]
    t2 = login(client).json()["token"]
    assert client.post("/api/auth/logout", headers=bearer(t1)).status_code == 204
    assert client.get("/api/me", headers=bearer(t1)).status_code == 401
    assert client.get("/api/me", headers=bearer(t2)).status_code == 200


def test_change_password_rules_and_revokes_other_sessions(db_session, client_for):
    add_user(db_session)
    client = client_for(db_session)
    t1 = login(client).json()["token"]
    t2 = login(client).json()["token"]
    body = {"current_password": "wrong", "new_password": "new-password-123"}
    assert client.post("/api/auth/password", json=body, headers=bearer(t1)).status_code == 401
    body = {"current_password": PASSWORD, "new_password": "short"}
    r = client.post("/api/auth/password", json=body, headers=bearer(t1))
    assert r.status_code == 400 and r.json() == {"detail": "weak_password"}
    body = {"current_password": PASSWORD, "new_password": "new-password-123"}
    assert client.post("/api/auth/password", json=body, headers=bearer(t1)).status_code == 204
    assert client.get("/api/me", headers=bearer(t1)).status_code == 200  # phiên hiện tại giữ
    assert client.get("/api/me", headers=bearer(t2)).status_code == 401  # phiên khác bị thu hồi
    assert login(client).status_code == 401
    assert login(client, password="new-password-123").status_code == 200


def test_require_admin_403_for_learner_200_for_admin(db_session):
    probe = FastAPI()

    @probe.get("/admin-only")
    def admin_only(user: CurrentUser = Depends(require_admin)) -> dict:
        return {"email": user.email}

    probe.dependency_overrides[get_session] = lambda: db_session
    add_user(db_session, email="test@gmail.com", roles=("learner",))
    add_user(db_session, email="phuongtt.tech1508@gmail.com", roles=("learner", "admin"))
    from app.auth import create_session

    learner = create_session(db_session, db_session.scalar(select(User.id).where(User.email == "test@gmail.com")))
    admin = create_session(
        db_session, db_session.scalar(select(User.id).where(User.email == "phuongtt.tech1508@gmail.com"))
    )
    db_session.flush()
    client = TestClient(probe)
    assert client.get("/admin-only").status_code == 401
    assert client.get("/admin-only", headers=bearer(learner)).status_code == 403
    assert client.get("/admin-only", headers=bearer(admin)).json() == {"email": "phuongtt.tech1508@gmail.com"}


def _solution(content_data, exercise_id):
    return content_data["exercises"][exercise_id]["judge"]["solution"]


def test_run_records_passed_only_for_logged_in_user_and_only_when_passed(loaded_session, content_data, client_for):
    user = add_user(loaded_session)
    client = client_for(loaded_session)
    token = login(client).json()["token"]
    code = _solution(content_data, "split-chunks")

    # Code sai: không ghi passed.
    r = client.post("/run", json={"exercise_id": "split-chunks", "code": "def split_chunks(t, s):\n    return []"},
                    headers=bearer(token))
    assert r.json()["status"] == "failed"
    assert loaded_session.get(UserProgress, (user.id, "split-chunks")) is None

    # Khách (không token) chạy đúng: vẫn chấm, không ghi gì.
    assert client.post("/run", json={"exercise_id": "split-chunks", "code": code}).json()["status"] == "passed"
    assert loaded_session.get(UserProgress, (user.id, "split-chunks")) is None

    # Token giả: vẫn chấm như khách, không 401 (app không bị đăng xuất vì Run).
    r = client.post("/run", json={"exercise_id": "split-chunks", "code": code}, headers=bearer("forged"))
    assert r.status_code == 200 and r.json()["status"] == "passed"

    r = client.post("/run", json={"exercise_id": "split-chunks", "code": code}, headers=bearer(token))
    assert r.json()["status"] == "passed"
    assert loaded_session.get(UserProgress, (user.id, "split-chunks")).passed is True


def test_progress_survives_content_reload(loaded_session, content_data):
    """INV-04: nạp lại nội dung (xoá-rồi-ghi) không đụng tiến độ."""
    user = add_user(loaded_session)
    record_pass(loaded_session, user.id, "split-chunks")
    load_content(loaded_session, copy.deepcopy(content_data))
    assert loaded_session.get(UserProgress, (user.id, "split-chunks")).passed is True


def test_record_pass_keeps_existing_drafts(loaded_session):
    user = add_user(loaded_session)
    loaded_session.add(UserProgress(user_id=user.id, exercise_id="split-chunks", passed=False,
                                    drafts={"A": "x"}, hints_used={"A": 1}, solution_viewed=[]))
    loaded_session.flush()
    record_pass(loaded_session, user.id, "split-chunks")
    loaded_session.expire_all()
    row = loaded_session.get(UserProgress, (user.id, "split-chunks"))
    assert (row.passed, row.drafts, row.hints_used) == (True, {"A": "x"}, {"A": 1})
