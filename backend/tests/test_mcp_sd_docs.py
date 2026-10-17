"""Tool tài liệu System Design qua `/mcp` (HTTP thật + lifespan): quyền (INV-05), vòng đời doc nhìn từ học viên
(INV-01, INV-03), một đường nhập (INV-02), create không ghi đè (INV-07)."""

from __future__ import annotations

import json

import pytest

from app.mcp_access import revoke
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_mcp import ADMIN, ACCEPT, _data, _headers, _text, call, env, granted, mcp, rpc, signer  # noqa: F401
from tests.test_mcp_auth import SUB
from tests.test_sd_admin import MINI

DOC = "mini"


@pytest.fixture()
def learner(granted, loaded_session):
    add_user(loaded_session, email="hv@example.com", roles=("learner",))
    return bearer(login(granted, email="hv@example.com").json()["token"])


def _learner_doc(client, h):
    return client.get(f"/api/sd/docs/{DOC}", headers=h)


def _learner_ids(client, h):
    return [d["id"] for d in client.get("/api/sd/docs", headers=h).json()["items"]]


def test_tools_need_token_and_grant(mcp, signer):
    r = mcp.post("/mcp", json={"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "sd_list_docs", "arguments": {}}}, headers=ACCEPT)
    assert r.status_code == 401
    result = call(mcp, signer, "sd_create_doc", markdown=MINI)
    assert result["isError"] and SUB in _text(result)


def test_lifecycle_seen_by_learner(granted, signer, learner):
    client = granted
    created = _data(call(client, signer, "sd_create_doc", markdown=MINI))
    assert created["id"] == DOC and created["status"] == "draft"
    assert DOC not in _learner_ids(client, learner)  # draft: học viên chưa thấy

    assert _data(call(client, signer, "sd_set_status", doc_id=DOC, status="published"))["status"] == "published"
    doc = _learner_doc(client, learner).json()
    section = doc["sections"][0]
    first_card = section["cards"][0]["id"]
    r = client.put(f"/api/sd/docs/{DOC}/sections/{section['id']}/progress", json={"read_cards": [first_card]}, headers=learner)
    assert r.status_code == 200, r.json()

    # INV-03: sửa card KHÁC → card đã đọc vẫn được tính là đã đọc.
    edited = _data(call(client, signer, "sd_edit_doc", doc_id=DOC, edits=[{"old_text": "Đoạn hai.", "new_text": "Đoạn hai đã sửa."}]))
    assert (edited["cards_added"], edited["cards_removed"]) == (1, 1)
    assert _learner_doc(client, learner).json()["sections"][0]["read"] == [first_card]

    # INV-01: xoá mềm → học viên không thấy, không ghi tiến độ được.
    deleted = _data(call(client, signer, "sd_delete_doc", doc_id=DOC))
    assert deleted["status"] == "archived" and "Khôi phục" in deleted["note"]
    assert DOC not in _learner_ids(client, learner)
    assert _learner_doc(client, learner).status_code == 404
    assert client.put(f"/api/sd/docs/{DOC}/sections/{section['id']}/progress", json={"read_cards": []}, headers=learner).status_code == 404
    assert [d["id"] for d in _data(call(client, signer, "sd_list_docs"))] == []
    assert [d["id"] for d in _data(call(client, signer, "sd_list_docs", include_archived=True))] == [DOC]

    # Khôi phục: tiến độ cũ còn nguyên.
    _data(call(client, signer, "sd_set_status", doc_id=DOC, status="published"))
    assert _learner_doc(client, learner).json()["sections"][0]["read"] == [first_card]


def test_create_refuses_archived_id(granted, signer):
    _data(call(granted, signer, "sd_create_doc", markdown=MINI))
    _data(call(granted, signer, "sd_delete_doc", doc_id=DOC))
    result = call(granted, signer, "sd_create_doc", markdown=MINI.replace("Đoạn một.", "Khác."))
    assert result["isError"] and "archived" in _text(result)
    assert "Đoạn một." in _data(call(granted, signer, "sd_get_doc", doc_id=DOC))["markdown"]


def test_admin_api_import_is_editable_through_mcp(granted, signer, loaded_session):
    # INV-02: doc nhập qua API admin có markdown gốc → sd_edit_doc dùng được.
    h = bearer(login(granted, email=ADMIN).json()["token"])
    assert granted.post("/api/admin/sd/docs", json={"markdown": MINI}, headers=h).status_code == 200
    got = _data(call(granted, signer, "sd_get_doc", doc_id=DOC))
    assert got["markdown"] == MINI and got["revision"]
    assert _data(call(granted, signer, "sd_edit_doc", doc_id=DOC, edits=[{"old_text": "Đoạn một.", "new_text": "Mở đầu."}]))["id"] == DOC


def test_replace_with_stale_revision_is_tool_error(granted, signer):
    _data(call(granted, signer, "sd_create_doc", markdown=MINI))
    rev = _data(call(granted, signer, "sd_get_doc", doc_id=DOC))["revision"]
    _data(call(granted, signer, "sd_replace_doc", doc_id=DOC, markdown=MINI.replace("Đoạn một.", "A.")))
    result = call(granted, signer, "sd_replace_doc", doc_id=DOC, markdown=MINI.replace("Đoạn một.", "B."), base_revision=rev)
    assert result["isError"] and "revision" in _text(result)


def test_dry_run_and_parser_errors(granted, signer):
    dry = _data(call(granted, signer, "sd_create_doc", markdown=MINI, dry_run=True))
    assert dry["dry_run"] is True
    assert _data(call(granted, signer, "sd_list_docs")) == []
    bad = call(granted, signer, "sd_create_doc", markdown="không có tiêu đề")
    assert bad["isError"] and "chưa ghi gì" in _text(bad)


def test_edit_tool_is_not_marked_idempotent(granted, signer):
    tools = {t["name"]: t for t in rpc(granted, "tools/list", token=signer.token()).json()["result"]["tools"]}
    assert tools["sd_edit_doc"]["annotations"]["idempotentHint"] is False
    assert tools["sd_edit_doc"]["annotations"]["destructiveHint"] is True
    assert tools["sd_delete_doc"]["annotations"]["destructiveHint"] is True


def test_bad_status_rejected_by_schema(granted, signer):
    _data(call(granted, signer, "sd_create_doc", markdown=MINI))
    assert call(granted, signer, "sd_set_status", doc_id=DOC, status="deleted")["isError"]
    assert call(granted, signer, "sd_create_doc", markdown=MINI, doc_id="x2", status="archived")["isError"]


def test_large_body_accepted_with_token(granted, signer):
    # 1.5MB qua được cổng + giới hạn body; service tự từ chối vì markdown > 1MB.
    big = "# Lớn\n\n## C\n\n" + "x" * 1_500_000
    body = json.dumps({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "sd_create_doc", "arguments": {"markdown": big}}})
    r = granted.post("/mcp", content=body, headers=_headers(signer.token()))
    assert r.status_code == 200
    result = r.json()["result"]
    assert result["isError"] and "quá lớn" in _text(result)


def test_large_body_without_token_is_401(mcp):
    body = json.dumps({"pad": "x" * 1_500_000})
    assert mcp.post("/mcp", content=body, headers=ACCEPT).status_code == 401


def test_revoked_sub_cannot_write(granted, signer, loaded_session):
    _data(call(granted, signer, "sd_create_doc", markdown=MINI))
    revoke(loaded_session, SUB)
    loaded_session.flush()
    result = call(granted, signer, "sd_delete_doc", doc_id=DOC)
    assert result["isError"] and SUB in _text(result)


def test_list_attempts_tool_can_include_archived(granted, signer, loaded_session):
    from app.tables import SdAttempt, User
    from sqlalchemy import select

    _data(call(granted, signer, "sd_create_doc", markdown=MINI, status="published"))
    uid = loaded_session.scalar(select(User.id).where(User.email == ADMIN))
    loaded_session.add(SdAttempt(user_id=uid, doc_id=DOC, task_id="task-a", n=1, answer="bài", auto_result={"hits": [False], "score": 0}))
    loaded_session.commit()
    assert len(_data(call(granted, signer, "sd_list_attempts", doc_id=DOC))) == 1
    _data(call(granted, signer, "sd_delete_doc", doc_id=DOC))
    assert _data(call(granted, signer, "sd_list_attempts", doc_id=DOC)) == []
    assert len(_data(call(granted, signer, "sd_list_attempts", doc_id=DOC, include_archived=True))) == 1
