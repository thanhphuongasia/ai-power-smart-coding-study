"""Tool course qua `/mcp` (HTTP thật): quyền (INV-06), trạng thái Literal (INV-03), gán doc + thứ tự (INV-07),
xoá mềm course giữ nhóm (INV-05)."""

from __future__ import annotations

from app.mcp_access import revoke
from tests.test_auth import client_for, fresh_throttle  # noqa: F401
from tests.test_mcp import _data, _text, call, env, granted, mcp, signer  # noqa: F401
from tests.test_mcp_auth import SUB
from tests.test_sd_admin import MINI

C = "python-basics"


def _doc(client, signer, title):
    return _data(call(client, signer, "sd_create_doc", markdown=MINI.replace("# Mini", f"# {title}"), status="published"))["id"]


def test_course_tools_need_grant(mcp, signer):
    result = call(mcp, signer, "sd_create_course", course_id=C, title="Python")
    assert result["isError"] and SUB in _text(result)


def test_create_assign_order_archive_restore(granted, signer):
    made = _data(call(granted, signer, "sd_create_course", course_id=C, title="Python cơ bản", skills=["python"], domain="basics"))
    assert made["status"] == "draft" and made["skills"] == ["python"]
    a, b = _doc(granted, signer, "Bài A"), _doc(granted, signer, "Bài B")
    _data(call(granted, signer, "sd_assign_doc", doc_id=a, course_id=C, position=1))
    _data(call(granted, signer, "sd_assign_doc", doc_id=b, course_id=C, position=0))
    listed = _data(call(granted, signer, "sd_list_courses"))
    assert [d["id"] for d in listed[0]["docs"]] == [b, a]  # INV-07
    assert {d["id"]: d["course_id"] for d in _data(call(granted, signer, "sd_list_docs"))}[a] == C

    assert _data(call(granted, signer, "sd_set_course_status", course_id=C, status="archived"))["status"] == "archived"
    assert _data(call(granted, signer, "sd_list_courses")) == []
    assert _data(call(granted, signer, "sd_get_doc", doc_id=a))["course_id"] == C  # INV-05: doc giữ liên kết
    refused = call(granted, signer, "sd_assign_doc", doc_id=a, course_id=C)
    assert refused["isError"] and "xoá mềm" in _text(refused)
    _data(call(granted, signer, "sd_set_course_status", course_id=C, status="published"))
    assert [d["id"] for d in _data(call(granted, signer, "sd_list_courses"))[0]["docs"]] == [b, a]

    unassigned = _data(call(granted, signer, "sd_assign_doc", doc_id=a, course_id=None))
    assert unassigned["course_id"] is None and unassigned["previous_course_id"] == C


def test_update_and_validation_errors(granted, signer):
    _data(call(granted, signer, "sd_create_course", course_id=C, title="Python"))
    assert _data(call(granted, signer, "sd_update_course", course_id=C, changes={"title": "Mới", "position": 3}))["position"] == 3
    assert call(granted, signer, "sd_update_course", course_id=C, changes={"status": "published"})["isError"]
    assert call(granted, signer, "sd_create_course", course_id=C, title="Trùng")["isError"]
    assert call(granted, signer, "sd_create_course", course_id="x2", title="T", status="archived")["isError"]  # Literal
    assert call(granted, signer, "sd_set_course_status", course_id=C, status="deleted")["isError"]
    assert call(granted, signer, "sd_assign_doc", doc_id="khong-co", course_id=C)["isError"]


def test_revoked_sub_cannot_manage_courses(granted, signer, loaded_session):
    _data(call(granted, signer, "sd_create_course", course_id=C, title="Python"))
    revoke(loaded_session, SUB)
    loaded_session.flush()
    result = call(granted, signer, "sd_set_course_status", course_id=C, status="published")
    assert result["isError"] and SUB in _text(result)
