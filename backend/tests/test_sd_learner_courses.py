"""GET /api/sd/docs với course: nhóm + thứ tự, course chỉ để nhóm (không đổi tập doc được xem)."""

from __future__ import annotations

from app.sd import courses as sdc
from app.sd import docs as sddocs
from tests.test_sd_admin import MINI
from tests.test_sd_learner import DOC, World, sample_md  # noqa: F401
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401


def _world(db_session, client_for, sample_md):
    return World(db_session, client_for, sample_md)


def _add(w, doc_id, status="published"):
    sddocs.import_markdown(w.session, MINI, actor="t", doc_id=doc_id, status=status)


def _course(w, cid, *, status="published", position=0, **kw):
    return sdc.create_course(w.session, course_id=cid, title=f"T {cid}", actor="t", status=status, position=position, **kw)


def _assign(w, doc_id, cid, position=None):
    sdc.assign_doc(w.session, doc_id, cid, actor="t", position=position)


def _list(w):
    r = w.client.get("/api/sd/docs", headers=w.hdr["ann"])
    assert r.status_code == 200, r.json()
    return r.json()


def _ids(body):
    return [i["id"] for i in body["items"]]


def test_no_course_keeps_old_order(db_session, client_for, sample_md):
    w = _world(db_session, client_for, sample_md)
    _add(w, "mini-a")
    _add(w, "mini-b")
    body = _list(w)
    assert body["courses"] == []
    assert all(i["course_id"] is None for i in body["items"])
    assert _ids(body) == [DOC, "mini-a", "mini-b"]


def test_published_course_orders_docs_and_lists_course(db_session, client_for, sample_md):
    w = _world(db_session, client_for, sample_md)
    _add(w, "mini-a")
    _add(w, "mini-b")
    _course(w, "c1", skills=["cache"], domain="web")
    _assign(w, "mini-a", "c1", position=2)  # tạo trước nhưng đứng sau
    _assign(w, "mini-b", "c1", position=1)
    body = _list(w)
    assert _ids(body) == ["mini-b", "mini-a", DOC]
    assert [i["course_id"] for i in body["items"]] == ["c1", "c1", None]
    assert body["courses"] == [{"id": "c1", "title": "T c1", "skills": ["cache"], "domain": "web"}]
    assert {"id", "title", "sections", "cards", "phase2_unlocked", "tasks_done"} <= set(body["items"][0])


def test_draft_and_archived_course_keep_docs_but_hide_group(db_session, client_for, sample_md):
    w = _world(db_session, client_for, sample_md)
    _add(w, "mini-a")
    _add(w, "mini-b")
    _course(w, "cd", status="draft")
    _course(w, "ca")
    _assign(w, "mini-a", "cd", position=0)
    _assign(w, "mini-b", "ca", position=0)
    sdc.set_course_status(w.session, "ca", "archived", actor="t")
    body = _list(w)
    assert _ids(body) == [DOC, "mini-a", "mini-b"]  # INV-01: tập doc không đổi, về thứ tự created_at
    assert all(i["course_id"] is None for i in body["items"])
    assert body["courses"] == []


def test_two_published_courses_ordered_by_position(db_session, client_for, sample_md):
    w = _world(db_session, client_for, sample_md)
    _add(w, "mini-a")
    _add(w, "mini-b")
    _course(w, "c-first-created", position=5)
    _course(w, "c-second-created", position=1)
    _assign(w, "mini-a", "c-first-created", position=0)
    _assign(w, "mini-b", "c-second-created", position=0)
    body = _list(w)
    assert _ids(body) == ["mini-b", "mini-a", DOC]
    assert [c["id"] for c in body["courses"]] == ["c-second-created", "c-first-created"]


def test_course_with_only_draft_docs_not_listed(db_session, client_for, sample_md):
    w = _world(db_session, client_for, sample_md)
    _add(w, "mini-d", status="draft")
    _course(w, "c1")
    _assign(w, "mini-d", "c1", position=0)
    body = _list(w)
    assert body["courses"] == []
    assert _ids(body) == [DOC]


def test_draft_doc_in_published_course_not_exposed(db_session, client_for, sample_md):
    w = _world(db_session, client_for, sample_md)
    _add(w, "mini-a")
    _add(w, "mini-d", status="draft")
    _course(w, "c1")
    _assign(w, "mini-a", "c1", position=1)
    _assign(w, "mini-d", "c1", position=0)
    body = _list(w)
    assert _ids(body) == ["mini-a", DOC]
    assert [c["id"] for c in body["courses"]] == ["c1"]
