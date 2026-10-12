"""Hàng chờ duyệt (app.review): diff theo mục, draft = live ⊕ pending, approve/reject từng mục."""

from __future__ import annotations

import copy

import pytest

from app import review
from app.content_api import read_content
from app.export_content import admin_version, export_content
from app.load_content import load_content
from app.review import (
    DependencyMissing,
    InvalidResult,
    ItemConflict,
    NotPending,
    VersionConflict,
    apply_change,
    diff,
    merge_pending,
)
from app.tables import ContentChange

AUTHOR = "admin@test"


def _content(data: dict) -> dict:
    return {"themes": copy.deepcopy(data["themes"]), "exercises": copy.deepcopy(data["exercises"])}


def _clone_exercise(ex: dict, new_id: str) -> dict:
    out = copy.deepcopy(ex)
    out["id"] = new_id
    for b in out["blocks"]:
        b["id"] = f"{new_id}-{b['label'].lower()}"
    return out


def _file(c: dict, file_id: str) -> dict:
    for theme in c["themes"]:
        for mod, _, _, _ in review._walk_modules(theme["topics"], theme["id"], None):
            for f in mod["files"]:
                if f["id"] == file_id:
                    return f
    raise KeyError(file_id)


def _module(c: dict, module_id: str) -> dict:
    for theme in c["themes"]:
        for mod, _, _, _ in review._walk_modules(theme["topics"], theme["id"], None):
            if mod["id"] == module_id:
                return mod
    raise KeyError(module_id)


def _same(a: dict, b: dict) -> bool:
    return admin_version(a) == admin_version(b)


# --- Thuần: diff + merge ------------------------------------------------------------------------


def test_identical_content_has_no_changes(content_data):
    assert diff(_content(content_data), _content(content_data)) == []


def _mut_title(c):
    c["exercises"]["bank-deposit"]["title"] = "Nạp tiền (sửa)"


def _mut_new_exercise_first(c):
    c["exercises"]["bank-new"] = _clone_exercise(c["exercises"]["bank-deposit"], "bank-new")
    _file(c, "oop-bank-account")["exercise_ids"].insert(0, "bank-new")


def _mut_new_module_file_exercise(c):
    parent = _module(c, "oop")
    parent.setdefault("modules", []).append(
        {"id": "oop-new", "name": "Mới", "description": "", "files": [
            {"id": "oop-new-py", "name": "new.py", "exercise_ids": ["bank-new"]}], "modules": []}
    )
    c["exercises"]["bank-new"] = _clone_exercise(c["exercises"]["bank-deposit"], "bank-new")


def _mut_move_exercise(c):
    ids = _file(c, "oop-bank-account")["exercise_ids"]
    ids.insert(len(ids) - 1, ids.pop(0))


def _mut_delete_exercise(c):
    _file(c, "oop-bank-account")["exercise_ids"].remove("bank-display-info")
    del c["exercises"]["bank-display-info"]


def _mut_delete_module(c):
    c["themes"][0]["topics"].pop()


def _mut_reorder_themes(c):
    c["themes"].insert(0, c["themes"].pop())


def _mut_new_project(c):
    c["themes"].append({"id": "p-new", "name": "P", "description": "", "tags": [], "diagram": {"classes": [], "relations": []},
                        "topics": [{"id": "p-new-m", "name": "M", "description": "", "files": [], "modules": []}]})


MUTATIONS = [_mut_title, _mut_new_exercise_first, _mut_new_module_file_exercise, _mut_move_exercise,
             _mut_delete_exercise, _mut_delete_module, _mut_reorder_themes, _mut_new_project]


@pytest.mark.parametrize("mutate", MUTATIONS, ids=lambda f: f.__name__)
def test_draft_round_trip(content_data, mutate):
    """draft = live ⊕ diff(live, X) phải ra đúng X — nếu không, admin Lưu xong mở lại sẽ thấy khác."""
    live = _content(content_data)
    x = _content(content_data)
    mutate(x)
    changes = diff(live, x)
    assert changes
    assert _same(merge_pending(live, changes), x)


def test_insert_at_file_start_is_one_change(content_data):
    """Chèn bài vào đầu file không biến mọi bài phía sau thành "đã sửa"."""
    live, x = _content(content_data), _content(content_data)
    _mut_new_exercise_first(x)
    assert [(c["kind"], c["item_id"], c["action"]) for c in diff(live, x)] == [("exercise", "bank-new", "create")]


def test_new_module_file_exercise_are_separate_items(content_data):
    live, x = _content(content_data), _content(content_data)
    _mut_new_module_file_exercise(x)
    got = {(c["kind"], c["item_id"], c["action"]) for c in diff(live, x)}
    assert got == {("module", "oop-new", "create"), ("file", "oop-new-py", "create"), ("exercise", "bank-new", "create")}


def test_exercise_before_its_new_file_needs_dependency(content_data):
    live, x = _content(content_data), _content(content_data)
    _mut_new_module_file_exercise(x)
    by_key = {(c["kind"], c["item_id"]): c for c in diff(live, x)}
    ex = by_key[("exercise", "bank-new")]
    with pytest.raises(DependencyMissing) as e:
        apply_change(live, "exercise", "bank-new", "create", ex["after"])
    assert "oop-new-py" in e.value.message
    f = by_key[("file", "oop-new-py")]
    with pytest.raises(DependencyMissing) as e:
        apply_change(live, "file", "oop-new-py", "create", f["after"])
    assert "oop-new" in e.value.message


def test_apply_single_exercise_lands_in_place(content_data):
    live, x = _content(content_data), _content(content_data)
    _mut_new_exercise_first(x)
    (ch,) = diff(live, x)
    out = apply_change(live, ch["kind"], ch["item_id"], ch["action"], ch["after"])
    assert _file(out, "oop-bank-account")["exercise_ids"][0] == "bank-new"
    assert _same(out, x)


# --- DB: submit / approve / reject ------------------------------------------------------------------


def _draft_version(session):
    return review.draft_version(session)


def _submit(session, mutate):
    live = export_content(session)
    x = _content(live)
    mutate(x)
    return review.submit(session, _draft_version(session), x, AUTHOR), x


def test_submit_does_not_touch_live(loaded_session):
    public_before = read_content(loaded_session)
    live_before = export_content(loaded_session)
    result, x = _submit(loaded_session, _mut_title)
    assert result["pending"] == 1
    assert read_content(loaded_session) == public_before
    assert export_content(loaded_session) == live_before
    # draft (thứ admin GET thấy) có sửa; version admin = hash(draft), KHÁC hash(live)
    draft = review.draft_content(loaded_session)
    assert draft["exercises"]["bank-deposit"]["title"] == "Nạp tiền (sửa)"
    assert result["version"] == admin_version(draft) != admin_version(live_before)


def test_submit_stale_version_conflicts(loaded_session):
    _submit(loaded_session, _mut_title)
    x = _content(export_content(loaded_session))
    with pytest.raises(VersionConflict):
        review.submit(loaded_session, admin_version(export_content(loaded_session)), x, AUTHOR)


def test_resubmit_reverted_item_drops_pending(loaded_session):
    _submit(loaded_session, _mut_title)
    live = export_content(loaded_session)
    review.submit(loaded_session, _draft_version(loaded_session), _content(live), AUTHOR)
    assert review.pending_rows(loaded_session) == []


def test_resubmit_same_item_updates_one_row(loaded_session):
    _submit(loaded_session, _mut_title)
    draft = review.draft_content(loaded_session)
    draft["exercises"]["bank-deposit"]["title"] = "Lần 2"
    review.submit(loaded_session, _draft_version(loaded_session), draft, AUTHOR)
    (row,) = review.pending_rows(loaded_session)
    assert row.after["fields"]["title"] == "Lần 2"


def test_approve_writes_live_and_keeps_draft(loaded_session):
    _submit(loaded_session, _mut_title)
    draft_before = review.draft_content(loaded_session)
    (row,) = review.pending_rows(loaded_session)
    review.approve(loaded_session, row.id, "boss")
    assert export_content(loaded_session)["exercises"]["bank-deposit"]["title"] == "Nạp tiền (sửa)"
    assert row.status == "approved" and row.decided_by == "boss"
    assert _same(review.draft_content(loaded_session), draft_before)


def test_approve_per_item_with_dependencies(loaded_session):
    _submit(loaded_session, _mut_new_module_file_exercise)
    rows = {r.kind: r for r in review.pending_rows(loaded_session)}
    with pytest.raises(DependencyMissing):
        review.approve(loaded_session, rows["exercise"].id, "boss")
    review.approve(loaded_session, rows["module"].id, "boss")
    review.approve(loaded_session, rows["file"].id, "boss")
    assert "bank-new" not in read_content(loaded_session)["exercises"]  # chưa duyệt bài → học viên chưa thấy
    review.approve(loaded_session, rows["exercise"].id, "boss")
    public = read_content(loaded_session)
    assert "bank-new" in public["exercises"]
    assert _file(public, "oop-new-py")["exercise_ids"] == ["bank-new"]


def test_approve_conflict_when_live_changed(loaded_session):
    _submit(loaded_session, _mut_title)
    (row,) = review.pending_rows(loaded_session)
    live = export_content(loaded_session)
    live["exercises"]["bank-deposit"]["title"] = "Ai đó nạp lại bằng CLI"
    load_content(loaded_session, live)
    with pytest.raises(ItemConflict):
        review.approve(loaded_session, row.id, "boss")
    assert export_content(loaded_session)["exercises"]["bank-deposit"]["title"] == "Ai đó nạp lại bằng CLI"
    assert row.status == "pending"


def test_approve_create_conflict_when_id_exists(loaded_session):
    _submit(loaded_session, _mut_new_exercise_first)
    (row,) = review.pending_rows(loaded_session)
    live = export_content(loaded_session)
    live["exercises"]["bank-new"] = _clone_exercise(live["exercises"]["bank-deposit"], "bank-new")
    load_content(loaded_session, live)
    with pytest.raises(ItemConflict):
        review.approve(loaded_session, row.id, "boss")


def test_approve_invalid_result_leaves_live(loaded_session):
    """Bài sửa hợp lệ trong draft, nhưng mục nó cần (sơ đồ project) chưa duyệt → áp riêng thì vi phạm luật."""
    def mutate(c):
        ex = c["exercises"]["bank-deposit"]
        ex["template"] = ex["template"].replace("def deposit(", "def deposit_money(")
        ex["judge"]["solution"] = ex["judge"]["solution"].replace("def deposit(", "def deposit_money(")
        ex["function_name"] = "deposit_money"
    live_before = export_content(loaded_session)
    _submit(loaded_session, mutate)
    (row,) = review.pending_rows(loaded_session)
    with pytest.raises(InvalidResult) as e:
        review.approve(loaded_session, row.id, "boss")
    assert e.value.errors
    assert export_content(loaded_session) == live_before


def test_reject_returns_item_to_live(loaded_session):
    _submit(loaded_session, _mut_title)
    (row,) = review.pending_rows(loaded_session)
    review.reject(loaded_session, row.id, "boss")
    assert row.status == "rejected"
    assert _same(review.draft_content(loaded_session), export_content(loaded_session))
    with pytest.raises(NotPending):
        review.approve(loaded_session, row.id, "boss")


def test_pending_unique_per_item(loaded_session):
    loaded_session.add(ContentChange(kind="exercise", item_id="x", action="delete", status="pending", author="a"))
    loaded_session.flush()
    loaded_session.add(ContentChange(kind="exercise", item_id="x", action="delete", status="pending", author="b"))
    with pytest.raises(Exception):
        loaded_session.flush()


def test_new_project_approves_with_its_first_modules(loaded_session):
    _submit(loaded_session, _mut_new_project)
    rows = {r.kind: r for r in review.pending_rows(loaded_session)}
    assert set(rows) == {"project", "module"}
    result = review.approve(loaded_session, rows["project"].id, "boss")
    assert result["also"] == [rows["module"].id]
    assert review.pending_rows(loaded_session) == []
    assert "p-new" in [t["id"] for t in read_content(loaded_session)["themes"]]


# --- Sửa sau review: thứ tự đầy đủ, xoá cha, bỏ cha, version ---------------------------------------

import itertools  # noqa: E402


@pytest.mark.parametrize("perm", list(itertools.permutations(range(5))))
def test_any_theme_permutation_round_trips(content_data, perm):
    live, x = _content(content_data), _content(content_data)
    x["themes"] = [x["themes"][i] for i in perm]
    assert _same(merge_pending(live, diff(live, x)), x)


def test_reverse_exercises_and_insert_round_trips(content_data):
    live, x = _content(content_data), _content(content_data)
    ids = _file(x, "oop-bank-account")["exercise_ids"]
    ids.reverse()
    x["exercises"]["bank-new"] = _clone_exercise(x["exercises"]["bank-deposit"], "bank-new")
    ids.insert(3, "bank-new")
    changes = diff(live, x)
    assert _same(merge_pending(live, changes), x)
    assert _same(merge_pending(live, list(reversed(changes))), x)  # thứ tự áp không quan trọng


def test_submit_version_equals_get_version_after_reorder(loaded_session):
    def rev(c):
        c["themes"].reverse()
        _file(c, "oop-bank-account")["exercise_ids"].reverse()
    result, x = _submit(loaded_session, rev)
    assert result["version"] == review.draft_version(loaded_session) == admin_version(x)
    # gửi lại đúng draft đang thấy (không sửa gì) → không đổi hàng chờ
    n = len(review.pending_rows(loaded_session))
    again = review.submit(loaded_session, result["version"], review.draft_content(loaded_session), AUTHOR)
    assert again["version"] == result["version"] and len(review.pending_rows(loaded_session)) == n


def test_approving_all_reordered_items_reaches_draft(loaded_session):
    def rev(c):
        _file(c, "oop-bank-account")["exercise_ids"].reverse()
    _, x = _submit(loaded_session, rev)
    for row in review.pending_rows(loaded_session):
        review.approve(loaded_session, row.id, "boss")
    assert _same(export_content(loaded_session), x)


def _delete_module_with_content(c):
    """Xoá module doc-storage (1 file, bài chỉ nằm ở đó) cùng bài của nó — nội dung sau vẫn hợp lệ."""
    theme = next(t for t in c["themes"] if t["id"] == "doc-system")
    mod = next(t for t in theme["topics"] if t["id"] == "doc-storage")
    theme["topics"].remove(mod)
    for f in mod["files"]:
        for eid in f["exercise_ids"]:
            del c["exercises"][eid]


def test_delete_module_bundles_its_deleted_exercises(loaded_session):
    """Bài trong module đều có mục XOÁ đang chờ (admin chủ động xoá) → duyệt xoá module kéo theo bài + file."""
    _, x = _submit(loaded_session, _delete_module_with_content)
    rows = {(r.kind, r.item_id): r for r in review.pending_rows(loaded_session)}
    result = review.approve(loaded_session, rows[("module", "doc-storage")].id, "boss")
    assert len(result["also"]) == len(rows) - 1
    assert _same(export_content(loaded_session), x)


def test_delete_module_after_exercises_takes_its_files(loaded_session):
    _, x = _submit(loaded_session, _delete_module_with_content)
    rows = review.pending_rows(loaded_session)
    for r in rows:
        if r.kind == "exercise":
            review.approve(loaded_session, r.id, "boss")
    mod = next(r for r in rows if (r.kind, r.item_id) == ("module", "doc-storage"))
    result = review.approve(loaded_session, mod.id, "boss")  # kéo theo file của nó
    assert len(result["also"]) == 1
    assert review.pending_rows(loaded_session) == []
    assert _same(export_content(loaded_session), x)


def test_reject_parent_also_rejects_stranded_children(loaded_session):
    _submit(loaded_session, _mut_new_module_file_exercise)
    rows = {r.kind: r for r in review.pending_rows(loaded_session)}
    result = review.reject(loaded_session, rows["file"].id, "boss")
    assert result["also"] == [rows["exercise"].id]
    assert rows["exercise"].status == "rejected" and rows["module"].status == "pending"


def test_delete_module_whose_file_moves_needs_move_first(loaded_session):
    """File được chuyển sang module khác (không bị xoá): xoá module cũ trước khi duyệt việc chuyển → từ chối,
    không để file biến mất ngầm theo cha."""
    def mutate(c):
        theme = next(t for t in c["themes"] if t["id"] == "doc-system")
        storage = next(t for t in theme["topics"] if t["id"] == "doc-storage")
        theme["topics"].remove(storage)
        theme["topics"][0]["files"].extend(storage["files"])
    _, x = _submit(loaded_session, mutate)
    rows = {(r.kind, r.item_id): r for r in review.pending_rows(loaded_session)}
    with pytest.raises(DependencyMissing):
        review.approve(loaded_session, rows[("module", "doc-storage")].id, "boss")
    for key, r in rows.items():
        if key[0] == "file":
            review.approve(loaded_session, r.id, "boss")
    review.approve(loaded_session, rows[("module", "doc-storage")].id, "boss")
    assert _same(export_content(loaded_session), x)


def _delete_python_fundamentals(c):
    theme = next(t for t in c["themes"] if t["id"] == "python-fundamentals")
    c["themes"].remove(theme)
    for f in theme["topics"][0]["files"]:
        for eid in f["exercise_ids"]:
            del c["exercises"][eid]


def test_delete_whole_project_with_diagram_approves_in_one_step(loaded_session):
    """Xoá riêng bài cuối của project vi phạm luật sơ đồ khi project còn → duyệt xoá project kéo theo các
    mục xoá bài + file + module của nó, kiểm luật một lần."""
    _, x = _submit(loaded_session, _delete_python_fundamentals)
    rows = review.pending_rows(loaded_session)
    project = next(r for r in rows if r.kind == "project")
    result = review.approve(loaded_session, project.id, "boss")
    assert len(result["also"]) == len(rows) - 1
    assert review.pending_rows(loaded_session) == []
    assert _same(export_content(loaded_session), x)


def test_reject_only_module_of_new_project_rejects_project(loaded_session):
    _submit(loaded_session, _mut_new_project)
    rows = {r.kind: r for r in review.pending_rows(loaded_session)}
    result = review.reject(loaded_session, rows["module"].id, "boss")
    assert result["also"] == [rows["project"].id]
    assert review.pending_rows(loaded_session) == []



def _reparent_reverse(c):
    tp = c["themes"][0]["topics"]
    parent = tp[0]
    child = parent["modules"].pop(0)
    tp[0] = child
    child.setdefault("modules", []).append(parent)


def _move_module_to_new_project(c):
    theme = next(t for t in c["themes"] if t["id"] == "doc-system")
    mod = next(t for t in theme["topics"] if t["id"] == "doc-storage")
    theme["topics"].remove(mod)
    c["themes"].append({"id": "np", "name": "N", "description": "", "tags": [],
                        "diagram": {"classes": [], "relations": []}, "topics": [mod]})


@pytest.mark.parametrize("mutate", [_reparent_reverse, _move_module_to_new_project], ids=lambda f: f.__name__)
def test_moving_existing_module_to_other_parent_is_refused(loaded_session, mutate):
    """Đổi cha của module có sẵn chưa duyệt từng mục an toàn được (phụ thuộc vòng) → chặn ở đầu vào."""
    x = _content(export_content(loaded_session))
    mutate(x)
    with pytest.raises(review.UnsupportedMove):
        review.submit(loaded_session, review.draft_version(loaded_session), x, AUTHOR)
    assert review.pending_rows(loaded_session) == []
