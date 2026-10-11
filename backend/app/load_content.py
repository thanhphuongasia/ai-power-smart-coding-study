"""Nạp `content/content.json` vào Postgres: thay toàn bộ, một transaction (idempotent).

    python -m app.load_content [path]     # mặc định content/content.json

`version` = sha256 của payload công khai (bỏ `judge` và `version`), nên cùng nội dung thì cùng version.
"""

from __future__ import annotations

import hashlib
import json
import sys
from collections import Counter
from typing import Any

from pydantic import ValidationError
from sqlalchemy import delete
from sqlalchemy.orm import Session

from app.content_schema import SourceContent
from app.tables import Block, CodeFile, ContentMeta, Exercise, FileExercise, Theme, Topic

DEFAULT_PATH = "content/content.json"


def public_payload(data: dict) -> dict:
    """Phần công khai của content.json: bỏ `version` và `judge` của từng bài (không sửa `data`)."""
    return {
        "themes": data["themes"],
        "exercises": {
            key: {k: v for k, v in exercise.items() if k != "judge"}
            for key, exercise in data["exercises"].items()
        },
    }


def compute_version(data: dict) -> str:
    canonical = json.dumps(public_payload(data), sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def _walk_topics(topics: list[dict], parent_id: str | None = None):
    """Duyệt trước (preorder) cây module: yield (topic, parent_id) — cha trước con."""
    for tp in topics:
        yield tp, parent_id
        yield from _walk_topics(tp.get("modules", []), tp.get("id"))


def _duplicates(ids: list[str]) -> list[str]:
    return sorted(i for i, n in Counter(ids).items() if n > 1)


def validate(data: dict) -> None:
    """Ném ValueError nêu rõ chỗ sai. Không đụng DB."""
    try:
        SourceContent.model_validate(data)
    except ValidationError as exc:
        details = "; ".join(
            f'{".".join(str(p) for p in err["loc"])}: {err["msg"]}' for err in exc.errors()
        )
        raise ValueError("content sai hình dạng: " + details) from None

    errors: list[str] = []
    themes = data.get("themes")
    exercises = data.get("exercises")
    if not isinstance(themes, list) or not isinstance(exercises, dict):
        raise ValueError("content cần `themes` (list) và `exercises` (object)")

    topics = [t for th in themes for t, _ in _walk_topics(th.get("topics", []))]
    files = [f for t in topics for f in t.get("files", [])]
    for kind, items in (("theme", themes), ("topic", topics), ("file", files)):
        dup = _duplicates([i.get("id") for i in items])
        if dup:
            errors.append(f"id {kind} trùng: {dup}")

    for key, ex in exercises.items():
        if ex.get("id") != key:
            errors.append(f'exercises["{key}"] có id khác key: "{ex.get("id")}"')
        blocks = ex.get("blocks", [])
        dup_labels = _duplicates([b.get("label") for b in blocks])
        if dup_labels:
            errors.append(f"bài {key}: label ô trùng {dup_labels}")
        judge = ex.get("judge")
        if not isinstance(judge, dict) or not judge.get("solution"):
            errors.append(f"bài {key}: thiếu judge.solution")
        if not isinstance(judge, dict) or not judge.get("cases"):
            errors.append(f"bài {key}: judge.cases cần ít nhất 1 case")

    dup_blocks = _duplicates([b.get("id") for ex in exercises.values() for b in ex.get("blocks", [])])
    if dup_blocks:
        errors.append(f"id block trùng: {dup_blocks}")

    for f in files:
        for ex_id in f.get("exercise_ids", []):
            if ex_id not in exercises:
                errors.append(f'file {f.get("id")}: exercise_ids có id không tồn tại: "{ex_id}"')
        dup_ex = _duplicates(f.get("exercise_ids", []))
        if dup_ex:
            errors.append(f'file {f.get("id")}: exercise_ids lặp {dup_ex}')

    if errors:
        raise ValueError("content không hợp lệ: " + "; ".join(errors))


def load_content(session: Session, data: dict[str, Any]) -> str:
    """Validate rồi thay toàn bộ nội dung trong transaction của `session`. Trả version.

    Không commit — caller quyết định (CLI commit; test rollback). Lỗi giữa chừng thì caller rollback.
    """
    validate(data)
    version = compute_version(data)

    # FileExercise/Block xoá trước cho rõ ràng; phần còn lại cascade theo FK.
    for model in (FileExercise, Block, CodeFile, Topic, Theme, Exercise, ContentMeta):
        session.execute(delete(model))

    exercises = data["exercises"]
    for key, ex in exercises.items():
        session.add(
            Exercise(
                id=key,
                title=ex["title"],
                class_name=ex["class_name"],
                function_name=ex["function_name"],
                params=ex["params"],
                template=ex["template"],
                challenge=ex["challenge"],
                judge_solution=ex["judge"]["solution"],
                judge_cases=ex["judge"]["cases"],
            )
        )
    session.flush()
    for ex in exercises.values():
        for pos, b in enumerate(ex["blocks"]):
            session.add(
                Block(
                    id=b["id"],
                    exercise_id=ex["id"],
                    position=pos,
                    label=b["label"],
                    title=b["title"],
                    prompt=b["prompt"],
                    indent_level=b["indent_level"],
                    accepted_answers=b["accepted_answers"],
                    expected_output=b["expected_output"],
                    explanation=b["explanation"],
                    hints=b["hints"],
                    vocab=b["vocab"],
                )
            )
    for ti, th in enumerate(data["themes"]):
        session.add(Theme(id=th["id"], position=ti, name=th["name"], description=th["description"], tags=th["tags"]))
        session.flush()
        # position = thứ tự preorder trong theme → cha flush trước con (FK parent_id).
        for pi, (tp, parent_id) in enumerate(_walk_topics(th["topics"])):
            session.add(
                Topic(
                    id=tp["id"],
                    theme_id=th["id"],
                    parent_id=parent_id,
                    position=pi,
                    name=tp["name"],
                    description=tp["description"],
                )
            )
            session.flush()
            for fi, f in enumerate(tp["files"]):
                session.add(CodeFile(id=f["id"], topic_id=tp["id"], position=fi, name=f["name"]))
                session.flush()
                for ei, ex_id in enumerate(f["exercise_ids"]):
                    session.add(FileExercise(file_id=f["id"], exercise_id=ex_id, position=ei))
    session.add(ContentMeta(key="version", value=version))
    session.flush()
    return version


def main(argv: list[str]) -> int:
    from app.db import SessionLocal

    path = argv[1] if len(argv) > 1 else DEFAULT_PATH
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    with SessionLocal() as session:
        try:
            version = load_content(session, data)
            session.commit()
        except Exception:
            session.rollback()
            raise
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
