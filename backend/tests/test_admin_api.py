"""API quản trị nội dung: quyền (INV-02), một đường ghi + version (INV-06), tiến độ sống sót (INV-04)."""

from __future__ import annotations

import copy

import pytest

from app.content_api import read_content
from app.load_content import has_content, main as load_main
from app.progress import record_pass
from app.tables import UserProgress
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401

ADMIN = "phuongtt.tech1508@gmail.com"


@pytest.fixture()
def admin(loaded_session, client_for):
    add_user(loaded_session, email=ADMIN, roles=("learner", "admin"))
    client = client_for(loaded_session)
    token = login(client, email=ADMIN).json()["token"]
    return client, bearer(token)


def _source(content_data: dict) -> dict:
    return {k: v for k, v in content_data.items() if k != "version"}


@pytest.mark.parametrize("roles", [None, ("learner",)])
def test_admin_endpoints_need_admin_role(loaded_session, client_for, content_data, roles):
    client = client_for(loaded_session)
    headers = {}
    if roles:
        add_user(loaded_session, roles=roles)
        headers = bearer(login(client).json()["token"])
    expected = 403 if roles else 401
    body = {"content": _source(content_data)}
    assert client.get("/api/admin/content", headers=headers).status_code == expected
    assert client.post("/api/admin/validate", json=body, headers=headers).status_code == expected
    put = {"base_version": "x", **body}
    assert client.put("/api/admin/content", json=put, headers=headers).status_code == expected


def test_get_returns_full_content_with_judge(admin, content_data):
    client, h = admin
    r = client.get("/api/admin/content", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["version"].startswith("sha256:")
    assert body["content"]["themes"] == content_data["themes"]
    assert body["content"]["exercises"] == content_data["exercises"]  # CÓ judge


def test_validate_reports_errors_without_writing(admin, content_data, loaded_session):
    client, h = admin
    ok = client.post("/api/admin/validate", json={"content": _source(content_data)}, headers=h).json()
    assert ok == {"ok": True, "errors": []}
    bad = copy.deepcopy(_source(content_data))
    bad["exercises"]["split-chunks"]["judge"]["solution"] += "\n"
    r = client.post("/api/admin/validate", json={"content": bad}, headers=h).json()
    assert r["ok"] is False and any("judge.solution" in e for e in r["errors"])
    assert read_content(loaded_session)["exercises"]["split-chunks"]["title"] == content_data["exercises"]["split-chunks"]["title"]


def test_save_with_current_version_updates_content_and_version(admin, loaded_session):
    client, h = admin
    got = client.get("/api/admin/content", headers=h).json()
    content = got["content"]
    content["exercises"]["split-chunks"]["title"] = "Chia văn bản (đã sửa)"
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
    assert r.status_code == 200
    new_version = r.json()["version"]
    assert new_version != got["version"]
    assert client.get("/api/admin/content", headers=h).json()["version"] == new_version
    public = client.get("/content").json()
    assert public["exercises"]["split-chunks"]["title"] == "Chia văn bản (đã sửa)"


def test_stale_base_version_is_409_and_keeps_db(admin, loaded_session):
    client, h = admin
    got = client.get("/api/admin/content", headers=h).json()
    first = copy.deepcopy(got["content"])
    first["exercises"]["split-chunks"]["title"] = "Admin A"
    assert client.put("/api/admin/content", json={"base_version": got["version"], "content": first}, headers=h).status_code == 200
    second = copy.deepcopy(got["content"])
    second["exercises"]["split-chunks"]["title"] = "Admin B"
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": second}, headers=h)
    assert r.status_code == 409 and r.json() == {"detail": "version_conflict"}
    assert client.get("/content").json()["exercises"]["split-chunks"]["title"] == "Admin A"


def test_judge_only_edit_changes_admin_version(admin):
    """Sửa mỗi test case (không công khai) vẫn phải đổi version, để admin khác bị 409."""
    client, h = admin
    got = client.get("/api/admin/content", headers=h).json()
    content = got["content"]
    content["exercises"]["split-chunks"]["judge"]["cases"].append(copy.deepcopy(content["exercises"]["split-chunks"]["judge"]["cases"][0]))
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
    assert r.status_code == 200 and r.json()["version"] != got["version"]


def test_invalid_save_is_422_with_errors_and_keeps_db(admin, content_data):
    client, h = admin
    got = client.get("/api/admin/content", headers=h).json()
    content = got["content"]
    content["exercises"]["split-chunks"]["blocks"][0]["hints"] = ["chỉ một"]
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
    assert r.status_code == 422
    assert any("đúng 3 gợi ý" in e for e in r.json()["errors"])
    assert client.get("/api/admin/content", headers=h).json()["version"] == got["version"]


def test_admin_save_keeps_learner_progress(admin, loaded_session):
    """INV-04: admin lưu = thay toàn bộ nội dung; tiến độ học viên không mất, kể cả bài bị xoá."""
    client, h = admin
    learner = add_user(loaded_session, email="test@gmail.com")
    record_pass(loaded_session, learner.id, "split-chunks")
    got = client.get("/api/admin/content", headers=h).json()
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": got["content"]}, headers=h)
    assert r.status_code == 200
    assert loaded_session.get(UserProgress, (learner.id, "split-chunks")).passed is True


def test_admin_body_limit_is_larger_than_learner_limit(admin, content_data):
    """content.json lớn hơn 64KB: lọt qua middleware ở /api/admin nhưng không ở chỗ khác."""
    import json

    client, h = admin
    raw = json.dumps({"content": _source(content_data)}).encode()
    assert len(raw) > 64 * 1024
    r = client.post("/api/admin/validate", content=raw, headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 200
    r = client.post("/api/auth/login", content=raw, headers={"Content-Type": "application/json"})
    assert r.status_code == 413


def test_extra_keys_rejected(admin, content_data):
    client, h = admin
    r = client.post("/api/admin/validate", json={"content": _source(content_data), "x": 1}, headers=h)
    assert r.status_code == 422


def test_cli_requires_explicit_mode(capsys):
    """DB là nguồn chính: CLI không còn mặc định ghi đè."""
    assert load_main(["load_content"]) == 2
    assert load_main(["load_content", "--yes"]) == 2
    assert "--if-empty" in capsys.readouterr().err


def test_has_content(loaded_session, db_session):
    assert has_content(loaded_session) is True


def test_unauthenticated_body_is_not_parsed(loaded_session, client_for):
    """Khách chưa đăng nhập gửi body hỏng: 401 (không phải 422) — server không parse body trước kiểm quyền."""
    client = client_for(loaded_session)
    r = client.post("/api/admin/validate", content=b"{", headers={"Content-Type": "application/json"})
    assert r.status_code == 401


@pytest.mark.parametrize("body", [b"{", b'{"content": {}}', b'{"base_version": "x", "content": [], "x": 1}'])
def test_every_admin_422_has_errors_list(admin, body):
    client, h = admin
    r = client.put("/api/admin/content", content=body, headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 422 and r.json()["errors"], r.json()


def test_long_id_rejected_by_validate_and_by_save_with_errors(admin):
    """validate và save cùng luật: id > 100 ký tự (cột String(100)) bị báo ở cả hai, có `errors`."""
    client, h = admin
    got = client.get("/api/admin/content", headers=h).json()
    content = got["content"]
    content["themes"][0]["id"] = "y" * 150
    v = client.post("/api/admin/validate", json={"content": content}, headers=h).json()
    assert v["ok"] is False and any("dài quá 100" in e for e in v["errors"])
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
    assert r.status_code == 422 and any("dài quá 100" in e for e in r.json()["errors"])


def test_deleting_exercise_with_progress_keeps_progress_and_state(admin, loaded_session):
    """INV-04: admin xoá hẳn một bài học viên đã làm → dòng tiến độ + lịch ôn vẫn còn (ẩn ở GET)."""
    from app.tables import UserState

    client, h = admin
    learner = add_user(loaded_session, email="test@gmail.com")
    record_pass(loaded_session, learner.id, "split-chunks")
    loaded_session.add(UserState(user_id=learner.id, review={"split-chunks-a": {"reps": 1}}, activity={"2026-10-11": 1}))
    loaded_session.flush()
    got = client.get("/api/admin/content", headers=h).json()
    content = got["content"]
    for th in content["themes"]:
        stack = list(th["topics"])
        while stack:
            tp = stack.pop()
            stack.extend(tp["modules"])
            for f in tp["files"]:
                f["exercise_ids"] = [i for i in f["exercise_ids"] if i != "split-chunks"]
    del content["exercises"]["split-chunks"]
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": content}, headers=h)
    assert r.status_code == 200, r.json()
    assert "split-chunks" not in client.get("/content").json()["exercises"]
    assert loaded_session.get(UserProgress, (learner.id, "split-chunks")).passed is True
    assert loaded_session.get(UserState, learner.id).activity == {"2026-10-11": 1}


def test_version_check_runs_while_holding_the_write_lock(admin, monkeypatch):
    """Kiểm version và ghi phải nằm trong cùng khoá ghi (không thì hai admin đua nhau ghi đè).

    Đo thứ tự gọi, không đo pg_locks: fixture đã nạp nội dung trong cùng transaction test nên khoá
    xact luôn đang được giữ — đo pg_locks thì bỏ lock_content khỏi admin_api test vẫn xanh."""
    from app import admin_api

    client, h = admin
    got = client.get("/api/admin/content", headers=h).json()
    calls: list[str] = []
    real_lock, real_export = admin_api.lock_content, admin_api.export_content

    def lock(session):
        calls.append("lock")
        real_lock(session)

    def export(session):
        calls.append("export")
        return real_export(session)

    monkeypatch.setattr(admin_api, "lock_content", lock)
    monkeypatch.setattr(admin_api, "export_content", export)
    r = client.put("/api/admin/content", json={"base_version": got["version"], "content": got["content"]}, headers=h)
    assert r.status_code == 200
    assert calls[:2] == ["lock", "export"]


def test_deeply_nested_json_body_is_422_not_500(admin):
    client, h = admin
    r = client.post("/api/admin/validate", content=b"[" * 300000, headers={**h, "Content-Type": "application/json"})
    assert r.status_code == 422 and r.json()["errors"]
