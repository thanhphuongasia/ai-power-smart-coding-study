"""Cấp/thu hồi quyền `/mcp`: API chỉ admin, hiệu lực qua `authorize_sub` (INV-04), CLI không chạm DB thật."""

from __future__ import annotations

import contextlib

import pytest

from app import db, mcp_access
from app.mcp_auth import authorize_sub
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401

ADMIN = "admin@gmail.com"
SUB = "7f1c2a9e-0000-4000-8000-000000000001"
URL = "/api/admin/mcp-access"


@pytest.fixture()
def admin(db_session, client_for):
    add_user(db_session, email=ADMIN, roles=("learner", "admin"))
    client = client_for(db_session)
    return client, bearer(login(client, email=ADMIN).json()["token"])


@pytest.mark.parametrize("roles", [None, ("learner",)])
def test_endpoints_need_admin(db_session, client_for, roles):
    client = client_for(db_session)
    headers = {}
    if roles:
        add_user(db_session, roles=roles)
        headers = bearer(login(client).json()["token"])
    expected = 403 if roles else 401
    assert client.get(URL, headers=headers).status_code == expected
    assert client.post(URL, json={"sub": SUB, "email": ADMIN}, headers=headers).status_code == expected
    assert client.delete(f"{URL}/{SUB}", headers=headers).status_code == expected


@pytest.mark.parametrize("email", ["nobody@gmail.com", "learner@gmail.com"])
def test_allow_rejects_non_admin_or_unknown_email(admin, db_session, email):
    client, h = admin
    add_user(db_session, email="learner@gmail.com")
    r = client.post(URL, json={"sub": SUB, "email": email}, headers=h)
    assert r.status_code == 422 and r.json()["errors"]
    assert authorize_sub(db_session, SUB) is None


@pytest.mark.parametrize("sub", ["", "   ", "x" * 101, "a b"])
def test_allow_rejects_bad_sub(admin, sub):
    client, h = admin
    r = client.post(URL, json={"sub": sub, "email": ADMIN}, headers=h)
    assert r.status_code == 422 and r.json()["errors"]


def test_allow_rejects_bad_body(admin):
    client, h = admin
    assert client.post(URL, json={"sub": SUB, "email": ADMIN, "x": 1}, headers=h).status_code == 422
    assert client.post(URL, json={"sub": 5, "email": ADMIN}, headers=h).status_code == 422
    assert client.post(URL, content=b"nope", headers=h).status_code == 422


def test_allow_revoke_regrant_cycle(admin, db_session):
    client, h = admin
    r = client.post(URL, json={"sub": f" {SUB} ", "email": ADMIN.upper(), "label": "claude.ai"}, headers=h)
    assert r.status_code == 200
    item = r.json()["item"]
    assert item["sub"] == SUB and item["email"] == ADMIN and item["label"] == "claude.ai"
    assert item["revoked_at"] is None and item["created_at"]
    assert authorize_sub(db_session, SUB).email == ADMIN

    assert client.delete(f"{URL}/{SUB}", headers=h).status_code == 204
    assert authorize_sub(db_session, SUB) is None  # INV-04: thu hồi có hiệu lực ngay

    listed = client.get(URL, headers=h).json()["items"]
    assert [i["sub"] for i in listed] == [SUB] and listed[0]["revoked_at"]

    again = client.post(URL, json={"sub": SUB, "email": ADMIN}, headers=h)
    assert again.status_code == 200 and again.json()["item"]["revoked_at"] is None
    assert authorize_sub(db_session, SUB) is not None


def test_delete_twice_or_unknown_is_404(admin):
    client, h = admin
    client.post(URL, json={"sub": SUB, "email": ADMIN}, headers=h)
    assert client.delete(f"{URL}/{SUB}", headers=h).status_code == 204
    r = client.delete(f"{URL}/{SUB}", headers=h)
    assert r.status_code == 404 and r.json() == {"detail": "not_found"}
    assert client.delete(f"{URL}/khong-co", headers=h).status_code == 404


def test_demoted_admin_loses_access(admin, db_session):
    client, h = admin
    user = add_user(db_session, email="second@gmail.com", roles=("learner", "admin"))
    client.post(URL, json={"sub": SUB, "email": user.email}, headers=h)
    assert authorize_sub(db_session, SUB) is not None
    user.roles = ["learner"]
    db_session.flush()
    assert authorize_sub(db_session, SUB) is None


@pytest.fixture()
def cli(db_session, monkeypatch):
    """`main(argv)` chạy trên session test (không đóng, không chạm DATABASE_URL)."""
    monkeypatch.setattr(db, "SessionLocal", lambda: contextlib.nullcontext(db_session))
    return mcp_access.main


def test_cli_flow(cli, db_session, capsys):
    add_user(db_session, email=ADMIN, roles=("admin",))
    assert cli(["allow", SUB, "--as", ADMIN, "--label", "claude.ai"]) == 0
    assert authorize_sub(db_session, SUB) is not None
    assert cli(["list"]) == 0
    out = capsys.readouterr().out
    assert SUB in out and ADMIN in out and "hiệu lực" in out
    assert cli(["revoke", SUB]) == 0
    assert authorize_sub(db_session, SUB) is None
    assert cli(["revoke", SUB]) == 1
    assert "không có quyền" in capsys.readouterr().err


def test_cli_errors_go_to_stderr_with_exit_1(cli, db_session, capsys):
    add_user(db_session, email="l@gmail.com")
    assert cli(["allow", SUB, "--as", "l@gmail.com"]) == 1
    assert "không phải admin" in capsys.readouterr().err
    assert cli(["allow", "a b", "--as", "l@gmail.com"]) == 1
    assert cli(["allow", SUB]) == 2  # thiếu --as
    assert authorize_sub(db_session, SUB) is None
