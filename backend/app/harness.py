"""Harness chạy trên máy chấm (Judge0, Python 3.12): đọc payload JSON từ stdin,
chạy code học viên + test case, in ĐÚNG MỘT dòng kết quả `__JUDGE_RESULT__{json}`.

Chỉ dùng thư viện chuẩn. Không import gì từ backend khác.
"""
import contextlib
import copy
import io
import json
import sys
import traceback

RESULT_PREFIX = "__JUDGE_RESULT__"
STDOUT_LIMIT = 4000
USER_FILE = "solution.py"


def parse_result(stdout):
    """Tìm dòng CUỐI có tiền tố RESULT_PREFIX, trả dict; không có/không parse được -> None."""
    if not isinstance(stdout, str):
        return None
    for line in reversed(stdout.splitlines()):
        if line.startswith(RESULT_PREFIX):
            try:
                value = json.loads(line[len(RESULT_PREFIX):])
            except ValueError:
                return None
            return value if isinstance(value, dict) else None
    return None


def _runtime_error(exc):
    line = None
    for frame in traceback.extract_tb(exc.__traceback__):
        if frame.filename == USER_FILE:
            line = frame.lineno  # frame cuối khớp = sâu nhất
    return {"kind": "runtime", "line": line, "message": "%s: %s" % (type(exc).__name__, exc)}


def _syntax_error(exc):
    return {"kind": "syntax", "line": exc.lineno, "message": exc.msg or str(exc)}


def _call_repr(function, args):
    return "%s(%s)" % (function, ", ".join(map(repr, args)))


def run(payload):
    """Trả dict kết quả (chưa gồm tiền tố)."""
    code = payload["code"]
    function = payload["function"]
    cases = payload["cases"]
    tests = []
    error = None
    buf = io.StringIO()

    def finish():
        if error is not None:
            status = "error"
        elif any(not t["passed"] for t in tests):
            status = "failed"
        else:
            status = "passed"
        return {"status": status, "error": error, "tests": tests,
                "stdout": buf.getvalue()[:STDOUT_LIMIT]}

    try:
        compiled = compile(code, USER_FILE, "exec")
    except SyntaxError as e:
        error = _syntax_error(e)
        return finish()

    namespace = {"__name__": "__student__"}
    with contextlib.redirect_stdout(buf):
        try:
            exec(compiled, namespace)
        except (Exception, SystemExit) as e:
            error = _runtime_error(e)
            return finish()

        func = namespace.get(function)
        if not callable(func):
            error = {"kind": "runtime", "line": None,
                     "message": "Không tìm thấy hàm %s() trong code" % function}
            return finish()

        for case in cases:
            args = case["args"]
            expect = case["expect"]
            call = _call_repr(function, args)
            if "return" in expect:
                expected_value = expect["return"]
            else:
                expected_value = expect["value"]
            expected_repr = repr(expected_value)
            run_args = copy.deepcopy(args)
            try:
                returned = func(*run_args)
            except (Exception, SystemExit) as e:
                # Chọn: DỪNG ở case ném exception, các case sau không chạy.
                error = _runtime_error(e)
                tests.append({"call": call, "expected": expected_repr,
                              "actual": None, "passed": False})
                return finish()
            actual_value = returned if "return" in expect else run_args[expect["arg"]]
            tests.append({"call": call, "expected": expected_repr,
                          "actual": repr(actual_value),
                          "passed": bool(actual_value == expected_value)})
    return finish()


def main():
    payload = json.loads(sys.stdin.read())
    result = run(payload)
    sys.stdout.write(RESULT_PREFIX + json.dumps(result, ensure_ascii=False) + "\n")
    sys.stdout.flush()


if __name__ == "__main__":
    main()
