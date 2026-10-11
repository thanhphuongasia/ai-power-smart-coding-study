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
            "id": i, "title": i, "function_name": "f", "params": ["a"], "template": "def f(a):\n    # TODO A",
            "challenge": {"statement": "s"}, "blocks": [block(i + "-a", "A"), block(i + "-b", "B")],
            "judge": {"solution": "def f(a):\n    return a", "cases": [{"args": [1], "expect": {"return": 1}}]},
        }

    return {
        "version": "source",
        "themes": [{"id": "th", "name": "T", "description": "d", "tags": ["x"], "topics": [
            {"id": "tp", "name": "N", "description": "d", "files": [
                {"id": "f1", "name": "a.py", "exercise_ids": ["e1", "e2"]},
                {"id": "f2", "name": "b.py", "exercise_ids": ["e2"]},
            ]}]}],
        "exercises": {"e1": ex("e1"), "e2": ex("e2")},
    }


def test_load_real_file(db_session, real_data):
    version = load_content(db_session, real_data)
    assert version.startswith("sha256:")
    assert count(db_session, Theme) == 3
    assert count(db_session, Exercise) == 5
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
    assert count(db_session, Exercise) == 4
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
        (_bad_no_judge, "judge.solution"),
        (_bad_no_cases, "judge.cases"),
        (_bad_dup_label, "label"),
    ],
)
def test_invalid_data_raises_and_keeps_db(db_session, real_data, make, msg):
    old = load_content(db_session, real_data)
    with pytest.raises(ValueError, match=msg):
        load_content(db_session, make())
    assert db_session.get(ContentMeta, "version").value == old
    assert count(db_session, Exercise) == 5
    assert count(db_session, Theme) == 3


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
