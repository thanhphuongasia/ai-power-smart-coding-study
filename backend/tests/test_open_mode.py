"""Chế độ mở (AUTH_OPEN_AS): không token → coi là user mở; token thật thắng; tắt cờ → như cũ (INV-01..04)."""

from __future__ import annotations

import pytest

from app.tables import UserProgress
from tests.test_auth import PASSWORD, add_user, bearer, client_for, fresh_throttle, login  # noqa: F401

OPEN = "test@gmail.com"
ADMIN = "phuongtt.tech1508@gmail.com"


@pytest.fixture()
def open_mode(monkeypatch):
    monkeypatch.setenv("AUTH_OPEN_AS", OPEN)


def test_flag_off_keeps_401(db_session, client_for, monkeypatch):
    monkeypatch.delenv("AUTH_OPEN_AS", raising=False)
    add_user(db_session, email=OPEN, roles=("learner", "admin"))
    client = client_for(db_session)
    assert client.get("/api/me").status_code == 401
    assert client.get("/api/progress").status_code == 401
    assert client.get("/api/admin/content").status_code == 401


def test_open_email_missing_in_db_keeps_401(db_session, client_for, monkeypatch):
    monkeypatch.setenv("AUTH_OPEN_AS", "nobody@example.com")
    assert client_for(db_session).get("/api/me").status_code == 401


def test_no_token_is_the_open_user(db_session, client_for, open_mode):
    add_user(db_session, email=OPEN, roles=("learner", "admin"))
    client = client_for(db_session)
    r = client.get("/api/me")
    assert r.status_code == 200
    assert r.json() == {"email": OPEN, "roles": ["learner", "admin"], "open": True}
    # Token rác cũng rơi về user mở (không 401 → app không bị đá ra).
    assert client.get("/api/me", headers=bearer("forged")).json()["open"] is True


def test_real_token_wins_over_open_user(db_session, client_for, open_mode):
    add_user(db_session, email=OPEN, roles=("learner", "admin"))
    add_user(db_session, email=ADMIN, roles=("learner", "admin"))
    client = client_for(db_session)
    token = login(client, email=ADMIN).json()["token"]
    r = client.get("/api/me", headers=bearer(token)).json()
    assert r == {"email": ADMIN, "roles": ["learner", "admin"], "open": False}


def test_open_user_progress_and_run_are_recorded(loaded_session, content_data, client_for, open_mode):
    user = add_user(loaded_session, email=OPEN, roles=("learner", "admin"))
    client = client_for(loaded_session)
    body = {"drafts": {"A": "x"}, "hints_used": {}, "solution_viewed": []}
    assert client.put("/api/progress/split-chunks", json=body).status_code == 204
    code = content_data["exercises"]["split-chunks"]["judge"]["solution"]
    assert client.post("/run", json={"exercise_id": "split-chunks", "code": code}).json()["status"] == "passed"
    row = loaded_session.get(UserProgress, (user.id, "split-chunks"))
    assert row.passed is True and row.drafts == {"A": "x"}
    assert client.get("/api/progress").json()["exercises"]["split-chunks"]["passed"] is True


def test_open_user_admin_follows_roles(db_session, client_for, open_mode):
    add_user(db_session, email=OPEN, roles=("learner",))
    assert client_for(db_session).get("/api/admin/content").status_code == 403


def test_logout_in_open_mode_is_harmless(db_session, client_for, open_mode):
    add_user(db_session, email=OPEN, roles=("learner", "admin"))
    client = client_for(db_session)
    real = login(client, email=OPEN).json()["token"]
    assert client.post("/api/auth/logout").status_code == 204  # phiên ảo: không xoá gì
    assert client.get("/api/me", headers=bearer(real)).json()["open"] is False  # phiên thật còn


def test_change_password_refused_in_open_mode_keeps_real_sessions(db_session, client_for, open_mode):
    add_user(db_session, email=OPEN, roles=("learner", "admin"))
    client = client_for(db_session)
    real = login(client, email=OPEN).json()["token"]
    body = {"current_password": PASSWORD, "new_password": "new-password-123"}
    r = client.post("/api/auth/password", json=body)
    assert r.status_code == 403 and r.json() == {"detail": "open_mode"}
    assert client.get("/api/me", headers=bearer(real)).json()["open"] is False
