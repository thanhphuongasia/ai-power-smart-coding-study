# Issue #66 — SD: preview không tính tiến độ, bỏ khoá tuần tự section, reset tiến độ

Run: `planning/crew/2026-10-17-sd-preview-reset/` · branch `crew/2026-10-17-sd-preview-reset` từ **origin/dev** (rule repo).
Kết thúc: `gh pr create --base dev`, **KHÔNG merge**.

## Context

Issue #66 (phần học System Design):
1. Lướt nhanh trong reader cũng tính "đã đọc", nên tiến độ không phản ánh việc học thật. Cần chế độ **preview** để lướt mà không ghi tiến độ.
2. Section sau bị khoá tới khi xong section trước ("Hoàn thành section trước để mở khoá"). Cần mở hết.
3. Cần nút **reset tiến độ** về đầu, có hỏi xác nhận.

Hiện trạng:
- Khoá tính ở server: `_sections_state` đặt `unlocked = prev_done` (`backend/app/sd/learner.py:50-70`), `put_progress` trả 409 `section_locked` (:197).
- App chỉ vẽ theo cờ server (`sd_path_screen.dart:31-35`, `reader_screen.dart:340`, `reader_menu.dart:234`).
- Reader đánh dấu card khi mép dưới card đi qua đáy màn (`reader_screen.dart:329-376`) và PUT theo section, debounce 800ms (:453), gửi nốt lúc `dispose`.
- Chưa có API reset.

## Thiết kế

- **Bỏ khoá ở server** (một chỗ):
  - `unlocked = True` cho mọi section; `put_progress` bỏ 409.
  - Field `unlocked` vẫn trả về (luôn `true`) để app cũ trên TestFlight không vỡ parse. App cũ cũng hết bị khoá luôn, vì nó đọc cờ server.
  - Phía app không cần đổi logic khoá; các toast khoá tự không còn xuất hiện.
- **Phase 2 không đổi:** task thực chiến vẫn chỉ mở khi mọi section đã đọc xong. Issue chỉ nói về section; nếu muốn mở luôn Phase 2 thì làm sau.
- **Reset:**
  - `DELETE /api/sd/docs/{doc_id}/progress` → 204: xoá các dòng `sd_progress` của **đúng user này và đúng doc này**.
  - **Không** xoá bài nộp (`sd_attempts`): đó là lịch sử chấm.
  - Doc không published thì 404. Cần đăng nhập.
  - Sau reset: số card đã đọc về 0, Phase 2 khoá lại cho tới khi đọc xong; bài đã nộp vẫn còn.
- **Preview (app):**
  - Route `/design/:docId/read?preview=1`.
  - Trong preview, reader **không đánh dấu và không gửi PUT nào**, kể cả lúc rời màn. Có banner "Xem trước — không tính tiến độ"; nhảy được tới mọi section qua mục lục.
  - Vào bằng icon con mắt trên màn lộ trình tài liệu (`SdPathScreen`): Design → doc → icon, 2 chạm từ tab.
- **Nút reset (app):**
  - Trên `SdPathScreen` (menu ⋮ hoặc icon) → hộp thoại "Đặt lại tiến độ đọc tài liệu này?" (Huỷ / Đặt lại).
  - Xác nhận thì gọi `SdRepository.resetProgress(docId)`, rồi invalidate `sdDocProvider(docId)` và `sdDocsProvider`. Lỗi thì hiện SnackBar.

## Sổ bất biến

```text
INV-01 · Preview không bao giờ ghi tiến độ: không _evaluate/không PUT kể cả dispose
         phải khớp: mobile/lib/features/system_design/reader_screen.dart (_evaluate, _schedule, dispose) · mobile/lib/app/router.dart (/design/:docId/read?preview)
         vỡ thì thấy gì: lướt preview xong quay ra thấy section đã "done"
INV-02 · Mọi section mở: server unlocked=true cho mọi section, put_progress không còn 409; app đọc cờ server nên không còn toast khoá
         phải khớp: backend/app/sd/learner.py:50-70,197 · mobile/lib/features/system_design/sd_path_screen.dart:222 · mobile/lib/features/system_design/reader_menu.dart:234
         vỡ thì thấy gì: chạm section 3 vẫn hiện "Hoàn thành section trước để mở khoá"
INV-03 · Phase 2 vẫn chỉ mở khi MỌI section done (không đổi), kể cả sau reset (reset → Phase 2 khoá lại)
         phải khớp: backend/app/sd/learner.py:148,168,224 · mobile/lib/features/system_design/sd_path_screen.dart:79
         vỡ thì thấy gì: reset xong Phase 2 vẫn mở, hoặc chưa đọc hết mà Phase 2 đã mở
INV-04 · Reset chỉ xoá sd_progress của đúng (user, doc); không đụng sd_attempts, user khác, doc khác
         phải khớp: backend/app/sd/learner.py (reset_progress) · backend/app/tables.py (SdProgress, SdAttempt)
         vỡ thì thấy gì: reset doc A làm mất tiến độ doc B hoặc của học viên khác, hoặc mất bài đã nộp
INV-05 · Tương thích ngược API: response giữ nguyên key (unlocked vẫn có, luôn true); app cũ không vỡ
         phải khớp: backend/app/sd/learner.py · mobile/lib/domain/sd_models.dart (SdSection.unlocked bắt buộc)
         vỡ thì thấy gì: app TestFlight báo lỗi tải tài liệu
INV-06 · Sau reset, app hiển thị đúng 0 đã đọc ở cả màn lộ trình lẫn danh sách tab Design
         phải khớp: mobile/lib/data/sd_repository.dart (resetProgress) · mobile/lib/features/system_design/sd_path_screen.dart (invalidate sdDocProvider + sdDocsProvider)
         vỡ thì thấy gì: bấm Đặt lại xong vẫn thấy % cũ cho tới khi kéo làm mới
```

## Task (role · tier · model)

| ID | Việc | Role · tier · model | Wave |
|---|---|---|---|
| T-01 | Backend: bỏ khoá + DELETE progress + test | orchestrator · L4 (public API) · session | 1 |
| T-02 | Reader chế độ preview + route + test | crew-impl-standard · T2 · sonnet | 1 |
| T-03 | Màn lộ trình: icon preview + nút reset có xác nhận + repository + test | crew-impl-standard · T2 · sonnet | 1 |

Ba task chạy song song, ownership rời nhau. T-03 dùng route preview theo hợp đồng `?preview=1`. Review: `crew-review` cho cả 3, cộng `crew-review-external` (prompt hẹp) cho T-01. Cuối run có reviewer mối nối.

### T-01 · L4 · orchestrator
- Owned: `backend/app/sd/learner.py`, `backend/tests/test_sd_learner.py`, `backend/tests/test_sd_progress_reset.py` (mới)
- Forbidden: `mobile/**`, `backend/app/sd/docs.py`, `backend/app/sd/attempts.py`
- Acceptance:
  - mọi section `unlocked=true`; PUT progress cho section bất kỳ thành công, không 409.
  - Phase 2 vẫn cần đọc hết.
  - DELETE progress → 204, tiến độ về 0, Phase 2 khoá lại, bài nộp còn; user khác/doc khác không đổi; doc draft/không có → 404; không token → 401.
  - Test cũ về khoá cập nhật theo hành vi mới; các assert khác không sửa.
- Validation: `cd backend && .venv/bin/python -m pytest -q tests/test_sd_learner.py tests/test_sd_progress_reset.py tests/test_sd_attempts.py`

### T-02 · L3 · crew-impl-standard
- Owned: `mobile/lib/features/system_design/reader_screen.dart`, `mobile/lib/app/router.dart`, `mobile/test/sd_reader_test.dart`
- Forbidden: `backend/**`, các file Flutter khác
- Acceptance:
  - `?preview=1`: không đánh dấu, không PUT (kể cả dispose); banner preview; mục lục nhảy tới mọi section.
  - Không có `preview`: hành vi cũ giữ nguyên.
- Validation: `cd mobile && flutter test test/sd_reader_test.dart test/sd_reader_menu_test.dart && flutter analyze lib`

### T-03 · L3 · crew-impl-standard
- Owned: `mobile/lib/features/system_design/sd_path_screen.dart`, `mobile/lib/data/sd_repository.dart`, `mobile/test/sd_path_screen_test.dart`, `mobile/test/sd_repository_test.dart`
- Forbidden: `backend/**`, `reader_screen.dart`, `router.dart`, các file Flutter khác
- Acceptance:
  - icon preview (`Key('sd-preview')`) push `/design/<id>/read?preview=1`.
  - nút reset (`Key('sd-reset')`) → dialog (`sd-reset-cancel`/`sd-reset-confirm`); Huỷ thì không gọi API; Đặt lại thì gọi DELETE rồi invalidate cả `sdDocProvider` và `sdDocsProvider`; lỗi thì SnackBar.
  - `resetProgress` mong 204, lỗi ném `SdApiException`.
  - Test bắt đầu từ tab Design.
- Validation: `cd mobile && flutter test test/sd_path_screen_test.dart test/sd_repository_test.dart && flutter analyze lib`

## Verification (orchestrator tự chạy)

1. Full pytest + `flutter test` + `flutter analyze lib`.
2. Uvicorn thật:
   - học viên PUT section 3 khi chưa đọc section 1 → 200 (INV-02).
   - đọc hết → Phase 2 mở → DELETE progress → Phase 2 khoá, bài nộp còn, tiến độ doc khác còn (INV-03, INV-04).
3. Flutter web + backend local (nếu dựng được) hoặc widget test: preview lướt hết → quay ra màn lộ trình vẫn 0 đã đọc (INV-01).
