# Review mối nối — run 2026-09-24-flutter-demo-core

Phạm vi: 5 bất biến (INV-01..05) trong `PLAN.md`, kiểm bằng đọc code qua mọi đầu mối nối + 3 test
tạm (viết, chạy, xoá — không còn trong git status) để chứng minh thực tế, không suy diễn.

INV-01: CÒN ĐÚNG — blockStatusOf là nguồn DUY NHẤT cho trạng thái block ở mọi nơi hiển thị; markBlockPassed chỉ tăng khi blockIndex khớp completedBlocks hiện tại — mobile/lib/features/exercise/session_controller.dart:82, mobile/lib/features/exercise/block_list_screen.dart:66, mobile/lib/features/exercise/block_list_screen.dart:93
INV-02: CÒN ĐÚNG — cell_screen truyền đúng knownIdentifiersFor(exercise, blockIndex) + block.vocab vào CodeInput cho MỌI exercise trong seed (kiểm bằng tay 5/5 exercise: split-chunks, overlap-chunks, clean-text, save-document, like-post) — mobile/lib/features/exercise/cell_screen.dart:227, mobile/lib/features/exercise/cell_screen.dart:251, mobile/lib/features/exercise/session_controller.dart:288
INV-03: CÒN ĐÚNG — test tạm gõ tay qua CodeInput thật (auto-close, overtype, Enter sau ':' tự thụt 4) cho block 2 dòng overlap-chunks-b2 → runBlock trả passed=true, xác nhận bằng lệnh `flutter test` (đã xoá file test) — mobile/lib/domain/answer_checker.dart:26, mobile/lib/domain/answer_checker.dart:68, mobile/lib/features/exercise/code_input.dart:315
INV-04: CÒN ĐÚNG — `grep -rn "Color(0x" lib/features lib/shared lib/main.dart` không có kết quả; AppColors.accent chỉ xuất hiện ở theme.dart, cell_screen hint sheet, và HintButton — mobile/lib/app/theme.dart:14, mobile/lib/features/exercise/cell_screen.dart:88, mobile/lib/shared/widgets.dart:342
INV-05: CÒN ĐÚNG — test tạm mô phỏng idle→timedOut→auto-pop→mở lại Cell qua router thật: draft "for i in ra" còn nguyên trong CodeInput lúc mở lại, và session reset elapsed=0/phase=active (khớp thiết kế start() idempotent chỉ reset sau timedOut) — mobile/lib/features/exercise/session_controller.dart:94, mobile/lib/features/exercise/session_controller.dart:167, mobile/lib/features/exercise/cell_screen.dart:249

## Chi tiết / bằng chứng

### INV-01
- `blockStatusOf` (session_controller.dart:276) là hàm suy trạng thái DUY NHẤT; grep toàn bộ `lib/features` không có nơi nào tự so sánh `completedBlocks` để suy done/active/locked theo per-block (Home/Topic detail dùng `completedBlocks`/`total` cho khái niệm KHÁC — trạng thái toàn bộ exercise "Mới/Đang dở/Đã xong", không đụng INV-01 vốn nói về per-block).
- `markBlockPassed` (session_controller.dart:82-91) guard `if (blockIndex != current.completedBlocks) return;` — chống Run muộn/Run sai thứ tự tăng nhầm tiến độ.
- `app_flow_test.dart` (168/168 test pass, `flutter test` chạy full) đã tự động hoá đúng kịch bản "vỡ thì thấy gì": Run đúng B3 (index 2) ở Cell → quay Block list → block-card-3 (B4) không còn `Opacity` mờ, không còn text "Mở khoá sau Block 3".

### INV-02
- Duyệt tay knownIdentifiersFor cho split-chunks (b3: known = text,size,chunks,i — đúng vocab `append/chunks/text`), overlap-chunks (b2: known = text,size,overlap,chunks — đúng vocab `range,overlap,append`), clean-text/save-document/like-post (mỗi exercise 1-2 block, không có biến trung gian, known chỉ gồm params — đúng).
- Giới hạn phát hiện (KHÔNG phải vi phạm INV-02 theo đúng chữ của INV, chỉ là khoảng trống UX): với block 2 dòng CÙNG một block (vd overlap-chunks-b2 `for i in ...:` rồi dòng 2 dùng lại `i`), biến `i` sinh ra ở dòng 1 của CHÍNH block đó không nằm trong `knownIdentifiersFor` (hàm chỉ quét acceptedAnswers[0] của các block TRƯỚC blockIndex) và cũng không có trong `vocab` của block đó (`['range','overlap','append']`, seed.dart dòng block overlap-chunks-b2). Đã in ra bằng test tạm: `knownIdentifiers at block index 2: [text, size, overlap, chunks]` — không có `i`. Người học gõ `i` ở dòng 2 sẽ không thấy gợi ý, phải gõ tay 1 ký tự — không chặn được INV-03 (đã kiểm, xem dưới), chỉ là UX kém hơn thiết kế autocomplete "khỏi nản" nhắm tới. Đề xuất (không bắt buộc, ngoài scope sửa ngay): thêm `i` vào vocab của các block 2 dòng dùng biến lặp từ dòng trước trong cùng block.

### INV-03
Test tạm (`mobile/test/_seam_probe_test.dart`, đã xoá sau khi chạy — `git status --porcelain` xác nhận sạch) gõ tay qua editor thật (không giả lập chuỗi cuối):
```
for i in range(0, len(text), size - overlap):    (gõ ký tự, auto-close (), [] hoạt động)
\n                                                 → tự thụt "    " (IndentModifier)
chunks.append(text[i:i + size])                   (gõ ký tự, auto-close [] + overtype ']')
```
Kết quả: `runBlock(finalText, block).passed == true`, `normalizeCode` của bản gõ tay khớp hệt `normalizeCode(acceptedAnswers.first)`. Cũng đã có sẵn trong repo `test/code_input_test.dart:166` ("end-to-end line 2 ... passes runBlock") phủ trường hợp tương tự cho split-chunks bằng cả suggestion tap + symbol key + gõ tay — 2 bằng chứng độc lập cho cùng loại block.

### INV-04
```
$ grep -rn "Color(0x" lib/features lib/shared lib/main.dart   → (không có kết quả)
$ grep -rn "AppColors.accent" lib                              → chỉ theme.dart, cell_screen.dart (Hint sheet), widgets.dart (HintButton)
```

### INV-05
Test tạm (`mobile/test/_seam_probe3_test.dart`, đã xoá) dựng app thật qua router (`SmartCodingStudyApp`), gõ draft `"for i in ra"` ở block split-chunks-b2, đẩy đồng hồ giả qua `idleThreshold + idleCountdown + 3s` → xác nhận:
- `CellScreen` tự pop (context.pop() trong `ref.listen` khi phase=timedOut), SnackBar "Đã lưu tiến độ" hiện ra.
- `progressProvider` giữ draft `"for i in ra"` sau khi pop (ProgressController KHÔNG autoDispose, sống qua SessionController autoDispose bị huỷ — đúng comment tại session_controller.dart:58-60).
- Mở lại Cell (cùng exerciseId/blockIndex qua block-list-continue-button): `CodeInput` hiện đúng `"for i in ra"` (initialCode = draft từ progress).
- `SessionController.start()` gọi lại lúc mount mới: vì `_timer` đã bị huỷ lúc timedOut (`_cancelTimer()` trong `_tick()`), `start()` đi nhánh reset toàn bộ → `elapsed=0, phase=active` (khớp thiết kế "đếm giờ cả bài" chỉ giữ nguyên khi phiên còn sống, reset khi đã timeout/thoát hẳn — không phải bug, là hành vi có chủ đích ghi trong docstring `start()`, session_controller.dart:161-166).

## Không kiểm được
- Không chạy app thật trên simulator/device (`flutter run`) — chỉ chạy `flutter analyze` + `flutter test` (168/168 pass) + 3 widget test tạm tự viết. Bước 3 của E2E trong PLAN.md (chụp màn Cell thật) không thuộc phạm vi reviewer mối nối, để orchestrator tự làm trước PR.
- Không kiểm exhaustive toàn bộ tổ hợp gõ tay (autocomplete tap + symbol key + gõ tay xen kẽ) cho tất cả 14 block trong seed — chỉ kiểm đại diện các dạng: block 1 dòng đơn giản (đã có test cũ), block 2 dòng có biến lặp nội bộ (overlap-chunks-b2, kiểm tạm), và luồng đủ end-to-end qua router thật (split-chunks-b2, app_flow_test.dart có sẵn + probe idle/timeout tạm).

Verdict: PASS
