# Đầu vào từ ngoài vào parser/validator: có trần và test thời gian ngay lần đầu

## Vì sao (bằng chứng, 2 lần trong repo này)

- Run `2026-10-11-users-progress-admin`: CPU không giới hạn, vá từng lớp, hết 3 vòng review L4.
- Run `2026-10-12-system-design-mode`, parser markdown nhận file ≤1MB (`backend/app/sd/parser.py`):
  - Vòng 1: `_unique` dò hậu tố từng bước. 60KB card trùng nhau mất 27 giây, 1MB không xong.
  - Vòng 2: regex heading lồng nhau `(.+?)[ \t]*#*[ \t]*$` chạy bậc ba. `# a` cộng 4000 khoảng trắng mất 40 giây.
    Dòng tiếp nối của rubric và gợi ý nối chuỗi bậc hai, và vượt trần độ dài đã khai.
  - Mỗi vòng reviewer chỉ một chỗ, bản vá sửa đúng chỗ đó và bỏ sót chỗ cùng họ.

Một request quản trị 1MB là đủ để một thread giữ GIL hàng chục giây; cả API (cả học viên) chậm theo.

## Luật

1. **Trần kiểm TRƯỚC khi tích luỹ.** Nối chuỗi, thêm vào list, dedupe: kiểm độ dài/số lượng của phần sắp thêm
   rồi mới thêm, và dừng sớm khi vượt. Không dựng hết rồi mới kiểm ở cuối.
2. **Không regex có hai lượng từ liền kề trên cùng một lớp ký tự** (vd `.+?` rồi `[ \t]*`, hoặc `[ \t]*\|?[ \t]*`).
   Viết bằng cắt chuỗi hoặc một lượt quét; regex chỉ neo `^` và không lồng nhóm lặp.
3. **Dedupe/đếm bằng dict/set**, không `x in list` và không dò từng bước để tìm tên chưa dùng.
4. **Một test thời gian cho đầu vào xấu nhất ≤ giới hạn kích thước**, ngưỡng <1 giây, cho MỖI vòng lặp và regex trên
   đường vào: một dòng cực dài, 250k dòng ngắn, ký tự lặp (`|`, `>`, `-`, `#`, khoảng trắng, tab), khối trùng nhau,
   Unicode tổ hợp, danh sách rất dài. Test phải đỏ khi đưa lại bản chậm.
5. **Có trần tổng cho đầu ra** (số card, kích thước JSONB), không chỉ trần từng phần.
6. Tên/định danh sinh từ văn bản người dùng: chuẩn hoá Unicode NFC ở cổng vào trước khi băm hoặc tạo slug.

## Giới hạn

Không có script kiểm tự động; reviewer L4 phải tự đo trên bản sao ngoài git (đã thành thông lệ của run
`system-design-mode`). Trần cụ thể của parser SD nằm ở đầu `backend/app/sd/parser.py`.
