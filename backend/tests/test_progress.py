"""API tiến độ theo user: GET /api/progress, PUT /api/progress/{exercise_id}, PUT /api/progress/state."""

from __future__ import annotations

import copy
import json

import pytest
from sqlalchemy import select

from app.load_content import load_content
from app.progress import record_pass
from app.tables import UserProgress, UserState

from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401

EX = "flight-init"  # có ô A, B, C
OTHER = "flight-seats-left"
BODY = {"drafts": {"A": "x = 1"}, "hints_used": {"A": 2}, "solution_viewed": ["B"]}


def _authed(session, client_for, email="test@gmail.com"):
    user = add_user(session, email=email)
    client = client_for(session)
    return user, client, bearer(login(client, email=email).json()["token"])


def test_all_endpoints_require_token(loaded_session, client_for):
    client = client_for(loaded_session)
    assert client.get("/api/progress").status_code == 401
    assert client.put(f"/api/progress/{EX}", json=BODY).status_code == 401
    assert client.put("/api/progress/state", json={"review": {}, "activity": {}}).status_code == 401
    assert client.put(f"/api/progress/{EX}", json=BODY, headers=bearer("forged")).status_code == 401


def test_get_empty(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    r = client.get("/api/progress", headers=h)
    assert r.status_code == 200
    assert r.json() == {"exercises": {}, "state": {"review": {}, "activity": {}}}


def test_put_then_get_round_trip_and_overwrite(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    assert client.put(f"/api/progress/{EX}", json=BODY, headers=h).status_code == 204
    got = client.get("/api/progress", headers=h).json()["exercises"]
    assert got == {EX: {"passed": False, **BODY}}
    newer = {"drafts": {"A": "y", "C": "z"}, "hints_used": {}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=newer, headers=h).status_code == 204
    assert client.get("/api/progress", headers=h).json()["exercises"][EX] == {"passed": False, **newer}


def test_put_cannot_set_passed_and_keeps_existing_passed(loaded_session, client_for):
    user, client, h = _authed(loaded_session, client_for)
    r = client.put(f"/api/progress/{EX}", json={**BODY, "passed": True}, headers=h)
    assert r.status_code == 422
    assert loaded_session.get(UserProgress, (user.id, EX)) is None

    record_pass(loaded_session, user.id, EX)
    assert client.put(f"/api/progress/{EX}", json=BODY, headers=h).status_code == 204
    loaded_session.expire_all()
    row = loaded_session.get(UserProgress, (user.id, EX))
    assert row.passed is True and row.drafts == BODY["drafts"]
    assert client.get("/api/progress", headers=h).json()["exercises"][EX]["passed"] is True


def test_missing_or_extra_fields_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    for body in ({"drafts": {}, "hints_used": {}}, {**BODY, "extra": 1}):
        assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 422


def test_unknown_exercise_404(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    r = client.put("/api/progress/no-such-exercise", json=BODY, headers=h)
    assert r.status_code == 404 and r.json() == {"detail": "exercise_not_found"}


@pytest.mark.parametrize(
    "body",
    [
        {"drafts": {"Z": "x"}, "hints_used": {}, "solution_viewed": []},
        {"drafts": {}, "hints_used": {"Z": 1}, "solution_viewed": []},
        {"drafts": {}, "hints_used": {}, "solution_viewed": ["Z"]},
    ],
)
def test_label_must_belong_to_exercise(loaded_session, client_for, body):
    _, client, h = _authed(loaded_session, client_for)
    assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 422


@pytest.mark.parametrize("value", [-1, 4, 1.5, "2", True])
def test_hints_out_of_range_422(loaded_session, client_for, value):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {}, "hints_used": {"A": value}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 422


def test_hints_boundaries_ok(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {}, "hints_used": {"A": 0, "B": 3}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 204


def test_oversized_drafts_413(loaded_session, client_for):
    # Middleware body 64KB của main.py chặn trước (detail body_too_large); cùng status 413.
    user, client, h = _authed(loaded_session, client_for)
    big = {"drafts": {"A": "x" * (64 * 1024 + 1)}, "hints_used": {}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=big, headers=h).status_code == 413
    assert loaded_session.get(UserProgress, (user.id, EX)) is None


def test_draft_limit_in_handler_counts_utf8_bytes(loaded_session, client_for, monkeypatch):
    """Giới hạn của handler (detail draft_too_large) tính theo byte UTF-8, không theo ký tự."""
    from app import progress

    monkeypatch.setattr(progress, "MAX_DRAFT_BYTES", 1000)
    user, client, h = _authed(loaded_session, client_for)

    def put(text):
        return client.put(f"/api/progress/{EX}", json={"drafts": {"A": text}, "hints_used": {}, "solution_viewed": []},
                          headers=h)

    assert put("x" * 900).status_code == 204
    assert put("é" * 400).status_code == 204  # 800 byte + khoá
    r = put("é" * 600)  # 600 ký tự nhưng 1200 byte
    assert r.status_code == 413 and r.json() == {"detail": "draft_too_large"}
    loaded_session.expire_all()
    assert loaded_session.get(UserProgress, (user.id, EX)).drafts == {"A": "é" * 400}  # lần hỏng không ghi


def test_users_are_isolated(loaded_session, client_for):
    a, client, ha = _authed(loaded_session, client_for, "a@gmail.com")
    add_user(loaded_session, email="b@gmail.com")
    hb = bearer(login(client, email="b@gmail.com").json()["token"])
    assert client.put(f"/api/progress/{EX}", json=BODY, headers=ha).status_code == 204
    assert client.put("/api/progress/state", json={"review": {"k": 1}, "activity": {"2026-01-02": 3}},
                      headers=ha).status_code == 204
    assert client.get("/api/progress", headers=hb).json() == {
        "exercises": {}, "state": {"review": {}, "activity": {}}}

    other = {"drafts": {"A": "b-code"}, "hints_used": {}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=other, headers=hb).status_code == 204
    loaded_session.expire_all()
    assert loaded_session.get(UserProgress, (a.id, EX)).drafts == BODY["drafts"]
    assert client.get("/api/progress", headers=ha).json()["exercises"][EX]["drafts"] == BODY["drafts"]


def _drop_exercise(content_data, exercise_id):
    data = copy.deepcopy(content_data)
    del data["exercises"][exercise_id]

    def strip(node):
        if isinstance(node, dict):
            if isinstance(node.get("exercise_ids"), list):
                node["exercise_ids"] = [i for i in node["exercise_ids"] if i != exercise_id]
            for v in node.values():
                strip(v)
        elif isinstance(node, list):
            for v in node:
                strip(v)

    strip(data)
    return data


def test_orphan_rows_hidden_from_get_but_kept_in_db(loaded_session, content_data, client_for):
    user, client, h = _authed(loaded_session, client_for)
    for ex in (EX, OTHER):
        assert client.put(f"/api/progress/{ex}", json=BODY, headers=h).status_code == 204
    load_content(loaded_session, _drop_exercise(content_data, OTHER))
    loaded_session.flush()

    assert set(client.get("/api/progress", headers=h).json()["exercises"]) == {EX}
    assert client.put(f"/api/progress/{OTHER}", json=BODY, headers=h).status_code == 404
    loaded_session.expire_all()
    assert loaded_session.get(UserProgress, (user.id, OTHER)) is not None

    # Nội dung trở lại → tiến độ cũ hiện lại.
    load_content(loaded_session, copy.deepcopy(content_data))
    loaded_session.flush()
    assert set(client.get("/api/progress", headers=h).json()["exercises"]) == {EX, OTHER}


def test_state_round_trip_and_replace(loaded_session, client_for):
    user, client, h = _authed(loaded_session, client_for)
    body = {"review": {"flight-init": {"due": "2026-02-01", "box": 2}}, "activity": {"2026-01-02": 3, "2026-01-03": 0}}
    assert client.put("/api/progress/state", json=body, headers=h).status_code == 204
    assert client.get("/api/progress", headers=h).json()["state"] == body
    body2 = {"review": {}, "activity": {"2026-02-01": 5}}
    assert client.put("/api/progress/state", json=body2, headers=h).status_code == 204
    assert client.get("/api/progress", headers=h).json()["state"] == body2
    assert len(loaded_session.scalars(select(UserState).where(UserState.user_id == user.id)).all()) == 1


def test_state_route_is_not_captured_by_exercise_route(loaded_session, client_for):
    """Nếu bị bắt nhầm bởi {exercise_id} thì body state sẽ 422 (thiếu drafts) hoặc 404."""
    _, client, h = _authed(loaded_session, client_for)
    assert client.put("/api/progress/state", json={"review": {}, "activity": {}}, headers=h).status_code == 204


@pytest.mark.parametrize(
    "body",
    [
        {"review": {}, "activity": {"2026-1-2": 1}},
        {"review": {}, "activity": {"not-a-date": 1}},
        {"review": {}, "activity": {"2026-13-45": 1}},
        {"review": {}, "activity": {"2026-01-02": -1}},
        {"review": {}, "activity": {"2026-01-02": 1.5}},
        {"review": {}, "activity": {"2026-01-02": "3"}},
        {"review": [], "activity": {}},
        {"review": {}},
        {"review": {}, "activity": {}, "extra": 1},
    ],
)
def test_state_validation_422(loaded_session, client_for, body):
    _, client, h = _authed(loaded_session, client_for)
    assert client.put("/api/progress/state", json=body, headers=h).status_code == 422


def test_state_size_limits(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    from datetime import date, timedelta

    start = date(2025, 1, 1)
    days = lambda n: {(start + timedelta(days=i)).isoformat(): 1 for i in range(n)}  # noqa: E731
    assert client.put("/api/progress/state", json={"review": {}, "activity": days(400)}, headers=h).status_code == 204
    assert client.put("/api/progress/state", json={"review": {}, "activity": days(401)}, headers=h).status_code == 422

    assert client.put("/api/progress/state", json={"review": {str(i): 1 for i in range(2000)}, "activity": {}},
                      headers=h).status_code == 204
    assert client.put("/api/progress/state", json={"review": {str(i): 1 for i in range(2001)}, "activity": {}},
                      headers=h).status_code == 422
    assert client.put("/api/progress/state", json={"review": {"k": "x" * (64 * 1024)}, "activity": {}},
                      headers=h).status_code == 413  # middleware body 64KB chặn trước


def test_state_review_byte_limit_in_validator(loaded_session, client_for, monkeypatch):
    from app import progress

    monkeypatch.setattr(progress, "MAX_REVIEW_BYTES", 100)
    _, client, h = _authed(loaded_session, client_for)
    assert client.put("/api/progress/state", json={"review": {"k": "x" * 50}, "activity": {}},
                      headers=h).status_code == 204
    assert client.put("/api/progress/state", json={"review": {"k": "é" * 80}, "activity": {}},
                      headers=h).status_code == 422


def test_draft_value_with_nul_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {"A": "x\u0000y"}, "hints_used": {}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 422


def test_draft_key_with_nul_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {"A\u0000": "x"}, "hints_used": {}, "solution_viewed": []}
    assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 422


def test_review_nested_nul_value_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"review": {"flight-init": {"note": ["ok", {"x": "a\u0000b"}]}}, "activity": {}}
    assert client.put("/api/progress/state", json=body, headers=h).status_code == 422


def test_review_key_with_nul_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"review": {"k\u0000": 1}, "activity": {}}
    assert client.put("/api/progress/state", json=body, headers=h).status_code == 422


def test_review_nan_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    raw = '{"review": {"k": NaN}, "activity": {}}'
    r = client.put("/api/progress/state", content=raw, headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 422


def test_solution_viewed_duplicates_deduped(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {}, "hints_used": {}, "solution_viewed": ["A", "A"]}
    assert client.put(f"/api/progress/{EX}", json=body, headers=h).status_code == 204
    assert client.get("/api/progress", headers=h).json()["exercises"][EX]["solution_viewed"] == ["A"]


# --- Surrogate (lone \ud800) và NUL trong path / lồng sâu: phải 422/404, không 500. ---
# Gửi ensure_ascii=True để "\ud800" đi qua dây dưới dạng escape, không phải byte UTF-8 hỏng.


def _put_raw(client, path, body, h):
    return client.put(path, content=json.dumps(body, ensure_ascii=True),
                      headers={**h, "Content-Type": "application/json"})


def test_surrogate_in_draft_value_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {"A": "x\ud800"}, "hints_used": {}, "solution_viewed": []}
    assert _put_raw(client, f"/api/progress/{EX}", body, h).status_code == 422


def test_surrogate_in_draft_key_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {"\ud800": "x"}, "hints_used": {}, "solution_viewed": []}
    assert _put_raw(client, f"/api/progress/{EX}", body, h).status_code == 422


def test_surrogate_in_solution_viewed_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {}, "hints_used": {}, "solution_viewed": ["\ud800"]}
    assert _put_raw(client, f"/api/progress/{EX}", body, h).status_code == 422


def test_surrogate_in_hints_used_key_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"drafts": {}, "hints_used": {"\ud800": 1}, "solution_viewed": []}
    assert _put_raw(client, f"/api/progress/{EX}", body, h).status_code == 422


def test_surrogate_in_review_value_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"review": {"flight-init": {"note": "\ud800"}}, "activity": {}}
    assert _put_raw(client, "/api/progress/state", body, h).status_code == 422


def test_nul_in_exercise_path_404(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    assert client.put("/api/progress/a%00b", json=BODY, headers=h).status_code == 404


def _nested(depth):
    node = "leaf"
    for _ in range(depth):
        node = {"n": node}
    return node


def test_review_nested_100_levels_422(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"review": {"flight-init": _nested(100)}, "activity": {}}
    assert _put_raw(client, "/api/progress/state", body, h).status_code == 422


def test_review_nested_10_levels_204(loaded_session, client_for):
    _, client, h = _authed(loaded_session, client_for)
    body = {"review": {"flight-init": _nested(10)}, "activity": {}}
    assert _put_raw(client, "/api/progress/state", body, h).status_code == 204
