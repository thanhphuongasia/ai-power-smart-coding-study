import json
import subprocess
import sys
from pathlib import Path

import pytest

APP = Path(__file__).resolve().parent.parent / "app"
HARNESS = APP / "harness.py"
EXERCISES = json.loads((APP / "exercises.json").read_text(encoding="utf-8"))

sys.path.insert(0, str(APP))
from harness import RESULT_PREFIX, parse_result  # noqa: E402


def run_harness(code, function, cases):
    payload = json.dumps({"code": code, "function": function, "cases": cases})
    proc = subprocess.run([sys.executable, str(HARNESS)], input=payload,
                          capture_output=True, text=True, timeout=20)
    assert proc.returncode == 0, proc.stderr
    result = parse_result(proc.stdout)
    assert result is not None, proc.stdout
    return result, proc.stdout


def run_exercise(ex_id, code):
    ex = EXERCISES[ex_id]
    return run_harness(code, ex["function"], ex["cases"])


@pytest.mark.parametrize("ex_id", sorted(EXERCISES))
def test_reference_solution_passes(ex_id):
    result, _ = run_exercise(ex_id, EXERCISES[ex_id]["solution"])
    assert result["status"] == "passed", result
    assert result["error"] is None
    assert len(result["tests"]) >= 3
    assert all(t["passed"] for t in result["tests"])


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
