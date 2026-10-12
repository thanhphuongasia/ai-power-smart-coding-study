"""Markdown → tài liệu System Design: chapter / section / card, bối cảnh và task thực chiến.

Quy ước (xem `content/sd/airline-reservation.md`):

- `# Tên tài liệu` đúng một lần, dòng đầu có nội dung.
- `## Bối cảnh`  → các card bối cảnh của Phase 2; `###`/`####` trong đó là tiêu đề cho các khối sau nó.
- `## Thực chiến` → mỗi `###` là một task, thân gồm các nhãn `Đề:`, `Gợi ý:`, `Rubric:`, `Đáp án mẫu:`.
  Mỗi dòng rubric là `- ý cần có :: từ khoá 1, từ khoá 2`.
- `##` còn lại là chapter, `###` là section, `####` là tiêu đề card. Nội dung nằm ngay dưới `##` (trước
  `###` đầu tiên) thành một section mang tên chapter.
- Mỗi khối (đoạn/danh sách, bảng, khối code, trích dẫn `>`) là một card. `card.id` là hash nội dung nên
  sửa một card không đổi id của card khác (tiến độ đọc bám theo id này).

Chỉ dùng thư viện chuẩn, một lượt qua các dòng: thời gian tuyến tính theo kích thước file.
"""

from __future__ import annotations

import hashlib
import re
import unicodedata

MAX_CHAPTERS = 50
MAX_SECTIONS = 200
MAX_TASKS = 12
MAX_CARDS_PER_SECTION = 200
MAX_CONTEXT_CARDS = 100
MAX_CARDS_TOTAL = 3000  # cả tài liệu: chặn JSONB phình vì hàng trăm nghìn khối rất ngắn
MAX_CARD_CHARS = 20_000
MAX_TITLE_CHARS = 200
MAX_HINTS = 5
MAX_RUBRIC = 12
MAX_KEYWORDS = 20
MAX_KEYWORD_CHARS = 60
MAX_RUBRIC_TEXT = 300
MAX_PROMPT_CHARS = 4000
MAX_ERRORS = 50

_HEADING = re.compile(r"^(#{1,6})[ \t]+(.+?)[ \t]*#*[ \t]*$")
_LABEL = re.compile(r"^(đề|prompt|gợi ý|hints?|rubric|đáp án mẫu|reference)[ \t]*:[ \t]*(.*)$", re.IGNORECASE)
_BULLET = re.compile(r"^[ \t]*[-*+][ \t]+(.*)$")
_LABEL_KIND = {
    "đề": "prompt", "prompt": "prompt",
    "gợi ý": "hints", "hint": "hints", "hints": "hints",
    "rubric": "rubric",
    "đáp án mẫu": "ref", "reference": "ref",
}


class MdError(Exception):
    """Tài liệu sai quy ước. `errors` là danh sách thông báo (kèm số dòng) để admin sửa."""

    def __init__(self, errors: list[str]):
        super().__init__("; ".join(errors[:3]))
        self.errors = errors


def slugify(text: str) -> str:
    """Tiếng Việt → slug ASCII: bỏ dấu, đ→d, mọi thứ khác chữ/số thành '-'. Rỗng → 'item'."""
    t = unicodedata.normalize("NFKD", text.replace("đ", "d").replace("Đ", "D"))
    t = "".join(c for c in t if not unicodedata.combining(c)).lower()
    t = re.sub(r"[^a-z0-9]+", "-", t).strip("-")[:60].strip("-")
    return t or "item"


def _bad_text(s: str) -> bool:
    # NUL làm Postgres JSONB lỗi; surrogate lẻ không encode được UTF-8 (cùng lý do app.progress._bad_text).
    if "\x00" in s:
        return True
    try:
        s.encode("utf-8")
    except UnicodeEncodeError:
        return True
    return False


def _unique(base: str, seen: dict[str, int]) -> str:
    """Id duy nhất trong một phạm vi, thời gian O(1) mỗi lần gọi: đếm số lần thấy `base`, lần thứ n>1 thêm
    hậu tố `-n`. (Dò hậu tố từng bước từng khiến 1MB khối trùng nhau chạy bậc hai, hàng chục giây.)"""
    n = seen.get(base, 0) + 1
    seen[base] = n
    out = base if n == 1 else f"{base}-{n}"
    while n > 1 and out in seen:  # hiếm: 'foo-2' đã là id của một mục khác
        n += 1
        out = f"{base}-{n}"
    seen[out] = seen.get(out, 0) or 1
    return out


def _card_id(kind: str, body: str) -> str:
    norm = " ".join(body.split())
    return hashlib.sha1(f"{kind}\n{norm}".encode("utf-8")).hexdigest()[:8]


def _is_fence(line: str) -> str | None:
    s = line.lstrip()
    for m in ("```", "~~~"):
        if s.startswith(m):
            return m
    return None


# Một "mục" trong một phạm vi là ("line", số_dòng, nội_dung) hoặc ("title", tiêu_đề).
Entry = tuple


def _blocks(entries: list[Entry], errors: list[str], where: str, limit: int) -> list[dict]:
    """Chia một phạm vi thành card, tối đa `limit` (vượt thì dừng ngay và báo lỗi). `where` chỉ để ghi lỗi."""
    cards: list[dict] = []
    seen: dict[str, int] = {}
    title = ""
    i, n = 0, len(entries)

    def add(kind: str, body: str, lineno: int, lang: str = "") -> None:
        if len(cards) >= limit:
            return
        body = body.strip("\n") if kind == "code" else body.strip()
        if not body.strip():
            return
        if len(body) > MAX_CARD_CHARS:
            errors.append(f"{where}: card quá dài ({len(body)} ký tự, tối đa {MAX_CARD_CHARS}), dòng {lineno}")
            return
        card = {"id": _unique(_card_id(kind, body), seen), "kind": kind, "title": title, "body": body}
        if lang:
            card["lang"] = lang
        cards.append(card)

    while i < n:
        if len(cards) >= limit:
            errors.append(f"{where}: quá {limit} card (giới hạn), dừng đọc tiếp")
            break
        e = entries[i]
        if e[0] == "title":
            title = e[1]
            i += 1
            continue
        _, lineno, line = e
        if not line.strip():
            i += 1
            continue
        fence = _is_fence(line)
        if fence:
            info = line.lstrip()[len(fence):].strip().split()
            lang = info[0].lower() if info else ""
            body: list[str] = []
            i += 1
            closed = False
            while i < n and entries[i][0] == "line":
                if _is_fence(entries[i][2]) == fence:
                    closed = True
                    i += 1
                    break
                body.append(entries[i][2])
                i += 1
            if not closed:
                errors.append(f"{where}: khối code mở ở dòng {lineno} không có dòng đóng")
            add("diagram" if lang == "mermaid" else "code", "\n".join(body), lineno, lang)
            continue
        stripped = line.lstrip()
        if stripped.startswith("|"):
            body = []
            while i < n and entries[i][0] == "line" and entries[i][2].lstrip().startswith("|"):
                body.append(entries[i][2].strip())
                i += 1
            add("table", "\n".join(body), lineno)
            continue
        if stripped.startswith(">"):
            body = []
            while i < n and entries[i][0] == "line" and entries[i][2].lstrip().startswith(">"):
                body.append(re.sub(r"^>[ \t]?", "", entries[i][2].lstrip()))
                i += 1
            add("callout", "\n".join(body), lineno)
            continue
        body = []
        while i < n and entries[i][0] == "line" and entries[i][2].strip():
            t = entries[i][2]
            if _is_fence(t) or t.lstrip().startswith(("|", ">")):
                break
            body.append(t.rstrip())
            i += 1
        add("text", "\n".join(body), lineno)
    return cards


def _task(name: str, entries: list[Entry], errors: list[str]) -> dict | None:
    where = f"task «{name}»"
    prompt: list[str] = []
    hints: list[str] = []
    rubric: list[dict] = []
    ref = ""
    kind = ""
    for e in entries:
        if e[0] != "line":
            continue
        _, lineno, line = e
        if not line.strip():
            continue
        m = _LABEL.match(line.strip())
        if m:
            kind = _LABEL_KIND[m.group(1).lower()]
            rest = m.group(2).strip()
            if kind == "prompt" and rest:
                prompt.append(rest)
            elif kind == "ref":
                ref = rest
            elif rest:
                errors.append(f"{where}: sau nhãn «{m.group(1)}:» phải xuống dòng rồi liệt kê bằng '- ' (dòng {lineno})")
            continue
        b = _BULLET.match(line)
        if kind == "prompt":
            prompt.append(line.strip())
        elif kind == "hints":
            if b:
                hints.append(b.group(1).strip())
            elif hints:
                hints[-1] += " " + line.strip()
        elif kind == "rubric":
            if not b:
                if rubric and "::" not in line:
                    rubric[-1]["text"] += " " + line.strip()
                else:
                    errors.append(f"{where}: dòng rubric phải bắt đầu bằng '- ' (dòng {lineno})")
                continue
            text, sep, kws = b.group(1).partition("::")
            keywords: list[str] = []
            for k in kws.split(","):
                k = k.strip().lower()
                if k and k not in keywords:
                    keywords.append(k)
            if not sep or not keywords or not text.strip():
                errors.append(f"{where}: rubric cần dạng '- ý cần có :: từ khoá, từ khoá' (dòng {lineno})")
                continue
            if len(keywords) > MAX_KEYWORDS or any(len(k) > MAX_KEYWORD_CHARS for k in keywords):
                errors.append(
                    f"{where}: tối đa {MAX_KEYWORDS} từ khoá, mỗi từ khoá ≤{MAX_KEYWORD_CHARS} ký tự (dòng {lineno})"
                )
                continue
            if len(text.strip()) > MAX_RUBRIC_TEXT:
                errors.append(f"{where}: ý rubric dài quá {MAX_RUBRIC_TEXT} ký tự (dòng {lineno})")
                continue
            rubric.append({"text": text.strip(), "keywords": keywords})
        elif kind == "ref":
            ref = (ref + " " + line.strip()).strip()
        else:
            errors.append(f"{where}: nội dung trước nhãn «Đề:» (dòng {lineno})")
    text_prompt = "\n".join(prompt).strip()
    if not text_prompt:
        errors.append(f"{where}: thiếu «Đề:»")
    if len(text_prompt) > MAX_PROMPT_CHARS:
        errors.append(f"{where}: «Đề:» dài quá {MAX_PROMPT_CHARS} ký tự")
    if not rubric:
        errors.append(f"{where}: thiếu «Rubric:» (cần ít nhất một ý)")
    if len(rubric) > MAX_RUBRIC:
        errors.append(f"{where}: tối đa {MAX_RUBRIC} ý rubric")
    if len(hints) > MAX_HINTS:
        errors.append(f"{where}: tối đa {MAX_HINTS} gợi ý")
    return {"name": name, "prompt": text_prompt, "hints": hints, "rubric": rubric, "ref": ref}


def parse_markdown(md: str) -> dict:
    """Trả `{title, context, sections, tasks}`; sai quy ước → `MdError` gom mọi lỗi tìm được."""
    errors: list[str] = []
    if _bad_text(md):
        raise MdError(["tài liệu chứa ký tự NUL hoặc ký tự không hợp lệ (surrogate)"])
    md = md.lstrip("﻿").replace("\r\n", "\n").replace("\r", "\n")

    # Lượt 1: tách heading (ngoài khối code) khỏi dòng thường.
    items: list[tuple] = []
    fence: str | None = None
    for no, line in enumerate(md.split("\n"), 1):
        f = _is_fence(line)
        if fence is None and f:
            fence = f
            items.append(("line", no, line))
            continue
        if fence is not None:
            if f == fence:
                fence = None
            items.append(("line", no, line))
            continue
        m = _HEADING.match(line)
        items.append(("heading", no, len(m.group(1)), m.group(2).strip()) if m else ("line", no, line))

    title = ""
    pre: list[int] = []
    context: list[Entry] = []
    # Mỗi chapter: {name, intro: [Entry], sections: [{name, entries}]}; task: {name, entries}.
    chapters: list[dict] = []
    tasks_raw: list[dict] = []
    region = "pre"  # pre | context | tasks | chapter
    cur_chapter: dict | None = None
    cur_section: dict | None = None
    cur_task: dict | None = None
    n_sections = 0

    def too_many(what: str, limit: int, no: int) -> MdError:
        return MdError([f"dòng {no}: quá {limit} {what} (giới hạn), dừng đọc tiếp"])

    for it in items:
        if it[0] == "heading":
            _, no, level, text = it
            if len(text) > MAX_TITLE_CHARS:
                errors.append(f"dòng {no}: tiêu đề dài quá {MAX_TITLE_CHARS} ký tự")
                text = text[:MAX_TITLE_CHARS]
            if level == 1:
                if title:
                    errors.append(f"dòng {no}: chỉ được có một tiêu đề '# ' (tên tài liệu)")
                else:
                    title = text
                continue
            if level == 2:
                key = slugify(text)
                cur_section = cur_task = cur_chapter = None
                if key in ("boi-canh", "context"):
                    region = "context"
                elif key in ("thuc-chien", "practice"):
                    region = "tasks"
                else:
                    region = "chapter"
                    if len(chapters) >= MAX_CHAPTERS:
                        raise too_many("chương", MAX_CHAPTERS, no)
                    cur_chapter = {"name": text, "line": no, "intro": [], "sections": []}
                    chapters.append(cur_chapter)
                continue
            if region == "context":
                context.append(("title", text))
            elif region == "tasks" and level == 3:
                if len(tasks_raw) >= MAX_TASKS:
                    raise too_many("task", MAX_TASKS, no)
                cur_task = {"name": text, "line": no, "entries": []}
                tasks_raw.append(cur_task)
            elif region == "tasks" and cur_task is not None:
                cur_task["entries"].append(("line", no, "#" * level + " " + text))
            elif region == "chapter" and level == 3:
                n_sections += 1
                if n_sections > MAX_SECTIONS:
                    raise too_many("section", MAX_SECTIONS, no)
                cur_section = {"name": text, "line": no, "entries": []}
                cur_chapter["sections"].append(cur_section)
            elif region == "chapter":
                (cur_section["entries"] if cur_section else cur_chapter["intro"]).append(("title", text))
            else:
                errors.append(f"dòng {no}: tiêu đề nằm trước chương đầu tiên ('## ...')")
            continue
        _, no, line = it
        if region == "context":
            context.append(it)
        elif region == "tasks":
            if cur_task is not None:
                cur_task["entries"].append(it)
            elif line.strip():
                errors.append(f"dòng {no}: nội dung trong «Thực chiến» phải nằm dưới một '### Tên task'")
        elif region == "chapter":
            (cur_section["entries"] if cur_section else cur_chapter["intro"]).append(it)
        elif line.strip():
            pre.append(no)

    if not title:
        errors.append("thiếu tên tài liệu: dòng '# ...' đầu tiên")
    if pre:
        errors.append(f"dòng {pre[0]}: nội dung nằm trước chương đầu tiên ('## ...')")

    # Chapter → section (chapter có nội dung ngay dưới '##' thì thành một section mang tên chapter).
    sections: list[dict] = []
    seen_sections: dict[str, int] = {}
    budget = MAX_CARDS_TOTAL
    for ci, ch in enumerate(chapters):
        raw = []
        if any(e[0] == "line" and e[2].strip() for e in ch["intro"]):
            raw.append({"name": ch["name"], "line": ch["line"], "entries": ch["intro"]})
        raw.extend(ch["sections"])
        if not raw:
            errors.append(f"dòng {ch['line']}: chương «{ch['name']}» không có nội dung")
        for s in raw:
            cards = _blocks(s["entries"], errors, f"section «{s['name']}»", min(MAX_CARDS_PER_SECTION, budget))
            budget -= len(cards)
            if not cards:
                errors.append(f"dòng {s['line']}: section «{s['name']}» không có card nào")
            sections.append({
                "id": _unique(slugify(s["name"]), seen_sections),
                "position": len(sections),
                "chapter": ch["name"],
                "chapter_position": ci,
                "title": s["name"],
                "cards": cards,
            })
    if not sections:
        errors.append("không có chương nào ('## Tên chương') kèm nội dung")

    context_cards = _blocks(context, errors, "Bối cảnh", min(MAX_CONTEXT_CARDS, max(budget, 0)))

    by_slug = {s["id"]: s["id"] for s in sections}
    by_title = {slugify(s["title"]): s["id"] for s in sections}
    tasks: list[dict] = []
    seen_tasks: dict[str, int] = {}
    for t in tasks_raw:
        parsed = _task(t["name"], t["entries"], errors)
        if parsed is None:
            continue
        ref = parsed.pop("ref")
        ref_id = None
        if ref:
            ref_id = by_slug.get(slugify(ref)) or by_title.get(slugify(ref))
            if ref_id is None:
                errors.append(f"task «{t['name']}»: «Đáp án mẫu: {ref}» không khớp section nào")
        tasks.append({"id": _unique(slugify(t["name"]), seen_tasks), "position": len(tasks), **parsed, "ref_section_id": ref_id})

    if errors:
        extra = len(errors) - MAX_ERRORS
        raise MdError(errors[:MAX_ERRORS] + ([f"… và {extra} lỗi nữa"] if extra > 0 else []))
    return {"title": title, "context": context_cards, "sections": sections, "tasks": tasks}
