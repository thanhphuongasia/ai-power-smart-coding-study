# Task L4 do orchestrator tự làm: bắt buộc review khác họ model, timeout 360s

## Vì sao (bằng chứng, 2 lần trong repo này)

- Run `2026-10-11-exercise-tabs-judge`, T-02 (`/run` + Judge0): `crew-review` PASS sau khi sửa 2
  Major; `crew-review-external` (Codex) tìm thêm 3 Major mà Claude bỏ sót — status Judge0 lạ thành
  lỗi học viên, body request không giới hạn, `CODE_RUNNER` sai → 500.
- Run `2026-10-11-content-api-postgres`, T-06 (`GET /content`): `crew-review` PASS với Minor;
  Codex tìm 2 Major — đọc 7 SELECT không cùng snapshot khi nạp lại xen vào (tái hiện `KeyError` →
  500), và `/run` báo 404 trong khi `/content` báo 503 lúc DB chưa nạp.

Lần đầu chạy external với timeout mặc định 90s thì timeout, không có second opinion.

## Luật

1. Mọi task L4 (security, schema/migration, public API, tích hợp ngoài) mà orchestrator tự làm →
   dispatch `crew-review` VÀ `crew-review-external` song song, ngay vòng đầu.
2. Prompt external đặt `EXTERNAL_AGENT_TIMEOUT=360`.
3. Finding của external được xử lý như finding của `crew-review` (Major chưa xử lý thì không đóng
   task); bác bỏ phải ghi lý do vào `DEVIATIONS.md`.

## Giới hạn

- File review của external là bản chép nguyên văn ý kiến CLI ngoài, thường không theo bảng 11 mã
  NFR → `verify-review.sh` báo fail trên file đó. Điều kiện "đủ mã NFR" vẫn do file `crew-review`
  của cùng task đáp ứng.
- Chưa có hook tự kiểm luật này.
