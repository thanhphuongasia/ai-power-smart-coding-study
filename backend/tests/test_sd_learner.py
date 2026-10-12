"""API học viên System Design: danh sách, tài liệu, tiến độ đọc, khoá tuần tự, không lộ rubric."""

from __future__ import annotations

import os

import pytest
from sqlalchemy import select

from app.tables import SdAttempt, SdProgress
from tests.conftest import BACKEND_DIR
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401

SAMPLE = os.path.join(BACKEND_DIR, "content", "sd", "airline-reservation.md")
DOC = "design-an-airline-reservation-system"


@pytest.fixture(scope="module")
def sample_md() -> str:
    with open(SAMPLE, encoding="utf-8") as f:
        return f.read()


class World:
    """Một client, hai tài khoản học viên và một admin, tài liệu mẫu đã nhập."""

    def __init__(self, session, client_for, md: str, status: str | None = "published"):
        self.session = session
        self.client = client_for(session)
        self.hdr = {}
        for name, roles in (("admin", ("learner", "admin")), ("ann", ("learner",)), ("bob", ("learner",))):
            add_user(session, email=f"{name}@example.com", roles=roles)
            self.hdr[name] = bearer(login(self.client, email=f"{name}@example.com").json()["token"])
        self.import_md(md, status)

    def import_md(self, md: str, status: str | None = None):
        body = {"markdown": md, **({"status": status} if status else {})}
        r = self.client.post("/api/admin/sd/docs", json=body, headers=self.hdr["admin"])
        assert r.status_code == 200, r.json()
        return r.json()

    def doc(self, who="ann"):
        r = self.client.get(f"/api/sd/docs/{DOC}", headers=self.hdr[who])
        assert r.status_code == 200, r.json()
        return r.json()

    def put(self, section_id, cards, who="ann"):
        return self.client.put(
            f"/api/sd/docs/{DOC}/sections/{section_id}/progress", json={"read_cards": cards}, headers=self.hdr[who]
        )

    def read_section(self, section, who="ann"):
        r = self.put(section["id"], [c["id"] for c in section["cards"]], who)
        assert r.status_code == 200, r.json()
        return r.json()

    def read_all(self, who="ann"):
        for s in self.doc(who)["sections"]:
            self.read_section(s, who)


@pytest.fixture()
def world(db_session, client_for, sample_md):
    return World(db_session, client_for, sample_md)


def _keys(node) -> set[str]:
    """Mọi khoá xuất hiện ở bất kỳ độ sâu nào trong JSON."""
    out: set[str] = set()
    stack = [node]
    while stack:
        n = stack.pop()
        if isinstance(n, dict):
            out |= set(n)
            stack.extend(n.values())
        elif isinstance(n, list):
            stack.extend(n)
    return out


# --- hiển thị và quyền ----------------------------------------------------------------------


def test_draft_docs_are_invisible_to_learners(db_session, client_for, sample_md):
    w = World(db_session, client_for, sample_md, status="draft")
    assert w.client.get("/api/sd/docs", headers=w.hdr["ann"]).json() == {"items": []}
    assert w.client.get(f"/api/sd/docs/{DOC}", headers=w.hdr["ann"]).status_code == 404
    assert w.put("requirements", []).status_code == 404


def test_login_required(world):
    assert world.client.get("/api/sd/docs").status_code == 401
    assert world.client.get(f"/api/sd/docs/{DOC}").status_code == 401
    assert world.client.put(f"/api/sd/docs/{DOC}/sections/x/progress", json={"read_cards": []}).status_code == 401


def test_list_summary_for_new_learner(world):
    (item,) = world.client.get("/api/sd/docs", headers=world.hdr["ann"]).json()["items"]
    assert item["id"] == DOC and (item["sections"], item["sections_done"], item["tasks"], item["tasks_done"]) == (9, 0, 6, 0)
    assert item["cards_read"] == 0 and item["cards"] > 9 and item["phase2_unlocked"] is False


def test_fresh_doc_unlocks_only_first_section_and_hides_phase2(world):
    d = world.doc()
    assert [s["unlocked"] for s in d["sections"]] == [True] + [False] * 8
    assert not any(s["done"] or s["read"] for s in d["sections"])
    assert d["phase2_unlocked"] is False and d["context"] == []
    assert all(not t["unlocked"] and t["prompt"] is None and t["hints"] == [] for t in d["tasks"])


# --- INV-02: không lộ rubric/từ khoá -------------------------------------------------------


def test_responses_never_contain_rubric_or_keywords(world):
    seen = [world.client.get("/api/sd/docs", headers=world.hdr["ann"]).json(), world.doc()]
    world.read_all()
    unlocked = world.doc()
    assert unlocked["phase2_unlocked"] is True and unlocked["tasks"][0]["prompt"]
    seen += [unlocked, world.put(unlocked["sections"][0]["id"], []).json()]
    for payload in seen:
        assert not _keys(payload) & {"rubric", "keywords", "auto_result", "verdicts"}, _keys(payload)


# --- tiến độ đọc và khoá tuần tự (INV-04) ---------------------------------------------------


def test_progress_marks_cards_done_and_unlocks_next_section(world):
    first = world.doc()["sections"][0]
    ids = [c["id"] for c in first["cards"]]
    part = world.put(first["id"], ids[:-1]).json()
    assert part["done"] is False and part["next_section_id"] is None and part["read"] == ids[:-1]
    full = world.put(first["id"], ids).json()
    assert full["done"] is True and full["next_section_id"] == world.doc()["sections"][1]["id"]
    assert [s["unlocked"] for s in world.doc()["sections"]][:3] == [True, True, False]


def test_progress_is_monotonic_and_ignores_unknown_ids(world):
    first = world.doc()["sections"][0]
    ids = [c["id"] for c in first["cards"]]
    world.put(first["id"], ids[:2])
    again = world.put(first["id"], ids[2:3] + ["no-such-card"]).json()
    assert again["read"] == ids[:3]  # cộng dồn: PUT sau không làm mất card đã đọc
    assert world.put(first["id"], []).json()["read"] == ids[:3]
    row = world.session.get(SdProgress, (world.session.scalars(select(SdProgress.user_id)).first(), DOC, first["id"]))
    assert "no-such-card" not in row.read_cards


def test_locked_section_cannot_record_progress(world):
    second = world.doc()["sections"][1]
    r = world.put(second["id"], [c["id"] for c in second["cards"]])
    assert r.status_code == 409 and r.json()["detail"] == "section_locked"
    assert world.session.scalars(select(SdProgress)).all() == []


def test_unknown_section_is_404(world):
    assert world.put("no-such-section", []).status_code == 404


def test_progress_is_per_user(world):
    first = world.doc()["sections"][0]
    world.read_section(first, "ann")
    assert world.doc("ann")["sections"][0]["done"] is True
    bob = world.doc("bob")
    assert bob["sections"][0]["done"] is False and bob["sections"][1]["unlocked"] is False


@pytest.mark.parametrize(
    "payload",
    [{"read_cards": "x"}, {"read_cards": ["a" * 21]}, {"read_cards": ["a"] * 201}, {"read_cards": [], "done": True}, {}],
)
def test_bad_progress_bodies_are_422(world, payload):
    first = world.doc()["sections"][0]["id"]
    r = world.client.put(f"/api/sd/docs/{DOC}/sections/{first}/progress", json=payload, headers=world.hdr["ann"])
    assert r.status_code == 422


# --- Phase 2 mở khoá khi đọc xong, task tuần tự theo lần thử ------------------------------


def test_phase2_unlocks_after_all_sections_and_tasks_follow_attempts(world):
    world.read_all()
    d = world.doc()
    assert d["phase2_unlocked"] is True and d["context"] and all(s["done"] for s in d["sections"])
    assert [t["unlocked"] for t in d["tasks"]] == [True] + [False] * 5
    assert d["tasks"][0]["prompt"] and d["tasks"][0]["hints"] and d["tasks"][0]["ref_section_id"]

    uid = world.session.scalars(select(SdProgress.user_id)).first()
    world.session.add(
        SdAttempt(user_id=uid, doc_id=DOC, task_id=d["tasks"][0]["id"], n=1, answer="a", auto_result={})
    )
    world.session.flush()
    d = world.doc()
    assert [t["done"] for t in d["tasks"]][:2] == [True, False]
    assert [t["unlocked"] for t in d["tasks"]] == [True, True] + [False] * 4
    assert d["tasks"][0]["attempts"] == 1
    item = world.client.get("/api/sd/docs", headers=world.hdr["ann"]).json()["items"][0]
    assert (item["phase2_unlocked"], item["tasks_done"]) == (True, 1)


def test_reimport_keeps_other_cards_read_but_edited_card_is_unread_again(world, sample_md):
    """INV-01 qua API: sửa 1 card rồi nhập lại, tiến độ card khác còn, section chứa card sửa hết `done`."""
    world.read_all()
    assert all(s["done"] for s in world.doc()["sections"])
    world.import_md(sample_md.replace("Chương trình khách hàng thân thiết", "Chương trình tích điểm"))
    d = world.doc()
    req = next(s for s in d["sections"] if s["id"] == "requirements")
    assert req["done"] is False and len(req["read"]) == len(req["cards"]) - 1
    assert sum(s["done"] for s in d["sections"]) == 8
    assert d["phase2_unlocked"] is False
