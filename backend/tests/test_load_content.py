"""Nạp content.json vào Postgres (INV-06) + judge.solution khớp exercises.json (INV-04)."""

from __future__ import annotations

import copy
import json
import os

import pytest
from sqlalchemy import func, select

from app.load_content import load_content, public_payload
from app.tables import Block, CodeFile, ContentMeta, Exercise, FileExercise, Theme, Topic

BACKEND_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONTENT_PATH = os.path.join(BACKEND_DIR, "content", "content.json")


@pytest.fixture(scope="module")
def real_data() -> dict:
    with open(CONTENT_PATH, encoding="utf-8") as fh:
        return json.load(fh)


def count(session, model) -> int:
    return session.scalar(select(func.count()).select_from(model))


def small() -> dict:
    def block(i: str, label: str) -> dict:
        return {
            "id": i, "label": label, "title": "t", "prompt": "p", "indent_level": 1,
            "accepted_answers": ["x"], "expected_output": "o", "explanation": "e",
            "hints": ["h"], "vocab": [],
        }

    def ex(i: str) -> dict:
        return {
            "id": i, "title": i, "class_name": None, "function_name": "f", "params": ["a"], "template": "def f(a):\n    # TODO A",
            "challenge": {
                "statement": "s", "motivation": "m",
                "small": {"caption": "c", "input": "f(1)", "output": "1", "note": None},
                "project": {"caption": "c", "input": "f(2)", "output": "2", "note": "n"},
            },
            "blocks": [block(i + "-a", "A"), block(i + "-b", "B")],
            "judge": {"solution": "def f(a):\n    return a", "cases": [{"args": [1], "expect": {"return": 1}}]},
        }

    return {
        "version": "source",
        "themes": [{"id": "th", "name": "T", "description": "d", "tags": ["x"], "topics": [
            {"id": "tp", "name": "N", "description": "d", "modules": [], "files": [
                {"id": "f1", "name": "a.py", "exercise_ids": ["e1", "e2"]},
                {"id": "f2", "name": "b.py", "exercise_ids": ["e2"]},
            ]}]}],
        "exercises": {"e1": ex("e1"), "e2": ex("e2")},
    }


def test_load_real_file(db_session, real_data):
    version = load_content(db_session, real_data)
    assert version.startswith("sha256:")
    assert count(db_session, Theme) == 4
    assert count(db_session, Exercise) == 13
    assert db_session.scalar(select(func.count()).select_from(FileExercise).where(FileExercise.exercise_id == "split-chunks")) == 2
    assert db_session.get(ContentMeta, "version").value == version
    assert count(db_session, Block) == sum(len(e["blocks"]) for e in real_data["exercises"].values())


def test_load_twice_same_version_and_rows(db_session, real_data):
    v1 = load_content(db_session, real_data)
    rows1 = [count(db_session, m) for m in (Theme, Topic, CodeFile, Exercise, FileExercise, Block, ContentMeta)]
    v2 = load_content(db_session, copy.deepcopy(real_data))
    rows2 = [count(db_session, m) for m in (Theme, Topic, CodeFile, Exercise, FileExercise, Block, ContentMeta)]
    assert v1 == v2
    assert rows1 == rows2


def test_version_ignores_judge_and_version_key():
    from app.load_content import compute_version

    a = small()
    b = small()
    b["version"] = "other"
    b["exercises"]["e1"]["judge"]["solution"] = "changed"
    assert compute_version(a) == compute_version(b)
    assert "judge" not in json.dumps(public_payload(a))
    b["exercises"]["e1"]["title"] = "new title"
    assert compute_version(a) != compute_version(b)


def test_position_order_kept(db_session):
    load_content(db_session, small())
    labels = db_session.scalars(select(Block.label).where(Block.exercise_id == "e1").order_by(Block.position)).all()
    assert labels == ["A", "B"]
    files = db_session.scalars(select(FileExercise.exercise_id).where(FileExercise.file_id == "f1").order_by(FileExercise.position)).all()
    assert files == ["e1", "e2"]


def nested() -> dict:
    """small() + cây module 3 tầng: tp → sub → leaf, và tp2 anh em; e2 là method của class."""
    d = small()
    d["themes"][0]["topics"][0]["modules"] = [
        {"id": "sub", "name": "S", "description": "d", "files": [
            {"id": "f3", "name": "svc.py", "exercise_ids": ["e2"]},
        ], "modules": [
            {"id": "leaf", "name": "L", "description": "d", "files": [], "modules": []},
        ]},
    ]
    d["themes"][0]["topics"].append({"id": "tp2", "name": "N2", "description": "d", "files": [], "modules": []})
    d["exercises"]["e2"]["class_name"] = "Svc"
    return d


def test_nested_modules_stored_preorder_with_parent(db_session):
    load_content(db_session, nested())
    rows = db_session.execute(select(Topic.id, Topic.parent_id).order_by(Topic.position)).all()
    assert [tuple(r) for r in rows] == [("tp", None), ("sub", "tp"), ("leaf", "sub"), ("tp2", None)]
    assert db_session.get(CodeFile, "f3").topic_id == "sub"
    assert db_session.get(Exercise, "e2").class_name == "Svc"
    assert db_session.get(Exercise, "e1").class_name is None


def test_sibling_order_kept_and_reload_replaces_tree(db_session):
    d = nested()
    sub = d["themes"][0]["topics"][0]["modules"][0]
    sub["modules"].append({"id": "leaf2", "name": "L2", "description": "d", "files": [], "modules": []})
    load_content(db_session, d)
    load_content(db_session, copy.deepcopy(d))  # nạp lại cùng id: không lỗi FK/unique
    order = db_session.scalars(select(Topic.id).order_by(Topic.position)).all()
    assert order == ["tp", "sub", "leaf", "leaf2", "tp2"]

    d2 = nested()
    d2["themes"][0]["topics"][0]["modules"] = []  # bỏ cả nhánh sub
    d2["exercises"]["e2"]["class_name"] = None
    load_content(db_session, d2)
    assert db_session.scalars(select(Topic.id).order_by(Topic.position)).all() == ["tp", "tp2"]
    assert db_session.get(CodeFile, "f3") is None


@pytest.mark.parametrize(
    "case, msg",
    [
        ({"steps": ["x = ("], "call": "x", "expect": {"return": 1}}, "compile"),
        ({"call": "1 +", "expect": {"return": 1}}, "compile"),
        ({"call": "1", "expect": {}}, "return"),
    ],
)
def test_scenario_case_checked_at_load(db_session, case, msg):
    """Lỗi soạn case kịch bản bị chặn lúc nạp, không để người học thấy như lỗi code của mình."""
    d = small()
    d["exercises"]["e1"]["judge"]["cases"] = [case]
    with pytest.raises(ValueError, match=msg):
        load_content(db_session, d)


def test_duplicate_module_id_across_levels_rejected(db_session):
    d = nested()
    d["themes"][0]["topics"][0]["modules"][0]["modules"][0]["id"] = "tp"
    with pytest.raises(ValueError, match="id topic trùng"):
        load_content(db_session, d)


@pytest.mark.parametrize("drop", ["modules", "class_name"])
def test_new_keys_are_required(db_session, drop):
    d = small()
    if drop == "modules":
        del d["themes"][0]["topics"][0]["modules"]
    else:
        del d["exercises"]["e1"]["class_name"]
    with pytest.raises(ValueError, match=drop):
        load_content(db_session, d)


def test_removed_exercise_disappears(db_session, real_data):
    load_content(db_session, real_data)
    data = copy.deepcopy(real_data)
    del data["exercises"]["like-post"]
    for th in data["themes"]:
        for tp in th["topics"]:
            for f in tp["files"]:
                f["exercise_ids"] = [i for i in f["exercise_ids"] if i != "like-post"]
    load_content(db_session, data)
    assert db_session.get(Exercise, "like-post") is None
    assert count(db_session, Exercise) == 12
    assert db_session.scalar(select(func.count()).select_from(Block).where(Block.exercise_id == "like-post")) == 0


def _bad_duplicate_id():
    d = small()
    d["themes"][0]["topics"][0]["files"][1]["id"] = "f1"
    return d


def _bad_unknown_exercise():
    d = small()
    d["themes"][0]["topics"][0]["files"][0]["exercise_ids"].append("nope")
    return d


def _bad_no_judge():
    d = small()
    del d["exercises"]["e1"]["judge"]
    return d


def _bad_no_cases():
    d = small()
    d["exercises"]["e1"]["judge"]["cases"] = []
    return d


def _bad_dup_label():
    d = small()
    d["exercises"]["e1"]["blocks"][1]["label"] = "A"
    return d


@pytest.mark.parametrize(
    "make,msg",
    [
        (_bad_duplicate_id, "trùng"),
        (_bad_unknown_exercise, "nope"),
        (_bad_no_judge, "exercises.e1.judge"),
        (_bad_no_cases, "judge.cases"),
        (_bad_dup_label, "label"),
    ],
)
def test_invalid_data_raises_and_keeps_db(db_session, real_data, make, msg):
    old = load_content(db_session, real_data)
    with pytest.raises(ValueError, match=msg):
        load_content(db_session, make())
    assert db_session.get(ContentMeta, "version").value == old
    assert count(db_session, Exercise) == 13
    assert count(db_session, Theme) == 4


def test_judge_solution_matches_legacy_exercises_json(real_data):
    legacy_path = os.path.join(BACKEND_DIR, "app", "exercises.json")
    if not os.path.exists(legacy_path):  # T-06 xoá file này; chỉ so khi còn
        pytest.skip("exercises.json đã bị xoá")
    with open(legacy_path, encoding="utf-8") as fh:
        legacy = json.load(fh)
    assert set(real_data["exercises"]) == set(legacy)
    for key, ex in real_data["exercises"].items():
        assert ex["judge"]["solution"] == legacy[key]["solution"], key
        assert ex["judge"]["cases"] == legacy[key]["cases"], key
        assert ex["function_name"] == legacy[key]["function"], key


def test_every_exercise_has_judge(real_data):
    for key, ex in real_data["exercises"].items():
        assert ex["judge"]["solution"], key
        assert ex["judge"]["cases"], key


# ---- Hình dạng (M1): sai shape bị chặn lúc nạp, DB giữ bản cũ ----

def _del_caption(d):
    del d["exercises"]["split-chunks"]["challenge"]["small"]["caption"]


def _indent_str(d):
    d["exercises"]["split-chunks"]["blocks"][0]["indent_level"] = "1"


def _indent_float(d):
    d["exercises"]["split-chunks"]["blocks"][0]["indent_level"] = 1.0


def _extra_block_key(d):
    d["exercises"]["split-chunks"]["blocks"][0]["extra_key"] = "x"


def _hints_not_str(d):
    d["exercises"]["split-chunks"]["blocks"][0]["hints"] = ["a", 2, "c"]


def _no_note_key(d):
    del d["exercises"]["split-chunks"]["challenge"]["project"]["note"]


@pytest.mark.parametrize(
    "mutate,path",
    [
        (_del_caption, "exercises.split-chunks.challenge.small.caption"),
        (_indent_str, "exercises.split-chunks.blocks.0.indent_level"),
        (_indent_float, "exercises.split-chunks.blocks.0.indent_level"),
        (_extra_block_key, "exercises.split-chunks.blocks.0.extra_key"),
        (_hints_not_str, "exercises.split-chunks.blocks.0.hints.1"),
        (_no_note_key, "exercises.split-chunks.challenge.project.note"),
    ],
)
def test_wrong_shape_raises_with_path_and_keeps_db(db_session, real_data, mutate, path):
    old = load_content(db_session, real_data)
    bad = copy.deepcopy(real_data)
    mutate(bad)
    with pytest.raises(ValueError) as err:
        load_content(db_session, bad)
    assert path in str(err.value)
    assert db_session.get(ContentMeta, "version").value == old
    assert count(db_session, Exercise) == 13
    assert count(db_session, Block) == sum(len(e["blocks"]) for e in real_data["exercises"].values())


def test_note_null_is_valid(db_session):
    d = small()
    assert d["exercises"]["e1"]["challenge"]["small"]["note"] is None
    load_content(db_session, d)
    assert count(db_session, Exercise) == 2


def test_public_payload_validates_against_shared_model(real_data):
    from app.content_schema import ContentPayload

    payload = {"version": "sha256:x", **public_payload(real_data)}
    assert ContentPayload.model_validate(payload).model_dump() == payload
