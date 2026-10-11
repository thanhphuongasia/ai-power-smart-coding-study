"""Luật nội dung (app/content_rules.py) — port của content_contract_test.dart sang server.

Mỗi luật một đột biến (mutant) trên content.json thật: bản gốc phải sạch, bản đột biến phải bị bắt
đúng câu. Mutant không bị bắt = luật đó không thật sự chạy.
"""

from __future__ import annotations

import copy

import pytest

from app.content_rules import content_rule_errors, merge_cells, normalize_code
from app.load_content import validation_errors


def test_real_content_has_no_rule_errors(content_data):
    assert content_rule_errors(content_data) == []
    assert validation_errors(content_data) == []


def _ex(d, i="split-chunks"):
    return d["exercises"][i]


def _second_answer_three_lines(d):
    _ex(d)["blocks"][1]["accepted_answers"][0] = "a\nb\nc"


def _merged_differs(d):
    _ex(d)["judge"]["solution"] += "\n"  # chỉ thêm newline cuối: so từng ký tự, không trim


def _four_blocks(d):
    ex = _ex(d)
    ex["blocks"].append({**ex["blocks"][0], "id": "split-chunks-d", "label": "D"})


def _two_hints(d):
    _ex(d)["blocks"][0]["hints"].pop()


def _marker_indent_wrong(d):
    _ex(d)["blocks"][0]["indent_level"] = 3


def _marker_missing(d):
    ex = _ex(d)
    ex["template"] = ex["template"].replace("# TODO C", "pass")


def _block_id_wrong(d):
    _ex(d)["blocks"][0]["id"] = "split-chunks-x"


def _empty_vocab(d):
    _ex(d)["blocks"][0]["vocab"] = []


def _dup_answers(d):
    ex = _ex(d)
    ex["blocks"][2]["accepted_answers"][0] = ex["blocks"][0]["accepted_answers"][0]


def _function_missing(d):
    _ex(d)["function_name"] = "nope"


def _challenge_input_no_call(d):
    _ex(d)["challenge"]["small"]["input"] = "print(1)"


def _global_id_clash(d):
    # id file trùng id một ô: hai loại id dùng chung một không gian tên.
    d["themes"][0]["topics"][0]["files"][0]["id"] = _ex(d, "flight-init")["blocks"][0]["id"]


def _diagram_method_not_in_code(d):
    d["themes"][0]["diagram"]["classes"][0]["methods"].append("ghost_method")


def _diagram_attr_not_in_code(d):
    d["themes"][0]["diagram"]["classes"][0]["attributes"].append({"name": "ghost", "type": "int", "group": "core"})


def _class_missing_in_diagram(d):
    theme = d["themes"][0]
    name = _ex(d, "flight-init")["class_name"]
    theme["diagram"]["classes"] = [c for c in theme["diagram"]["classes"] if c["name"] != name]
    theme["diagram"]["relations"] = [
        r for r in theme["diagram"]["relations"] if name not in (r["from"], r["to"])
    ]


@pytest.mark.parametrize(
    "mutate, needle",
    [
        (_second_answer_three_lines, "tối đa 2 dòng"),
        (_merged_differs, "KHÔNG bằng judge.solution"),
        (_four_blocks, "tối đa 3 ô"),
        (_two_hints, "đúng 3 gợi ý"),
        (_marker_indent_wrong, "marker thụt"),
        (_marker_missing, "đúng 1 dòng `# TODO C`"),
        (_block_id_wrong, 'id phải là "split-chunks-a"'),
        (_empty_vocab, "vocab không được rỗng"),
        (_dup_answers, "trùng đáp án"),
        (_function_missing, "không định nghĩa `def nope(`"),
        (_challenge_input_no_call, "challenge.small.input phải gọi"),
        (_global_id_clash, "id trùng giữa các loại"),
        (_diagram_method_not_in_code, "ghost_method"),
        (_diagram_attr_not_in_code, "ghost"),
        (_class_missing_in_diagram, "thiếu class Flight"),
    ],
)
def test_each_rule_catches_its_mutant(content_data, mutate, needle):
    d = copy.deepcopy(content_data)
    mutate(d)
    errors = validation_errors(d)
    assert any(needle in e for e in errors), errors


def test_cell_after_return_in_same_branch_is_caught(content_data):
    """Ô B đặt sau `return` của ô A ở cùng mức thụt: B không bao giờ chạy (code chết)."""
    d = copy.deepcopy(content_data)
    ex = _ex(d, "flight-seats-left")
    ex["blocks"] = ex["blocks"][:1]
    a = ex["blocks"][0]
    b = {**a, "id": "flight-seats-left-b", "label": "B", "accepted_answers": ["pass"]}
    a["accepted_answers"] = ["return 1"]
    ex["blocks"] = [a, b]
    marker = " " * (4 * a["indent_level"])
    lines = [ln for ln in ex["template"].split("\n") if "# TODO" not in ln]
    lines += [f"{marker}# TODO A", f"{marker}# TODO B"]
    ex["template"] = "\n".join(lines)
    ex["judge"]["solution"] = merge_cells(ex["template"], {"A": "return 1", "B": "pass"})
    errors = validation_errors(d)
    assert any("code chết" in e for e in errors), errors


def test_merge_cells_matches_dart_semantics():
    template = "def f(x):\n    # TODO A\n    return y"
    assert merge_cells(template, {"A": "\n\tif x:\n\t    y = 1\n"}) == "def f(x):\n    if x:\n        y = 1\n    return y"


def test_normalize_code_like_dart():
    assert normalize_code("x  =  ( 1 , 2 )") == normalize_code("x=(1,2)")
    assert normalize_code("print('a')") == normalize_code('print("a")')


@pytest.mark.parametrize("bad", ["a\x00b", float("nan")])
def test_unstorable_values_rejected(content_data, bad):
    d = copy.deepcopy(content_data)
    _ex(d)["judge"]["cases"][0]["expect"]["return"] = bad
    errors = validation_errors(d)
    assert errors and ("NUL" in errors[0] or "NaN" in errors[0]), errors


def _args_case_without_expect(d):
    _ex(d)["judge"]["cases"][0] = {"args": ["x", 1]}


def _args_case_args_not_list(d):
    _ex(d)["judge"]["cases"][0] = {"args": 1, "expect": {"return": 1}}


def _args_case_bad_arg_index(d):
    _ex(d)["judge"]["cases"][0] = {"args": [1], "expect": {"value": 1, "arg": 5}}


def _init_without_class(d):
    ex = _ex(d, "split-chunks")
    ex["function_name"] = "__init__"


def _theme_without_topics(d):
    d["themes"][0]["topics"] = []


def _no_themes(d):
    d["themes"] = []


@pytest.mark.parametrize(
    "mutate, needle",
    [
        (_args_case_without_expect, "case cần `expect`"),
        (_args_case_args_not_list, "case cần `args`"),
        (_args_case_bad_arg_index, "chỉ số hợp lệ"),
        (_init_without_class, "`__init__` cần class_name"),
        (_theme_without_topics, "cần ít nhất 1 module"),
        (_no_themes, "cần ít nhất 1 theme"),
    ],
)
def test_more_mutants(content_data, mutate, needle):
    d = copy.deepcopy(content_data)
    mutate(d)
    errors = validation_errors(d)
    assert any(needle in e for e in errors), errors


def test_parser_overflow_in_case_is_an_error_not_a_crash(content_data):
    d = copy.deepcopy(content_data)
    _ex(d, "flight-init")["judge"]["cases"][0]["steps"] = ["(" * 400 + "1" + ")" * 400]  # < MAX_CODE_LINE nhưng tràn parser
    errors = validation_errors(d)
    assert any("không compile được" in e for e in errors), errors


def test_literal_backslash_u0000_text_is_allowed(content_data):
    """Chuỗi chứa CHỮ `\\u0000` (vd bài dạy escape) hợp lệ; chỉ ký tự NUL thật mới bị chặn."""
    d = copy.deepcopy(content_data)
    _ex(d)["blocks"][0]["explanation"] += " (vd chuỗi '\\u0000')"
    assert validation_errors(d) == []


def test_too_many_themes_rejected_before_expensive_rules(content_data):
    from app.load_content import MAX_THEMES

    d = copy.deepcopy(content_data)
    d["themes"] = [dict(d["themes"][0], id=f"t{i}") for i in range(MAX_THEMES + 1)]
    errors = validation_errors(d)
    assert errors == [f"quá nhiều theme: {MAX_THEMES + 1} > {MAX_THEMES}"]


@pytest.mark.parametrize(
    "template, cells, expected",
    [
        # tab → 4 space, bỏ dòng trống đầu/cuối, dedent chung, giữ dòng trống giữa ô
        ("def f():\n    # TODO A", {"A": "\n\n\tx = 1\n\n\ty = 2\n\n"}, "def f():\n    x = 1\n\n    y = 2"),
        ("def f():\n    # TODO A", {"A": "        a\n            b"}, "def f():\n    a\n        b"),
        ("# TODO A\nz", {"A": "x"}, "x\nz"),
    ],
)
def test_merge_cells_edge_cases(template, cells, expected):
    assert merge_cells(template, cells) == expected


@pytest.mark.parametrize(
    "a, b",
    [
        ("  for i in range( 0 , n ) :", "for i in range(0,n):"),
        ("x\t=\t1", "x = 1"),
        ("if a:\n    b = 1", "  if a:\n      b=1\n\n"),
    ],
)
def test_normalize_code_equivalences(a, b):
    assert normalize_code(a) == normalize_code(b)


def test_normalize_code_keeps_relative_indent():
    assert normalize_code("if a:\n    b") != normalize_code("if a:\nb")


def test_pathological_answer_is_rejected_fast(content_data):
    """Đáp án dài toàn ký tự trắng lạ (\\x0c) từng làm regex normalize chạy O(N²) → chặn bằng trần độ dài."""
    import time

    d = copy.deepcopy(content_data)
    _ex(d)["blocks"][0]["accepted_answers"][0] = "a" + "\x0c" * 1000 + "b"  # < MAX_TEXT, > MAX_ANSWER
    t = time.monotonic()
    errors = validation_errors(d)
    assert time.monotonic() - t < 1
    assert any("đáp án dài quá" in e for e in errors), errors


def test_class_member_cap(content_data):
    d = copy.deepcopy(content_data)
    cls = d["themes"][0]["diagram"]["classes"][0]
    cls["attributes"] = [{"name": f"a{i}", "type": "int", "group": "core"} for i in range(101)]
    assert any("thuộc tính + method" in e for e in validation_errors(d))


def _steps_not_list(d):
    case = next(c for c in _ex(d, "flight-init")["judge"]["cases"] if "call" in c)
    case["steps"] = "x = 1"


def _raises_not_str(d):
    case = next(c for c in _ex(d, "flight-init")["judge"]["cases"] if "call" in c)
    case["expect"] = {"raises": []}


@pytest.mark.parametrize(
    "mutate, needle",
    [(_steps_not_list, "`steps` phải là list chuỗi"), (_raises_not_str, "`raises` phải là tên exception")],
)
def test_scenario_case_shape(content_data, mutate, needle):
    d = copy.deepcopy(content_data)
    mutate(d)
    assert any(needle in e for e in validation_errors(d))


def test_huge_list_rejected_before_schema(content_data):
    """Trần chạy TRƯỚC pydantic: triệu phần tử sai không sinh triệu dòng lỗi."""
    d = copy.deepcopy(content_data)
    d["themes"][0]["tags"] = [1] * 500_000
    assert validation_errors(d) == ["có danh sách quá 1000 phần tử"]


def test_worst_case_diagram_payload_validates_fast(content_data):
    """Probe của review vòng 3 (3.85MB, 15s trước khi sửa): 80 bài code dài × 50 theme cùng trỏ vào × lớp
    100 thuộc tính không có trong code. Kiểm sơ đồ giờ tra tập tên → phải < 1s."""
    import time

    d = copy.deepcopy(content_data)
    base = d["exercises"]["flight-init"]
    ids = []
    for i in range(80):
        ex = copy.deepcopy(base)
        eid = f"pad-{i}"
        ex["id"] = eid
        for b in ex["blocks"]:
            b["id"] = f"{eid}-{b['label'].lower()}"
        pad = "\n".join("# " + "self.zz" * 2500 for _ in range(1))
        ex["template"] = ex["template"] + "\n" + pad[:19000]
        ex["judge"]["solution"] = ex["judge"]["solution"] + "\n" + pad[:19000]
        d["exercises"][eid] = ex
        ids.append(eid)
    theme = d["themes"][0]
    cls = theme["diagram"]["classes"][0]
    cls["attributes"] = [{"name": f"zz{i}", "type": "int", "group": "core"} for i in range(100 - len(cls["methods"]))]
    theme["topics"][0]["files"][0]["exercise_ids"] += ids
    d["themes"] = [dict(copy.deepcopy(theme), id=f"t{i}",
                        topics=[dict(tp, id=f"t{i}-{tp['id']}", files=[dict(f, id=f"t{i}-{f['id']}") for f in tp["files"]],
                                     modules=[]) for tp in theme["topics"]]) for i in range(50)]
    t = time.monotonic()
    errors = validation_errors(d)
    assert time.monotonic() - t < 1, time.monotonic() - t
    assert any("zz0" in e for e in errors)


def test_too_many_cases_rejected(content_data, monkeypatch):
    """Trần TỔNG số case (mỗi steps/call bị compile) — đếm trên toàn nội dung, không chỉ một bài."""
    from app import load_content as lc

    total = sum(len(ex["judge"]["cases"]) for ex in content_data["exercises"].values())
    monkeypatch.setattr(lc, "MAX_CASES", total - 1)
    assert any("quá nhiều test case" in e for e in validation_errors(content_data))


def test_long_call_rejected(content_data):
    d = copy.deepcopy(content_data)
    case = next(c for c in _ex(d, "flight-init")["judge"]["cases"] if "call" in c)
    case["call"] = "lambda:" * 200 + "1"
    assert any("steps/call dài quá" in e for e in validation_errors(d))
