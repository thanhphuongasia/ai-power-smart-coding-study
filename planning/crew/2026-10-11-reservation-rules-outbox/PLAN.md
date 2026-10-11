# Run `reservation-rules-outbox` — nghiệp vụ đặt chỗ có edge case, Notifier, Outbox dùng chung 2 project

## Context

User muốn module Reservation của Airline có **method nghiệp vụ thật** (đổi vé, huỷ phải trước 24h bay,
tăng/giảm số vé kèm hoàn tiền), một **Notifier**, và bài **fault tolerance** chỉ rõ khi nào cần
**outbox pattern** — bài này dùng chung nhiều project. Hiện Reservation chỉ có `BookingService.book/cancel`
(không có giờ bay, giá) và `SeatMap.assign_seat`.

Ràng buộc nội dung có sẵn (mobile/test/content_contract_test.dart + loader): ≤3 ô/bài, đáp án ≤2 dòng,
3 hint, marker = 4×indent_level, ghép accepted_answers[0] == judge.solution, không code chết sau return,
ví dụ challenge gọi tên method/class, sơ đồ class khớp code (INV-02/03 của run trước). Judge chạy thật
trên Judge0 bằng case kịch bản `{steps, call, expect{return|raises}}`.

Git: thẳng trên main (memory work-directly-on-main), push + deploy sau seam gate.

## Quyết định thiết kế

1. **Không sửa bài cũ**. Thêm class mới `ReservationService` ở file mới `services/reservation_service.py`
   (module `airline-reservation`), mô hình đầy đủ hơn BookingService: mỗi đặt chỗ có `flight_code`,
   `seats`, `price` (giá/ghế lúc mua), chuyến có `departure` (datetime) và số ghế trống.
   **Thời gian luôn truyền vào** (`now: datetime`), không gọi `datetime.now()` → judge xác định.
2. **Luật nghiệp vụ** (trình duyệt):
   - `cancel(rid, now)`:
     - mã không có / đã huỷ → `ValueError`;
     - còn **< 24 giờ** trước giờ bay (kể cả đã bay) → `ValueError("Chỉ được huỷ trước giờ bay 24 tiếng")`;
       đúng 24 giờ vẫn được huỷ;
     - huỷ được → trả ghế về chuyến, xoá đặt chỗ, **trả về số tiền hoàn = seats × price**.
   - `change_seats(rid, new_seats, now)`, trả về số tiền: **dương = khách trả thêm, âm = hoàn tiền, 0 = không đổi**:
     - `new_seats < 1` → `ValueError` (muốn bỏ hết thì dùng cancel); chuyến đã bay → `ValueError`;
     - **tăng**: cần đủ ghế trống, thiếu → `ValueError` và không đổi gì; trả `+diff × price`;
     - **giảm**: chỉ khi còn **≥ 24 giờ**, nếu không → `ValueError` (giảm sát giờ không hoàn tiền); trả `−diff × price`.
   - `change_flight(rid, new_flight, now)` (khách đổi sang chuyến khác):
     - phải còn ≥ 24 giờ trước giờ bay **chuyến cũ**;
     - chuyến mới không có hoặc thiếu ghế → `ValueError`, không đổi gì;
     - chuyển ghế sang chuyến mới; trả **chênh lệch giá** `seats × (giá mới − giá cũ)` (dương thu thêm, âm hoàn).
   - `Notifier.notify(event)` (sub-module `airline-notification`, `notifications/notifier.py`):
     - event `{"id", "type", "reservation", "amount"}`; render theo `type` (`cancelled`, `seats_changed`,
       `flight_changed`); type lạ → `ValueError`;
     - **chống gửi trùng**: `id` đã gửi → trả `False`, không gửi lại (vì outbox giao "ít nhất một lần");
       gửi mới → thêm vào `sent`, trả `True`.
   - **Outbox** (module mới `airline-reliability` "Reliability — chịu lỗi", file `reliability/outbox.py`):
     - `Outbox.save_with_event(key, value, event)`: ghi trạng thái **và** sự kiện cùng một lần —
       event thiếu `id`/`type` → `ValueError` và **không ghi gì** (giả lập một transaction);
     - `OutboxRelay.relay()`: đẩy `pending` lần lượt qua `broker.publish` (Broker giả lập nằm sẵn trong
       template, có thể "sập" ở event chỉ định); thành công mới xoá khỏi pending; gặp lỗi thì **dừng**,
       giữ nguyên event lỗi và các event sau để lần sau thử lại, **giữ thứ tự**; trả số event đã đẩy.
     - Challenge nêu rõ **khi nào cần outbox**: huỷ vé ghi DB rồi mới gửi thông báo/hoàn tiền; app sập
       giữa hai bước thì mất thông báo, còn gửi trước rồi commit lỗi thì thông báo "ma".
3. **Dùng chung 2 project**: file `reliability/outbox.py` (cùng tên, **cùng exercise id**) nằm ở Airline
   (module Reliability) **và** Twitter feed (module mới `feed-reliability`; ví dụ: like/đăng bài xong mới báo
   follower). App sẽ hiện nhãn "Dùng ở 2 theme" như `chunker.py`.
4. **Sơ đồ class**:
   - Airline thêm `ReservationService`, `Notifier`, `Outbox`, `OutboxRelay`, `Broker`, cùng các quan hệ:
     - ReservationService → Notifier (association, qua cancel / change_*);
     - ReservationService → Outbox (association, ghi sự kiện);
     - OutboxRelay ◇ Outbox (aggregation);
     - OutboxRelay → Broker (association);
     - Notifier ⇢ … (nhãn ghi rõ phần nào là thiết kế).
   - Twitter feed: sơ đồ có `Outbox`, `OutboxRelay`, `Broker` (bắt buộc theo INV-03).
5. **6 bài mới**:
   - reservation-cancel, reservation-change-seats, reservation-change-flight;
   - notifier-notify;
   - outbox-save, outbox-relay.

   Mỗi bài 2–3 ô, 5–7 case, có case biên (đúng 24h, 23h59, đã bay, thiếu ghế không đổi gì, trùng
   event id, broker sập giữa chừng rồi thử lại).

## Sổ bất biến

```text
INV-01 · Mọi bài mới qua luật nội dung: ≤3 ô, ≤2 dòng/đáp án, 3 hint, ghép đáp án == judge.solution, marker = 4×indent_level, không code chết sau return
         phải khớp: backend/content/content.json · mobile/test/content_contract_test.dart · mobile/lib/domain/merge.dart
         vỡ thì thấy gì: người học gõ đúng vẫn bị chấm sai / test hợp đồng đỏ
INV-02 · Judge xác định: lời giải mẫu pass trên harness, thân `pass` thì fail; không datetime.now()/random trong solution hay case
         phải khớp: backend/content/content.json · backend/app/harness.py · backend/tests/test_harness.py
         vỡ thì thấy gì: kết quả Run đổi theo ngày giờ chạy; bài pass ngẫu nhiên
INV-03 · Sơ đồ class khớp code ở CẢ Airline và Twitter feed; mọi bài method có class trong sơ đồ theme chứa nó
         phải khớp: backend/content/content.json (themes[*].diagram) · mobile/test/content_contract_test.dart · backend/app/load_content.py
         vỡ thì thấy gì: tab Challenge thiếu sơ đồ ở Twitter, hoặc sơ đồ có member không tồn tại
INV-04 · Bài dùng chung: reliability/outbox.py cùng tên + cùng exercise id ở 2 theme → cross-cut "Dùng ở 2 theme"; khoá/mở theo file độc lập
         phải khớp: backend/content/content.json · mobile/lib/domain/content.dart (locateFilesNamed) · mobile/lib/domain/progression.dart
         vỡ thì thấy gì: không hiện nhãn dùng chung, hoặc bài ở theme thứ 2 bị khoá sai
INV-05 · Bài cũ và số đếm: BookingService/SeatMap/Flight không đổi; test cũ xanh; các số đếm (16 → 22 bài, 11 → 17 bài method) cập nhật đúng
         phải khớp: backend/tests/test_load_content.py · mobile/test/content_contract_test.dart · backend/content/content.json
         vỡ thì thấy gì: test đếm đỏ; bài cũ đổi hành vi
```

## Task (owned files PHẢI có diff; forbidden = ngoài owned; evidence = `git diff --stat -- <owned>`)

| ID | Role · tier · model | Mục tiêu | Owned files | Validation |
|---|---|---|---|---|
| T-01 | `crew-impl-standard` · T2 · sonnet | ReservationService: cancel / change_seats / change_flight + sơ đồ Airline cho class này + cập nhật số đếm | `backend/content/content.json`, `backend/tests/test_load_content.py`, `mobile/test/content_contract_test.dart` | `cd backend && .venv/bin/python -m pytest -q && cd ../mobile && flutter test test/content_contract_test.dart` |
| T-02 | `crew-impl-standard` · T2 · sonnet | Notifier.notify + Outbox.save_with_event + OutboxRelay.relay; module Reliability ở Airline + Twitter (cross-cut); sơ đồ 2 theme; số đếm | (như T-01, chạy SAU T-01 vì chung content.json) | như T-01 + `flutter test` toàn bộ |

Thứ tự: T-01 → commit checkpoint → T-02 → commit. Review: `crew-review` mỗi task (góc nhìn giáo viên
+ tester: luật đúng, case biên bắt được lời giải sai hợp lý). Reviewer mối nối INV-01..05 → `verify-seam.sh`
→ push + deploy. Không có thay đổi code app/backend (chỉ nội dung + test) → không cần external review L4.

## Verification (e2e — orchestrator tự chạy)

1. `pytest -q`, `flutter test`, `flutter analyze`.
2. Deploy; `/run` lời giải mẫu 6 bài mới → passed; một lời giải sai cố ý (huỷ khi còn 23h) → failed.
3. Chrome: Home → Airline → Reservation → `reservation_service.py` (lộ trình 3 nút) → bài cancel: tab
   Challenge có sơ đồ ReservationService. Airline → Reliability → `reliability/outbox.py`.
4. **Mối nối cũ/chung**: Twitter feed → Reliability → `reliability/outbox.py` có nhãn "Dùng ở 2 theme";
   bài `like-post` cũ vẫn Run passed; `booking-book` vẫn passed.

## Rủi ro / giới hạn

- Mỗi bài vẫn là bản rút gọn độc lập (ReservationService không gọi Notifier thật trong code mẫu); sơ đồ
  ghi quan hệ thiết kế, nhãn nói rõ.
- Outbox giả lập transaction trong bộ nhớ, không có DB thật; challenge nói rõ phần "thật" sẽ là cùng
  transaction DB.
- Luật 24h/hoàn tiền là chính sách mẫu (không theo hãng cụ thể).
