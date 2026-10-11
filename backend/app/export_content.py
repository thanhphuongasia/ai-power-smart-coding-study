"""Xuất nội dung trong DB ra đúng shape `content.json` (CÓ judge) — DB là nguồn chính.

    python -m app.export_content [path]     # mặc định in ra stdout

Sửa nội dung bằng file thì: export → sửa file → `python -m app.load_content --force <file>`.
`admin_version` là sha256 của TOÀN BỘ nội dung (kể cả judge) — khác `version` công khai của
`/content` (bỏ judge): admin chỉ sửa test case cũng phải đổi version để kiểm xung đột (409).
"""

from __future__ import annotations

import hashlib
import json
import sys

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.content_api import ContentNotLoaded, _read_tree, _version
from app.tables import Exercise

_READ_ATTEMPTS = 3


def _with_judges(session: Session, tree: dict) -> dict:
    judges = {
        i: {"solution": s, "cases": c}
        for i, s, c in session.execute(select(Exercise.id, Exercise.judge_solution, Exercise.judge_cases))
    }
    return {
        "themes": tree["themes"],
        "exercises": {i: {**ex, "judge": judges[i]} for i, ex in tree["exercises"].items()},
    }


def export_content(session: Session) -> dict:
    """Nội dung đầy đủ đang có trong DB. Cùng cơ chế đọc-lại của `read_content`: version đầu == cuối
    thì mọi câu SELECT thấy cùng một lần nạp."""
    for _ in range(_READ_ATTEMPTS):
        before = _version(session)
        if before is None:
            raise ContentNotLoaded()
        try:
            data = _with_judges(session, _read_tree(session))
        except KeyError:
            continue
        if _version(session) == before:
            return data
    raise RuntimeError("Nội dung đang được nạp lại liên tục, đọc không ổn định")


def admin_version(data: dict) -> str:
    full = {"themes": data["themes"], "exercises": data["exercises"]}
    canonical = json.dumps(full, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def main(argv: list[str]) -> int:
    from app.db import SessionLocal

    with SessionLocal() as session:
        data = export_content(session)
    text = json.dumps({"version": "source", **data}, ensure_ascii=False, indent=2) + "\n"
    if len(argv) > 1:
        with open(argv[1], "w", encoding="utf-8") as fh:
            fh.write(text)
    else:
        sys.stdout.write(text)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
