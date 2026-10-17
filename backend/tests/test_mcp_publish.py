"""Tool publish riêng qua `/mcp`: xem/duyệt/bỏ hàng chờ bài code (INV-01..05) và publish tài liệu SD (INV-06)."""

from __future__ import annotations

import pytest

from app.mcp_access import revoke
from app.tables import ContentChange
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_mcp import ADMIN, _data, _first_file, _new_lesson, _text, call, env, granted, mcp, signer  # noqa: F401
from tests.test_mcp_auth import SUB
from tests.test_sd_admin import MINI


def _pending(client, signer) -> dict[tuple[str, str], int]:
    return {(c["kind"], c["item_id"]): c["id"] for c in _data(call(client, signer, "list_pending_changes"))}


def _standalone_lesson(content: dict, new_id: str) -> dict:
    """Bài hàm rời (không class) — đặt được vào project mới mà không vướng luật sơ đồ class."""
    src = next(k for k, e in content["exercises"].items() if e["class_name"] is None)
    return _new_lesson({"exercises": {src: content["exercises"][src]}}, new_id)


def _live_lessons(client) -> set[str]:
    return set(client.get("/content").json()["exercises"])


@pytest.mark.parametrize(
    "name, args",
    [
        ("list_pending_changes", {}),
        ("get_pending_change", {"change_id": 1}),
        ("publish_changes", {"change_ids": [1]}),
        ("reject_changes", {"change_ids": [1]}),
        ("sd_publish_doc", {"doc_id": "mini"}),
        ("sd_unpublish_doc", {"doc_id": "mini"}),
    ],
)
def test_tools_need_grant(mcp, signer, name, args):
    result = call(mcp, signer, name, **args)
    assert result["isError"] and SUB in _text(result)


def test_publish_lesson_goes_live_with_trace(granted, signer, loaded_session, content_data):
    lesson = _new_lesson(content_data)
    msg = _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson))["message"]
    assert "publish_changes" in msg and lesson["id"] not in _live_lessons(granted)
    cid = _pending(granted, signer)[("exercise", lesson["id"])]
    listed = {c["id"]: c for c in _data(call(granted, signer, "list_pending_changes"))}
    assert listed[cid]["name"] == lesson["title"]
    detail = _data(call(granted, signer, "get_pending_change", change_id=cid))
    assert detail["action"] == "create" and detail["after"]["fields"]["title"] == lesson["title"]

    out = _data(call(granted, signer, "publish_changes", change_ids=[cid]))
    assert out["results"] == [{"id": cid, "status": "approved", "also": []}]
    assert lesson["id"] in _live_lessons(granted)  # INV-01: học viên thấy qua /content
    row = loaded_session.get(ContentChange, cid)
    assert row.status == "approved" and row.decided_by == f"mcp:{SUB}" and row.decided_at  # INV-02

    # INV-05: ghi tiếp ngay sau khi publish không bị 409.
    again = call(granted, signer, "update_lesson", lesson_id=lesson["id"], changes={"title": "Tiêu đề mới"})
    assert not again.get("isError"), _text(again)


def test_dependency_order_and_one_bad_id_does_not_block_others(granted, signer, content_data):
    # Bài mới trong file MỚI (đang chờ) + một bài khác trong file có sẵn.
    _data(call(granted, signer, "create_project", project={"id": "zz-proj", "name": "P", "description": "d", "tags": []},
               first_module={"id": "zz-mod", "name": "M", "description": "m"}))
    _data(call(granted, signer, "create_file", module_id="zz-mod", file={"id": "zz-file", "name": "a.py"}))
    in_new = _standalone_lesson(content_data, "zz-in-new")
    in_old = _new_lesson(content_data, "zz-in-old")
    _data(call(granted, signer, "create_lesson", file_id="zz-file", lesson=in_new))
    _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=in_old))
    ids = _pending(granted, signer)

    out = _data(call(granted, signer, "publish_changes", change_ids=[ids[("exercise", "zz-in-new")], ids[("exercise", "zz-in-old")]]))
    first, second = out["results"]
    assert first["status"] == "error" and "trước" in first["error"]  # INV-03: bài trong file chưa duyệt
    assert second["status"] == "approved"  # id lỗi không kéo id còn lại
    assert "zz-in-old" in _live_lessons(granted) and "zz-in-new" not in _live_lessons(granted)

    out = _data(call(granted, signer, "publish_changes",
                     change_ids=[ids[("project", "zz-proj")], ids[("module", "zz-mod")], ids[("file", "zz-file")], ids[("exercise", "zz-in-new")]]))
    statuses = {r["id"]: r["status"] for r in out["results"]}
    assert ids[("module", "zz-mod")] in out["results"][0]["also"]  # project kéo module đầu
    assert statuses[ids[("module", "zz-mod")]] == "skipped"  # đã duyệt kèm → bỏ qua, không lỗi
    assert statuses[ids[("exercise", "zz-in-new")]] == "approved"
    assert "zz-in-new" in _live_lessons(granted) and out["pending"] == 0


def test_failure_after_partial_write_is_rolled_back_per_id(granted, signer, content_data, monkeypatch):
    # INV-03: id lỗi SAU khi load_content đã ghi dở → savepoint hoàn tác phần đó; id sau vẫn publish.
    from sqlalchemy.exc import DataError

    from app import mcp_server, review

    bad, good = _new_lesson(content_data, "zz-bad"), _new_lesson(content_data, "zz-good")
    for lesson in (bad, good):
        _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson))
    ids = _pending(granted, signer)
    bad_id = ids[("exercise", "zz-bad")]
    real = review.approve

    def flaky(session, change_id, reviewer):
        out = real(session, change_id, reviewer)  # đã load_content → live đã có bài
        if change_id == bad_id:
            raise DataError("stmt", {}, Exception("giả lập DB từ chối sau khi ghi"))
        return out

    monkeypatch.setattr(mcp_server.review, "approve", flaky)
    out = _data(call(granted, signer, "publish_changes", change_ids=[bad_id, ids[("exercise", "zz-good")]]))
    assert [r["status"] for r in out["results"]] == ["error", "approved"]
    live = _live_lessons(granted)
    assert "zz-bad" not in live and "zz-good" in live


def test_reject_keeps_lesson_off_live(granted, signer, content_data):
    lesson = _new_lesson(content_data)
    _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson))
    cid = _pending(granted, signer)[("exercise", lesson["id"])]
    out = _data(call(granted, signer, "reject_changes", change_ids=[cid]))
    assert out["results"][0]["status"] == "rejected"
    assert lesson["id"] not in _live_lessons(granted) and _data(call(granted, signer, "list_pending_changes")) == []


def test_unknown_or_already_decided_ids_are_skipped(granted, signer, content_data):
    lesson = _new_lesson(content_data)
    _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson))
    cid = _pending(granted, signer)[("exercise", lesson["id"])]
    _data(call(granted, signer, "publish_changes", change_ids=[cid]))
    out = _data(call(granted, signer, "publish_changes", change_ids=[cid, 999_999]))
    assert [r["status"] for r in out["results"]] == ["skipped", "skipped"]
    assert call(granted, signer, "get_pending_change", change_id=999_999)["isError"]


@pytest.mark.parametrize("ids", [[], list(range(1, 52)), [0], [-1]])
def test_bad_id_lists_are_tool_errors(granted, signer, ids):
    assert call(granted, signer, "publish_changes", change_ids=ids)["isError"]


def test_revoked_sub_cannot_publish(granted, signer, loaded_session, content_data):
    lesson = _new_lesson(content_data)
    _data(call(granted, signer, "create_lesson", file_id=_first_file(content_data), lesson=lesson))
    cid = _pending(granted, signer)[("exercise", lesson["id"])]
    revoke(loaded_session, SUB)
    loaded_session.flush()
    result = call(granted, signer, "publish_changes", change_ids=[cid])
    assert result["isError"] and SUB in _text(result)  # INV-04


def test_sd_publish_and_unpublish_seen_by_learner(granted, signer, loaded_session):
    # INV-06: cùng đường set_status; học viên thấy/không thấy theo đó, tiến độ không mất.
    add_user(loaded_session, email="hv@example.com", roles=("learner",))
    h = bearer(login(granted, email="hv@example.com").json()["token"])
    doc_id = _data(call(granted, signer, "sd_create_doc", markdown=MINI))["id"]
    ids = lambda: [d["id"] for d in granted.get("/api/sd/docs", headers=h).json()["items"]]  # noqa: E731
    assert doc_id not in ids()
    assert _data(call(granted, signer, "sd_publish_doc", doc_id=doc_id))["status"] == "published"
    assert doc_id in ids()
    assert _data(call(granted, signer, "sd_unpublish_doc", doc_id=doc_id))["status"] == "draft"
    assert doc_id not in ids()
    assert call(granted, signer, "sd_publish_doc", doc_id="khong-co")["isError"]
