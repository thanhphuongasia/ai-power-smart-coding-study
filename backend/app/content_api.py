"""Đọc nội dung học từ Postgres: payload `GET /content` (công khai) và phần chấm của một bài.

Payload dựng từ 8 query cố định (version đầu + cuối, một query mỗi bảng), không N+1. Thứ tự theo `position`.
`judge_solution`/`judge_cases` không bao giờ vào payload `/content`.
"""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Callable
from dataclasses import dataclass

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.content_schema import ContentPayload
from app.db import SessionLocal, get_session
from app.tables import Block, CodeFile, ContentMeta, Exercise, FileExercise, Theme, Topic

router = APIRouter()


@dataclass(frozen=True)
class Judge:
    function: str
    cases: list


class ContentNotLoaded(Exception):
    """DB đã có bảng nhưng chưa nạp nội dung lần nào (chưa chạy load_content)."""


_READ_ATTEMPTS = 3


def _version(session: Session) -> str | None:
    # select cột (không session.get) để luôn hỏi DB, không lấy từ identity map.
    return session.scalar(select(ContentMeta.value).where(ContentMeta.key == "version"))


def read_content(session: Session) -> dict:
    """Toàn bộ cây nội dung đúng shape hợp đồng `/content`.

    Các SELECT (6 bảng) chạy ở READ COMMITTED nên một lần nạp lại có thể commit xen giữa. Nạp lại ghi
    `version` cùng transaction với dữ liệu, nên version đầu == version cuối ⇒ mọi câu giữa thấy
    cùng một bản. Khác nhau (hoặc cây lệch gây KeyError) thì đọc lại.
    """
    for _ in range(_READ_ATTEMPTS):
        before = _version(session)
        if before is None:
            raise ContentNotLoaded()
        try:
            payload = _read_tree(session)
        except KeyError:
            continue
        if _version(session) == before:
            return {"version": before, **payload}
    raise RuntimeError("Nội dung đang được nạp lại liên tục, đọc không ổn định")


def _read_tree(session: Session) -> dict:
    themes = session.scalars(select(Theme).order_by(Theme.position)).all()
    topics = session.scalars(select(Topic).order_by(Topic.position)).all()
    files = session.scalars(select(CodeFile).order_by(CodeFile.position)).all()
    links = session.scalars(select(FileExercise).order_by(FileExercise.position)).all()
    exercises = {e.id: e for e in session.scalars(select(Exercise)).all()}
    blocks = session.scalars(select(Block).order_by(Block.position)).all()

    topics_by_theme: dict[str, list[Topic]] = defaultdict(list)
    for topic in topics:
        topics_by_theme[topic.theme_id].append(topic)
    files_by_topic: dict[str, list[CodeFile]] = defaultdict(list)
    for code_file in files:
        files_by_topic[code_file.topic_id].append(code_file)
    exercise_ids_by_file: dict[str, list[str]] = defaultdict(list)
    for link in links:
        exercise_ids_by_file[link.file_id].append(link.exercise_id)
    blocks_by_exercise: dict[str, list[Block]] = defaultdict(list)
    for block in blocks:
        blocks_by_exercise[block.exercise_id].append(block)

    # Bài theo thứ tự xuất hiện đầu tiên trong cây (khớp uniqueExercises ở app); bài không thuộc
    # file nào xếp cuối theo id.
    ordered_ids: list[str] = []
    payload_themes = []
    for theme in themes:
        payload_topics = []
        for topic in topics_by_theme[theme.id]:
            payload_files = []
            for code_file in files_by_topic[topic.id]:
                ids = exercise_ids_by_file[code_file.id]
                ordered_ids.extend(i for i in ids if i not in ordered_ids)
                payload_files.append({"id": code_file.id, "name": code_file.name, "exercise_ids": ids})
            payload_topics.append(
                {"id": topic.id, "name": topic.name, "description": topic.description, "files": payload_files}
            )
        payload_themes.append(
            {
                "id": theme.id,
                "name": theme.name,
                "description": theme.description,
                "tags": theme.tags,
                "topics": payload_topics,
            }
        )
    ordered_ids.extend(sorted(i for i in exercises if i not in ordered_ids))

    return {
        "themes": payload_themes,
        "exercises": {i: _exercise_payload(exercises[i], blocks_by_exercise[i]) for i in ordered_ids},
    }


def _exercise_payload(exercise: Exercise, blocks: list[Block]) -> dict:
    return {
        "id": exercise.id,
        "title": exercise.title,
        "function_name": exercise.function_name,
        "params": exercise.params,
        "template": exercise.template,
        "challenge": exercise.challenge,
        "blocks": [
            {
                "id": b.id,
                "label": b.label,
                "title": b.title,
                "prompt": b.prompt,
                "indent_level": b.indent_level,
                "accepted_answers": b.accepted_answers,
                "expected_output": b.expected_output,
                "explanation": b.explanation,
                "hints": b.hints,
                "vocab": b.vocab,
            }
            for b in blocks
        ],
    }


def read_judge(session: Session, exercise_id: str) -> Judge | None:
    """Phần chấm của một bài cho `/run`; None nếu không có bài. Chưa nạp nội dung → ContentNotLoaded
    (để `/run` và `/content` cùng báo 503, không để `/run` báo nhầm "không có bài")."""
    exercise = session.get(Exercise, exercise_id)
    if exercise is None:
        if _version(session) is None:
            raise ContentNotLoaded()
        return None
    return Judge(function=exercise.function_name, cases=exercise.judge_cases)


JudgeLookup = Callable[[str], "Judge | None"]


def get_judge_lookup() -> JudgeLookup:
    """Dependency cho `/run`: mỗi lần tra mở một session ngắn và trả kết nối NGAY sau khi đọc.

    `/run` chờ máy chấm vài giây; giữ session suốt request sẽ chiếm kết nối pool trong lúc đó
    (nhiều request đồng thời → cạn pool → `/content` cũng chết theo).
    """

    def lookup(exercise_id: str) -> Judge | None:
        with SessionLocal() as session:
            return read_judge(session, exercise_id)

    return lookup


@router.get("/content", response_model=ContentPayload)
def get_content(session: Session = Depends(get_session)) -> dict:
    return read_content(session)
