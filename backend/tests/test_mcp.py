"""`/mcp` qua HTTP thật (TestClient + lifespan): cổng 401 trước SDK (INV-05), không rơi về chế độ mở hay
token app (INV-03), ghi vào hàng chờ duyệt, không đụng /content (INV-02), Admin cầm version cũ nhận 409
(INV-01), thu hồi có hiệu lực ngay (INV-04)."""

from __future__ import annotations

import copy
import json
from contextlib import contextmanager

import httpx
import pytest

from app import mcp_auth, mcp_server, review
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
        "sd_list_attempts", "sd_get_attempt", "sd_submit_feedback",
        "sd_list_docs", "sd_get_doc", "sd_create_doc", "sd_replace_doc", "sd_edit_doc", "sd_set_status", "sd_delete_doc",
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
    assert review.pending_rows(loaded_session) == []


def test_create_lesson_goes_to_review_queue_and_stale_admin_gets_409(granted, signer, loaded_session, content_data):
    token = login(granted, email=ADMIN).json()["token"]
    stale = granted.get("/api/admin/content", headers=bearer(token)).json()
    live_before = granted.get("/content").json()
    lesson = _new_lesson(content_data)
    file_id = _first_file(content_data)
    result = _data(call(granted, signer, "create_lesson", file_id=file_id, lesson=lesson))
    assert result["ok"] and result["version"] != stale["version"] and result["pending"] >= 1
    assert "hàng chờ duyệt" in result["message"]
    # INV-02: nội dung đang chạy KHÔNG đổi; có mục pending đúng kind/action.
    assert granted.get("/content").json() == live_before
    assert lesson["id"] not in read_content(loaded_session)["exercises"]
    rows = review.pending_rows(loaded_session)
    row = next(r for r in rows if (r.kind, r.item_id) == ("exercise", lesson["id"]))
    assert row.action == "create" and row.author == f"mcp:{SUB} ({ADMIN})"
    # INV-01: màn Admin cầm version cũ không ghi đè được bài Claude vừa gửi.
    r = granted.put("/api/admin/content", json={"base_version": stale["version"], "content": stale["content"]}, headers=bearer(token))
    assert r.status_code == 409


def test_second_call_sees_pending_of_first(granted, signer, loaded_session, content_data):
    lesson = _new_lesson(content_data)
    _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson))
    seen = _data(call(granted, signer, "get_lesson", lesson_id=lesson["id"]))
    assert seen["id"] == lesson["id"]
    # Cập nhật bài đang chờ: vẫn một mục pending cho bài đó (create), không hai.
    _data(call(granted, signer, "update_lesson", lesson_id=lesson["id"], changes={"title": "Tiêu đề mới"}))
    rows = [r for r in review.pending_rows(loaded_session) if (r.kind, r.item_id) == ("exercise", lesson["id"])]
    assert len(rows) == 1 and rows[0].action == "create" and rows[0].after["fields"]["title"] == "Tiêu đề mới"


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
    assert "zz-proj" not in [t["id"] for t in granted.get("/content").json()["themes"]]
    assert {("project", "zz-proj"), ("module", "zz-mod"), ("module", "zz-sub"), ("file", "zz-file")} <= {
        (r.kind, r.item_id) for r in review.pending_rows(loaded_session)
    }


def test_lesson_in_pending_file_then_approve_in_order(granted, signer, loaded_session, content_data):
    """Tạo file rồi tạo bài trong file đó (cả hai đang chờ) — sau đó admin duyệt cha trước con thì bài lên đúng chỗ."""
    project = {"id": "zz-proj", "name": "Dự án thử", "description": "mô tả", "tags": ["python"]}
    first = {"id": "zz-mod", "name": "Module 1", "description": "m1"}
    assert _data(call(granted, signer, "create_project", project=project, first_module=first))["ok"]
    assert _data(call(granted, signer, "create_file", module_id="zz-mod", file={"id": "zz-file", "name": "main.py"}))["ok"]
    src = next(k for k, e in content_data["exercises"].items() if e["class_name"] is None)  # project mới chưa có sơ đồ
    lesson = _new_lesson({"exercises": {src: content_data["exercises"][src]}})
    assert _data(call(granted, signer, "create_lesson", file_id="zz-file", lesson=lesson))["ok"]
    assert _data(call(granted, signer, "get_lesson", lesson_id=lesson["id"]))["id"] == lesson["id"]
    rows = {r.kind: r for r in review.pending_rows(loaded_session)}
    with pytest.raises(review.DependencyMissing):
        review.approve(loaded_session, rows["exercise"].id, "boss")
    result = review.approve(loaded_session, rows["project"].id, "boss")  # kéo theo module cấp 1 mới
    assert result["also"] == [rows["module"].id] and rows["module"].status == "approved"
    for kind in ("file", "exercise"):
        review.approve(loaded_session, rows[kind].id, "boss")
    public = granted.get("/content").json()
    theme = next(t for t in public["themes"] if t["id"] == "zz-proj")
    assert theme["topics"][0]["files"][0]["exercise_ids"] == [lesson["id"]]


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


# --- Đồng thời + biên (review external T-04) -----------------------------------------------------


def test_concurrent_requests_do_not_share_claims(granted, signer, monkeypatch):
    # Hai request chạy CÙNG LÚC: sub đã cấp và sub chưa cấp. Claims để ở biến global sẽ lẫn nhau.
    import threading

    other = "11111111-2222-3333-4444-555555555555"
    barrier, db_lock, seen = threading.Barrier(2, timeout=10), threading.Lock(), []
    real = mcp_server.authorize_sub

    def gated(session, sub):
        seen.append(sub)
        barrier.wait()  # cả hai request đều đã vào tool rồi mới đi tiếp
        with db_lock:  # session test dùng chung một connection: không cho hai thread chạm cùng lúc
            return real(session, sub)

    monkeypatch.setattr(mcp_server, "authorize_sub", gated)
    results: dict[str, dict] = {}

    def run(sub: str):
        r = rpc(granted, "tools/call", {"name": "list_projects", "arguments": {}}, signer.token(sub=sub))
        results[sub] = r.json()["result"]

    threads = [threading.Thread(target=run, args=(s,)) for s in (SUB, other)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(15)
    assert sorted(seen) == sorted([SUB, other])
    assert not results[SUB].get("isError")
    assert results[other]["isError"] and other in _text(results[other])


def test_write_between_validate_and_lock_is_refused(granted, signer, loaded_session, content_data, monkeypatch):
    # Người khác lưu đúng lúc tool vừa validate xong (trước khi có khoá): tool phải từ chối, không
    # ghi đè. Bỏ lock_content hoặc bỏ bước so version dưới khoá trong review.submit thì test này đỏ.
    from app import content_ops
    from app.export_content import export_content
    from app.load_content import load_content as real_load
    from app.load_content import lock_content as real_lock

    def lock_then_competing_write(session):
        real_lock(session)
        competing = content_ops.update_project(export_content(session), content_data["themes"][0]["id"], {"name": "Người khác vừa sửa"})
        real_load(session, competing, validated=True)

    monkeypatch.setattr(review, "lock_content", lock_then_competing_write)
    lesson = _new_lesson(content_data)
    result = call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson)
    # Session test dùng chung nên rollback của tool xoá cả dữ liệu fixture — chỉ kiểm được thông điệp.
    assert result["isError"] and "Người khác vừa sửa" in _text(result)


def test_gate_rejects_without_reading_body(env):
    import asyncio

    async def receive():
        raise AssertionError("cổng đã đọc body trước khi xác thực")

    sent = []

    async def send(message):
        sent.append(message)

    scope = {"type": "http", "method": "POST", "path": "/mcp", "headers": [(b"content-type", b"application/json")]}
    asyncio.run(mcp_server.McpGate()(scope, receive, send))
    assert sent[0]["status"] == 401


def test_body_over_limit_is_413(mcp, signer):
    big = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {"pad": "x" * (2 * 1024 * 1024 + 1)}})
    r = mcp.post("/mcp", content=big, headers=_headers(signer.token()))
    assert r.status_code == 413
