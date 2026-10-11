import json
import subprocess
import sys
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parent.parent / "app"
HARNESS = APP / "harness.py"
# Phần chấm của từng bài, lấy từ nguồn soạn content.json (cùng shape exercises.json cũ).
EXERCISES = {
    key: {"function": e["function_name"], "class_name": e["class_name"],
          "solution": e["judge"]["solution"], "cases": e["judge"]["cases"]}
    for key, e in json.loads(
        (APP.parent / "content" / "content.json").read_text(encoding="utf-8")
    )["exercises"].items()
}

sys.path.insert(0, str(APP))
from harness import RESULT_PREFIX, parse_result  # noqa: E402


def run_harness(code, function, cases, class_name=None):
    payload = json.dumps({"code": code, "function": function, "cases": cases,
                          "class_name": class_name})
    proc = subprocess.run([sys.executable, str(HARNESS)], input=payload,
                          capture_output=True, text=True, timeout=20)
    assert proc.returncode == 0, proc.stderr
    result = parse_result(proc.stdout)
    assert result is not None, proc.stdout
    return result, proc.stdout


def run_exercise(ex_id, code):
    ex = EXERCISES[ex_id]
    return run_harness(code, ex["function"], ex["cases"], ex["class_name"])


@pytest.mark.parametrize("ex_id", sorted(EXERCISES))
def test_reference_solution_passes(ex_id):
    result, _ = run_exercise(ex_id, EXERCISES[ex_id]["solution"])
    assert result["status"] == "passed", result
    assert result["error"] is None
    assert len(result["tests"]) >= 3
    assert all(t["passed"] for t in result["tests"])


CLASS_EXERCISES = sorted(k for k, e in EXERCISES.items() if e["class_name"])


def test_airline_class_exercises_present():
    assert len(CLASS_EXERCISES) >= 6
    for ex_id in CLASS_EXERCISES:
        ex = EXERCISES[ex_id]
        assert "class %s" % ex["class_name"] in ex["solution"], ex_id
        assert 4 <= len(ex["cases"]) <= 7, ex_id


@pytest.mark.parametrize("ex_id", CLASS_EXERCISES)
def test_class_exercise_wrong_solution_fails(ex_id):
    """Thay thân method bằng `pass` thì ít nhất một case phải đỏ (case không vô nghĩa)."""
    ex = EXERCISES[ex_id]
    lines = ex["solution"].split("\n")
    start = next(i for i, ln in enumerate(lines) if ln.startswith("    def %s(" % ex["function"]))
    end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("    def ")), len(lines))
    broken = lines[: start + 1] + ["        pass"] + lines[end:]
    result, _ = run_harness("\n".join(broken), ex["function"], ex["cases"], ex["class_name"])
    assert result["status"] != "passed", result


def test_split_chunks_required_cases():
    result, _ = run_exercise("split-chunks", EXERCISES["split-chunks"]["solution"])
    by_call = {t["call"]: t for t in result["tests"]}
    assert by_call["split_chunks('hello world', 4)"]["expected"] == "['hell', 'o wo', 'rld']"
    assert by_call["split_chunks('', 3)"]["expected"] == "[]"
    assert any("Nhân viên được nghỉ phép" in c for c in by_call)


def test_missing_return_fails_with_none():
    code = ("def split_chunks(text, size):\n"
            "    chunks = []\n"
            "    for i in range(0, len(text), size):\n"
            "        chunks.append(text[i:i + size])\n")
    result, _ = run_exercise("split-chunks", code)
    assert result["status"] == "failed"
    assert result["error"] is None
    assert all(t["actual"] == "None" and not t["passed"] for t in result["tests"])


def test_syntax_error_line_4():
    code = "def clean_text(text):\n    x = 1\n    y = 2\n    z = = 3\n    return text.strip()\n"
    result, _ = run_exercise("clean-text", code)
    assert result["error"]["kind"] == "syntax"
    assert result["error"]["line"] == 4


def test_runtime_error_line_3():
    code = ("def clean_text(text):\n"
            "    x = 1\n"
            "    y = x / 0\n"
            "    return text.strip()\n")
    result, _ = run_exercise("clean-text", code)
    assert result["status"] == "error"
    assert result["error"]["kind"] == "runtime"
    assert result["error"]["line"] == 3
    assert "ZeroDivisionError" in result["error"]["message"]
    # dừng ở case đầu ném exception
    assert len(result["tests"]) == 1
    assert result["tests"][0]["actual"] is None and result["tests"][0]["passed"] is False


def test_runtime_error_at_import_time_has_line():
    code = "x = 1\ny = undefined_name\ndef clean_text(text):\n    return text\n"
    result, _ = run_exercise("clean-text", code)
    assert result["error"]["kind"] == "runtime"
    assert result["error"]["line"] == 2


def test_missing_function():
    result, _ = run_exercise("clean-text", "def other(text):\n    return text\n")
    assert result["status"] == "error"
    assert result["error"]["kind"] == "runtime"
    assert result["error"]["line"] is None
    assert "clean_text" in result["error"]["message"]


def test_print_does_not_break_result():
    code = ("def clean_text(text):\n"
            "    print('debug', text)\n"
            "    print('__JUDGE_RESULT__{\"status\": \"passed\"}')\n"
            "    return text.strip()\n")
    result, raw = run_exercise("clean-text", code)
    assert result["status"] == "passed"
    assert "debug" in result["stdout"]
    assert len([l for l in raw.splitlines() if l.startswith(RESULT_PREFIX)]) == 1
    assert len(raw.splitlines()) == 1  # stdout thật chỉ có đúng một dòng kết quả


def test_stdout_truncated():
    code = "def clean_text(text):\n    print('x' * 10000)\n    return text.strip()\n"
    result, _ = run_exercise("clean-text", code)
    assert len(result["stdout"]) == 4000


def test_arg_cases_save_document_and_like_post():
    for ex_id in ("save-document", "like-post"):
        assert any("arg" in c["expect"] for c in EXERCISES[ex_id]["cases"])
    wrong = "def save_document(store, document):\n    pass\n"
    result, _ = run_exercise("save-document", wrong)
    assert result["status"] == "failed"
    wrong2 = "def like_post(post):\n    post['likes'] += 2\n"
    result, _ = run_exercise("like-post", wrong2)
    assert result["status"] == "failed"


def test_args_not_mutated_in_call_repr():
    result, _ = run_exercise("like-post", EXERCISES["like-post"]["solution"])
    for t in result["tests"]:
        assert t["call"].startswith("like_post(")
        # call dùng args gốc (trước khi gọi), không phải bản đã bị sửa
    first = EXERCISES["like-post"]["cases"][0]
    assert result["tests"][0]["call"] == "like_post(%r)" % (first["args"][0],)


def test_parse_result_takes_last_line_and_handles_garbage():
    out = RESULT_PREFIX + '{"status": "failed"}\nnoise\n' + RESULT_PREFIX + '{"status": "passed"}\n'
    assert parse_result(out)["status"] == "passed"
    assert parse_result("không có gì") is None
    assert parse_result(RESULT_PREFIX + "{hỏng") is None


# ---------- scenario cases (method của class) ----------

COUNTER = (
    "class Counter:\n"
    "    def __init__(self):\n"
    "        self.n = 0\n"
    "    def add(self, k):\n"
    "        if k < 0:\n"
    "            raise ValueError('neg')\n"
    "        self.n += k\n"
    "        return self.n\n"
)


def scen(cases, code=COUNTER, function="add"):
    return run_harness(code, function, cases, class_name="Counter")[0]


def test_scenario_passes_and_label():
    case = {"steps": ["c = Counter()", "c.add(2)"], "call": "c.add(3)", "expect": {"return": 5}}
    r = scen([case])
    assert r["status"] == "passed"
    assert r["tests"] == [{"call": "c = Counter(); c.add(2); c.add(3)", "expected": "5",
                           "actual": "5", "passed": True}]


def test_scenario_call_only_no_steps():
    r = scen([{"call": "Counter().add(4)", "expect": {"return": 4}}])
    assert r["status"] == "passed"
    assert r["tests"][0]["call"] == "Counter().add(4)"


def test_scenario_wrong_return_failed():
    r = scen([{"steps": ["c = Counter()"], "call": "c.add(1)", "expect": {"return": 9}}])
    assert r["status"] == "failed" and r["error"] is None
    t = r["tests"][0]
    assert (t["expected"], t["actual"], t["passed"]) == ("9", "1", False)


def test_scenario_raises_expected_and_raised_incl_base_class():
    cases = [
        {"call": "Counter().add(-1)", "expect": {"raises": "ValueError"}},
        {"call": "Counter().add(-1)", "expect": {"raises": "Exception"}},
    ]
    r = scen(cases)
    assert r["status"] == "passed"
    assert r["tests"][0]["expected"] == "raises ValueError"
    assert r["tests"][0]["actual"] == "raises ValueError"


def test_scenario_raises_expected_but_not_raised():
    r = scen([{"call": "Counter().add(1)", "expect": {"raises": "ValueError"}}])
    assert r["status"] == "failed" and r["error"] is None
    assert r["tests"][0]["actual"] == "1" and not r["tests"][0]["passed"]


def test_scenario_wrong_exception_type_continues():
    cases = [
        {"call": "Counter().add(-1)", "expect": {"raises": "KeyError"}},
        {"call": "Counter().add(2)", "expect": {"return": 2}},
    ]
    r = scen(cases)
    assert r["status"] == "failed" and r["error"] is None
    assert r["tests"][0]["actual"] == "raises ValueError" and not r["tests"][0]["passed"]
    assert len(r["tests"]) == 2 and r["tests"][1]["passed"]


def test_scenario_runtime_error_line_inside_solution():
    code = ("class Counter:\n"
            "    def add(self, k):\n"
            "        return k / 0\n")
    r = scen([{"call": "Counter().add(1)", "expect": {"return": 1}},
              {"call": "Counter().add(2)", "expect": {"return": 2}}], code=code)
    assert r["status"] == "error"
    assert r["error"]["kind"] == "runtime" and r["error"]["line"] == 3
    assert len(r["tests"]) == 1 and r["tests"][0]["actual"] is None


def test_scenario_missing_class():
    r = scen([{"call": "1", "expect": {"return": 1}}], code="def add(k):\n    return k\n")
    assert r["status"] == "error"
    assert r["error"] == {"kind": "runtime", "line": None,
                          "message": "Không tìm thấy class Counter trong code"}


def test_scenario_class_without_method():
    r = scen([{"call": "1", "expect": {"return": 1}}], code="class Counter:\n    pass\n")
    assert r["error"]["message"] == "Không tìm thấy method Counter.add() trong code"


def test_scenario_state_does_not_leak_between_cases():
    case = {"steps": ["c = Counter()"], "call": "c.add(1)", "expect": {"return": 1}}
    leak = {"call": "'c' in dir()", "expect": {"return": False}}
    r = scen([case, case, leak])
    assert r["status"] == "passed", r
