"""`GET /content` đọc từ Postgres: đúng hợp đồng, không lộ phần chấm, cùng nguồn với `/run`."""

from __future__ import annotations

import copy
import json
import subprocess
import sys

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event
from sqlalchemy.orm import sessionmaker

from app.content_api import get_judge_lookup, read_judge
from app.db import get_session
from app.load_content import compute_version, load_content, public_payload
from app.main import app, get_runner
from app.runner import Execution


class LocalRunner:
    async def run(self, source: str, stdin: str) -> Execution:
        proc = subprocess.run([sys.executable, "-c", source], input=stdin, capture_output=True, text=True, timeout=5)
        return Execution("ok" if proc.returncode == 0 else "error", proc.stdout, proc.stderr)


@pytest.fixture()
def client_for():
    def make(session) -> TestClient:
        app.dependency_overrides[get_session] = lambda: session
        app.dependency_overrides[get_judge_lookup] = lambda: (lambda i: read_judge(session, i))
        app.dependency_overrides[get_runner] = lambda: LocalRunner()
        return TestClient(app)

    yield make
    app.dependency_overrides.clear()


def test_content_matches_source_without_judge(loaded_session, content_data, client_for):
    response = client_for(loaded_session).get("/content")
    assert response.status_code == 200
    body = response.json()
    assert body["version"] == compute_version(content_data)
    assert {"themes": body["themes"], "exercises": body["exercises"]} == public_payload(content_data)
    # Thứ tự bài = thứ tự xuất hiện đầu tiên trong cây (khớp uniqueExercises ở app).
    assert list(body["exercises"]) == list(content_data["exercises"])


def test_content_never_exposes_judge(loaded_session, client_for):
    text = client_for(loaded_session).get("/content").text
    for secret in ('"judge"', '"cases"', "judge_solution", "judge_cases", '"expect"'):
        assert secret not in text


def test_shared_exercise_listed_in_both_files(loaded_session, client_for):
    body = client_for(loaded_session).get("/content").json()
    files = [f for t in body["themes"] for tp in t["topics"] for f in tp["files"]]
    holders = [f["id"] for f in files if "split-chunks" in f["exercise_ids"]]
    assert len(holders) == 2
    assert list(body["exercises"]).count("split-chunks") == 1


def test_content_not_loaded_is_503(db_session, client_for):
    response = client_for(db_session).get("/content")
    assert response.status_code == 503
    assert response.json() == {"detail": "content_not_loaded"}


def test_content_uses_fixed_number_of_queries(loaded_session, client_for):
    statements: list[str] = []
    engine = loaded_session.get_bind().engine
    listener = lambda conn, cursor, stmt, *args: statements.append(stmt)  # noqa: E731
    event.listen(engine, "before_cursor_execute", listener)
    try:
        client_for(loaded_session).get("/content")
    finally:
        event.remove(engine, "before_cursor_execute", listener)
    selects = [s for s in statements if s.lstrip().upper().startswith("SELECT")]
    assert len(selects) <= 7, selects  # meta + 6 bảng, không phụ thuộc số bài


def test_new_exercise_in_source_is_served_and_runnable(db_session, content_data, client_for):
    """INV-03: thêm bài vào content.json + nạp → /content có bài đó VÀ /run chấm được bài đó."""
    data = copy.deepcopy(content_data)
    new = copy.deepcopy(data["exercises"]["clean-text"])
    new["id"] = "clean-text-2"
    for block in new["blocks"]:
        block["id"] = block["id"].replace("clean-text", "clean-text-2")
    data["exercises"]["clean-text-2"] = new
    data["themes"][0]["topics"][0]["files"][0]["exercise_ids"].append("clean-text-2")
    load_content(db_session, data)
    db_session.flush()

    client = client_for(db_session)
    assert "clean-text-2" in client.get("/content").json()["exercises"]
    run = client.post("/run", json={"exercise_id": "clean-text-2", "code": new["judge"]["solution"]})
    assert run.status_code == 200
    assert run.json()["status"] == "passed"


def test_removed_exercise_disappears_from_both(db_session, content_data, client_for):
    data = copy.deepcopy(content_data)
    del data["exercises"]["like-post"]
    for theme in data["themes"]:
        for topic in theme["topics"]:
            for code_file in topic["files"]:
                code_file["exercise_ids"] = [i for i in code_file["exercise_ids"] if i != "like-post"]
    load_content(db_session, data)
    db_session.flush()

    client = client_for(db_session)
    assert "like-post" not in json.dumps(client.get("/content").json())
    assert client.post("/run", json={"exercise_id": "like-post", "code": "x = 1"}).status_code == 404


@pytest.fixture()
def dead_db_session():
    engine = create_engine("postgresql+psycopg://localhost:1/nope", connect_args={"connect_timeout": 1})
    session = sessionmaker(bind=engine)()
    yield session
    session.close()
    engine.dispose()


def test_database_down_is_503_for_both_endpoints(dead_db_session, client_for):
    client = client_for(dead_db_session)
    assert client.get("/content").status_code == 503
    assert client.get("/content").json() == {"detail": "database_unavailable"}
    run = client.post("/run", json={"exercise_id": "clean-text", "code": "x = 1"})
    assert run.status_code == 503
    assert run.json() == {"detail": "database_unavailable"}


def test_run_releases_db_session_before_judging(loaded_session, monkeypatch):
    """Session tra bài phải đóng (trả kết nối về pool) TRƯỚC khi gọi máy chấm (chậm vài giây)."""
    from app import content_api

    events: list[str] = []

    class TrackedSession:
        def __enter__(self):
            events.append("open")
            return loaded_session

        def __exit__(self, *exc):
            events.append("close")
            return False

    class SlowRunner:
        async def run(self, source, stdin):
            events.append("judge")
            return Execution("timeout", "", "", "slow")

    monkeypatch.setattr(content_api, "SessionLocal", lambda: TrackedSession())
    app.dependency_overrides[get_runner] = lambda: SlowRunner()
    try:
        response = TestClient(app).post("/run", json={"exercise_id": "clean-text", "code": "x = 1"})
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 200
    assert events == ["open", "close", "judge"]
