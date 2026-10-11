# Run `python-oop-bank` — project "Python Fundamentals", chương OOP, bài BankAccount

## Context

User muốn thêm một project nền tảng Python, chương OOP, lấy bài "Bank Account Manager" (class
`BankAccount` có class variable, thuộc tính private, property getter/setter, các method) làm nội dung
đầu tiên. Nội dung app có luật chặt (≤3 ô/bài, ≤2 dòng/đáp án, ghép đáp án == lời giải, case kịch bản cho
bài method, sơ đồ class khớp code) → chẻ class thành 7 bài method nhỏ. DB VPS là nguồn chính nhưng hiện
trùng khớp `content.json` (đã kiểm: 4 theme, 22 bài, bằng nhau) → soạn trong `content.json` rồi nạp
`--force`. Đề/hint viết lại tiếng Việt, không chép đề gốc; chuỗi in ra giữ đúng tiếng Anh.

## Thiết kế nội dung

- Theme `python-fundamentals` "Python Fundamentals" (tags python, oop), đặt CUỐI danh sách theme (không đổi
  thứ tự hiển thị và test "airline đứng đầu"). Module `oop` "OOP — Lập trình hướng đối tượng", file
  `bank_account.py` chứa 7 bài theo thứ tự học:
  1. `bank-init` — `interest_rate = 0.02` + `__init__` (lưu `__owner_name`; âm → `ValueError("Initial balance cannot be negative")`; lưu `__balance`)
  2. `bank-properties` — property `owner_name` + `balance` (getter)
  3. `bank-balance-setter` — setter: âm → in "Balance cannot be negative", không đổi
  4. `bank-deposit` — ≤0 → in "Deposit amount must be positive", False; ngược lại cộng, True
  5. `bank-withdraw` — ≤0 → "Withdrawal amount must be positive"/False; > số dư → "Insufficient funds"/False; trừ, True
  6. `bank-apply-interest` — lãi = số dư × `interest_rate`, cộng vào, trả lãi
  7. `bank-display-info` — in 3 dòng `Account Owner: …` / `Balance: $…` / `Interest Rate: …%` (×100)
- Mỗi bài: template là class `BankAccount` đủ để chạy (phần khác khoá sẵn), ô TODO chỉ phần đang học;
  `class_name` = `BankAccount`; `function_name` đúng tên method (`__init__`, `owner_name`, `balance`,
  `deposit`, …); 4–7 case `call` kiểm cả nhánh lỗi; case in ra dùng `steps` với
  `contextlib.redirect_stdout` rồi `call` trả `buf.getvalue()`; challenge small/project gọi đúng hàm.
- Sơ đồ class theme: `BankAccount` — thuộc tính `__owner_name`, `__balance` (core), `interest_rate`
  (support, class variable phải xuất hiện dạng `self.<name> =`? → KHÔNG: luật INV-02 tìm `self.x =`,
  nên chỉ khai `__owner_name`, `__balance`); methods đủ 7 tên có `def …(` trong thân class.

## Sổ bất biến

```text
INV-01 · Mọi bài mới qua đủ luật nội dung server + Dart: validation_errors == [] và content_contract_test xanh (merge == solution, marker, ≤3 ô, 3 hint, code chết, sơ đồ khớp)
         phải khớp: backend/content/content.json · backend/app/content_rules.py · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: admin Lưu bị 422; app ghép đáp án đúng vẫn chấm sai
INV-02 · Judge thật chấm đúng: lời giải pass mọi case, mỗi đáp án sai tiêu biểu (mutant) fail ít nhất một case
         phải khớp: backend/content/content.json (judge.cases) · backend/app/harness.py (_run_scenario)
         vỡ thì thấy gì: học viên gõ sai vẫn "passed", hoặc gõ đúng bị chấm sai
INV-03 · Nạp lên VPS không mất sửa của admin và không đổi theme cũ: trước --force, DB VPS == content.json cũ (chỉ khác theme mới); sau nạp /content có theme mới, 22 bài cũ y nguyên
         phải khớp: backend/content/content.json · VPS DB (export_content) · https://codewithphuong.jacons-corp.com/content
         vỡ thì thấy gì: bài/tiêu đề admin đã sửa biến mất
INV-04 · Test đếm cứng cập nhật đúng số mới (22→29 bài, 17→24 bài method) và danh sách id bài bắt buộc có bài mới
         phải khớp: backend/tests/test_load_content.py · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: suite đỏ sau khi thêm nội dung
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | `crew-impl-standard` · T2 · sonnet | soạn theme + 7 bài + sơ đồ; cập nhật test đếm; mutation-check judge | `backend/content/content.json`, `backend/tests/test_load_content.py`, `mobile/test/content_contract_test.dart` | `cd backend && .venv/bin/python -m pytest -q` + `cd mobile && flutter test test/content_contract_test.dart` + script mutation (scratchpad) |
| T-02 | orchestrator · L2 (dữ liệu prod) · session | nạp lên VPS: kiểm DB==content.json cũ → rsync content → `load_content --force` → kiểm /content | (không file repo) | curl /content: 5 theme, 29 bài |

Review: T-01 `crew-review` (kiểm sư phạm + judge + luật + chép đề); seam reviewer INV-01..04 →
`verify-seam.sh` → commit, push, deploy + nạp.

## Verification

1. pytest, flutter test (toàn bộ), `validation_errors(content.json) == []`.
2. Chạy judge thật (LocalRunner/harness local) cho 7 lời giải → passed; mutant mỗi bài → failed.
3. Local: uvicorn + web local (cửa sổ Chrome phải `visible`) mở Python Fundamentals → OOP → làm bài 4 → Run passed.
4. VPS: `/content` có `python-fundamentals`, 29 bài; bài cũ không đổi (so hash public payload theme cũ).
