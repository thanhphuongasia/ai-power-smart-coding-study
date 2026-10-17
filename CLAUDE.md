# AI-power smart coding study

Ôn lại lập trình qua bài tập nhỏ: đọc đề, viết vài dòng, chạy, xem kết quả ngay.

## Cấu trúc

- `mobile/` — Flutter app (web + iOS), giao diện học viên + admin.
- `backend/` — FastAPI + Postgres (alembic), judge chạy test, nội dung bài tập.
- `deploy/` — script triển khai lên VPS (`deploy.sh`), cấu hình nginx/systemd.

## Git workflow — PR vào `dev`, không vào `main`

**`main` tự động deploy lên production** mỗi khi có commit mới (xem mục Deploy bên
dưới). Vì vậy:

- Mọi PR (branch mới, qua `/crew`, hay tự tay) nhắm **`dev`**, không nhắm `main`.
- `main` chỉ nhận code qua **merge PR `dev` → `main`** — đây là hành động "đẩy lên
  production", phải làm có chủ đích, không phải tác dụng phụ của việc merge một PR
  tính năng bình thường.
- Trước khi merge `dev` → `main`: CI xanh, và tốt nhất đã chạy `flutter test` sạch ở
  `dev`.

### Vì sao luật này tồn tại

Sự cố 2026-10-13: Claude chạy `deploy/deploy.sh` thủ công từ một checkout local đã cũ
(chưa `git fetch`), ghi đè code production bằng bản thiếu migration mới nhất (`0007`)
→ `alembic upgrade head` fail giữa chừng, backend/web trên server tạm thời lệch nhau.
Nguyên nhân gốc: trước đó không có nhánh trung gian nào — mọi PR merge thẳng vào
`main`, tự động deploy ngay, không có bước "integration" trước khi đụng production.

Thêm `dev` không tự nó chặn được lỗi "checkout cũ" (vẫn phải `git fetch` đúng lúc), mà
tách rõ hai việc: "merge code" (vào `dev`, rủi ro thấp — code ở đó không tự chạy đâu cả)
và "đẩy production" (merge `dev` → `main`, luôn là một quyết định rõ ràng, dễ kiểm
`git fetch origin main` ngay trước khi bấm merge).

## Deploy — `main` tự động đẩy lên VPS qua GitHub Actions

Workflow `.github/workflows/deploy.yml` ("Deploy VPS") chạy `deploy/deploy.sh` **mỗi
khi có push vào `main`** (kể cả merge PR) — build Flutter web, rsync backend + web lên
VPS, chạy `alembic upgrade head`, restart service, smoke test qua nginx. Theo dõi tiến
trình: `gh run list --workflow="Deploy VPS"`.

**Không tự chạy `deploy/deploy.sh` từ máy local**, trừ khi cả hai điều sau đều đúng:

1. Workflow GitHub Actions đang thật sự hỏng (kiểm bằng `gh run list`, đừng đoán).
2. Đã `git fetch origin main` rồi build/deploy đúng từ `origin/main` mới nhất — KHÔNG
   chạy từ branch feature cũ hay local `main` chưa fetch. Đây đúng là lỗi đã gây sự cố
   ở trên.

Muốn deploy lại thủ công mà không chắc trạng thái máy local: dùng
`gh workflow run "Deploy VPS" --ref main` — kích hoạt lại đúng pipeline có sẵn, build
từ commit thật trên GitHub, không phụ thuộc máy local đang ở branch/commit nào.

Migration mới (`backend/migrations/versions/NNNN_*.py`) merge vào `main` ở PR nào thì
PR đó đã tự kéo theo deploy — không cần bước thủ công riêng cho alembic.
