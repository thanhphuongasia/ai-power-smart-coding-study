"""Lần thử thực chiến: chấm từ khoá, nhiều lần thử, khoá task, trần, cô lập giữa học viên, bản reviewed thắng."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.sd.evaluator import KeywordEvaluator, fold
from app.tables import SdAttempt, SdTask, User
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401
from tests.test_sd_learner import DOC, World, _keys, sample_md  # noqa: F401

API = f"/api/sd/docs/{DOC}/tasks/api-design/attempts"
GOOD = "POST /holds giữ ghế riêng; đặt vé dùng Idempotency-Key; ghế bị giữ trả 409 Conflict; tìm chuyến theo date, from, origin."
HALF = "Có endpoint hold để giữ ghế và trả 409 khi ghế đã bị giữ."


@pytest.fixture()
def world(db_session, client_for, sample_md):
    w = World(db_session, client_for, sample_md)
    w.read_all()  # ann đọc xong Phase 1 → Phase 2 mở
    return w


def _post(w, answer, who="ann", url=API):
    return w.client.post(url, json={"answer": answer}, headers=w.hdr[who])


def _uid(w, who="ann") -> int:
    return w.session.scalars(select(User.id).where(User.email == f"{who}@example.com")).one()


# --- evaluator ------------------------------------------------------------------------------


def test_fold_ignores_case_and_vietnamese_marks():
    assert fold("Khoá GHẾ Đặt vé") == "khoa ghe dat ve"


def test_keyword_evaluator_scores_hits():
    rubric = [{"text": "a", "keywords": ["khoá", "lock"]}, {"text": "b", "keywords": ["redis"]}, {"text": "c", "keywords": ["cache"]}]
    r = KeywordEvaluator().evaluate("Dùng khoa ghe va REDIS", rubric)
    assert r == {"hits": [True, True, False], "score": 67}
    assert KeywordEvaluator().evaluate("x", []) == {"hits": [], "score": 0}


# --- nộp bài --------------------------------------------------------------------------------


def test_good_answer_hits_all_rubric_items(world):
    r = _post(world, GOOD)
    assert r.status_code == 201, r.json()
    a = r.json()["attempt"]
    assert (a["n"], a["source"], a["score"]) == (1, "auto", 100)
    assert [i["ok"] for i in a["items"]] == [True] * 4 and a["feedback"] is None
    assert a["items"][1]["text"].startswith("Đặt vé dùng Idempotency-Key")


def test_partial_answer_marks_missing_items(world):
    a = _post(world, HALF).json()["attempt"]
    assert [i["ok"] for i in a["items"]] == [True, False, True, False] and a["score"] == 50


def test_matching_ignores_missing_diacritics(world):
    _post(world, HALF)  # mở task kế
    url = f"/api/sd/docs/{DOC}/tasks/database-design/attempts"
    a = _post(world, "bang seats; ghe het han sau 10 phut; chan trung bang dieu kien", url=url).json()["attempt"]
    assert [i["ok"] for i in a["items"]] == [True, True, True, False]  # seats, hết hạn, điều kiện; không có bookings


def test_every_submit_is_a_new_numbered_row_newest_first(world):
    for text in (HALF, GOOD, "chưa biết"):
        assert _post(world, text).status_code == 201
    items = world.client.get(API, headers=world.hdr["ann"]).json()["items"]
    assert [i["n"] for i in items] == [3, 2, 1] and [i["score"] for i in items] == [0, 100, 50]
    assert world.client.get(API + "?limit=1", headers=world.hdr["ann"]).json()["items"][0]["n"] == 3


def test_next_task_unlocks_after_first_attempt(world):
    d = world.doc()
    assert [t["unlocked"] for t in d["tasks"]][:2] == [True, False]
    second = f"/api/sd/docs/{DOC}/tasks/database-design/attempts"
    assert _post(world, HALF, url=second).status_code == 409
    _post(world, HALF)
    assert [t["unlocked"] for t in world.doc()["tasks"]][:3] == [True, True, False]
    assert _post(world, "bảng seats có version", url=second).status_code == 201


def test_task_locked_before_phase2(db_session, client_for, sample_md):
    w = World(db_session, client_for, sample_md)  # chưa đọc gì
    r = _post(w, HALF)
    assert r.status_code == 409 and r.json()["detail"] == "task_locked"
    assert db_session.scalars(select(SdAttempt)).all() == []


def test_unknown_task_and_draft_doc_are_404(world, db_session, client_for, sample_md):
    assert _post(world, HALF, url=f"/api/sd/docs/{DOC}/tasks/nope/attempts").status_code == 404
    assert world.client.get(f"/api/sd/docs/{DOC}/tasks/nope/attempts", headers=world.hdr["ann"]).status_code == 404
    world.client.put(f"/api/admin/sd/docs/{DOC}/status", json={"status": "draft"}, headers=world.hdr["admin"])
    assert _post(world, HALF).status_code == 404


@pytest.mark.parametrize("answer", ["", "   \n", "x" * 8193, "é" * 4100, "a\x00b"])
def test_bad_answers_are_422(world, answer):
    assert _post(world, answer).status_code == 422
    assert world.session.scalars(select(SdAttempt)).all() == []


def test_exactly_eight_kilobytes_is_accepted(world):
    assert _post(world, "a" * 8192).status_code == 201


def test_extra_fields_are_422_and_login_is_required(world):
    r = world.client.post(API, json={"answer": "x", "status": "reviewed"}, headers=world.hdr["ann"])
    assert r.status_code == 422
    assert world.client.post(API, json={"answer": "x"}).status_code == 401
    assert world.client.get(API).status_code == 401


def test_daily_attempt_limit(world):
    uid, now = _uid(world), datetime.now(timezone.utc)
    for n in range(1, 21):
        world.session.add(SdAttempt(user_id=uid, doc_id=DOC, task_id="api-design", n=n, answer="a", auto_result={}, created_at=now))
    world.session.flush()
    r = _post(world, HALF)
    assert r.status_code == 429 and r.json()["detail"] == "attempt_limit"
    world.session.execute(SdAttempt.__table__.update().values(created_at=now - timedelta(days=2)))
    assert _post(world, HALF).status_code == 201  # đã quá 24 giờ: được nộp tiếp, n tiếp nối


def test_attempt_number_continues_after_gaps(world):
    world.session.add(SdAttempt(user_id=_uid(world), doc_id=DOC, task_id="api-design", n=7, answer="a", auto_result={}))
    world.session.flush()
    assert _post(world, HALF).json()["attempt"]["n"] == 8


# --- INV-02 và INV-06 -----------------------------------------------------------------------


def test_responses_never_expose_keywords_or_internal_fields(world):
    created = _post(world, GOOD).json()
    listed = world.client.get(API, headers=world.hdr["ann"]).json()
    for payload in (created, listed):
        assert not _keys(payload) & {"keywords", "rubric", "auto_result", "verdicts", "user_id", "reviewed_by"}, _keys(payload)


def test_learner_only_sees_own_attempts(world):
    _post(world, GOOD)
    world.read_all("bob")
    assert world.client.get(API, headers=world.hdr["bob"]).json() == {"items": []}
    bob = _post(world, HALF, "bob").json()["attempt"]
    assert bob["n"] == 1  # đếm n riêng từng user
    assert [i["n"] for i in world.client.get(API, headers=world.hdr["ann"]).json()["items"]] == [1]


# --- INV-03: bản reviewed thắng auto --------------------------------------------------------


def test_reviewed_attempt_replaces_auto_result_in_api(world):
    first = _post(world, GOOD).json()["attempt"]
    row = world.session.get(SdAttempt, first["id"])
    row.status, row.feedback, row.reviewed_by, row.reviewed_at = "reviewed", "Thiếu phân trang khi tìm chuyến.", "claude", datetime.now(timezone.utc)
    row.verdicts = [{"text": "Có endpoint giữ ghế", "ok": True, "note": "đúng"}, {"text": "Phân trang", "ok": False, "note": "chưa nói"}]
    world.session.flush()
    a = world.client.get(API, headers=world.hdr["ann"]).json()["items"][0]
    assert a["source"] == "reviewed" and a["feedback"] == "Thiếu phân trang khi tìm chuyến."
    assert [(i["text"], i["ok"], i["note"]) for i in a["items"]] == [("Có endpoint giữ ghế", True, "đúng"), ("Phân trang", False, "chưa nói")]
    assert a["score"] == 50 and a["reviewed_at"]
    assert not _keys(a) & {"verdicts", "reviewed_by"}


# --- cô lập quota / danh sách theo user và theo task (INV-06) --------------------------------


def test_quota_is_per_user_and_per_task(world):
    ann, now = _uid(world), datetime.now(timezone.utc)
    for n in range(1, 21):
        world.session.add(SdAttempt(user_id=ann, doc_id=DOC, task_id="api-design", n=n, answer="a", auto_result={}, created_at=now))
    world.session.flush()
    assert _post(world, HALF).status_code == 429
    world.read_all("bob")
    assert _post(world, HALF, "bob").status_code == 201  # lần thử của ann không khoá bob
    assert _post(world, "bảng seats", url=f"/api/sd/docs/{DOC}/tasks/database-design/attempts").status_code == 201  # quota của task khác


def test_attempt_list_is_scoped_to_the_task(world):
    _post(world, "câu trả lời cho api-design")
    other = f"/api/sd/docs/{DOC}/tasks/database-design/attempts"
    _post(world, "câu trả lời cho database-design", url=other)
    mine_api = world.client.get(API, headers=world.hdr["ann"]).json()["items"]
    mine_db = world.client.get(other, headers=world.hdr["ann"]).json()["items"]
    assert [i["answer"] for i in mine_api] == ["câu trả lời cho api-design"]
    assert [i["answer"] for i in mine_db] == ["câu trả lời cho database-design"]


def test_history_keeps_the_rubric_the_learner_saw(world, sample_md):
    a = _post(world, GOOD).json()["attempt"]
    assert len(a["items"]) == 4
    world.import_md(sample_md.replace("- Có Booking Service :: booking\n", "- Có Booking Service :: booking\n- Ý mới chen vào :: zzz\n"))
    world.import_md(sample_md.replace(
        "- Có endpoint giữ ghế (hold) tách riêng khỏi đặt vé :: hold, giữ ghế\n",
        "- Ý mới chen đầu :: zzz\n- Có endpoint giữ ghế (hold) tách riêng khỏi đặt vé :: hold, giữ ghế\n",
    ))
    again = world.client.get(API, headers=world.hdr["ann"]).json()["items"][0]
    assert [i["text"] for i in again["items"]] == [i["text"] for i in a["items"]] and all(i["ok"] for i in again["items"])
