"""Tài liệu archived (xoá mềm): học viên không thấy/không thao tác được, dữ liệu còn nguyên, hàng đợi chấm bỏ qua."""

from __future__ import annotations

import pytest
from sqlalchemy import select

from app.sd import docs as sd_docs
from app.sd.attempts import review_queue
from app.tables import SdAttempt, SdProgress
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_sd_learner import DOC, World, sample_md  # noqa: F401

ATT = f"/api/sd/docs/{DOC}/tasks/api-design/attempts"
ANSWER = "POST /holds giữ ghế riêng; đặt vé dùng Idempotency-Key."


@pytest.fixture()
def world(db_session, client_for, sample_md):
    w = World(db_session, client_for, sample_md)
    w.read_all()  # Phase 2 mở
    return w


def _set(w, status):
    sd_docs.set_status(w.session, DOC, status, actor="test")


def _queue(w, **kw):
    return review_queue(w.session, doc_id=None, task_id=None, status=None, limit=50, **kw)


def _submit(w):
    r = w.client.post(ATT, json={"answer": ANSWER}, headers=w.hdr["ann"])
    assert r.status_code == 201, r.json()


def test_learner_gets_404_everywhere_when_archived(world):
    w = world
    sec = w.doc()["sections"][0]
    _set(w, "archived")
    h = w.hdr["ann"]
    assert DOC not in [d["id"] for d in w.client.get("/api/sd/docs", headers=h).json()["items"]]
    assert w.client.get(f"/api/sd/docs/{DOC}", headers=h).status_code == 404
    put = w.client.put(f"/api/sd/docs/{DOC}/sections/{sec['id']}/progress", json={"read_cards": []}, headers=h)
    assert put.status_code == 404
    assert w.client.post(ATT, json={"answer": ANSWER}, headers=h).status_code == 404
    assert w.client.get(ATT, headers=h).status_code == 404


def test_archive_keeps_data_and_restore_shows_it_again(world):
    w = world
    _submit(w)
    _set(w, "archived")
    assert w.session.scalars(select(SdAttempt).where(SdAttempt.doc_id == DOC)).all()
    assert w.session.scalars(select(SdProgress).where(SdProgress.doc_id == DOC)).all()
    _set(w, "published")
    d = w.doc()
    assert all(s["done"] for s in d["sections"])  # tiến độ cũ còn
    items = w.client.get(ATT, headers=w.hdr["ann"]).json()["items"]
    assert [a["n"] for a in items] == [1]
    listed = [x for x in w.client.get("/api/sd/docs", headers=w.hdr["ann"]).json()["items"] if x["id"] == DOC]
    assert listed and listed[0]["tasks_done"] == 1


def test_review_queue_skips_archived_unless_asked(world):
    w = world
    _submit(w)
    assert [a["doc_id"] for a in _queue(w)] == [DOC]
    _set(w, "archived")
    assert _queue(w) == []
    assert [a["doc_id"] for a in _queue(w, include_archived=True)] == [DOC]
    _set(w, "draft")  # draft không phải archived: vẫn nằm trong hàng đợi
    assert [a["doc_id"] for a in _queue(w)] == [DOC]
    _set(w, "published")
    assert [a["doc_id"] for a in _queue(w)] == [DOC]
