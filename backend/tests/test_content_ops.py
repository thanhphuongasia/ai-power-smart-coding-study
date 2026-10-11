"""Test `app.content_ops` — thuần dict, không DB. Dữ liệu: content.json thật."""

import copy
import json
from pathlib import Path

import pytest

from app import content_ops as ops
from app.content_ops import ContentOpError
from app.load_content import validation_errors

CONTENT = json.loads((Path(__file__).resolve().parent.parent / "content" / "content.json").read_text("utf-8"))


@pytest.fixture
def content():
    return copy.deepcopy(CONTENT)


def _ids(c):
    th = c["themes"][0]
    tp = th["topics"][0]
    f = tp["files"][0]
    return th["id"], tp["id"], f["id"], f["exercise_ids"][0]


def _new_lesson(c, new_id="zz-new-lesson", src=None):
    src = src or _ids(c)[3]
    ex = copy.deepcopy(c["exercises"][src])
    ex["id"] = new_id
    for b in ex["blocks"]:
        b["id"] = f"{new_id}-{b['label'].lower()}"
    return ex


def _ok(result):
    assert validation_errors(result) == []


def _frozen(c, fn, *a, **kw):
    before = copy.deepcopy(c)
    out = fn(c, *a, **kw)
    assert c == before, "input bị mutate"
    assert out is not c
    return out


def test_baseline_valid():
    _ok(CONTENT)


# ---- đọc ----


def test_list_projects(content):
    res = ops.list_projects(content)
    assert [p["id"] for p in res] == [t["id"] for t in content["themes"]]
    p = res[0]
    assert set(p) == {"id", "name", "description", "tags", "module_count", "file_count", "lesson_count"}
    th = content["themes"][0]

    def walk(ts):
        for t in ts:
            yield t
            yield from walk(t["modules"])

    mods = list(walk(th["topics"]))
    assert p["module_count"] == len(mods)
    assert p["file_count"] == sum(len(m["files"]) for m in mods)
    assert p["lesson_count"] == len({e for m in mods for f in m["files"] for e in f["exercise_ids"]})


def test_project_tree(content):
    pid, mid, fid, eid = _ids(content)
    tree = ops.project_tree(content, pid)
    assert tree["diagram"] == content["themes"][0]["diagram"]
    m = tree["modules"][0]
    assert m["id"] == mid and "modules" in m
    f = m["files"][0]
    assert f["id"] == fid
    les = f["lessons"][0]
    ex = content["exercises"][eid]
    assert les == {"id": eid, "title": ex["title"], "class_name": ex["class_name"], "function_name": ex["function_name"]}
    with pytest.raises(ContentOpError):
        ops.project_tree(content, "nope")


def test_get_lesson(content):
    pid, mid, fid, eid = _ids(content)
    les = ops.get_lesson(content, eid)
    assert les["judge"] == content["exercises"][eid]["judge"]
    assert {"project_id": pid, "module_id": mid, "file_id": fid} in les["locations"]
    with pytest.raises(ContentOpError):
        ops.get_lesson(content, "nope")


def test_get_lesson_multiple_locations(content):
    pid, mid, fid, eid = _ids(content)
    other = content["themes"][0]["topics"][0]["files"]
    c = ops.create_file(content, mid, {"id": "zz-f2", "name": "f2", "exercise_ids": [eid]})
    assert len(ops.get_lesson(c, eid)["locations"]) == 2


# ---- create_lesson / update_lesson ----


def test_create_lesson(content):
    _, _, fid, _ = _ids(content)
    lesson = _new_lesson(content)
    out = _frozen(content, ops.create_lesson, fid, lesson)
    _ok(out)
    assert out["exercises"]["zz-new-lesson"] == lesson
    f = next(f for t in out["themes"] for tp in t["topics"] for f in tp["files"] if f["id"] == fid)
    assert f["exercise_ids"][-1] == "zz-new-lesson"
    # phần ngoài phạm vi không đổi
    assert {k: v for k, v in out["exercises"].items() if k != "zz-new-lesson"} == content["exercises"]


def test_create_lesson_dup_ids(content):
    pid, mid, fid, eid = _ids(content)
    for dup in (eid, pid, mid, fid, content["exercises"][eid]["blocks"][0]["id"]):
        with pytest.raises(ContentOpError):
            ops.create_lesson(content, fid, _new_lesson(content, dup))
    # id ô trùng id loại khác
    les = _new_lesson(content)
    les["blocks"][0]["id"] = mid
    with pytest.raises(ContentOpError):
        ops.create_lesson(content, fid, les)
    # id ô trùng chính id bài
    les = _new_lesson(content)
    les["blocks"][0]["id"] = les["id"]
    with pytest.raises(ContentOpError):
        ops.create_lesson(content, fid, les)


def test_create_lesson_bad(content):
    _, _, fid, _ = _ids(content)
    with pytest.raises(ContentOpError):
        ops.create_lesson(content, "nope", _new_lesson(content))
    with pytest.raises(ContentOpError):
        ops.create_lesson(content, fid, "x")
    with pytest.raises(ContentOpError):
        ops.create_lesson(content, fid, {"title": "no id"})
    with pytest.raises(ContentOpError):
        ops.create_lesson(content, fid, {**_new_lesson(content), "id": ""})


def test_update_lesson(content):
    _, _, _, eid = _ids(content)
    out = _frozen(content, ops.update_lesson, eid, {"title": "Tiêu đề mới"})
    _ok(out)
    assert out["exercises"][eid]["title"] == "Tiêu đề mới"
    old = {k: v for k, v in content["exercises"][eid].items() if k != "title"}
    assert {k: v for k, v in out["exercises"][eid].items() if k != "title"} == old
    assert out["themes"] == content["themes"]
    assert {k: v for k, v in out["exercises"].items() if k != eid} == {k: v for k, v in content["exercises"].items() if k != eid}


def test_update_lesson_judge_shallow(content):
    _, _, _, eid = _ids(content)
    judge = copy.deepcopy(content["exercises"][eid]["judge"])
    out = ops.update_lesson(content, eid, {"judge": judge})
    _ok(out)


def test_update_lesson_errors(content):
    pid, mid, fid, eid = _ids(content)
    with pytest.raises(ContentOpError):
        ops.update_lesson(content, eid, {"id": "other"})
    with pytest.raises(ContentOpError):
        ops.update_lesson(content, "nope", {"title": "x"})
    blocks = copy.deepcopy(content["exercises"][eid]["blocks"])
    blocks[0]["id"] = mid
    with pytest.raises(ContentOpError):
        ops.update_lesson(content, eid, {"blocks": blocks})
    # giữ nguyên id ô cũ thì được
    ops.update_lesson(content, eid, {"blocks": copy.deepcopy(content["exercises"][eid]["blocks"])})


def test_update_lesson_keeps_files(content):
    _, _, fid, eid = _ids(content)
    out = ops.update_lesson(content, eid, {"title": "t"})
    assert out["themes"] == content["themes"]


# ---- project ----


def _project(pid="zz-proj"):
    return (
        {"id": pid, "name": "P", "description": "d"},
        {"id": pid + "-m1", "name": "M", "description": "d"},
    )


def test_create_project(content):
    p, m = _project()
    out = _frozen(content, ops.create_project, p, m)
    _ok(out)
    th = out["themes"][-1]
    assert th["id"] == "zz-proj" and th["tags"] == [] and th["diagram"] == {"classes": [], "relations": []}
    assert th["topics"] == [{"id": "zz-proj-m1", "name": "M", "description": "d", "files": [], "modules": []}]
    assert out["themes"][:-1] == content["themes"]
    assert out["exercises"] == content["exercises"]


def test_create_project_errors(content):
    pid, mid, fid, eid = _ids(content)
    p, m = _project()
    for dup in (pid, mid, fid, eid):
        with pytest.raises(ContentOpError):
            ops.create_project(content, {**p, "id": dup}, m)
        with pytest.raises(ContentOpError):
            ops.create_project(content, p, {**m, "id": dup})
    with pytest.raises(ContentOpError):
        ops.create_project(content, p, {**m, "id": p["id"]})
    with pytest.raises(ContentOpError):
        ops.create_project(content, {"id": "x"}, m)


def test_update_project(content):
    pid = _ids(content)[0]
    out = _frozen(content, ops.update_project, pid, {"name": "Tên mới", "tags": ["a"]})
    _ok(out)
    th = out["themes"][0]
    assert th["name"] == "Tên mới" and th["tags"] == ["a"]
    assert th["description"] == content["themes"][0]["description"]
    assert th["topics"] == content["themes"][0]["topics"]
    for bad in ({"id": "x"}, {"topics": []}):
        with pytest.raises(ContentOpError):
            ops.update_project(content, pid, bad)
    with pytest.raises(ContentOpError):
        ops.update_project(content, "nope", {"name": "x"})


# ---- module ----


def test_create_module_top_and_nested(content):
    pid, mid, _, _ = _ids(content)
    top = _frozen(content, ops.create_module, pid, {"id": "zz-m", "name": "n", "description": "d"})
    _ok(top)
    assert top["themes"][0]["topics"][-1]["id"] == "zz-m"
    nested = _frozen(content, ops.create_module, pid, {"id": "zz-sub", "name": "n", "description": "d"}, mid)
    _ok(nested)
    parent = nested["themes"][0]["topics"][0]
    assert parent["modules"][-1] == {"id": "zz-sub", "name": "n", "description": "d", "files": [], "modules": []}
    assert len(nested["themes"][0]["topics"]) == len(content["themes"][0]["topics"])
    # lồng sâu 2 tầng
    deep = ops.create_module(nested, pid, {"id": "zz-sub2", "name": "n", "description": "d"}, "zz-sub")
    _ok(deep)


def test_create_module_errors(content):
    pid, mid, fid, eid = _ids(content)
    m = {"id": "zz-m", "name": "n", "description": "d"}
    for dup in (pid, mid, fid, eid):
        with pytest.raises(ContentOpError):
            ops.create_module(content, pid, {**m, "id": dup})
    with pytest.raises(ContentOpError):
        ops.create_module(content, "nope", m)
    with pytest.raises(ContentOpError):
        ops.create_module(content, pid, m, "nope")


def test_create_module_parent_other_project(content):
    p, m1 = _project()
    c = ops.create_project(content, p, m1)
    with pytest.raises(ContentOpError, match="không thuộc project"):
        ops.create_module(c, _ids(content)[0], {"id": "zz-m", "name": "n", "description": "d"}, m1["id"])


def test_update_module(content):
    mid = _ids(content)[1]
    out = _frozen(content, ops.update_module, mid, {"name": "mới"})
    _ok(out)
    tp = out["themes"][0]["topics"][0]
    old = content["themes"][0]["topics"][0]
    assert tp["name"] == "mới" and tp["description"] == old["description"] and tp["files"] == old["files"]
    with pytest.raises(ContentOpError):
        ops.update_module(content, mid, {"files": []})
    with pytest.raises(ContentOpError):
        ops.update_module(content, "nope", {"name": "x"})


# ---- file ----


def test_create_file(content):
    _, mid, _, eid = _ids(content)
    out = _frozen(content, ops.create_file, mid, {"id": "zz-f", "name": "f.py"})
    _ok(out)
    assert out["themes"][0]["topics"][0]["files"][-1] == {"id": "zz-f", "name": "f.py", "exercise_ids": []}
    out2 = ops.create_file(content, mid, {"id": "zz-f", "name": "f.py", "exercise_ids": [eid]})
    _ok(out2)


def test_create_file_errors(content):
    pid, mid, fid, eid = _ids(content)
    for dup in (pid, mid, fid, eid):
        with pytest.raises(ContentOpError):
            ops.create_file(content, mid, {"id": dup, "name": "f"})
    with pytest.raises(ContentOpError):
        ops.create_file(content, "nope", {"id": "zz-f", "name": "f"})
    with pytest.raises(ContentOpError):
        ops.create_file(content, mid, {"id": "zz-f", "name": "f", "exercise_ids": ["nope"]})


def test_update_file(content):
    _, _, fid, _ = _ids(content)
    f0 = content["themes"][0]["topics"][0]["files"][0]
    rev = list(reversed(f0["exercise_ids"]))
    out = _frozen(content, ops.update_file, fid, {"exercise_ids": rev})
    _ok(out)
    f = out["themes"][0]["topics"][0]["files"][0]
    assert f["exercise_ids"] == rev and f["name"] == f0["name"]
    out = ops.update_file(content, fid, {"name": "mới.py"})
    _ok(out)
    assert out["themes"][0]["topics"][0]["files"][0]["exercise_ids"] == f0["exercise_ids"]


def test_update_file_errors(content):
    _, _, fid, _ = _ids(content)
    with pytest.raises(ContentOpError):
        ops.update_file(content, fid, {"id": "x"})
    with pytest.raises(ContentOpError):
        ops.update_file(content, fid, {"exercise_ids": ["nope"]})
    with pytest.raises(ContentOpError):
        ops.update_file(content, "nope", {"name": "x"})
