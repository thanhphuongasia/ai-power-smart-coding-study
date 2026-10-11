"""Đọc nội dung học từ Postgres: payload `GET /content` (công khai) và phần chấm của một bài.

Payload dựng từ đúng 7 query cố định (một query mỗi bảng), không N+1. Thứ tự theo `position`.
`judge_solution`/`judge_cases` không bao giờ vào payload `/content`.
"""

from __future__ import annotations

from collections import defaultdict
from dataclasses import dataclass

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_session
from app.tables import Block, CodeFile, ContentMeta, Exercise, FileExercise, Theme, Topic

router = APIRouter()


@dataclass(frozen=True)
class Judge:
    function: str
    cases: list


def read_content(session: Session) -> dict | None:
    """Toàn bộ cây nội dung đúng shape hợp đồng `/content`, hoặc None nếu chưa nạp lần nào."""
    version = session.get(ContentMeta, "version")
    if version is None:
        return None

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
        "version": version.value,
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
    """Phần chấm của một bài cho `/run`; None nếu không có bài."""
    exercise = session.get(Exercise, exercise_id)
    if exercise is None:
        return None
    return Judge(function=exercise.function_name, cases=exercise.judge_cases)


@router.get("/content")
def get_content(session: Session = Depends(get_session)) -> dict:
    payload = read_content(session)
    if payload is None:
        raise HTTPException(status_code=503, detail="content_not_loaded")
    return payload
