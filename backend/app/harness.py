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


def _run_scenario(case, namespace, tests):
    """Chạy một case dạng kịch bản trong bản sao nông của namespace. Thêm 1 test vào `tests`.
    Trả error dict nếu phải dừng (exception ngoài kỳ vọng với expect.return), ngược lại None."""
    steps = list(case.get("steps") or [])
    call_expr = case["call"]
    expect = case["expect"]
    label = "; ".join([*steps, call_expr])
    # Filename "<case>" để _runtime_error chỉ lấy frame nằm trong solution.py.
    compiled_steps = [compile(st, "<case>", "exec") for st in steps]
    compiled_call = compile(call_expr, "<case>", "eval")
    scope = dict(namespace)  # mỗi case một bản sao mới: state không rò giữa các case
    raised = None
    value = None
    try:
        for st in compiled_steps:
            exec(st, scope)
        value = eval(compiled_call, scope)
    except (Exception, SystemExit) as e:
        raised = e

    if "raises" in expect:
        want = expect["raises"]
        expected_label = "raises %s" % want
        if raised is None:
            tests.append({"call": label, "expected": expected_label,
                          "actual": repr(value), "passed": False})
        else:
            names = {c.__name__ for c in type(raised).__mro__}
            tests.append({"call": label, "expected": expected_label,
                          "actual": "raises %s" % type(raised).__name__,
                          "passed": want in names})
        return None

    expected_repr = repr(expect["return"])
    if raised is not None:
        tests.append({"call": label, "expected": expected_repr, "actual": None, "passed": False})
        return _runtime_error(raised)
    tests.append({"call": label, "expected": expected_repr, "actual": repr(value),
                  "passed": bool(value == expect["return"])})
    return None


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

        class_name = payload.get("class_name")
        func = None
        if class_name:
            cls = namespace.get(class_name)
            if not isinstance(cls, type):
                error = {"kind": "runtime", "line": None,
                         "message": "Không tìm thấy class %s trong code" % class_name}
                return finish()
            # hasattr (không phải callable): property (owner_name, balance…) cũng là thành viên hợp lệ.
            if not hasattr(cls, function):
                error = {"kind": "runtime", "line": None,
                         "message": "Không tìm thấy method %s.%s() trong code" % (class_name, function)}
                return finish()
        else:
            func = namespace.get(function)
            if not callable(func):
                error = {"kind": "runtime", "line": None,
                         "message": "Không tìm thấy hàm %s() trong code" % function}
                return finish()

        for case in cases:
            if "call" in case:
                # `steps`/`call` do tác giả bài viết trong content DB, không bao giờ đến từ client.
                outcome = _run_scenario(case, namespace, tests)
                if outcome is not None:
                    error = outcome
                    return finish()
                continue
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
