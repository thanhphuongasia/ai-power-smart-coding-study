"""Nghiệp vụ tài liệu SD dùng chung (app/sd/docs.py): mode create/replace/upsert, markdown gốc, sửa theo đoạn,
xoá mềm. INV-02 (một đường nhập, luôn lưu source_md), INV-03 (không chạm tiến độ/bài nộp), INV-04 (archived),
INV-07 (create không ghi đè)."""

from __future__ import annotations

import time

import pytest
from sqlalchemy import select

from app.sd import docs
from app.sd.docs import SdDocError, SdDocNotFound, apply_edits
from app.tables import SdAttempt, SdDoc, SdProgress
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_sd_admin import MINI, sample_md  # noqa: F401

ACTOR = "mcp:test-sub"


def _imp(session, md, **kw):
    kw.setdefault("actor", ACTOR)
    return docs.import_markdown(session, md, **kw)


# --- mode + markdown gốc -----------------------------------------------------------------------


def test_every_mode_stores_source_markdown(db_session, sample_md):
    created = _imp(db_session, MINI, mode="create")
    assert db_session.get(SdDoc, created["id"]).source_md == MINI
    edited = MINI.replace("Đoạn hai.", "Đoạn hai, đã sửa.")
    _imp(db_session, edited, doc_id=created["id"], mode="replace")
    assert db_session.get(SdDoc, created["id"]).source_md == edited
    up = _imp(db_session, sample_md)  # upsert (đường của API admin)
    assert db_session.get(SdDoc, up["id"]).source_md == sample_md


def test_admin_api_import_stores_markdown_too(db_session, client_for, sample_md):
    # INV-02: doc nhập qua API admin sửa được bằng edit (có markdown gốc).
    add_user(db_session, email="a@example.com", roles=("learner", "admin"))
    client = client_for(db_session)
    h = bearer(login(client, email="a@example.com").json()["token"])
    doc_id = client.post("/api/admin/sd/docs", json={"markdown": sample_md}, headers=h).json()["id"]
    assert docs.get_doc(db_session, doc_id)["markdown"] == sample_md
    listed = client.get("/api/admin/sd/docs", headers=h).json()["items"]
    assert listed[0]["has_markdown"] is True


def test_create_refuses_existing_id_even_when_archived(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    with pytest.raises(SdDocError, match="đã có tài liệu"):
        _imp(db_session, MINI, mode="create")
    docs.set_status(db_session, doc_id, "archived", actor=ACTOR)
    with pytest.raises(SdDocError, match="archived"):
        _imp(db_session, MINI.replace("Đoạn một.", "Khác."), mode="create")
    assert db_session.get(SdDoc, doc_id).source_md == MINI  # không bị ghi đè lặng lẽ


def test_replace_needs_existing_doc(db_session):
    with pytest.raises(SdDocNotFound):
        _imp(db_session, MINI, doc_id="khong-co", mode="replace")


def test_replace_with_stale_revision_is_refused(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    stale = docs.get_doc(db_session, doc_id)["revision"]
    _imp(db_session, MINI.replace("Đoạn một.", "Bản A."), doc_id=doc_id, mode="replace")
    with pytest.raises(SdDocError, match="revision"):
        _imp(db_session, MINI.replace("Đoạn một.", "Bản B."), doc_id=doc_id, mode="replace", base_revision=stale)
    fresh = docs.get_doc(db_session, doc_id)["revision"]
    _imp(db_session, MINI.replace("Đoạn một.", "Bản B."), doc_id=doc_id, mode="replace", base_revision=fresh)
    assert "Bản B." in db_session.get(SdDoc, doc_id).source_md


def test_dry_run_writes_nothing(db_session):
    summary = _imp(db_session, MINI, mode="create", dry_run=True)
    assert summary["dry_run"] is True and summary["status"] == "draft"
    assert db_session.get(SdDoc, summary["id"]) is None


def test_dry_run_reports_card_diff_against_current(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    s = _imp(db_session, MINI.replace("Đoạn hai.", "Đoạn hai mới."), doc_id=doc_id, mode="replace", dry_run=True)
    assert (s["cards_added"], s["cards_removed"]) == (1, 1)
    assert db_session.get(SdDoc, doc_id).source_md == MINI


@pytest.mark.parametrize(
    "kwargs, needle",
    [
        ({"mode": "bogus"}, "mode"),
        ({"status": "archived"}, "status"),
        ({"doc_id": "Có Dấu"}, "id tài liệu"),
        ({"doc_id": "x" * 101}, "id tài liệu"),
    ],
)
def test_bad_arguments(db_session, kwargs, needle):
    with pytest.raises(SdDocError, match=needle):
        _imp(db_session, MINI, **kwargs)


def test_parser_errors_surface_as_list(db_session):
    with pytest.raises(SdDocError) as exc:
        _imp(db_session, "không có tiêu đề")
    assert exc.value.errors


# --- tiến độ / bài nộp không bị chạm (INV-03) --------------------------------------------------


def test_reimport_and_edit_keep_progress_and_attempts(db_session):
    doc_id = _imp(db_session, MINI, mode="create", status="published")["id"]
    uid = add_user(db_session, email="hv@example.com").id
    db_session.add(SdProgress(user_id=uid, doc_id=doc_id, section_id="muc-a", read_cards=["x1"]))
    db_session.add(SdAttempt(user_id=uid, doc_id=doc_id, task_id="task-a", n=1, answer="bài", auto_result={}))
    db_session.commit()
    docs.edit_doc(db_session, doc_id, [{"old_text": "Đoạn hai.", "new_text": "Đoạn hai đã sửa."}], actor=ACTOR)
    docs.set_status(db_session, doc_id, "archived", actor=ACTOR)
    docs.set_status(db_session, doc_id, "published", actor=ACTOR)
    assert db_session.get(SdProgress, (uid, doc_id, "muc-a")).read_cards == ["x1"]
    assert len(db_session.scalars(select(SdAttempt).where(SdAttempt.doc_id == doc_id)).all()) == 1


# --- sửa theo đoạn -----------------------------------------------------------------------------


def test_edit_doc_applies_and_keeps_status(db_session):
    doc_id = _imp(db_session, MINI, mode="create", status="published")["id"]
    out = docs.edit_doc(db_session, doc_id, [{"old_text": "Đoạn một.", "new_text": "Đoạn đầu."}], actor=ACTOR)
    assert out["status"] == "published" and (out["cards_added"], out["cards_removed"]) == (1, 1)
    assert "Đoạn đầu." in db_session.get(SdDoc, doc_id).source_md


def test_edit_doc_without_source_markdown_explains(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    db_session.get(SdDoc, doc_id).source_md = None  # doc nhập trước migration 0008
    db_session.commit()
    with pytest.raises(SdDocError, match="replace"):
        docs.edit_doc(db_session, doc_id, [{"old_text": "a", "new_text": "b"}], actor=ACTOR)


def test_edit_dry_run_changes_nothing(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    out = docs.edit_doc(db_session, doc_id, [{"old_text": "Đoạn một.", "new_text": "X."}], actor=ACTOR, dry_run=True)
    assert out["dry_run"] is True
    assert db_session.get(SdDoc, doc_id).source_md == MINI


def test_edit_unknown_doc(db_session):
    with pytest.raises(SdDocNotFound):
        docs.edit_doc(db_session, "khong-co", [{"old_text": "a", "new_text": "b"}], actor=ACTOR)


@pytest.mark.parametrize(
    "edits, needle",
    [
        ([], "ít nhất 1"),
        ("abc", "ít nhất 1"),
        ([{"old_text": "zzz", "new_text": "y"}], "không tìm thấy"),
        ([{"old_text": "Đoạn", "new_text": "y"}], "nhiều hơn một lần"),
        ([{"old_text": "", "new_text": "y"}], "không rỗng"),
        ([{"old_text": "a"}], "đúng hai khoá"),
        ([{"old_text": "a", "new_text": "b", "x": 1}], "đúng hai khoá"),
        ([{"old_text": "a" * 20_001, "new_text": "b"}], "tối đa"),
        ([{"old_text": "Đoạn một.", "new_text": "b"}] * 51, "tối đa 50"),
    ],
)
def test_apply_edits_rejects(edits, needle):
    with pytest.raises(SdDocError, match=needle):
        apply_edits(MINI, edits)


def test_apply_edits_detects_overlapping_matches():
    with pytest.raises(SdDocError, match="nhiều hơn một lần"):
        apply_edits("aaa", [{"old_text": "aa", "new_text": "b"}])


def test_apply_edits_sequential():
    assert apply_edits("a-b-c", [{"old_text": "a-", "new_text": ""}, {"old_text": "b-", "new_text": "B+"}]) == "B+c"


def test_apply_edits_worst_case_is_fast():
    # hostile-input-budget: 1MB markdown, 50 edit, mỗi old_text 20k ký tự gần khớp ở khắp nơi.
    source = ("a" * 19_999 + "b") * 50
    edits = [{"old_text": "a" * 19_999 + "c", "new_text": "x"}] * 50
    started = time.monotonic()
    with pytest.raises(SdDocError):
        apply_edits(source, edits)
    assert time.monotonic() - started < 1.0


# --- list / get / status -----------------------------------------------------------------------


def test_list_hides_archived_by_default(db_session):
    keep = _imp(db_session, MINI, mode="create")["id"]
    gone = _imp(db_session, MINI.replace("# Mini", "# Mini hai"), mode="create")["id"]
    docs.set_status(db_session, gone, "archived", actor=ACTOR)
    assert [d["id"] for d in docs.list_docs(db_session)] == [keep]
    assert {d["id"] for d in docs.list_docs(db_session, include_archived=True)} == {keep, gone}


def test_get_doc_outline_tasks_markdown(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    got = docs.get_doc(db_session, doc_id)
    assert got["markdown"] == MINI and got["revision"] == docs.revision(MINI)
    assert got["outline"][0]["title"] == "Mục A" and got["outline"][0]["cards"] == 2
    assert got["tasks"][0]["name"] == "Task A" and got["tasks"][0]["rubric_items"] == 1


def test_set_status_validates(db_session):
    doc_id = _imp(db_session, MINI, mode="create")["id"]
    with pytest.raises(SdDocError, match="status"):
        docs.set_status(db_session, doc_id, "deleted", actor=ACTOR)
    with pytest.raises(SdDocNotFound):
        docs.set_status(db_session, "khong-co", "archived", actor=ACTOR)
    assert docs.set_status(db_session, doc_id, "archived", actor=ACTOR) == {"id": doc_id, "status": "archived", "previous": "draft"}


def test_admin_api_can_archive_and_restore(db_session, client_for):
    # INV-04: Literal API admin nhận archived, DB constraint nhận archived.
    add_user(db_session, email="a2@example.com", roles=("learner", "admin"))
    client = client_for(db_session)
    h = bearer(login(client, email="a2@example.com").json()["token"])
    doc_id = client.post("/api/admin/sd/docs", json={"markdown": MINI}, headers=h).json()["id"]
    r = client.put(f"/api/admin/sd/docs/{doc_id}/status", json={"status": "archived"}, headers=h)
    assert r.status_code == 200 and r.json() == {"id": doc_id, "status": "archived"}
    assert client.get("/api/admin/sd/docs?include_archived=false", headers=h).json()["items"] == []
    assert client.put(f"/api/admin/sd/docs/{doc_id}/status", json={"status": "published"}, headers=h).status_code == 200
