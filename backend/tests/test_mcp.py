"""`/mcp` qua HTTP thật (TestClient + lifespan): cổng 401 trước SDK (INV-05), không rơi về chế độ mở hay
token app (INV-03), ghi đúng một đường + hiện ở /content (INV-02), Admin cầm version cũ nhận 409
(INV-01), thu hồi có hiệu lực ngay (INV-04)."""

from __future__ import annotations

import copy
import json
from contextlib import contextmanager

import httpx
import pytest

from app import mcp_auth, mcp_server
from app.content_api import read_content
from app.mcp_access import allow, revoke
from app.mcp_auth import JwksCache
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_mcp_auth import AUD, BASE, ISS, SUB, Signer

ADMIN = "admin@gmail.com"
PROTOCOL = "2025-06-18"
ACCEPT = {"Accept": "application/json, text/event-stream", "Content-Type": "application/json"}


@pytest.fixture(scope="module")
def signer() -> Signer:
    return Signer()


@pytest.fixture()
def env(monkeypatch, signer):
    monkeypatch.setenv("PUBLIC_BASE_URL", BASE)
    monkeypatch.setenv("IDENTITY_ISSUER", ISS)
    monkeypatch.delenv("AUTH_OPEN_AS", raising=False)
    monkeypatch.setitem(mcp_auth._caches, ISS, signer.cache())


@pytest.fixture()
def mcp(env, loaded_session, client_for, monkeypatch):
    """Client đã chạy lifespan; tool dùng session test (rollback sau test)."""

    @contextmanager
    def session():
        yield loaded_session

    monkeypatch.setattr(mcp_server, "open_session", session)
    add_user(loaded_session, email=ADMIN, roles=("learner", "admin"))
    with client_for(loaded_session) as client:
        yield client


@pytest.fixture()
def granted(mcp, loaded_session):
    allow(loaded_session, SUB, ADMIN, "test")
    loaded_session.flush()
    return mcp


def _headers(token: str | None) -> dict:
    headers = {**ACCEPT, "MCP-Protocol-Version": PROTOCOL}
    if token is not None:
        headers["Authorization"] = f"Bearer {token}"
    return headers


def rpc(client, method: str, params: dict | None = None, token: str | None = None) -> httpx.Response:
    body = {"jsonrpc": "2.0", "id": 1, "method": method, **({"params": params} if params is not None else {})}
    return client.post("/mcp", json=body, headers=_headers(token))


def call(client, signer, name: str, **arguments) -> dict:
    r = rpc(client, "tools/call", {"name": name, "arguments": arguments}, signer.token())
    assert r.status_code == 200, r.text
    return r.json()["result"]


def _text(result: dict) -> str:
    return "\n".join(c["text"] for c in result["content"] if c["type"] == "text")


def _data(result: dict):
    assert not result.get("isError"), _text(result)
    structured = result.get("structuredContent")
    if structured is not None:
        return structured.get("result", structured)
    return json.loads(_text(result))


def _new_lesson(content: dict, new_id: str = "zz-mcp-lesson") -> dict:
    src = next(iter(content["exercises"]))
    lesson = copy.deepcopy(content["exercises"][src])
    lesson["id"] = new_id
    for b in lesson["blocks"]:
        b["id"] = f"{new_id}-{b['label'].lower()}"
    return lesson


def _first_file(content: dict) -> str:
    return content["themes"][0]["topics"][0]["files"][0]["id"]


# --- Cổng HTTP (INV-05, INV-03, INV-07) -----------------------------------------------------------


def test_no_token_is_401_with_resource_metadata(mcp):
    r = mcp.post("/mcp", content=b"{not json", headers=ACCEPT)  # body rác: cổng không đọc body
    assert r.status_code == 401
    challenge = r.headers["www-authenticate"]
    assert challenge.startswith("Bearer ")
    assert f'resource_metadata="{BASE}/.well-known/oauth-protected-resource/mcp"' in challenge
    assert "error=" not in challenge


@pytest.mark.parametrize("overrides", [{"aud": "fishing-rod"}, {"aud": "https://moneyflow.jacons-corp.com/mcp"}, {"iss": "https://x.test"}])
def test_token_for_other_resource_is_401(mcp, signer, overrides):
    r = rpc(mcp, "tools/list", token=signer.token(**overrides))
    assert r.status_code == 401 and 'error="invalid_token"' in r.headers["www-authenticate"]


def test_open_mode_and_app_session_token_do_not_open_mcp(mcp, loaded_session, monkeypatch):
    monkeypatch.setenv("AUTH_OPEN_AS", ADMIN)
    assert rpc(mcp, "tools/list").status_code == 401
    app_token = login(mcp, email=ADMIN).json()["token"]
    assert rpc(mcp, "tools/list", token=app_token).status_code == 401


def test_get_and_delete_are_405(mcp, signer):
    assert mcp.get("/mcp", headers=_headers(signer.token())).status_code == 405
    assert mcp.delete("/mcp", headers=_headers(signer.token())).status_code == 405


def test_not_configured_is_503(mcp, signer, monkeypatch):
    monkeypatch.delenv("PUBLIC_BASE_URL")
    assert rpc(mcp, "tools/list", token=signer.token()).status_code == 503


def test_identity_down_is_503_not_401(mcp, signer, monkeypatch):
    def down(url):
        raise httpx.ConnectError("down")

    monkeypatch.setitem(mcp_auth._caches, ISS, JwksCache("u", fetch=down))
    r = rpc(mcp, "tools/list", token=signer.token())
    assert r.status_code == 503 and "www-authenticate" not in r.headers


def test_prm_on_main_app(mcp):
    body = mcp.get("/.well-known/oauth-protected-resource/mcp").json()
    assert body["resource"] == AUD and body["authorization_servers"] == [ISS]


# --- Giao thức + quyền -----------------------------------------------------------------------------


def test_initialize_and_list_tools(mcp, signer):
    init = rpc(mcp, "initialize", {"protocolVersion": PROTOCOL, "capabilities": {}, "clientInfo": {"name": "t", "version": "1"}}, signer.token())
    assert init.status_code == 200 and init.json()["result"]["serverInfo"]["name"] == "smart-coding-study"
    tools = {t["name"]: t for t in rpc(mcp, "tools/list", token=signer.token()).json()["result"]["tools"]}
    assert set(tools) == {
        "list_projects", "get_project", "get_lesson", "get_authoring_guide",
        "create_project", "update_project", "create_module", "update_module",
        "create_file", "update_file", "create_lesson", "update_lesson",
    }
    assert tools["list_projects"]["annotations"]["readOnlyHint"] is True
    assert "dry_run" in tools["create_lesson"]["inputSchema"]["properties"]


def test_tools_refuse_sub_without_grant(mcp, signer):
    result = call(mcp, signer, "list_projects")
    assert result["isError"] and SUB in _text(result)


def test_open_mode_does_not_grant_tools(mcp, signer, monkeypatch):
    # INV-03: JWT hợp lệ nhưng sub chưa cấp; chế độ mở trỏ tới admin cũng không được bù quyền.
    monkeypatch.setenv("AUTH_OPEN_AS", ADMIN)
    assert call(mcp, signer, "list_projects")["isError"]


def test_read_tools(granted, signer, content_data):
    projects = _data(call(granted, signer, "list_projects"))
    assert [p["id"] for p in projects] == [t["id"] for t in content_data["themes"]]
    lesson_id = next(iter(content_data["exercises"]))
    lesson = _data(call(granted, signer, "get_lesson", lesson_id=lesson_id))
    assert lesson["id"] == lesson_id and "judge" in lesson
    guide = _data(call(granted, signer, "get_authoring_guide"))
    assert "TODO" in guide["rules"] and guide["example_lesson"]["id"]
    missing = call(granted, signer, "get_lesson", lesson_id="khong-co")
    assert missing["isError"]


# --- Ghi (INV-01, INV-02, INV-04) ------------------------------------------------------------------


def _admin_version(client) -> str:
    token = login(client, email=ADMIN).json()["token"]
    return client.get("/api/admin/content", headers=bearer(token)).json()["version"]


def test_dry_run_does_not_write(granted, signer, loaded_session, content_data):
    before = _admin_version(granted)
    lesson = _new_lesson(content_data)
    result = _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson, dry_run=True))
    assert result["dry_run"] is True
    assert _admin_version(granted) == before
    assert lesson["id"] not in read_content(loaded_session)["exercises"]


def test_create_lesson_shows_in_content_and_stale_admin_gets_409(granted, signer, loaded_session, content_data):
    token = login(granted, email=ADMIN).json()["token"]
    stale = granted.get("/api/admin/content", headers=bearer(token)).json()
    lesson = _new_lesson(content_data)
    file_id = _first_file(content_data)
    result = _data(call(granted, signer, "create_lesson", file_id=file_id, lesson=lesson))
    assert result["ok"] and result["version"] != stale["version"]
    # INV-02: app thấy bài qua /content.
    public = granted.get("/content").json()
    assert lesson["id"] in public["exercises"] and "judge" not in public["exercises"][lesson["id"]]
    # INV-01: màn Admin cầm version cũ không ghi đè được bài Claude vừa tạo.
    r = granted.put("/api/admin/content", json={"base_version": stale["version"], "content": stale["content"]}, headers=bearer(token))
    assert r.status_code == 409


def test_invalid_lesson_is_tool_error_and_nothing_written(granted, signer, content_data):
    before = _admin_version(granted)
    lesson = _new_lesson(content_data)
    lesson["judge"]["solution"] = "def khac():\n    pass\n"  # không khớp template + đáp án
    result = call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson)
    assert result["isError"] and "không hợp lệ" in _text(result)
    assert _admin_version(granted) == before


def test_content_op_error_is_tool_error(granted, signer):
    result = call(granted, signer, "update_module", module_id="khong-co", changes={"name": "x"})
    assert result["isError"]


def test_create_project_module_file_chain(granted, signer, loaded_session):
    project = {"id": "zz-proj", "name": "Dự án thử", "description": "mô tả", "tags": ["python"]}
    first = {"id": "zz-mod", "name": "Module 1", "description": "m1"}
    assert _data(call(granted, signer, "create_project", project=project, first_module=first))["ok"]
    sub = {"id": "zz-sub", "name": "Module con", "description": "m2"}
    assert _data(call(granted, signer, "create_module", project_id="zz-proj", module=sub, parent_module_id="zz-mod"))["ok"]
    assert _data(call(granted, signer, "create_file", module_id="zz-sub", file={"id": "zz-file", "name": "main.py"}))["ok"]
    tree = _data(call(granted, signer, "get_project", project_id="zz-proj"))
    assert tree["modules"][0]["modules"][0]["files"][0]["id"] == "zz-file"


def test_revoke_takes_effect_on_next_call(granted, signer, loaded_session):
    assert not call(granted, signer, "list_projects").get("isError")
    revoke(loaded_session, SUB)
    loaded_session.flush()
    result = call(granted, signer, "update_module", module_id="x", changes={"name": "y"})
    assert result["isError"] and SUB in _text(result)


def test_admin_demoted_loses_mcp(granted, signer, loaded_session):
    from sqlalchemy import select

    from app.tables import User

    user = loaded_session.scalar(select(User).where(User.email == ADMIN))
    user.roles = ["learner"]
    loaded_session.flush()
    assert call(granted, signer, "list_projects")["isError"]
