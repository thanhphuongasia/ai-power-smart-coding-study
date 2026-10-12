"""Duyệt nội dung: mọi thay đổi (admin editor, MCP) vào hàng chờ, admin approve/reject TỪNG MỤC.

Hai khái niệm, không lẫn nhau:

- **live**  = các bảng nội dung (`load_content`). Học viên (`/content`, `/run`, tiến độ) chỉ đọc live.
  Chỉ hai đường ghi live: `approve` ở đây và CLI `load_content --force`.
- **draft** = live ⊕ mọi dòng `content_changes` còn `pending`. Admin editor và MCP đọc/ghi draft.

Một **mục** là project (theme), module (topic), file hoặc bài (exercise). Mỗi mục có `fields` (nội dung
riêng của nó) và chỗ đứng: cha + `order` = thứ tự ĐẦY ĐỦ các anh em trong draft. Áp một mục = đặt nó vào
cha rồi xếp lại các anh em có trong `order` theo đúng `order` (anh em chỉ có trên live giữ chỗ). Vì vậy
áp mọi mục theo bất kỳ thứ tự nào cũng ra đúng draft; duyệt một mục thì thứ tự tương đối của các anh em
chung trong thùng chứa đó cũng theo draft (thứ tự là của thùng chứa, không của riêng mục). Diff chỉ coi
là "đã sửa" những mục thật sự đổi chỗ (dãy con chung dài nhất), nên chèn một bài vào đầu file không biến
mọi bài sau nó thành mục chờ. Vị trí của bài trong file thuộc về BÀI (`placements`), nên duyệt một bài mới
là bài hiện đúng chỗ.

Ràng buộc cha–con khi duyệt từng mục:
- tạo con trước cha → `DependencyMissing` ("cần duyệt X trước");
- project mới kéo theo module cấp 1 mới của nó (luật "project cần ít nhất 1 module");
- xoá project/module/file kéo theo các mục XOÁ của module/file con; còn bài trong file (hoặc con không bị
  xoá) → `DependencyMissing` — bài không bao giờ bị xoá ngầm theo cha;
- bỏ (reject) một mục kéo theo các mục chờ không còn áp được vì thiếu nó.
"""

from __future__ import annotations

import copy
import logging
from datetime import datetime, timezone
from typing import Any, Iterator

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.content_api import Judge
from app.db import SessionLocal
from app.export_content import admin_version, export_content
from app.load_content import load_content, lock_content, validation_errors
from app.tables import ContentChange

logger = logging.getLogger("review")

KINDS = ("project", "module", "file", "exercise")
KIND_LABEL = {"project": "project", "module": "module", "file": "file", "exercise": "bài"}
PROJECT_FIELDS = ("id", "name", "description", "tags", "diagram")
MODULE_FIELDS = ("id", "name", "description")
FILE_FIELDS = ("id", "name")


class ReviewError(Exception):
    """Lỗi có mã cho API: `code` là chuỗi ổn định (client so), `message` cho người đọc."""

    status = 409

    def __init__(self, code: str, message: str, errors: list[str] | None = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.errors = errors or [message]


class VersionConflict(ReviewError):
    def __init__(self):
        super().__init__("version_conflict", "Nội dung đã đổi từ lúc bạn tải — tải lại rồi sửa tiếp")


class ItemConflict(ReviewError):
    def __init__(self, message: str):
        super().__init__("item_conflict", message)


class DependencyMissing(ReviewError):
    status = 422

    def __init__(self, message: str):
        super().__init__("dependency_missing", message)


class InvalidResult(ReviewError):
    status = 422

    def __init__(self, errors: list[str]):
        super().__init__("invalid", "Áp mục này lên nội dung đang chạy thì vi phạm luật", errors)


class UnsupportedMove(ReviewError):
    status = 422

    def __init__(self, module_id: str):
        super().__init__(
            "unsupported_move",
            f"Chưa hỗ trợ chuyển module '{module_id}' sang project/module cha khác — tạo module mới ở chỗ mới "
            "rồi chuyển file/bài sang",
        )


class NotPending(ReviewError):
    status = 404

    def __init__(self):
        super().__init__("change_not_found", "Không có mục chờ duyệt này (đã duyệt/bỏ, hoặc không tồn tại)")


# --- Nội dung ↔ mục (thuần, không DB) ------------------------------------------------------------


def _walk_modules(topics: list[dict], theme_id: str, parent_id: str | None) -> Iterator[tuple[dict, str, str | None, list]]:
    for t in topics:
        yield t, theme_id, parent_id, topics
        yield from _walk_modules(t.get("modules", []), theme_id, t["id"])


def items(content: dict) -> dict[tuple[str, str], dict]:
    """Mọi mục của một bản nội dung, khoá `(kind, id)`."""
    out: dict[tuple[str, str], dict] = {}
    themes = content["themes"]
    theme_ids = [t["id"] for t in themes]
    placements: dict[str, dict[str, list[str]]] = {}
    for theme in themes:
        out[("project", theme["id"])] = {
            "fields": {k: theme[k] for k in PROJECT_FIELDS},
            "order": theme_ids,
        }
        for mod, theme_id, parent_id, siblings in _walk_modules(theme["topics"], theme["id"], None):
            sib_ids = [s["id"] for s in siblings]
            out[("module", mod["id"])] = {
                "fields": {k: mod[k] for k in MODULE_FIELDS},
                "theme_id": theme_id,
                "parent_id": parent_id,
                "order": sib_ids,
            }
            file_ids = [f["id"] for f in mod["files"]]
            for f in mod["files"]:
                out[("file", f["id"])] = {
                    "fields": {k: f[k] for k in FILE_FIELDS},
                    "module_id": mod["id"],
                    "order": file_ids,
                }
                for eid in f["exercise_ids"]:
                    placements.setdefault(eid, {})[f["id"]] = list(f["exercise_ids"])
    for eid, ex in content["exercises"].items():
        out[("exercise", eid)] = {"fields": ex, "placements": placements.get(eid, {})}
    return out


def _core(kind: str, item: dict | None) -> Any:
    """Phần của mục dùng để so "có đổi không" (diff, kiểm xung đột) — bỏ thứ tự anh em (`order`): thêm/bớt
    hay duyệt mục khác làm danh sách anh em đổi không phải là mục này đổi. Đổi chỗ thật thì `_moved` bắt."""
    if item is None:
        return None
    if kind == "exercise":
        return {"fields": item["fields"], "files": sorted(item["placements"])}
    return {k: v for k, v in item.items() if k != "order"}


def _lcs_keep(a: list[str], b: list[str]) -> set[str]:
    """Phần tử chung giữ nguyên thứ tự tương đối (dãy con chung dài nhất); phần tử chung còn lại = đã di chuyển."""
    n, m = len(a), len(b)
    dp = [[0] * (m + 1) for _ in range(n + 1)]
    for i in range(n - 1, -1, -1):
        for j in range(m - 1, -1, -1):
            dp[i][j] = dp[i + 1][j + 1] + 1 if a[i] == b[j] else max(dp[i + 1][j], dp[i][j + 1])
    keep, i, j = set(), 0, 0
    while i < n and j < m:
        if a[i] == b[j]:
            keep.add(a[i])
            i, j = i + 1, j + 1
        elif dp[i + 1][j] >= dp[i][j + 1]:
            i += 1
        else:
            j += 1
    return keep


def _containers(content: dict) -> dict[tuple, list[str]]:
    """Thứ tự anh em theo từng "thùng chứa": danh sách theme, con của theme/module, file của module,
    bài của file."""
    out: dict[tuple, list[str]] = {("root",): [t["id"] for t in content["themes"]]}
    for theme in content["themes"]:
        out[("theme", theme["id"])] = [t["id"] for t in theme["topics"]]
        for mod, _, _, _ in _walk_modules(theme["topics"], theme["id"], None):
            out[("module", mod["id"])] = [t["id"] for t in mod.get("modules", [])]
            out[("files", mod["id"])] = [f["id"] for f in mod["files"]]
            for f in mod["files"]:
                out[("exercises", f["id"])] = list(f["exercise_ids"])
    return out


def _moved(live: dict, draft: dict) -> set[tuple[str, str]]:
    """Mục đổi chỗ trong cùng thùng chứa (không tính chỗ xê dịch do mục khác được thêm/bớt)."""
    kind_of = {"root": "project", "theme": "module", "module": "module", "files": "file", "exercises": "exercise"}
    lc, dc = _containers(live), _containers(draft)
    out: set[tuple[str, str]] = set()
    for key, d_ids in dc.items():
        l_ids = lc.get(key)
        if not l_ids:
            continue
        common_d = [x for x in d_ids if x in set(l_ids)]
        common_l = [x for x in l_ids if x in set(d_ids)]
        keep = _lcs_keep(common_l, common_d)
        out |= {(kind_of[key[0]], x) for x in common_d if x not in keep}
    return out


def diff(live: dict, draft: dict) -> list[dict]:
    """Các mục khác nhau giữa live và draft: `{kind, item_id, action, before, after}`."""
    li, di = items(live), items(draft)
    moved = _moved(live, draft)
    out = []
    for kind in KINDS:
        keys = sorted({k for k in (*li, *di) if k[0] == kind}, key=lambda k: k[1])
        for key in keys:
            before, after = li.get(key), di.get(key)
            if before is None:
                action = "create"
            elif after is None:
                action = "delete"
            elif _core(kind, before) != _core(kind, after) or key in moved:
                action = "update"
            else:
                continue
            out.append({"kind": kind, "item_id": key[1], "action": action, "before": before, "after": after})
    return out


# --- Áp một mục lên một bản nội dung (thuần) --------------------------------------------------------


def _place(lst: list, value: Any, order: list[str], key=lambda x: x) -> None:
    """Đặt `value` vào `lst` rồi xếp các phần tử có trong `order` theo đúng `order`, giữ nguyên các ô của
    phần tử không có trong `order` (chỉ có trên live)."""
    my_id = key(value)
    rank = {x: i for i, x in enumerate(order)}
    ids = [key(x) for x in lst]
    before = [x for x in order[: rank.get(my_id, len(order))] if x in ids]
    pos = ids.index(before[-1]) + 1 if before else 0
    lst.insert(pos, value)
    slots = [i for i, x in enumerate(lst) if key(x) in rank]
    ranked = sorted((lst[i] for i in slots), key=lambda x: rank[key(x)])
    for i, x in zip(slots, ranked):
        lst[i] = x


def _remove(lst: list, item_id: str, key=lambda x: x) -> Any:
    for i, x in enumerate(lst):
        if key(x) == item_id:
            return lst.pop(i)
    return None


def _index(content: dict) -> tuple[dict, dict, dict]:
    themes = {t["id"]: t for t in content["themes"]}
    modules: dict[str, tuple[dict, list]] = {}
    files: dict[str, tuple[dict, dict]] = {}
    for theme in content["themes"]:
        for mod, _, _, siblings in _walk_modules(theme["topics"], theme["id"], None):
            modules[mod["id"]] = (mod, siblings)
            for f in mod["files"]:
                files[f["id"]] = (f, mod)
    return themes, modules, files


def _need(kind: str, item_id: str) -> DependencyMissing:
    return DependencyMissing(f"Cần duyệt {KIND_LABEL[kind]} '{item_id}' trước")


def _need_gone(kind: str, item_id: str) -> DependencyMissing:
    return DependencyMissing(f"Còn {KIND_LABEL[kind]} '{item_id}' bên trong — cần duyệt xoá/chuyển nó trước")


def apply_change(content: dict, kind: str, item_id: str, action: str, after: dict | None) -> dict:
    """Bản sao của `content` sau khi áp đúng một mục. Thiếu cha (cha chưa duyệt) → DependencyMissing."""
    c = copy.deepcopy(content)
    themes, modules, files = _index(c)
    by_id = lambda x: x["id"]  # noqa: E731
    if kind == "project":
        node = themes.get(item_id)
        if action == "delete":
            if node and node["topics"]:
                raise _need_gone("module", node["topics"][0]["id"])
            _remove(c["themes"], item_id, by_id)
            return c
        if node is None:
            node = {"topics": []}
        else:
            _remove(c["themes"], item_id, by_id)
        node.update(after["fields"])
        _place(c["themes"], node, after["order"], by_id)
    elif kind == "module":
        found = modules.get(item_id)
        if action == "delete":
            if found:
                if found[0].get("modules"):
                    raise _need_gone("module", found[0]["modules"][0]["id"])
                if found[0]["files"]:
                    raise _need_gone("file", found[0]["files"][0]["id"])
                _remove(found[1], item_id, by_id)
            return c
        node = found[0] if found else {"files": [], "modules": []}
        if after["parent_id"] is not None:
            if after["parent_id"] not in modules:
                raise _need("module", after["parent_id"])
            target = modules[after["parent_id"]][0].setdefault("modules", [])
        else:
            if after["theme_id"] not in themes:
                raise _need("project", after["theme_id"])
            target = themes[after["theme_id"]]["topics"]
        if found:
            _remove(found[1], item_id, by_id)
        node.update(after["fields"])
        node.setdefault("modules", [])
        _place(target, node, after["order"], by_id)
    elif kind == "file":
        found = files.get(item_id)
        if action == "delete":
            if found:
                if found[0]["exercise_ids"]:
                    raise _need_gone("exercise", found[0]["exercise_ids"][0])
                _remove(found[1]["files"], item_id, by_id)
            return c
        if after["module_id"] not in modules:
            raise _need("module", after["module_id"])
        node = found[0] if found else {"exercise_ids": []}
        if found:
            _remove(found[1]["files"], item_id, by_id)
        node.update(after["fields"])
        _place(modules[after["module_id"]][0]["files"], node, after["order"], by_id)
    elif kind == "exercise":
        for f, _ in files.values():
            if item_id in f["exercise_ids"]:
                f["exercise_ids"].remove(item_id)
        if action == "delete":
            c["exercises"].pop(item_id, None)
            return c
        for file_id in after["placements"]:
            if file_id not in files:
                raise _need("file", file_id)
        c["exercises"][item_id] = copy.deepcopy(after["fields"])
        for file_id, order in after["placements"].items():
            _place(files[file_id][0]["exercise_ids"], item_id, order)
    else:  # pragma: no cover — kind lấy từ KINDS
        raise ValueError(kind)
    return c


def merge_pending(live: dict, changes: list[dict], skipped: list[dict] | None = None) -> dict:
    """draft = live ⊕ changes. Áp theo thứ tự cha trước con (project → module → file → bài, xoá sau cùng);
    mục còn thiếu cha thì thử lại sau khi các mục khác đã áp. Mục không áp được (cha bị bỏ) thì bỏ qua."""
    order = {k: i for i, k in enumerate(KINDS)}
    todo = sorted(
        changes,
        key=lambda ch: (ch["action"] == "delete", order[ch["kind"]] * (-1 if ch["action"] == "delete" else 1)),
    )
    content = {"themes": live["themes"], "exercises": live["exercises"]}
    while todo:
        left = []
        for ch in todo:
            try:
                content = apply_change(content, ch["kind"], ch["item_id"], ch["action"], ch["after"])
            except DependencyMissing:
                left.append(ch)
        if len(left) == len(todo):
            for ch in left:
                logger.warning("draft: bỏ qua %s %s (thiếu cha)", ch["kind"], ch["item_id"])
            if skipped is not None:
                skipped.extend(left)
            break
        todo = left
    return content


# --- DB ----------------------------------------------------------------------------------------------


def _now() -> datetime:
    return datetime.now(timezone.utc)


def pending_rows(session: Session) -> list[ContentChange]:
    return list(
        session.scalars(select(ContentChange).where(ContentChange.status == "pending").order_by(ContentChange.id))
    )


def _as_change(row: ContentChange) -> dict:
    return {"kind": row.kind, "item_id": row.item_id, "action": row.action, "after": row.after}


def draft_content(session: Session, rows: list[ContentChange] | None = None) -> dict:
    rows = pending_rows(session) if rows is None else rows
    return merge_pending(export_content(session), [_as_change(r) for r in rows])


def draft_version(session: Session) -> str:
    return admin_version(draft_content(session))


def submit(session: Session, base_version: str, content: dict, author: str) -> dict:
    """Ghi bản sửa của admin/MCP thành các mục pending (KHÔNG đụng live). `content` đã qua
    `validation_errors`. Kiểm `base_version` == hash(draft) trong khoá ghi. Không commit."""
    lock_content(session)
    live = export_content(session)
    rows = {(r.kind, r.item_id): r for r in pending_rows(session)}
    current = admin_version(merge_pending(live, [_as_change(r) for r in rows.values()]))
    if base_version != current:
        raise VersionConflict()
    new = {"themes": content["themes"], "exercises": content["exercises"]}
    changes = diff(live, new)
    # Đổi cha của module có sẵn (kể cả đảo cha–con, hay kéo vào project mới) chưa duyệt từng mục an toàn
    # được (phụ thuộc vòng); editor và MCP chưa có thao tác này nên chặn ở đầu vào.
    for ch in changes:
        if ch["kind"] == "module" and ch["action"] == "update" and (
            (ch["before"]["theme_id"], ch["before"]["parent_id"]) != (ch["after"]["theme_id"], ch["after"]["parent_id"])
        ):
            raise UnsupportedMove(ch["item_id"])
    seen = set()
    for ch in changes:
        key = (ch["kind"], ch["item_id"])
        seen.add(key)
        row = rows.get(key)
        if row is None:
            session.add(ContentChange(status="pending", author=author, **ch))
        elif (row.action, row.before, row.after) != (ch["action"], ch["before"], ch["after"]):
            row.action, row.before, row.after = ch["action"], ch["before"], ch["after"]
            row.author, row.updated_at = author, _now()
    for key, row in rows.items():
        if key not in seen:  # mục đã quay về giống live: không còn gì để duyệt
            session.delete(row)
    session.flush()
    # Cùng một đường tính với GET (draft từ các dòng pending) để version trả về dùng làm base tiếp được.
    version = admin_version(merge_pending(live, [_as_change(r) for r in pending_rows(session)]))
    logger.info("%s gửi %d mục chờ duyệt (%s -> %s)", author, len(changes), base_version, version)
    return {"version": version, "pending": len(changes)}


def _pending(session: Session, change_id: int) -> ContentChange:
    row = session.get(ContentChange, change_id, with_for_update=True)
    if row is None or row.status != "pending":
        raise NotPending()
    return row


def _descendants(live: dict, kind: str, item_id: str) -> list[tuple[str, str, int]]:
    """Module/file con (mọi tầng) của một project/module/file trên live, kèm độ sâu."""
    themes, modules, _ = _index(live)
    out: list[tuple[str, str, int]] = []

    def walk(topics: list[dict], depth: int) -> None:
        for t in topics:
            out.append(("module", t["id"], depth))
            out.extend(("file", f["id"], depth + 1) for f in t["files"])
            walk(t.get("modules", []), depth + 1)

    if kind == "project" and item_id in themes:
        walk(themes[item_id]["topics"], 1)
    elif kind == "module" and item_id in modules:
        mod = modules[item_id][0]
        out.extend(("file", f["id"], 1) for f in mod["files"])
        walk(mod.get("modules", []), 1)
    return out


def _companions(session: Session, live: dict, row: ContentChange) -> list[ContentChange]:
    """Mục phải duyệt CÙNG `row` vì luật cha–con (thứ tự trả về = thứ tự áp)."""
    pending = {(r.kind, r.item_id): r for r in pending_rows(session) if r.id != row.id}
    if row.kind == "project" and row.action == "create":
        # luật "project cần ít nhất 1 module": module cấp 1 mới của chính nó (rỗng — chưa lộ bài nào)
        return [
            r for r in pending.values()
            if r.kind == "module" and r.action == "create"
            and r.after["theme_id"] == row.item_id and r.after["parent_id"] is None
        ]
    if row.action == "delete" and row.kind in ("project", "module"):
        # Xoá cả nhánh: các mục XOÁ đang chờ của bài trong nhánh (admin đã chủ động xoá — không phải xoá ngầm;
        # xoá riêng bài cuối của project vi phạm luật sơ đồ khi project còn, nên phải đi cùng), rồi file/module
        # con sâu nhất trước. Con không có mục xoá (hoặc bài không bị xoá) → apply_change báo DependencyMissing.
        desc = sorted(_descendants(live, row.kind, row.item_id), key=lambda d: (-d[2], d[0] == "module"))
        _, _, files = _index(live)
        in_branch = [eid for k, i, _ in desc if k == "file" for eid in files[i][0]["exercise_ids"]]
        out = [pending[("exercise", e)] for e in dict.fromkeys(in_branch)
               if ("exercise", e) in pending and pending[("exercise", e)].action == "delete"]
        return out + [pending[(k, i)] for k, i, _ in desc if (k, i) in pending and pending[(k, i)].action == "delete"]
    return []


def approve(session: Session, change_id: int, reviewer: str) -> dict:
    """Áp đúng một mục (kèm mục bắt buộc đi cùng, xem `_companions`) lên live. Khoá ghi → mục live hiện tại
    phải còn như lúc gửi (`before`) → áp → toàn bộ live mới phải qua `validation_errors` → `load_content`.
    Không commit."""
    lock_content(session)
    row = _pending(session, change_id)
    live = export_content(session)
    current_items = items(live)
    companions = _companions(session, live, row)
    new_live = live
    for r in (*companions, row) if row.action == "delete" else (row, *companions):
        current = current_items.get((r.kind, r.item_id))
        label = f"{KIND_LABEL[r.kind]} '{r.item_id}'"
        if r.action == "create" and current is not None:
            raise ItemConflict(f"{label} đã có trên nội dung đang chạy — bỏ mục này rồi sửa lại")
        if r.action != "create" and _core(r.kind, current) != _core(r.kind, r.before):
            raise ItemConflict(f"{label} trên nội dung đang chạy đã khác lúc gửi duyệt — bỏ mục này rồi sửa lại")
        new_live = apply_change(new_live, r.kind, r.item_id, r.action, r.after)
    errors = validation_errors(new_live)
    if errors:
        raise InvalidResult(errors)
    load_content(session, new_live, validated=True)
    for r in (row, *companions):
        r.status, r.decided_by, r.decided_at = "approved", reviewer, _now()
    session.flush()
    also = [r.id for r in companions]
    logger.info("%s duyệt %s %s (%s) kèm %s", reviewer, row.kind, row.item_id, row.action, also)
    return {"id": row.id, "status": row.status, "also": also}


def reject(session: Session, change_id: int, reviewer: str) -> dict:
    """Bỏ một mục, kèm các mục chờ không còn áp được vì thiếu nó (vd bài trong file mới vừa bị bỏ)."""
    lock_content(session)
    row = _pending(session, change_id)
    row.status, row.decided_by, row.decided_at = "rejected", reviewer, _now()
    session.flush()
    rest = pending_rows(session)
    skipped: list[dict] = []
    merge_pending(export_content(session), [_as_change(r) for r in rest], skipped)
    gone = {(c["kind"], c["item_id"]) for c in skipped}
    # project mới mất module cấp 1 mới cuối cùng → không bao giờ duyệt được ("cần ít nhất 1 module"): bỏ kèm
    new_projects = {r.item_id for r in rest if r.kind == "project" and r.action == "create"}
    with_module = {r.after["theme_id"] for r in rest if r.kind == "module" and r.action == "create"
                   and r.after["parent_id"] is None and (r.kind, r.item_id) not in gone}
    for pid in new_projects - with_module:
        gone.add(("project", pid))
        gone |= {(r.kind, r.item_id) for r in rest if r.kind == "module" and r.after and r.after.get("theme_id") == pid}
    also = [r for r in rest if (r.kind, r.item_id) in gone]
    for r in also:
        r.status, r.decided_by, r.decided_at = "rejected", reviewer, _now()
    session.flush()
    logger.info("%s bỏ %s %s (%s) kèm %s", reviewer, row.kind, row.item_id, row.action, [r.item_id for r in also])
    return {"id": row.id, "status": row.status, "also": [r.id for r in also]}


def draft_judge(session: Session, exercise_id: str) -> Judge | None:
    ex = draft_content(session)["exercises"].get(exercise_id)
    if ex is None:
        return None
    return Judge(function=ex["function_name"], cases=ex["judge"]["cases"], class_name=ex["class_name"])


def get_draft_judge_lookup():
    """Dependency cho `/api/admin/run`: phần chấm theo DRAFT; session ngắn như `get_judge_lookup`."""

    def lookup(exercise_id: str) -> Judge | None:
        with SessionLocal() as session:
            return draft_judge(session, exercise_id)

    return lookup


def change_json(row: ContentChange) -> dict:
    return {
        "id": row.id,
        "kind": row.kind,
        "item_id": row.item_id,
        "action": row.action,
        "before": row.before,
        "after": row.after,
        "status": row.status,
        "author": row.author,
        "created_at": row.created_at.isoformat() if row.created_at else None,
        "updated_at": row.updated_at.isoformat() if row.updated_at else None,
    }
