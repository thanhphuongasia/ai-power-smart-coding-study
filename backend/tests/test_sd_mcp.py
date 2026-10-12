"""Tool MCP chấm bài thực chiến System Design: quyền, hàng đợi, đọc bài, ghi feedback, học viên thấy bản reviewed."""

from __future__ import annotations

import pytest

from app.mcp_access import revoke
from app.tables import SdAttempt
from tests.test_auth import client_for, fresh_throttle  # noqa: F401
from tests.test_mcp import ADMIN, _data, _text, call, env, granted, mcp, rpc, signer  # noqa: F401
from tests.test_mcp_auth import SUB
from tests.test_sd_learner import DOC, World, _keys, sample_md  # noqa: F401

API = f"/api/sd/docs/{DOC}/tasks/api-design/attempts"
GOOD = "POST /holds giữ ghế riêng; đặt vé dùng Idempotency-Key; ghế bị giữ trả 409 Conflict; tìm chuyến theo date, from, origin."
HALF = "Có endpoint hold để giữ ghế và trả 409 khi ghế đã bị giữ."
SECRET_WORDS = {"keywords", "rubric", "auto_result"}


@pytest.fixture()
def world(granted, loaded_session, client_for, sample_md):
    w = World(loaded_session, client_for, sample_md)
    w.read_all("ann")
    w.read_all("bob")
    return w


def _submit(w, answer, who="ann"):
    r = w.client.post(API, json={"answer": answer}, headers=w.hdr[who])
    assert r.status_code == 201, r.json()
    return r.json()["attempt"]


def _verdicts(oks, note="ghi chú"):
    return [{"ok": ok, "note": note} for ok in oks]


# --- quyền ---------------------------------------------------------------------------------


def test_tools_are_listed_with_right_annotations(granted, signer):
    tools = {t["name"]: t for t in rpc(granted, "tools/list", token=signer.token()).json()["result"]["tools"]}
    assert tools["sd_list_attempts"]["annotations"]["readOnlyHint"] is True
    assert tools["sd_get_attempt"]["annotations"]["readOnlyHint"] is True
    assert tools["sd_submit_feedback"]["annotations"]["readOnlyHint"] is False
    assert tools["sd_submit_feedback"]["annotations"]["idempotentHint"] is True
    assert not any(n.startswith("sd_") and "delete" in n for n in tools)  # không có tool xoá


@pytest.mark.parametrize(
    "name, args",
    [
        ("sd_list_attempts", {}),
        ("sd_get_attempt", {"attempt_id": 1}),
        ("sd_submit_feedback", {"attempt_id": 1, "verdicts": [], "feedback": "x"}),
    ],
)
def test_sub_without_access_cannot_use_any_sd_tool(mcp, signer, name, args):
    r = call(mcp, signer, name, **args)  # `mcp` chưa cấp quyền cho SUB
    assert r["isError"] is True and "chưa được cấp quyền" in _text(r)


def test_revoking_access_takes_effect_immediately(world, granted, loaded_session, signer):
    attempt = _submit(world, GOOD)
    assert _data(call(granted, signer, "sd_get_attempt", attempt_id=attempt["id"]))["answer"] == GOOD
    revoke(loaded_session, SUB)
    loaded_session.flush()
    assert call(granted, signer, "sd_get_attempt", attempt_id=attempt["id"])["isError"] is True


def test_learner_app_session_token_is_not_an_mcp_credential(world, granted):
    r = rpc(granted, "tools/call", {"name": "sd_get_attempt", "arguments": {"attempt_id": 1}}, token=world.hdr["ann"]["Authorization"][7:])
    assert r.status_code == 401


# --- hàng đợi và đọc bài -------------------------------------------------------------------


def test_queue_is_oldest_first_and_defaults_to_unreviewed(world, granted, signer):
    a1 = _submit(world, HALF, "ann")
    b1 = _submit(world, GOOD, "bob")
    a2 = _submit(world, GOOD, "ann")
    items = _data(call(granted, signer, "sd_list_attempts"))
    assert [i["attempt_id"] for i in items] == [a1["id"], b1["id"], a2["id"]]
    first = items[0]
    assert first["task_name"] == "API Design" and first["status"] == "auto" and first["auto_score"] == 50
    assert first["learner_id"] and "email" not in first and len(first["answer_preview"]) <= 200
    only = _data(call(granted, signer, "sd_list_attempts", task_id="database-design"))
    assert only == []
    assert len(_data(call(granted, signer, "sd_list_attempts", limit=2))) == 2


def test_queue_rejects_unknown_status(world, granted, signer):
    r = call(granted, signer, "sd_list_attempts", status="weird")
    assert r["isError"] is True and "status" in _text(r)


def test_get_attempt_gives_everything_needed_but_no_keywords(world, granted, signer):
    a = _submit(world, HALF)
    d = _data(call(granted, signer, "sd_get_attempt", attempt_id=a["id"]))
    assert d["answer"] == HALF and d["status"] == "auto" and d["task"]["name"] == "API Design"
    assert len(d["task"]["rubric_items"]) == 4 and d["task"]["auto_hits"] == [True, False, True, False]
    assert d["task"]["prompt"].startswith("Phác các endpoint")
    assert d["reference"]["title"] == "API Endpoints" and d["reference"]["cards"]
    assert not _keys(d) & SECRET_WORDS


def test_get_unknown_attempt_is_a_tool_error(world, granted, signer):
    r = call(granted, signer, "sd_get_attempt", attempt_id=999999)
    assert r["isError"] is True and "không có lần thử" in _text(r)


# --- ghi feedback (INV-03) ------------------------------------------------------------------


def test_feedback_becomes_the_only_version_the_learner_sees(world, granted, signer):
    a = _submit(world, GOOD)
    out = _data(call(granted, signer, "sd_submit_feedback", attempt_id=a["id"], verdicts=[
        {"ok": True, "note": "hold tách riêng, tốt"}, {"ok": False, "note": "chưa nói header"},
        {"ok": True, "note": ""}, {"ok": True, "note": "đủ bộ lọc"},
    ], feedback="Khá tốt, thiếu Idempotency-Key ở header."))
    assert out == {"attempt_id": a["id"], "status": "reviewed", "score": 75}

    mine = world.client.get(API, headers=world.hdr["ann"]).json()["items"][0]
    assert mine["source"] == "reviewed" and mine["feedback"] == "Khá tốt, thiếu Idempotency-Key ở header."
    assert [i["ok"] for i in mine["items"]] == [True, False, True, True] and mine["score"] == 75
    assert mine["items"][0]["text"].startswith("Có endpoint giữ ghế")  # chữ ý rubric do SERVER giữ
    assert mine["items"][1]["note"] == "chưa nói header"
    assert not _keys(mine) & (SECRET_WORDS | {"verdicts", "reviewed_by"})

    assert _data(call(granted, signer, "sd_list_attempts")) == []  # ra khỏi hàng đợi
    done = _data(call(granted, signer, "sd_list_attempts", status="reviewed"))
    assert [i["attempt_id"] for i in done] == [a["id"]]
    assert world.session.get(SdAttempt, a["id"]).reviewed_by == f"mcp:{SUB}"


def test_other_learner_does_not_see_the_feedback(world, granted, signer):
    a = _submit(world, GOOD, "ann")
    call(granted, signer, "sd_submit_feedback", attempt_id=a["id"], verdicts=_verdicts([True] * 4), feedback="ok")
    assert world.client.get(API, headers=world.hdr["bob"]).json() == {"items": []}


def test_feedback_can_be_replaced(world, granted, signer):
    a = _submit(world, GOOD)
    call(granted, signer, "sd_submit_feedback", attempt_id=a["id"], verdicts=_verdicts([True] * 4), feedback="lần một")
    call(granted, signer, "sd_submit_feedback", attempt_id=a["id"], verdicts=_verdicts([False] * 4), feedback="lần hai")
    mine = world.client.get(API, headers=world.hdr["ann"]).json()["items"][0]
    assert mine["feedback"] == "lần hai" and mine["score"] == 0


@pytest.mark.parametrize(
    "verdicts, feedback, needle",
    [
        (_verdicts([True] * 3), "ok", "đúng 4 phần tử"),
        (_verdicts([True] * 5), "ok", "đúng 4 phần tử"),
        ([{"ok": "yes", "note": ""}] * 4, "ok", "boolean"),
        ([{"note": "thiếu ok"}] * 4, "ok", "boolean"),
        (["x"] * 4, "ok", "dict"),  # SDK từ chối trước khi tới hàm nghiệp vụ
        ([{"ok": True, "note": "n" * 501}] * 4, "ok", "note"),
        ([{"ok": True, "note": "a\x00b"}] * 4, "ok", "note"),
        (_verdicts([True] * 4), "", "feedback"),
        (_verdicts([True] * 4), "   ", "feedback"),
        (_verdicts([True] * 4), "f" * 4001, "feedback"),
        (_verdicts([True] * 4), "a\x00b", "NUL"),
    ],
)
def test_bad_feedback_is_rejected_and_changes_nothing(world, granted, signer, verdicts, feedback, needle):
    a = _submit(world, GOOD)
    r = call(granted, signer, "sd_submit_feedback", attempt_id=a["id"], verdicts=verdicts, feedback=feedback)
    assert r["isError"] is True and needle in _text(r)
    world.session.expire_all()
    row = world.session.get(SdAttempt, a["id"])
    assert row.status == "auto" and row.feedback is None and row.verdicts is None


def test_feedback_for_unknown_attempt_is_a_tool_error(world, granted, signer):
    r = call(granted, signer, "sd_submit_feedback", attempt_id=424242, verdicts=_verdicts([True] * 4), feedback="ok")
    assert r["isError"] is True and "không có lần thử" in _text(r)
