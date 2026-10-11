"""Luật nội dung chạy được trên MỌI bộ nội dung (không chỉ content.json): port từ
`mobile/test/content_contract_test.dart` + `mobile/lib/domain/merge.dart`.

Trước đây luật chỉ chạy trong test Dart trên file content.json; giờ DB là nguồn chính và admin sửa
thẳng DB, nên `load_content.validate` gọi `content_rule_errors` cho mọi đường ghi (CLI + admin).

Gọi SAU khi đã qua schema pydantic (`SourceContent`): hàm này giả định đúng hình dạng.
Nhân đôi có chủ đích với Dart (`mergeCells`, `normalizeCode`): app chấm ô bằng bản Dart, server
kiểm nội dung bằng bản Python. `tests/test_content_rules.py` chỉ khoá bản Python (content.json thật
sạch + mỗi luật một mutant + vài ca biên của merge/normalize); không có test so trực tiếp hai bản.
"""

from __future__ import annotations

import re

MARKER = re.compile(r"^(\s*)# TODO ([A-Z])\s*$")
MAX_BLOCKS = 3
MAX_ANSWER_LINES = 2
MAX_TOTAL_ANSWER_LINES = 10
HINTS_PER_BLOCK = 3


def _normalize_cell(raw: str) -> list[str]:
    """Như `_normalizeCell` (Dart): tab → 4 space, bỏ dòng trống đầu/cuối, dedent chung."""
    lines = raw.replace("\t", "    ").split("\n")
    while lines and not lines[0].strip():
        lines.pop(0)
    while lines and not lines[-1].strip():
        lines.pop()
    indents = [len(ln) - len(ln.lstrip()) for ln in lines if ln.strip()]
    common = min(indents) if indents else 0
    if common <= 0:
        return lines
    return ["" if not ln.strip() else ln[common:] for ln in lines]


def merge_cells(template: str, cells: dict[str, str]) -> str:
    """Như `mergeCells` (Dart): thay từng marker bằng nội dung ô, thụt theo marker."""
    out: list[str] = []
    for line in template.split("\n"):
        m = MARKER.match(line)
        if m is None:
            out.append(line)
            continue
        raw = cells.get(m.group(2))
        if raw is None:
            raise KeyError(m.group(2))
        indent = m.group(1)
        out.extend("" if not cl else indent + cl for cl in _normalize_cell(raw))
    return "\n".join(out)


_PUNCT = re.compile(r"\s*([()\[\],:=+\-*/%<>!&|^])\s*")


def normalize_code(code: str) -> str:
    """Như `normalizeCode` (Dart, answer_checker.dart) — dùng để bắt 2 ô trùng đáp án."""
    lines = [ln.replace("\t", "    ").rstrip() for ln in code.split("\n")]
    lines = [ln for ln in lines if ln.strip()]
    if not lines:
        return ""
    base = min(len(ln) - len(ln.lstrip()) for ln in lines)
    out = []
    for ln in lines:
        rel = len(ln) - len(ln.lstrip()) - base
        content = re.sub(r"[ \t]+", " ", ln.strip())
        content = _PUNCT.sub(lambda m: m.group(1), content).replace("'", '"')
        out.append(" " * rel + content)
    return "\n".join(out)


def _indent(line: str) -> int:
    return len(line) - len(line.lstrip())


def _walk(topics: list[dict]):
    for tp in topics:
        yield tp
        yield from _walk(tp["modules"])


def _exercise_errors(key: str, ex: dict) -> list[str]:
    errs: list[str] = []
    p = f"bài {key}"
    blocks = ex["blocks"]
    template = ex["template"]
    solution = ex["judge"]["solution"]

    if not blocks:
        errs.append(f"{p}: cần ít nhất 1 ô")
    if len(blocks) > MAX_BLOCKS:
        errs.append(f"{p}: tối đa {MAX_BLOCKS} ô (đang có {len(blocks)})")

    # Marker: mỗi ô đúng một marker, thụt = 4 × indent_level, không marker thừa.
    found: dict[str, list[int]] = {}
    for line in template.split("\n"):
        m = MARKER.match(line)
        if m:
            found.setdefault(m.group(2), []).append(len(m.group(1)))
    labels = [b["label"] for b in blocks]
    extra = sorted(set(found) - set(labels))
    if extra:
        errs.append(f"{p}: template có marker không có ô: {extra}")
    for b in blocks:
        lab = b["label"]
        bp = f"{p} ô {lab}"
        if not re.fullmatch(r"[A-Z]", lab):
            errs.append(f"{bp}: label phải là 1 chữ in hoa")
        if b["id"] != f"{key}-{lab.lower()}":
            errs.append(f'{bp}: id phải là "{key}-{lab.lower()}"')
        marks = found.get(lab, [])
        if len(marks) != 1:
            errs.append(f"{bp}: template cần đúng 1 dòng `# TODO {lab}` (đang có {len(marks)})")
        elif marks[0] != 4 * b["indent_level"]:
            errs.append(f"{bp}: marker thụt {marks[0]} space, indent_level {b['indent_level']} cần {4 * b['indent_level']}")
        if not b["accepted_answers"]:
            errs.append(f"{bp}: cần ít nhất 1 đáp án")
        for ans in b["accepted_answers"]:
            if len(ans.split("\n")) > MAX_ANSWER_LINES:
                errs.append(f"{bp}: mỗi đáp án tối đa {MAX_ANSWER_LINES} dòng")
                break
        if len(b["hints"]) != HINTS_PER_BLOCK:
            errs.append(f"{bp}: cần đúng {HINTS_PER_BLOCK} gợi ý (đang có {len(b['hints'])})")
        if not b["vocab"]:
            errs.append(f"{bp}: vocab không được rỗng")
        if not b["explanation"].strip():
            errs.append(f"{bp}: explanation không được rỗng")
    if errs:
        return errs  # các luật dưới cần marker/đáp án hợp lệ

    firsts = {b["label"]: b["accepted_answers"][0] for b in blocks}
    total = sum(len(a.split("\n")) for a in firsts.values())
    if total > MAX_TOTAL_ANSWER_LINES:
        errs.append(f"{p}: tổng số dòng đáp án đầu {total} > {MAX_TOTAL_ANSWER_LINES}")

    seen: dict[str, str] = {}
    for b in blocks:
        n = normalize_code(firsts[b["label"]])
        if n in seen:
            errs.append(f"{p}: ô {b['label']} trùng đáp án với ô {seen[n]}")
        seen[n] = b["label"]

    # Ghép đáp án đầu của từng ô vào template phải ra đúng lời giải chấm (từng ký tự).
    merged = merge_cells(template, firsts)
    if merged != solution:
        errs.append(f"{p}: ghép đáp án đầu các ô vào template KHÔNG bằng judge.solution{_first_diff(merged, solution)}")

    fn = ex["function_name"]
    if f"def {fn}(" not in solution:
        errs.append(f"{p}: judge.solution không định nghĩa `def {fn}(`")
    cn = ex["class_name"]
    if cn is not None:
        if f"class {cn}" not in solution:
            errs.append(f"{p}: judge.solution thiếu `class {cn}`")
        if f"class {cn}" not in template:
            errs.append(f"{p}: template thiếu `class {cn}`")

    # Code chết: ô kế tiếp nằm sau ô `return` trong cùng nhánh thì không bao giờ chạy tới.
    lines = template.split("\n")
    line_of = {}
    for i, ln in enumerate(lines):
        m = MARKER.match(ln)
        if m:
            line_of[m.group(2)] = i
    for cur, nxt in zip(blocks, blocks[1:]):
        if not firsts[cur["label"]].strip().startswith("return"):
            continue
        start, end = line_of[cur["label"]], line_of[nxt["label"]]
        ret = _indent(lines[start])
        closed = _indent(lines[end]) < ret or any(
            ln.strip() and _indent(ln) < ret for ln in lines[start + 1 : end]
        )
        if not closed:
            errs.append(f"{p}: ô {nxt['label']} nằm sau return của ô {cur['label']} trong cùng nhánh (code chết)")

    called = cn if fn == "__init__" and cn else fn
    ch = ex["challenge"]
    for field in ("statement", "motivation"):
        if not ch[field].strip():
            errs.append(f"{p}: challenge.{field} không được rỗng")
    for name in ("small", "project"):
        exm = ch[name]
        if not exm["caption"].strip() or not exm["output"].strip():
            errs.append(f"{p}: challenge.{name} cần caption và output")
        if called not in exm["input"]:
            errs.append(f"{p}: challenge.{name}.input phải gọi `{called}`")
    return errs


def _first_diff(a: str, b: str) -> str:
    la, lb = a.split("\n"), b.split("\n")
    for i in range(max(len(la), len(lb))):
        x = la[i] if i < len(la) else "<hết>"
        y = lb[i] if i < len(lb) else "<hết>"
        if x != y:
            return f" (dòng {i + 1}: ghép ra {x!r}, solution {y!r})"
    return ""


def _class_bodies(code: str) -> dict[str, str]:
    """Mọi `class X` ở cột 0 trong code → thân của nó. Một lượt qua code (thay vì quét lại cho từng
    lớp của sơ đồ — với nội dung lớn, cách cũ là O(lớp × bài × độ dài code))."""
    out: dict[str, str] = {}
    lines = code.split("\n")
    head = re.compile(r"^class (\w+)\b")
    i = 0
    while i < len(lines):
        m = head.match(lines[i])
        if not m:
            i += 1
            continue
        end = i + 1
        while end < len(lines) and (not lines[end].strip() or lines[end][:1].isspace()):
            end += 1
        out.setdefault(m.group(1), "\n".join(lines[i:end]))
        i = end
    return out


_ATTR = re.compile(r"self\.(\w+) =")
_DEF = re.compile(r"def (\w+)\(")


def _class_members(code: str) -> dict[str, tuple[set[str], set[str]]]:
    """`class X` → (tên thuộc tính gán `self.a =`, tên method `def m(`) trong thân lớp đó."""
    return {
        name: ({m.group(1) for m in _ATTR.finditer(body)}, {m.group(1) for m in _DEF.finditer(body)})
        for name, body in _class_bodies(code).items()
    }


def _diagram_code_errors(
    theme: dict, exercises: dict, bodies_by_ex: dict[str, dict[str, tuple[set[str], set[str]]]]
) -> list[str]:
    """INV-02/03 của run sơ đồ: sơ đồ khớp code (đáp án ghép) của các bài trong theme."""
    errs: list[str] = []
    ids = sorted({eid for tp in _walk(theme["topics"]) for f in tp["files"] for eid in f["exercise_ids"]})
    classes = theme["diagram"]["classes"]
    names = {c["name"] for c in classes}
    tp = f'theme {theme["id"]}: sơ đồ'
    # Gộp tập tên (đã tính sẵn mỗi bài một lần) theo lớp: tra tập thay vì quét code cho từng
    # thuộc tính × từng theme — cách quét cũ cho phép body <4MB chạy >10s (giữ GIL, treo server).
    members: dict[str, tuple[set[str], set[str]]] = {}
    for eid in ids:
        for name, (attrs, methods) in bodies_by_ex.get(eid, {}).items():
            a, m = members.setdefault(name, (set(), set()))
            a |= attrs
            m |= methods
    for cls in classes:
        name = cls["name"]
        if name not in members:
            if cls["methods"]:
                errs.append(f"{tp}: không bài nào chứa `class {name}`")
            attrs, methods = set(), set()
        else:
            attrs, methods = members[name]
        for a in cls["attributes"]:
            if a["name"] not in attrs:
                errs.append(f'{tp}: {name}.{a["name"]} — không bài nào có "self.{a["name"]} ="')
        for m in cls["methods"]:
            if m not in methods:
                errs.append(f'{tp}: {name}.{m}() — không bài nào có "def {m}("')
    for eid in ids:
        ex = exercises.get(eid)
        if ex is not None and ex["class_name"] and ex["class_name"] not in names:
            errs.append(f'{tp}: thiếu class {ex["class_name"]} (bài {eid})')
    return errs


MAX_ID = 100  # cột String(100) trong tables.py — dài hơn thì DB từ chối lúc ghi


def content_rule_errors(data: dict) -> list[str]:
    """Mọi vi phạm luật nội dung, rỗng = đạt. `data` đã qua schema."""
    errs: list[str] = []
    themes, exercises = data["themes"], data["exercises"]
    if not themes:
        errs.append("cần ít nhất 1 theme")

    # ID duy nhất TOÀN CỤC (theme/topic/file/bài/ô dùng chung một không gian tên).
    ids: list[str] = []
    for th in themes:
        ids.append(th["id"])
        if not th["topics"]:
            errs.append(f'theme {th["id"]}: cần ít nhất 1 module')
        # Module/file rỗng được phép: admin xoá bài cuối của module, hoặc dựng khung trước rồi thêm bài.
        for tp in _walk(th["topics"]):
            ids.append(tp["id"])
            ids.extend(f["id"] for f in tp["files"])
    # Bài/ô: một bài dùng ở nhiều file (cross-project) vẫn chỉ một id.
    ids.extend(exercises.keys())
    ids.extend(b["id"] for ex in exercises.values() for b in ex["blocks"])
    seen: set[str] = set()
    dups = sorted({i for i in ids if i in seen or seen.add(i)})
    if dups:
        errs.append(f"id trùng giữa các loại: {dups}")
    too_long = sorted({i[:40] + "…" for i in ids if len(i) > MAX_ID})
    if too_long:
        errs.append(f"id dài quá {MAX_ID} ký tự: {too_long}")

    for key, ex in exercises.items():
        for field in ("class_name", "function_name"):
            if ex[field] is not None and len(ex[field]) > MAX_ID:
                errs.append(f"bài {key}: {field} dài quá {MAX_ID} ký tự")
        if ex["function_name"] == "__init__" and not ex["class_name"]:
            errs.append(f"bài {key}: function_name `__init__` cần class_name")
        errs.extend(_exercise_errors(key, ex))

    # Code ghép của mỗi bài tính MỘT lần, dùng chung cho mọi theme chứa bài đó.
    bodies_by_ex: dict[str, dict[str, tuple[set[str], set[str]]]] = {}
    for key, ex in exercises.items():
        try:
            code = merge_cells(ex["template"], {b["label"]: b["accepted_answers"][0] for b in ex["blocks"]})
        except (KeyError, IndexError):
            continue  # đã báo ở luật bài
        bodies_by_ex[key] = _class_members(code)
    for th in themes:
        errs.extend(_diagram_code_errors(th, exercises, bodies_by_ex))
    return errs
