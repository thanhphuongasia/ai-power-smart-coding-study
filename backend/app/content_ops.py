"""Phép đọc/ghi THUẦN trên cây nội dung (shape `content.json`) cho MCP server.

Không đụng DB, không mutate input: hàm ghi deepcopy rồi trả bản mới. Chỉ kiểm cấu trúc (tồn tại /
trùng / field cho phép / kiểu cơ bản); luật nội dung chi tiết là việc của `load_content.validation_errors`
ở tầng gọi. "project" = theme, "module" = topic, "lesson" = exercise.
"""

from __future__ import annotations

import copy
from typing import Any, Iterator


class ContentOpError(Exception):
    """Thao tác sai (id không tồn tại / đã tồn tại / field không cho sửa / kiểu sai). Thông điệp tiếng Việt."""


# ---------- helper nội bộ ----------


def _need_dict(value: Any, what: str) -> dict:
    if not isinstance(value, dict):
        raise ContentOpError(f"{what} phải là object (dict)")
    return value


def _need_id(value: Any, what: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ContentOpError(f"{what} phải là chuỗi không rỗng")
    return value


def _need_str(value: Any, what: str) -> str:
    if not isinstance(value, str):
        raise ContentOpError(f"{what} phải là chuỗi")
    return value


def _need_list(value: Any, what: str) -> list:
    if not isinstance(value, list):
        raise ContentOpError(f"{what} phải là danh sách")
    return value


def _walk(topics: list[dict]) -> Iterator[dict]:
    for tp in topics:
        yield tp
        yield from _walk(tp.get("modules", []))


def _all_modules(content: dict) -> Iterator[tuple[dict, dict]]:
    """(theme, module) cho mọi module ở mọi độ sâu."""
    for th in content.get("themes", []):
        for tp in _walk(th.get("topics", [])):
            yield th, tp


def _all_files(content: dict) -> Iterator[tuple[dict, dict, dict]]:
    for th, tp in _all_modules(content):
        for f in tp.get("files", []):
            yield th, tp, f


def _used_ids(content: dict) -> set[str]:
    """Không gian tên chung: theme, module, file, bài, ô."""
    ids: set[str] = set()
    for th in content.get("themes", []):
        ids.add(th["id"])
    for _, tp in _all_modules(content):
        ids.add(tp["id"])
    for _, _, f in _all_files(content):
        ids.add(f["id"])
    for key, ex in content.get("exercises", {}).items():
        ids.add(key)
        ids.add(ex.get("id", key))
        for b in ex.get("blocks", []):
            if isinstance(b, dict) and "id" in b:
                ids.add(b["id"])
    return ids


def _find_theme(content: dict, project_id: str) -> dict:
    for th in content.get("themes", []):
        if th["id"] == project_id:
            return th
    raise ContentOpError(f"Không tìm thấy project '{project_id}'")


def _find_module(content: dict, module_id: str) -> tuple[dict, dict]:
    for th, tp in _all_modules(content):
        if tp["id"] == module_id:
            return th, tp
    raise ContentOpError(f"Không tìm thấy module '{module_id}'")


def _find_file(content: dict, file_id: str) -> dict:
    for _, _, f in _all_files(content):
        if f["id"] == file_id:
            return f
    raise ContentOpError(f"Không tìm thấy file '{file_id}'")


def _find_lesson(content: dict, lesson_id: str) -> dict:
    ex = content.get("exercises", {})
    if lesson_id not in ex:
        raise ContentOpError(f"Không tìm thấy bài '{lesson_id}'")
    return ex[lesson_id]


def _check_free(content: dict, new_id: str, what: str, extra: set[str] | None = None) -> None:
    if new_id in _used_ids(content) or (extra and new_id in extra):
        raise ContentOpError(f"{what} '{new_id}' đã tồn tại (id dùng chung cho project/module/file/bài/ô)")


def _check_changes(changes: Any, allowed: set[str], what: str) -> dict:
    _need_dict(changes, "changes")
    bad = sorted(set(changes) - allowed)
    if bad:
        raise ContentOpError(f"Không được sửa field {bad} của {what}; chỉ được sửa {sorted(allowed)}")
    return changes


def _check_fields(obj: dict, fields: dict[str, type], what: str) -> None:
    for name, typ in fields.items():
        if name not in obj:
            raise ContentOpError(f"{what} thiếu field '{name}'")
        if not isinstance(obj[name], typ):
            raise ContentOpError(f"{what}: field '{name}' sai kiểu (cần {typ.__name__})")


# ---------- đọc ----------


def _count(topics: list[dict]) -> tuple[int, int, set[str]]:
    modules = files = 0
    lessons: set[str] = set()
    for tp in _walk(topics):
        modules += 1
        files += len(tp.get("files", []))
        for f in tp.get("files", []):
            lessons.update(f.get("exercise_ids", []))
    return modules, files, lessons


def list_projects(content: dict) -> list[dict]:
    out = []
    for th in content.get("themes", []):
        m, f, lessons = _count(th.get("topics", []))
        out.append(
            {
                "id": th["id"],
                "name": th["name"],
                "description": th["description"],
                "tags": copy.deepcopy(th.get("tags", [])),
                "module_count": m,
                "file_count": f,
                "lesson_count": len(lessons),
            }
        )
    return out


def project_tree(content: dict, project_id: str) -> dict:
    th = _find_theme(content, project_id)
    exercises = content.get("exercises", {})

    def mod(tp: dict) -> dict:
        files = []
        for f in tp.get("files", []):
            lessons = []
            for eid in f.get("exercise_ids", []):
                ex = exercises.get(eid, {})
                lessons.append(
                    {
                        "id": eid,
                        "title": ex.get("title"),
                        "class_name": ex.get("class_name"),
                        "function_name": ex.get("function_name"),
                    }
                )
            files.append({"id": f["id"], "name": f["name"], "lessons": lessons})
        return {
            "id": tp["id"],
            "name": tp["name"],
            "description": tp["description"],
            "files": files,
            "modules": [mod(s) for s in tp.get("modules", [])],
        }

    return {
        "id": th["id"],
        "name": th["name"],
        "description": th["description"],
        "tags": copy.deepcopy(th.get("tags", [])),
        "diagram": copy.deepcopy(th.get("diagram", {"classes": [], "relations": []})),
        "modules": [mod(tp) for tp in th.get("topics", [])],
    }


def get_lesson(content: dict, lesson_id: str) -> dict:
    ex = copy.deepcopy(_find_lesson(content, lesson_id))
    locations = [
        {"project_id": th["id"], "module_id": tp["id"], "file_id": f["id"]}
        for th, tp, f in _all_files(content)
        if lesson_id in f.get("exercise_ids", [])
    ]
    ex["locations"] = locations
    return ex


# ---------- ghi: bài ----------


def create_lesson(content: dict, file_id: str, lesson: dict) -> dict:
    _need_dict(lesson, "lesson")
    lid = _need_id(lesson.get("id"), "lesson.id")
    new = copy.deepcopy(content)
    f = _find_file(new, file_id)
    blocks = lesson.get("blocks", [])
    _need_list(blocks, "lesson.blocks")
    block_ids: list[str] = []
    for b in blocks:
        _need_dict(b, "ô (block)")
        block_ids.append(_need_id(b.get("id"), "block.id"))
    if len(set(block_ids)) != len(block_ids):
        raise ContentOpError("lesson có id ô (block) bị trùng nhau")
    _check_free(new, lid, "id bài")
    for bid in block_ids:
        _check_free(new, bid, "id ô", extra={lid})
    new["exercises"][lid] = copy.deepcopy(lesson)
    f["exercise_ids"].append(lid)
    return new


def update_lesson(content: dict, lesson_id: str, changes: dict) -> dict:
    _need_dict(changes, "changes")
    if "id" in changes:
        raise ContentOpError("Không được đổi 'id' của bài")
    new = copy.deepcopy(content)
    ex = _find_lesson(new, lesson_id)
    if "blocks" in changes:
        _need_list(changes["blocks"], "blocks")
        old_ids = {b["id"] for b in ex.get("blocks", []) if isinstance(b, dict) and "id" in b}
        taken = _used_ids(new) - old_ids
        seen: set[str] = set()
        for b in changes["blocks"]:
            _need_dict(b, "ô (block)")
            bid = _need_id(b.get("id"), "block.id")
            if bid in taken or bid in seen:
                raise ContentOpError(f"id ô '{bid}' đã tồn tại hoặc bị trùng")
            seen.add(bid)
    ex.update(copy.deepcopy(changes))
    return new


# ---------- ghi: project / module / file ----------


def create_project(content: dict, project: dict, first_module: dict) -> dict:
    _need_dict(project, "project")
    _need_dict(first_module, "first_module")
    pid = _need_id(project.get("id"), "project.id")
    mid = _need_id(first_module.get("id"), "first_module.id")
    _check_fields(project, {"name": str, "description": str}, "project")
    _check_fields(first_module, {"name": str, "description": str}, "first_module")
    if pid == mid:
        raise ContentOpError(f"project và module đầu không được cùng id '{pid}'")
    new = copy.deepcopy(content)
    _check_free(new, pid, "id project")
    _check_free(new, mid, "id module", extra={pid})
    module = {
        "id": mid,
        "name": first_module["name"],
        "description": first_module["description"],
        "files": copy.deepcopy(first_module.get("files", [])),
        "modules": copy.deepcopy(first_module.get("modules", [])),
    }
    theme = {
        "id": pid,
        "name": project["name"],
        "description": project["description"],
        "tags": copy.deepcopy(project.get("tags", [])),
        "diagram": copy.deepcopy(project.get("diagram", {"classes": [], "relations": []})),
        "topics": [module],
    }
    new["themes"].append(theme)
    return new


_PROJECT_EDITABLE = {"name", "description", "tags", "diagram"}


def update_project(content: dict, project_id: str, changes: dict) -> dict:
    _check_changes(changes, _PROJECT_EDITABLE, "project")
    new = copy.deepcopy(content)
    _find_theme(new, project_id).update(copy.deepcopy(changes))
    return new


def create_module(content: dict, project_id: str, module: dict, parent_module_id: str | None = None) -> dict:
    _need_dict(module, "module")
    mid = _need_id(module.get("id"), "module.id")
    _check_fields(module, {"name": str, "description": str}, "module")
    new = copy.deepcopy(content)
    th = _find_theme(new, project_id)
    _check_free(new, mid, "id module")
    entry = {
        "id": mid,
        "name": module["name"],
        "description": module["description"],
        "files": copy.deepcopy(module.get("files", [])),
        "modules": copy.deepcopy(module.get("modules", [])),
    }
    if parent_module_id is None:
        th["topics"].append(entry)
        return new
    for tp in _walk(th["topics"]):
        if tp["id"] == parent_module_id:
            tp["modules"].append(entry)
            return new
    # phân biệt "không tồn tại" và "thuộc project khác"
    try:
        _find_module(new, parent_module_id)
    except ContentOpError:
        raise ContentOpError(f"Không tìm thấy module cha '{parent_module_id}'") from None
    raise ContentOpError(f"Module cha '{parent_module_id}' không thuộc project '{project_id}'")


def update_module(content: dict, module_id: str, changes: dict) -> dict:
    _check_changes(changes, {"name", "description"}, "module")
    new = copy.deepcopy(content)
    _find_module(new, module_id)[1].update(copy.deepcopy(changes))
    return new


def create_file(content: dict, module_id: str, file: dict) -> dict:
    _need_dict(file, "file")
    fid = _need_id(file.get("id"), "file.id")
    _check_fields(file, {"name": str}, "file")
    eids = _need_list(file.get("exercise_ids", []), "file.exercise_ids")
    new = copy.deepcopy(content)
    _, tp = _find_module(new, module_id)
    _check_free(new, fid, "id file")
    _check_exercise_ids(new, eids)
    tp["files"].append({"id": fid, "name": file["name"], "exercise_ids": list(eids)})
    return new


def _check_exercise_ids(content: dict, eids: list) -> None:
    for e in eids:
        _need_id(e, "exercise_ids[]")
        if e not in content.get("exercises", {}):
            raise ContentOpError(f"Bài '{e}' không tồn tại trong exercises")


def update_file(content: dict, file_id: str, changes: dict) -> dict:
    _check_changes(changes, {"name", "exercise_ids"}, "file")
    if "name" in changes:
        _need_str(changes["name"], "name")
    if "exercise_ids" in changes:
        _need_list(changes["exercise_ids"], "exercise_ids")
    new = copy.deepcopy(content)
    f = _find_file(new, file_id)
    if "exercise_ids" in changes:
        _check_exercise_ids(new, changes["exercise_ids"])
    f.update(copy.deepcopy(changes))
    return new
