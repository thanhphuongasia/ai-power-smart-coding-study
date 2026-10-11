# Run `oop-bank-progressive` — BankAccount: notebook tiến dần, không lộ đáp án, mọi TODO là ô

## Context

User mở bài OOP BankAccount và thấy ô khoá "[2] có sẵn" chứa lời giải đầy đủ của `deposit`, `withdraw`,
`apply_interest`, `display_info`. Nguyên nhân: template của cả 7 bài đều là class đã giải xong, chỉ đục lỗ
phần của bài đó. Ngoài ra vài gạch TODO của skeleton gốc bị khoá sẵn: `return False` trong `withdraw`,
validate trong `__init__` bị gộp. User muốn mỗi TODO là bài/ô học viên tự gõ, bài dài thì tách.

Luật sơ đồ (`content_rules.py:263`) chỉ cần *một bài nào đó* có `def m(` ⇒ template các bài đầu bỏ được
phần thân method chưa học.

## Thiết kế

**Template kiểu notebook tiến dần** (thứ tự bài trong file `bank_account.py`):

- method của bài trước → đầy đủ, khoá;
- method của bài hiện tại → ô TODO;
- method chưa học → decorator + chữ ký + `pass`, đúng skeleton gốc của user.

Case/challenge chỉ dùng phần đã học. Bài 1–2 chưa có property `balance` ⇒ đọc số dư bằng
`acc._BankAccount__balance` (nhân tiện dạy name mangling).

**9 bài.** Giữ id cũ để không mất tiến độ; thêm 2 id mới. Mỗi gạch TODO của skeleton ↔ một ô:

| # | id | Ô học viên gõ |
|---|---|---|
| 1 | `bank-init` | A `interest_rate = 0.02` · B `self.__owner_name = owner_name` · C `self.__balance = initial_balance` |
| 2 | `bank-init-validate` (mới) | A `if initial_balance < 0:` · B `raise ValueError("Initial balance cannot be negative")` |
| 3 | `bank-properties` | A `return self.__owner_name` · B `return self.__balance` (decorator khoá như skeleton) |
| 4 | `bank-balance-setter` | A `if value < 0:` · B `print("Balance cannot be negative")` + `return` · C `self.__balance = value` |
| 5 | `bank-deposit` | A `if amount <= 0:` · B print + `return False` · C `self.__balance += amount` + `return True` |
| 6 | `bank-withdraw` | A `if amount <= 0:` · B `print("Withdrawal amount must be positive")` · C `return False` |
| 7 | `bank-withdraw-funds` (mới) | A `if amount > self.__balance:` · B `print("Insufficient funds")` + `return False` · C `self.__balance -= amount` + `return True` |
| 8 | `bank-apply-interest` | giữ 3 ô hiện có |
| 9 | `bank-display-info` | giữ 3 ô + case đổi `interest_rate` |

Ở bài 6, `withdraw` dừng sau khối `if`. Bài 7 khoá phần của bài 6 rồi thêm tiếp.

## Sổ bất biến

```text
INV-01 · Nội dung qua đủ luật server + Dart: validation_errors == [], content_contract_test xanh
         phải khớp: backend/content/content.json · backend/app/content_rules.py:274 · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: admin Lưu bị 422; app ghép đáp án đúng vẫn chấm sai
INV-02 · Không bài nào lộ đáp án bài sau: template bài i không chứa dòng đáp án (đã strip, bỏ dòng tầm thường như `return`) của bài j>i trong cùng file
         phải khớp: backend/content/content.json · backend/tests/test_load_content.py (test mới)
         vỡ thì thấy gì: ô "có sẵn" hiện lời giải method chưa học
INV-03 · Judge chấm đúng: lời giải pass mọi case; mutant tiêu biểu mỗi bài fail ≥1 case; case chỉ dùng method đã học (method chưa học là `pass` → lời giải sẽ fail nếu case dùng nó)
         phải khớp: content.json judge.cases · backend/app/harness.py · backend/tests/test_harness.py (test_reference_solution_passes)
         vỡ thì thấy gì: gõ đúng vẫn failed / gõ sai vẫn passed
INV-04 · Nạp VPS không mất sửa của admin, 22 bài theme cũ y nguyên; id bài BankAccount cũ còn đủ (tiến độ không mất)
         phải khớp: backend/app/export_content.py:36 · backend/app/load_content.py:398 · https://codewithphuong.jacons-corp.com/content
         vỡ thì thấy gì: bài/tiến độ biến mất
INV-05 · Test đếm cứng đúng số mới (29→31 bài, 24→26 bài method, theme cũ không đổi), danh sách id bắt buộc có 2 id mới
         phải khớp: backend/tests/test_load_content.py · mobile/test/content_contract_test.dart
         vỡ thì thấy gì: suite đỏ
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned | Validation |
|---|---|---|---|---|
| T-01 | `crew-impl-standard` · T2 · sonnet | viết lại 7 bài + 2 bài mới theo bảng; test chống lộ đáp án (INV-02); cập nhật số đếm; mutation-check | `backend/content/content.json`, `backend/tests/test_load_content.py`, `mobile/test/content_contract_test.dart` | `cd backend && .venv/bin/python -m pytest -q && cd ../mobile && flutter test` |
| T-02 | orchestrator · L2 (dữ liệu prod) | export VPS == HEAD content cũ → `deploy.sh` → `load_content --force` → kiểm `/content` | (không file repo) | curl `/content`: 31 bài, 9 bài bank-* |

Thứ tự: viết bài 1 trước (khó nhất vì đổi case sang `_BankAccount__balance`), chạy validate, rồi tới các bài sau.
Forbidden: `mobile/ios/**` (thay đổi chưa commit của user), `backend/app/**`.

Review: `crew-review` T-01 (lộ đáp án, đủ TODO, case dùng method chưa học, mutant) → seam reviewer INV-01..05
→ `verify-seam.sh` → commit + push main → T-02 → distill.

## Verification

1. pytest + flutter test toàn bộ; `validation_errors == []`.
2. Script quét: với từng bài bank-*, không dòng đáp án nào của bài sau nằm trong template.
3. Harness thật: 9 lời giải passed; mutant mỗi bài failed.
4. Prod: `POST /run` lời giải `bank-init` (bài 1, không có property) → passed; `/content` có 31 bài; template `bank-init` không chứa `self.__balance -= amount`.
