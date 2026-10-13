# Design an Airline Reservation System

## Bối cảnh

### SkyBridge Air cần một hệ thống đặt vé

SkyBridge Air là hãng bay nội địa, mỗi ngày khai thác **200 chuyến**, mỗi chuyến khoảng 180 ghế. Hiện khách phải gọi tổng đài để đặt vé, và đã có ít nhất ba lần hai khách nhận cùng một ghế. Bạn được giao thiết kế hệ thống đặt vé trực tuyến.

### Yêu cầu chức năng

- Tìm chuyến theo ngày, điểm đi và điểm đến.
- Giữ ghế 10 phút trong lúc thanh toán.
- Thanh toán và xuất vé điện tử.
- Huỷ vé và hoàn tiền.

### Yêu cầu phi chức năng

- Tìm chuyến p99 dưới 300ms.
- Không bao giờ bán trùng một ghế.
- Sẵn sàng 99.95%.
- Chịu tải đỉnh gấp 10 lần ngày thường.

### Quy mô

| Chỉ số | Giá trị |
| --- | --- |
| Lượt tìm chuyến/ngày | 1.000.000 |
| QPS tìm chuyến (đỉnh) | 120 |
| Lượt đặt vé/ngày | 30.000 |
| QPS ghi (đỉnh) | 5 |

> Ngoài phạm vi: khách hàng thân thiết, đổi lịch nhiều chặng, định giá động.

## Đề bài và yêu cầu

### Problem Description

Hãng bay có 200 chuyến/ngày, mỗi chuyến khoảng 180 ghế. Khách tìm chuyến, giữ ghế, thanh toán rồi nhận vé điện tử.

#### Thách thức 1: hai người cùng đặt ghế cuối

> Double booking: hai khách bấm đặt ghế 14C trong cùng một giây. Chỉ một người được giữ ghế, người còn lại phải nhận thông báo rõ ràng, không bị trừ tiền.

#### Thách thức 2 và 3

- Giữ ghế trong lúc thanh toán (10 phút), hết hạn thì nhả ghế.
- Tiền đã trừ nhưng vé chưa gửi: hai việc này phải khớp nhau dù hệ thống lỗi giữa chừng.

### Requirements

#### Hai nhóm yêu cầu

| Functional | Non-functional |
| --- | --- |
| Tìm chuyến theo ngày, điểm đi/đến | Tìm chuyến p99 dưới 300ms |
| Giữ ghế 10 phút | Không bao giờ bán trùng một ghế |
| Thanh toán và xuất vé | Sẵn sàng 99.95% |
| Huỷ vé, hoàn tiền | Chịu tải đỉnh gấp 10 lần ngày thường |

#### Ngoài phạm vi

Chương trình khách hàng thân thiết, đổi lịch bay nhiều chặng, và định giá động không nằm trong bài này.

> Mẹo phỏng vấn: nói to yêu cầu "không bán trùng ghế" trước khi vẽ gì. Nó quyết định gần như toàn bộ phần database.

### Traffic & Data Estimation

| Chỉ số | Giá trị |
| --- | --- |
| Lượt tìm chuyến/ngày | 1.000.000 |
| QPS tìm chuyến (trung bình / đỉnh) | 12 / 120 |
| Lượt đặt vé/ngày | 30.000 |
| QPS ghi (đỉnh) | 5 |

```text
1.000.000 / 86.400 s = 11,6 QPS
đỉnh = 10 x 11,6 = ~120 QPS
200 chuyến x 180 ghế = 36.000 ghế/ngày
```

> Dữ liệu nhỏ, ghi ít. Một Postgres đủ sức; cái khó là tranh chấp trên cùng một dòng ghế, không phải dung lượng.

## Dữ liệu và API

### API Endpoints

#### Tìm chuyến

```http
GET /flights?from=SGN&to=HAN&date=2026-11-02
200 OK  { "flights": [ { "id": "VN123", "seats_left": 42 } ] }
```

#### Giữ ghế

```http
POST /holds   { "flight_id": "VN123", "seat": "14C" }
201 Created   { "hold_id": "h_81", "expires_in": 600 }
409 Conflict  { "error": "seat_taken" }
```

#### Đặt vé

```http
POST /bookings   Idempotency-Key: 7c1e
{ "hold_id": "h_81", "payment_token": "tok_9" }
201 Created      { "booking_id": "b_204" }
```

### Database Schema

| Bảng | Cột quan trọng |
| --- | --- |
| flights | id, origin, dest, departs_at |
| seats | flight_id, seat_no, status, version |
| holds | id, seat_id, user_id, expires_at |
| bookings | id, hold_id, status, idempotency_key |

```sql
CREATE TABLE seats (
  flight_id TEXT NOT NULL,
  seat_no   TEXT NOT NULL,
  status    TEXT NOT NULL DEFAULT 'free',
  version   INT  NOT NULL DEFAULT 0,
  PRIMARY KEY (flight_id, seat_no)
);
```

> Chặn bán trùng ở tầng database: UPDATE seats SET status='held' WHERE ... AND status='free'. Chỉ một câu lệnh thấy 1 dòng bị đổi.

## Kiến trúc

### System Architecture

```text
Client -> Booking Service -> Postgres (bookings + outbox, một transaction)
                         \-> Payment
Outbox Relay (poll 1s) -> Broker -> Notification
```

#### Luồng dữ liệu khi đặt vé

- Client gọi POST /holds, Booking Service đổi ghế sang held.
- Client trả tiền, Payment xác nhận.
- Booking ghi vé và một dòng outbox trong cùng một transaction.
- Relay đẩy sự kiện sang Broker, Notification gửi vé.

> Vì sao có Outbox: ghi vé và gửi sự kiện là hai hệ thống khác nhau. Outbox biến hai việc đó thành một lần ghi duy nhất, nên không có chuyện "có vé mà không có email".

### Detailed Components

#### Booking Service

Việc: giữ ghế, tạo vé, nhả ghế hết hạn. Công nghệ: Python và Postgres, một transaction cho mỗi lần đặt.

#### Outbox Relay

Việc: đọc dòng outbox chưa gửi, đẩy sang Broker, đánh dấu đã gửi. Công nghệ: worker poll mỗi 1 giây, gửi lại nếu lỗi.

#### Hold Expirer

Việc: mỗi 30 giây nhả các ghế held quá 10 phút. Công nghệ: job định kỳ, chạy được nhiều bản nhờ FOR UPDATE SKIP LOCKED.

## Đánh đổi và sự cố

### Design Trade-offs

#### Khoá ghế: hai cách

| | Optimistic | Pessimistic |
| --- | --- | --- |
| Cách làm | Đọc version, ghi nếu chưa đổi | SELECT ... FOR UPDATE |
| Hợp khi | Ít tranh chấp | Nhiều người tranh một ghế |
| Nhược | Thua thì phải thử lại | Giữ khoá, dễ nghẽn |

> Chọn optimistic cho ghế thường. Ghế sát cửa thoát hiểm hay hết nhanh, nhưng 5 QPS ghi vẫn đủ thấp để thử lại không đáng kể.

#### Đã bỏ: lưu ghế trong Redis

Nhanh hơn, nhưng thêm một nguồn sự thật thứ hai phải đồng bộ với Postgres. Với 5 QPS ghi, lợi ích không đáng với rủi ro lệch dữ liệu.

### Failure Scenarios

| Sự cố | Hậu quả | Xử lý |
| --- | --- | --- |
| Trả tiền xong, service chết | Có tiền, chưa có vé | Idempotency-Key và job đối soát |
| Broker chết | Không gửi được vé | Outbox giữ sự kiện, gửi lại |
| Hold hết hạn lúc đang trả tiền | Ghế bị người khác lấy | Kiểm lại hold khi xác nhận, hoàn tiền |

> Nếu Payment báo timeout thì đã trừ tiền chưa? Không đoán: hỏi lại bằng cùng Idempotency-Key.

## Thực chiến

### API Design

Đề: Phác các endpoint chính cho luồng tìm chuyến, giữ ghế và đặt vé. Với mỗi endpoint nêu method, request, response và mã lỗi quan trọng.

Gợi ý:
- Đặt vé là thao tác ghi. Nếu client gọi lại hai lần thì sao?
- Hai người cùng giữ một ghế thì người sau nhận mã lỗi gì?
- Tìm chuyến trả về nhiều kết quả: lọc theo gì?

Rubric:
- Có endpoint giữ ghế (hold) tách riêng khỏi đặt vé :: hold, giữ ghế
- Đặt vé dùng Idempotency-Key để gọi lại không bị trừ tiền hai lần :: idempoten
- Ghế đã bị giữ trả 409 Conflict :: 409, conflict
- Tìm chuyến lọc theo ngày, điểm đi, điểm đến :: date, ngày, from, origin

Đáp án mẫu: API Endpoints

### Database Design

Đề: Vẽ các bảng chính, khoá chính, và cách database tự chặn bán trùng một ghế.

Gợi ý:
- Một ghế là một dòng hay nhiều dòng?
- Cột nào cho biết ghế giữ hết hạn lúc nào?
- Chặn trùng bằng ràng buộc hay bằng code ứng dụng?

Rubric:
- Có bảng seats, mỗi ghế một dòng :: seats, seat
- Giữ ghế có thời điểm hết hạn :: expire, hết hạn
- Chặn trùng bằng version, unique hoặc UPDATE có điều kiện :: version, unique, điều kiện
- Có bảng bookings :: booking

Đáp án mẫu: Database Schema

### High Level Architecture

Đề: Vẽ các thành phần chính và nói luồng dữ liệu khi khách đặt vé.

Gợi ý:
- Ghi vé và gửi email là hai hệ thống khác nhau. Ghép chúng thế nào?
- Phần nào chịu tải đọc 120 QPS?

Rubric:
- Có Booking Service :: booking
- Có database làm nguồn sự thật :: postgres, database, db
- Gửi sự kiện qua outbox hoặc queue :: outbox, broker, queue, kafka
- Payment là thành phần riêng :: payment, thanh toán

Đáp án mẫu: System Architecture

### Detailed Components Design

Đề: Chọn hai thành phần quan trọng nhất và mô tả chi tiết cách chúng hoạt động.

Gợi ý:
- Ghế giữ quá 10 phút thì ai nhả?
- Nhiều bản worker chạy cùng lúc có xử lý một dòng hai lần không?

Rubric:
- Có job nhả ghế hết hạn :: expir, nhả, hết hạn
- Nhiều worker chạy an toàn :: skip locked, for update, lock, khoá
- Relay gửi lại khi lỗi :: retry, gửi lại, thử lại
- Đặt vé nằm trong một transaction :: transaction

Đáp án mẫu: Detailed Components

### Trade-off Discussion

Đề: Nêu hai quyết định thiết kế, phương án bạn bỏ, và vì sao.

Gợi ý:
- Optimistic hay pessimistic locking?
- Có nên đưa trạng thái ghế vào Redis?

Rubric:
- Nói về optimistic locking :: optimistic
- So với pessimistic locking :: pessimistic
- Nêu phương án đã bỏ :: redis, cache
- Lý do dựa trên số liệu :: qps, tải, số liệu

Đáp án mẫu: Design Trade-offs

### Failure Scenario Discussion

Đề: Liệt kê các sự cố có thể xảy ra, hậu quả và cách xử lý.

Gợi ý:
- Trả tiền xong thì service chết.
- Broker chết hoặc chậm.
- Hold hết hạn đúng lúc khách đang trả tiền.

Rubric:
- Trả tiền xong mà mất vé: idempotency hoặc đối soát :: idempoten, đối soát, reconcil
- Broker chết: outbox giữ sự kiện :: outbox
- Hold hết hạn lúc đang trả tiền: hoàn tiền :: hoàn tiền, refund
- Có timeout hoặc retry :: timeout, retry, thử lại

Đáp án mẫu: Failure Scenarios
