"""Course nhóm tài liệu SD (app/sd/courses.py): CRUD + validate, xoá mềm giữ nhóm (INV-05), nhập lại doc giữ
course (INV-02), trạng thái thống nhất (INV-03), thứ tự doc (INV-07)."""

from __future__ import annotations

import pytest

from app.sd import courses, docs
from app.sd.courses import CourseNotFound
from app.sd.docs import SdDocError, SdDocNotFound
from app.tables import Course, SdDoc
from tests.test_sd_admin import MINI

ACTOR = "mcp:test-sub"


def _doc(session, title: str) -> str:
    return docs.import_markdown(session, MINI.replace("# Mini", f"# {title}"), actor=ACTOR, mode="create")["id"]


def _course(session, cid="python-basics", **kw):
    kw.setdefault("title", "Python cơ bản")
    return courses.create_course(session, course_id=cid, actor=ACTOR, **kw)


def test_create_and_list(db_session):
    made = _course(db_session, skills=["python", "python", " oop "], domain="document-management", position=2)
    assert made == {
        "id": "python-basics", "title": "Python cơ bản", "skills": ["python", "oop"],
        "domain": "document-management", "status": "draft", "position": 2, "docs": [],
    }
    assert [c["id"] for c in courses.list_courses(db_session)] == ["python-basics"]


def test_create_refuses_existing_id_even_archived(db_session):
    _course(db_session)
    courses.set_course_status(db_session, "python-basics", "archived", actor=ACTOR)
    with pytest.raises(SdDocError, match="archived"):
        _course(db_session, title="Khác")


@pytest.mark.parametrize(
    "kwargs, needle",
    [
        ({"course_id": "Có Dấu"}, "id"),
        ({"title": "  "}, "title"),
        ({"title": "x" * 201}, "title"),
        ({"skills": ["a"] * 21}, "skills"),
        ({"skills": ["x" * 41]}, "skill"),
        ({"skills": "python"}, "skills"),
        ({"domain": "x" * 101}, "domain"),
        ({"position": -1}, "position"),
        ({"position": True}, "position"),
        ({"status": "archived"}, "status"),
    ],
)
def test_create_validates(db_session, kwargs, needle):
    kwargs.setdefault("course_id", "c1")
    kwargs.setdefault("title", "T")
    with pytest.raises(SdDocError, match=needle):
        courses.create_course(db_session, actor=ACTOR, **kwargs)


def test_update_only_editable_fields(db_session):
    _course(db_session)
    out = courses.update_course(db_session, "python-basics", {"title": "Mới", "skills": ["sd"], "domain": None}, actor=ACTOR)
    assert (out["title"], out["skills"], out["domain"]) == ("Mới", ["sd"], None)
    with pytest.raises(SdDocError, match="không sửa được"):
        courses.update_course(db_session, "python-basics", {"status": "published"}, actor=ACTOR)
    with pytest.raises(SdDocError, match="ít nhất"):
        courses.update_course(db_session, "python-basics", {}, actor=ACTOR)
    with pytest.raises(CourseNotFound):
        courses.update_course(db_session, "khong-co", {"title": "x"}, actor=ACTOR)


def test_status_set_matches_db_constraint(db_session):
    # INV-03: cả ba trạng thái ghi được xuống DB; giá trị lạ bị service chặn trước DB.
    _course(db_session)
    for status in ("published", "archived", "draft"):
        assert courses.set_course_status(db_session, "python-basics", status, actor=ACTOR)["status"] == status
    with pytest.raises(SdDocError, match="status"):
        courses.set_course_status(db_session, "python-basics", "deleted", actor=ACTOR)
    with pytest.raises(CourseNotFound):
        courses.set_course_status(db_session, "khong-co", "draft", actor=ACTOR)


def test_assign_and_order(db_session):
    # INV-07: vị trí đã đặt trước, chưa đặt xếp cuối theo ngày tạo.
    _course(db_session)
    a, b, c = _doc(db_session, "Bài A"), _doc(db_session, "Bài B"), _doc(db_session, "Bài C")
    courses.assign_doc(db_session, c, "python-basics", actor=ACTOR, position=1)
    courses.assign_doc(db_session, a, "python-basics", actor=ACTOR)
    courses.assign_doc(db_session, b, "python-basics", actor=ACTOR, position=0)
    listed = courses.list_courses(db_session)[0]["docs"]
    assert [d["id"] for d in listed] == [b, c, a]
    assert docs.get_doc(db_session, b)["course_id"] == "python-basics"
    assert {d["id"]: d["course_id"] for d in docs.list_docs(db_session)}[a] == "python-basics"


def test_unassign_clears_position(db_session):
    _course(db_session)
    a = _doc(db_session, "Bài A")
    courses.assign_doc(db_session, a, "python-basics", actor=ACTOR, position=3)
    out = courses.assign_doc(db_session, a, None, actor=ACTOR, position=5)
    assert out["course_id"] is None and out["previous_course_id"] == "python-basics"
    doc = db_session.get(SdDoc, a)
    assert (doc.course_id, doc.course_position) == (None, None)


def test_assign_refuses_archived_or_unknown(db_session):
    _course(db_session)
    a = _doc(db_session, "Bài A")
    courses.set_course_status(db_session, "python-basics", "archived", actor=ACTOR)
    with pytest.raises(SdDocError, match="xoá mềm"):
        courses.assign_doc(db_session, a, "python-basics", actor=ACTOR)
    with pytest.raises(CourseNotFound):
        courses.assign_doc(db_session, a, "khong-co", actor=ACTOR)
    courses.set_course_status(db_session, "python-basics", "draft", actor=ACTOR)
    with pytest.raises(SdDocNotFound):
        courses.assign_doc(db_session, "khong-co-doc", "python-basics", actor=ACTOR)
    with pytest.raises(SdDocError, match="position"):
        courses.assign_doc(db_session, a, "python-basics", actor=ACTOR, position=10_001)


def test_archive_keeps_docs_grouped_and_restore(db_session):
    # INV-05: xoá mềm course không gỡ doc; khôi phục là doc về đúng nhóm.
    _course(db_session)
    a = _doc(db_session, "Bài A")
    courses.assign_doc(db_session, a, "python-basics", actor=ACTOR, position=0)
    courses.set_course_status(db_session, "python-basics", "archived", actor=ACTOR)
    assert db_session.get(SdDoc, a).course_id == "python-basics"
    assert courses.list_courses(db_session) == []
    archived = courses.list_courses(db_session, include_archived=True)
    assert archived[0]["status"] == "archived" and [d["id"] for d in archived[0]["docs"]] == [a]
    courses.set_course_status(db_session, "python-basics", "published", actor=ACTOR)
    assert [d["id"] for d in courses.list_courses(db_session)[0]["docs"]] == [a]


def test_reimport_edit_and_doc_status_keep_course(db_session):
    # INV-02: nhập lại / sửa / đổi status doc không đụng course_id, course_position.
    _course(db_session)
    a = _doc(db_session, "Bài A")
    courses.assign_doc(db_session, a, "python-basics", actor=ACTOR, position=4)
    md = db_session.get(SdDoc, a).source_md
    docs.import_markdown(db_session, md.replace("Đoạn một.", "Đoạn đầu."), actor=ACTOR, doc_id=a, mode="replace")
    docs.edit_doc(db_session, a, [{"old_text": "Đoạn hai.", "new_text": "Đoạn sau."}], actor=ACTOR)
    docs.set_status(db_session, a, "published", actor=ACTOR)
    docs.import_markdown(db_session, md, actor=ACTOR, doc_id=a)  # upsert (đường API admin)
    doc = db_session.get(SdDoc, a)
    assert (doc.course_id, doc.course_position) == ("python-basics", 4)


def test_course_row_defaults(db_session):
    _course(db_session)
    row = db_session.get(Course, "python-basics")
    assert row.skills == [] and row.domain is None and row.position == 0
