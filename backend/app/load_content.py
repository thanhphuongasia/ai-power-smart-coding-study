"""Nạp `content/content.json` vào Postgres: thay toàn bộ, một transaction (idempotent).

DB là nguồn chính của nội dung (admin sửa thẳng DB qua `/api/admin/content`), nên CLI không còn
mặc định ghi đè:

    python -m app.load_content --if-empty [path]   # chỉ nạp khi DB chưa có nội dung (deploy dùng cái này)
    python -m app.load_content --force [path]      # ghi đè có chủ ý (export trước: app.export_content)

`version` = sha256 của payload công khai (bỏ `judge` và `version`), nên cùng nội dung thì cùng version.
"""

from __future__ import annotations

import hashlib
import json
import math
import sys
from collections import Counter
from typing import Any

from pydantic import ValidationError
from sqlalchemy import delete, select, text
from sqlalchemy.orm import Session

from app.content_rules import content_rule_errors
from app.content_schema import SourceContent
from app.tables import Block, CodeFile, ContentMeta, Exercise, FileExercise, Theme, Topic

DEFAULT_PATH = "content/content.json"
# Mọi đường ghi nội dung (CLI + admin PUT) giữ khoá này tới hết transaction: hai lần ghi không xen nhau,
# và admin kiểm version rồi ghi trong cùng một khoá.
CONTENT_WRITE_LOCK = 0x5C5_C0DE


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


def _scenario_errors(cases: list) -> list[tuple[int, str]]:
    """Case dạng kịch bản (`call`): steps/call phải compile được và expect có `return` hoặc `raises`.

    Bắt lỗi soạn bài ở đây — để lọt tới harness thì người học thấy lỗi như thể code của mình sai.
    """
    out: list[tuple[int, str]] = []
    for i, case in enumerate(cases):
        if not isinstance(case, dict):
            out.append((i, "case phải là object"))
            continue
        if "call" not in case:
            out.extend((i, msg) for msg in _args_case_errors(case))
            continue
        steps = case.get("steps", [])
        if not isinstance(steps, list) or not all(isinstance(x, str) for x in steps) or not isinstance(case["call"], str):
            out.append((i, "`steps` phải là list chuỗi và `call` là chuỗi"))
            continue
        try:
            for step in steps:
                compile(step, "<case>", "exec")
            compile(case["call"], "<case>", "eval")
        except (SyntaxError, TypeError, ValueError, MemoryError, RecursionError) as exc:
            # MemoryError/RecursionError: biểu thức lồng quá sâu làm parser tràn — vẫn là lỗi soạn bài.
            out.append((i, f"steps/call không compile được: {type(exc).__name__}: {exc}"[:300]))
        expect = case.get("expect")
        if not isinstance(expect, dict) or not ({"return", "raises"} & expect.keys()):
            out.append((i, "expect cần `return` hoặc `raises`"))
        elif "raises" in expect and not isinstance(expect["raises"], str):
            out.append((i, "`raises` phải là tên exception (chuỗi)"))
    return out


def _args_case_errors(case: dict) -> list[str]:
    """Case dạng `args` (hàm rời) đúng shape harness đọc: `args` list, `expect` có `return`, hoặc
    `value` + `arg` (chỉ số tham số bị sửa tại chỗ). Sai shape thì học viên Run sẽ thấy lỗi như thể
    code của mình sai."""
    expect = case.get("expect")
    if not isinstance(case.get("args"), list):
        return ["case cần `args` (list) hoặc `call`"]
    if not isinstance(expect, dict):
        return ["case cần `expect` (object)"]
    if "return" in expect:
        return []
    arg = expect.get("arg")
    if "value" in expect and isinstance(arg, int) and not isinstance(arg, bool) and 0 <= arg < len(case["args"]):
        return []
    return ["expect cần `return`, hoặc `value` + `arg` là chỉ số hợp lệ trong `args`"]


def _diagram_errors(diagram: dict) -> list[str]:
    """Sơ đồ class: tên class duy nhất; quan hệ trỏ tới class có thật; `via` là method của `from`."""
    out: list[str] = []
    classes = diagram.get("classes", [])
    dup = _duplicates([c.get("name") for c in classes])
    if dup:
        out.append(f"sơ đồ: class trùng {dup}")
    methods = {c.get("name"): set(c.get("methods", [])) for c in classes}
    for r in diagram.get("relations", []):
        src, dst = r.get("from"), r.get("to")
        for end in (src, dst):
            if end not in methods:
                out.append(f'sơ đồ: quan hệ {src} → {dst} trỏ tới class không có: "{end}"')
        if src in methods:
            extra = [m for m in r.get("via", []) if m not in methods[src]]
            if extra:
                out.append(f"sơ đồ: via {extra} không phải method của {src}")
    return out


def _duplicates(ids: list[str]) -> list[str]:
    return sorted(i for i, n in Counter(ids).items() if n > 1)


MAX_DEPTH = 64
MAX_NODES = 200_000  # tổng số giá trị trong cây (content.json thật ~10k); chặn trước pydantic


def _unstorable(value: Any) -> str | None:
    """Thứ Postgres không lưu được trong text/JSONB: ký tự NUL, chuỗi không mã hoá UTF-8 được (surrogate
    lẻ), NaN/Infinity. Duyệt từng giá trị (không đệ quy) — kiểm trên JSON đã dump sẽ bắt nhầm chuỗi
    hợp lệ chứa chữ `\\u0000` (vd bài dạy escape)."""
    stack: list[tuple[Any, int]] = [(value, 0)]
    nodes = 0
    while stack:
        v, depth = stack.pop()
        nodes += 1
        if nodes > MAX_NODES:
            return f"content quá lớn (> {MAX_NODES} giá trị)"
        if depth > MAX_DEPTH:
            return f"content lồng quá {MAX_DEPTH} tầng"
        if isinstance(v, dict):
            stack.extend((k, depth + 1) for k in v.keys())
            stack.extend((x, depth + 1) for x in v.values())
        elif isinstance(v, list):
            if len(v) > MAX_LIST:
                return f"có danh sách quá {MAX_LIST} phần tử"
            stack.extend((x, depth + 1) for x in v)
        elif isinstance(v, str):
            if len(v) > MAX_TEXT:
                return f"có chuỗi dài quá {MAX_TEXT} ký tự"
            if "\x00" in v:
                return "content chứa ký tự NUL"
            try:
                v.encode("utf-8")
            except UnicodeEncodeError:
                return "content chứa chuỗi không mã hoá UTF-8 được"
        elif isinstance(v, float) and not math.isfinite(v):
            return "content chứa số NaN/Infinity"
    return None


# Trần số lượng: nội dung thật ~3 theme / ~25 bài; trần rộng gấp nhiều lần nhưng giữ chi phí kiểm có hạn.
MAX_THEMES = 50
MAX_TOPICS = 1000
MAX_EXERCISES = 1000
MAX_DIAGRAM_CLASSES = 200
# Trần độ dài: luật nội dung có regex/quét chuỗi; không có trần thì một chuỗi dài vài trăm KB làm CPU
# chạy hàng chục giây (regex giữ GIL → treo cả server, kể cả /run của học viên).
MAX_TEXT = 20_000  # template/solution thật vài trăm ký tự
MAX_LIST = 1000
MAX_ANSWER = 500  # đáp án một ô ≤ 2 dòng
MAX_CLASS_MEMBERS = 100  # thuộc tính + method của một lớp trong sơ đồ
MAX_CASES = 1000  # tổng test case toàn bộ nội dung (thật ~110) — mỗi steps/call được compile()
MAX_CODE_LINE = 1000  # một step/call: compile biểu thức lồng sâu dài vài chục KB tốn hàng chục ms


def _size_errors(data: dict) -> list[str]:
    out = []
    themes = data["themes"]
    topics = sum(1 for th in themes for _ in _walk_topics(th["topics"]))
    for what, n, cap in (
        ("theme", len(themes), MAX_THEMES),
        ("module", topics, MAX_TOPICS),
        ("bài", len(data["exercises"]), MAX_EXERCISES),
    ):
        if n > cap:
            out.append(f"quá nhiều {what}: {n} > {cap}")
    for th in themes:
        n = len(th["diagram"]["classes"])
        if n > MAX_DIAGRAM_CLASSES:
            out.append(f'theme {th["id"]}: sơ đồ quá nhiều class: {n} > {MAX_DIAGRAM_CLASSES}')
        for c in th["diagram"]["classes"]:
            if len(c["attributes"]) + len(c["methods"]) > MAX_CLASS_MEMBERS:
                out.append(f'theme {th["id"]}: class {c["name"][:40]} quá {MAX_CLASS_MEMBERS} thuộc tính + method')
    cases = [c for ex in data["exercises"].values() for c in ex["judge"]["cases"]]
    if len(cases) > MAX_CASES:
        out.append(f"quá nhiều test case: {len(cases)} > {MAX_CASES}")
    if any(
        isinstance(c, dict) and any(isinstance(x, str) and len(x) > MAX_CODE_LINE for x in [c.get("call"), *(c.get("steps") or [] if isinstance(c.get("steps"), list) else [])])
        for c in cases
    ):
        out.append(f"có steps/call dài quá {MAX_CODE_LINE} ký tự")
    for key, ex in data["exercises"].items():
        for b in ex["blocks"]:
            if any(len(a) > MAX_ANSWER for a in b["accepted_answers"]):
                out.append(f"bài {key[:40]}: đáp án dài quá {MAX_ANSWER} ký tự")
    return out


def validation_errors(data: Any) -> list[str]:
    """Mọi lỗi của bộ nội dung (rỗng = hợp lệ). Không đụng DB. Dùng chung cho CLI và admin."""
    if not isinstance(data, dict):
        return ["content phải là object"]
    bad = _unstorable(data)
    if bad:
        return [bad]
    try:
        SourceContent.model_validate(data)
    except ValidationError as exc:
        return [f'{".".join(str(p) for p in err["loc"])}: {err["msg"]}' for err in exc.errors()]
    too_big = _size_errors(data)
    if too_big:
        return too_big  # chặn trước các luật tốn CPU (ghép code, sơ đồ)

    errors: list[str] = []
    themes = data.get("themes")
    exercises = data.get("exercises")

    topics = [t for th in themes for t, _ in _walk_topics(th.get("topics", []))]
    files = [f for t in topics for f in t.get("files", [])]
    for kind, items in (("theme", themes), ("topic", topics), ("file", files)):
        dup = _duplicates([i.get("id") for i in items])
        if dup:
            errors.append(f"id {kind} trùng: {dup}")

    for th in themes:
        errors.extend(f'theme {th.get("id")}: {msg}' for msg in _diagram_errors(th.get("diagram") or {}))

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
        else:
            errors.extend(f"bài {key}: case {i}: {msg}" for i, msg in _scenario_errors(judge["cases"]))
            if ex.get("class_name"):
                # Bài method chỉ chấm được bằng case kịch bản (harness không gọi method theo `args`).
                errors.extend(
                    f"bài {key}: case {i}: bài method cần case dạng `call`"
                    for i, case in enumerate(judge["cases"])
                    if not isinstance(case, dict) or "call" not in case
                )

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

    if not errors:
        # Luật nội dung (marker, ghép == solution, ≤3 ô, sơ đồ khớp code…) cần cấu trúc đã đúng.
        errors.extend(content_rule_errors(data))
    return errors


def validate(data: dict) -> None:
    """Ném ValueError nêu rõ chỗ sai. Không đụng DB."""
    errors = validation_errors(data)
    if errors:
        raise ValueError("content không hợp lệ: " + "; ".join(errors))


# Chờ khoá tối đa chừng này (một lần ghi đang treo không được chặn mọi lần ghi khác vô hạn). SET LOCAL
# áp cho MỌI lần chờ khoá tới hết transaction (cả DELETE/INSERT sau đó), không chỉ advisory lock.
LOCK_TIMEOUT = "15s"


def lock_content(session: Session) -> None:
    session.execute(text(f"SET LOCAL lock_timeout = '{LOCK_TIMEOUT}'"))
    session.execute(text("SELECT pg_advisory_xact_lock(:k)"), {"k": CONTENT_WRITE_LOCK})


def has_content(session: Session) -> bool:
    return session.scalar(select(ContentMeta.value).where(ContentMeta.key == "version")) is not None


def load_content(session: Session, data: dict[str, Any], *, validated: bool = False) -> str:
    """Validate rồi thay toàn bộ nội dung trong transaction của `session`. Trả version.

    Không commit — caller quyết định (CLI commit; test rollback). Lỗi giữa chừng thì caller rollback.
    """
    if not validated:  # admin đã validate NGOÀI khoá ghi, không chạy lại luật tốn CPU trong khoá
        validate(data)
    version = compute_version(data)
    lock_content(session)

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
        session.add(
            Theme(
                id=th["id"],
                position=ti,
                name=th["name"],
                description=th["description"],
                tags=th["tags"],
                diagram=th["diagram"],
            )
        )
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


USAGE = "usage: python -m app.load_content (--if-empty | --force) [path]"


def main(argv: list[str]) -> int:
    from app.db import SessionLocal

    flags = [a for a in argv[1:] if a.startswith("--")]
    paths = [a for a in argv[1:] if not a.startswith("--")]
    if len(flags) != 1 or flags[0] not in ("--if-empty", "--force") or len(paths) > 1:
        print(USAGE, file=sys.stderr)
        return 2
    path = paths[0] if paths else DEFAULT_PATH
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    with SessionLocal() as session:
        try:
            lock_content(session)  # kiểm "rỗng" và ghi trong cùng khoá
            if flags[0] == "--if-empty" and has_content(session):
                print("skip: DB đã có nội dung (DB là nguồn chính; ghi đè thì dùng --force)")
                return 0
            version = load_content(session, data)
            session.commit()
        except Exception:
            session.rollback()
            raise
    print(version)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
