# Decisions

## Vì sao khoá cấu trúc này

File này lưu các quyết định tiền đề (premise decisions) — lựa chọn có cân nhắc đánh đổi, chọn
một hướng và bỏ hướng khác, không phải mô tả "hệ thống hôm nay trông thế nào" (đó là việc của
`docs/ARCHITECTURE.md` và `docs/modules/*.md`). Tách riêng vì lý do chọn một hướng thường sống
lâu hơn bản thân code — code có thể đổi, nhưng câu hỏi "sao lúc đó không chọn X" vẫn cần trả lời
được nhiều tháng sau. File này **append-only**: chỉ thêm mục mới, hoặc sửa mục đã sai vì code đã
đổi (kèm commit ref) — không viết lại cho gọn.

## Cách áp dụng

Đọc lúc thiết kế feature mới trong cùng khu vực (đặc biệt là phase 2 của app mobile) để biết
những lựa chọn đã cân nhắc và bị bỏ — tránh đề xuất lại một hướng đã bị bác mà không biết vì sao.
Đọc trước khi quyết định "có nên thêm lại gói X đã bỏ ở phase 1 không".

## Giới hạn đã biết

File này không phải audit trail đầy đủ mọi lựa chọn nhỏ trong run — chỉ chưng cất các quyết định
có đánh đổi thật, đủ quan trọng để người sau cần biết trước khi đổi hướng.

## Nội dung

### Bỏ Dio/Retrofit/get_it/injectable ở phase 1 mobile app

**Quyết định**: không thêm các gói HTTP client (Dio/Retrofit) và dependency injection
(get_it/injectable) vào `mobile/pubspec.yaml` ở phase 1.

**Vì sao**: chưa có backend thật để gọi (toàn bộ nội dung bài học là seed tĩnh trong
`mobile/lib/data/seed.dart`), và Riverpod (đã dùng cho state management) đã đảm nhiệm việc
inject dependency (vd `clockProvider` bơm đồng hồ giả cho test) — thêm get_it/injectable là
một tầng DI thứ hai không cần thiết.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/PLAN.md, mục "Quyết định", điểm 2;
mobile/pubspec.yaml:33-42 (danh sách dependencies thật).

**Còn đúng tới khi nào**: tới khi phase 2 (issue #5, backend thật) quyết định app cần gọi API —
lúc đó phải quyết định lại có đưa Dio/Retrofit trở lại hay dùng `http` package đơn giản hơn.

### Bỏ Hive (lưu tiến độ qua restart) ở phase 1

**Quyết định**: tiến độ làm bài (block đã xong, draft code, hint đã dùng) chỉ sống trong bộ nhớ
Riverpod (`ProgressController`), không ghi xuống đĩa bằng Hive hay cơ chế nào khác.

**Vì sao**: phase 1 ưu tiên chứng minh UX màn làm bài (đặc biệt autocomplete) trước khi đầu tư
vào lưu trữ bền vững — mất tiến độ khi kill app là chấp nhận được cho một bản demo.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/PLAN.md, mục "Quyết định", điểm 2 và mục
"Phạm vi phase 1" (liệt kê Hive ở "Ngoài phạm vi").

**Còn đúng tới khi nào**: tới phase 2 (issue #5) — đã liệt kê Hive là việc cần làm ở đó.

### Run = so khớp đáp án đã chuẩn hoá, không chạy Python thật

**Quyết định**: nút Run trong màn Cell không thực thi code Python — nó chuẩn hoá code người học
gõ (`normalizeCode`) rồi so với danh sách `acceptedAnswers` viết sẵn trong seed cho từng block.

**Vì sao**: dựng sandbox chạy Python thật an toàn trên thiết bị di động (hoặc gọi server chấm
bài) là một hạng mục lớn, vượt phạm vi một app demo phase 1 tập trung vào UX làm bài.

**Đánh đổi đã chấp nhận**: cách viết đúng nhưng khác cấu trúc code với mọi `acceptedAnswers` đã
liệt kê sẽ bị chấm sai. Bù lại, `normalizeCode` đã bỏ qua khác biệt không quan trọng (khoảng
trắng thừa, nháy đơn/kép) để giảm bớt false negative do lỗi gõ vặt.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/PLAN.md, mục "Quyết định", điểm 3;
mobile/lib/domain/answer_checker.dart:11-90.

### Bundle font thay vì dùng gói `google_fonts`

**Quyết định**: hai font family (IBM Plex Sans, JetBrains Mono) được bundle sẵn dạng `.ttf`
trong `mobile/assets/fonts/` và khai trực tiếp trong `pubspec.yaml`, thay vì dùng gói
`google_fonts` như PLAN.md ban đầu định.

**Vì sao**: `google_fonts` tải font qua mạng lúc chạy lần đầu — test chạy trong môi trường
không có mạng (CI, sandbox) dễ fail, và đi ngược hướng "app hoạt động không cần mạng" mà phase 1
đang nhắm tới (không có backend).

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/DEVIATIONS.md, dòng đầu tiên ("Plan: giữ
`google_fonts`"); mobile/pubspec.yaml:64-76.

### Overtype/auto-close xử lý trong `set value` của controller, không trong `CodeModifier`

**Quyết định**: logic overtype (gõ trùng dấu đóng sẵn có thì nhảy qua thay vì chèn thêm) và xoá
cặp ngoặc rỗng được implement bằng cách override `set value` của một `CodeController` con
(`_PythonCodeController`), không phải bằng một `CodeModifier` như PLAN.md ban đầu định.

**Vì sao**: viết logic này trong `CodeModifier` khiến package `flutter_code_editor` (bên thứ ba)
tự ném `RangeError` khi modifier trả về text không đổi — đã thử và xác nhận lỗi trước khi đổi
hướng.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/DEVIATIONS.md, dòng "Plan: overtype qua
CodeModifier"; mobile/lib/features/exercise/code_input.dart:375-431.

### `start()` của session phải idempotent (không reset đồng hồ mỗi lần vào block mới)

**Quyết định**: gọi `SessionController.start()` nhiều lần trong cùng một phiên (vd từ
`initState` của mỗi block) không reset đồng hồ về 0, trừ khi phiên trước đó đã timeout hoặc
chưa từng khởi động.

**Vì sao**: thiết kế ban đầu (T-04) cho `start()` luôn reset — đúng theo contract của riêng
task đó. Khi ghép với T-06 (mỗi block gọi lại `start()` lúc mount màn hình), đồng hồ cả bài bị
nhảy về `00:00` mỗi lần chuyển block — lỗi mối nối giữa hai task đã review PASS riêng lẻ, phát
hiện và sửa bằng task hẹp T-04b.

**Nguồn**: planning/crew/2026-09-24-flutter-demo-core/STATUS.md, dòng "T-04b start() idempotent
(timer reset mỗi block — lỗi mối nối T-04↔T-06)";
mobile/lib/features/exercise/session_controller.dart:161-186.
