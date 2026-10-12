"""Nộp bài đồng thời thật (nhiều luồng, nhiều connection, dữ liệu commit thật).

Fixture `db_session` bọc mọi thứ trong một connection nên KHÔNG tạo được hai request đồng thời: xoá dòng
`pg_advisory_xact_lock` ở app/sd/attempts.py mà mọi test khác vẫn xanh. Test này là bằng chứng của khoá đó:
cấp `n` không trùng và quota 20/24h không bị vượt khi 30 request đến cùng lúc.
"""

from __future__ import annotations

import os
import threading
from concurrent.futures import ThreadPoolExecutor

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import delete, select
from sqlalchemy.orm import sessionmaker

from app.auth import CurrentUser, current_user
from app.db import get_session
from app.main import app
from app.sd.parser import parse_markdown
from app.tables import SdAttempt, SdDoc, SdProgress, SdSection, SdTask, User
from tests.conftest import BACKEND_DIR

DOC = "conc-doc"
THREADS = 30
QUOTA = 20


@pytest.fixture()
def committed_world(db_engine):
    """Học viên đã đọc xong Phase 1 của tài liệu mẫu, dữ liệu commit thật; dọn sạch khi xong."""
    Session = sessionmaker(bind=db_engine)
    with open(os.path.join(BACKEND_DIR, "content", "sd", "airline-reservation.md"), encoding="utf-8") as f:
        doc = parse_markdown(f.read())
    with Session() as s:
        user = User(email="conc-learner@example.com", password_hash="x", roles=["learner"])
        s.add(user)
        s.flush()
        uid = user.id
        s.add(SdDoc(id=DOC, title=doc["title"], status="published", context=doc["context"], created_by="test"))
        s.flush()
        s.add_all(SdSection(doc_id=DOC, **sec) for sec in doc["sections"])
        s.add_all(SdTask(doc_id=DOC, **t) for t in doc["tasks"])
        s.add_all(
            SdProgress(user_id=uid, doc_id=DOC, section_id=sec["id"], read_cards=[c["id"] for c in sec["cards"]])
            for sec in doc["sections"]
        )
        s.commit()

    def _session():
        with Session() as s:
            yield s

    app.dependency_overrides[get_session] = _session
    app.dependency_overrides[current_user] = lambda: CurrentUser(id=uid, email="conc-learner@example.com", roles=("learner",), session_id=0)
    try:
        yield Session, uid
    finally:
        app.dependency_overrides.clear()
        with Session() as s:
            s.execute(delete(SdAttempt).where(SdAttempt.doc_id == DOC))
            s.execute(delete(SdProgress).where(SdProgress.doc_id == DOC))
            s.execute(delete(SdTask).where(SdTask.doc_id == DOC))
            s.execute(delete(SdSection).where(SdSection.doc_id == DOC))
            s.execute(delete(SdDoc).where(SdDoc.id == DOC))
            s.execute(delete(User).where(User.id == uid))
            s.commit()


def test_concurrent_submits_get_distinct_consecutive_numbers_and_respect_quota(committed_world):
    Session, uid = committed_world
    barrier = threading.Barrier(THREADS)

    def submit(i: int) -> int:
        client = TestClient(app)
        barrier.wait()
        r = client.post(f"/api/sd/docs/{DOC}/tasks/api-design/attempts", json={"answer": f"hold giữ ghế {i}"})
        return r.status_code

    with ThreadPoolExecutor(THREADS) as pool:
        codes = list(pool.map(submit, range(THREADS)))

    assert sorted(set(codes)) == [201, 429], codes  # không có 500 (IntegrityError do trùng n)
    assert codes.count(201) == QUOTA and codes.count(429) == THREADS - QUOTA
    with Session() as s:
        numbers = sorted(s.scalars(select(SdAttempt.n).where(SdAttempt.user_id == uid, SdAttempt.doc_id == DOC)))
    assert numbers == list(range(1, QUOTA + 1))
