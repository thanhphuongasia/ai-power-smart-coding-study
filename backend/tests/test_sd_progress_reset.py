"""DELETE /api/sd/docs/{id}/progress (issue #66): đặt lại tiến độ đọc của đúng (học viên, tài liệu) — INV-03, INV-04."""

from __future__ import annotations

from sqlalchemy import select

from app.tables import SdAttempt, SdProgress, User
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_sd_admin import MINI
from tests.test_sd_learner import DOC, World, sample_md  # noqa: F401

URL = f"/api/sd/docs/{DOC}/progress"


def _uid(w, who) -> int:
    return w.session.scalars(select(User.id).where(User.email == f"{who}@example.com")).one()


def _rows(w, who, doc=DOC) -> list[SdProgress]:
    return list(w.session.scalars(select(SdProgress).where(SdProgress.user_id == _uid(w, who), SdProgress.doc_id == doc)))


def test_reset_clears_reading_relocks_phase2_and_keeps_attempts(db_session, client_for, sample_md):
    w = World(db_session, client_for, sample_md)
    w.import_md(MINI, "published")  # doc khác của cùng học viên: không được đụng
    mini = w.client.get("/api/sd/docs/mini", headers=w.hdr["ann"]).json()["sections"][0]
    assert w.client.put(f"/api/sd/docs/mini/sections/{mini['id']}/progress",
                        json={"read_cards": [c["id"] for c in mini["cards"]]}, headers=w.hdr["ann"]).status_code == 200
    w.read_all("ann")
    w.read_all("bob")
    assert w.doc()["phase2_unlocked"] is True
    r = w.client.post(f"/api/sd/docs/{DOC}/tasks/api-design/attempts", json={"answer": "giữ ghế"}, headers=w.hdr["ann"])
    assert r.status_code == 201, r.json()

    r = w.client.delete(URL, headers=w.hdr["ann"])
    assert r.status_code == 204 and r.content == b""

    d = w.doc()
    assert all(s["read"] == [] and not s["done"] and s["unlocked"] for s in d["sections"])
    assert d["phase2_unlocked"] is False and d["context"] == []  # INV-03: Phase 2 khoá lại
    (item,) = [i for i in w.client.get("/api/sd/docs", headers=w.hdr["ann"]).json()["items"] if i["id"] == DOC]
    assert (item["cards_read"], item["sections_done"], item["phase2_unlocked"]) == (0, 0, False)
    assert _rows(w, "ann") == []
    # INV-04: bài nộp, doc khác, học viên khác còn nguyên.
    assert w.session.scalars(select(SdAttempt).where(SdAttempt.user_id == _uid(w, "ann"))).all()
    assert len(_rows(w, "ann", "mini")) == 1
    assert w.doc("bob")["phase2_unlocked"] is True and _rows(w, "bob")

    # Đọc lại từ đầu vẫn ghi được; reset lần nữa (đã rỗng) vẫn 204.
    w.read_section(w.doc()["sections"][0])
    assert w.doc()["sections"][0]["done"] is True
    assert w.client.delete(URL, headers=w.hdr["ann"]).status_code == 204
    assert w.client.delete(URL, headers=w.hdr["ann"]).status_code == 204


def test_reset_needs_login_and_published_doc(db_session, client_for, sample_md):
    w = World(db_session, client_for, sample_md, status="draft")
    assert w.client.delete(URL).status_code == 401
    assert w.client.delete(URL, headers=w.hdr["ann"]).status_code == 404
    assert w.client.delete("/api/sd/docs/khong-co/progress", headers=w.hdr["ann"]).status_code == 404
