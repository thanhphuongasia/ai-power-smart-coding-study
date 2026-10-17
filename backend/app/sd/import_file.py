"""Nhập tài liệu System Design từ file `.md` qua dòng lệnh (dùng để backfill `source_md` cho tài liệu đã có).

    python -m app.sd.import_file <path.md> [--id <slug>] [--mode create|replace|upsert] [--status draft|published]
                                 [--dry-run] [--actor <text>]
"""

from __future__ import annotations

import argparse
import sys

from app import db
from app.sd import docs


def main(argv: list[str]) -> int:
    """`argv` không gồm tên chương trình. Trả exit code."""
    parser = argparse.ArgumentParser(prog="python -m app.sd.import_file")
    parser.add_argument("path")
    parser.add_argument("--id", dest="doc_id", default=None)
    parser.add_argument("--mode", choices=docs.MODES, default="upsert")
    parser.add_argument("--status", choices=docs.IMPORT_STATUSES, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--actor", default="cli")
    try:
        args = parser.parse_args(argv)
    except SystemExit as exc:  # argparse tự in usage ra stderr
        return exc.code if isinstance(exc.code, int) else 2

    try:
        with open(args.path, encoding="utf-8") as f:
            markdown = f.read()
    except (OSError, UnicodeDecodeError) as exc:
        print(f"không đọc được file: {exc}", file=sys.stderr)
        return 1

    with db.SessionLocal() as session:
        try:
            s = docs.import_markdown(
                session,
                markdown,
                actor=args.actor,
                doc_id=args.doc_id,
                status=args.status,
                mode=args.mode,
                dry_run=args.dry_run,
            )
        except docs.SdDocError as exc:
            for err in exc.errors:
                print(err, file=sys.stderr)
            return 1

    line = (
        f"{s['id']} status={s['status']} sections={s['sections']} cards={s['cards']} "
        f"cards_added={s['cards_added']} cards_removed={s['cards_removed']}"
    )
    print(line + (" dry_run" if args.dry_run else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
