# mcp

> MCP server (`POST /mcp`) để Claude trên claude.ai đọc và tạo/sửa nội dung học; đăng nhập OAuth qua identity-service, backend chỉ là resource server; mọi lần ghi vào hàng chờ duyệt chung đường với admin PUT, admin duyệt thì học viên mới thấy.

## Là gì

Trước run này nội dung học chỉ sửa được qua màn Admin hoặc CLI. Module này cho phép người dùng chat với Claude trên claude.ai để tạo project, module, file và bài. Claude gọi 12 tool qua giao thức MCP (Model Context Protocol: chuẩn để chatbot gọi công cụ bên ngoài) tại `/mcp`. Backend không tự phát token và không giữ secret: người dùng đăng nhập GitHub ở identity-service (dịch vụ đăng nhập riêng của chủ repo, đã chạy cho các app khác), identity-service ký JWT (chuỗi token có chữ ký), còn backend chỉ kiểm chữ ký và kiểm xem tài khoản đó có được cấp quyền không. Quyền nằm ở bảng `mcp_access` và kiểm lại ở mỗi tool call, nên thu hồi có hiệu lực ngay dù JWT còn hạn. Mọi lần ghi dùng đúng khoá, cách so phiên bản và hàm `review.submit` của admin PUT: bản sửa chỉ vào hàng chờ duyệt (`content_changes`, xem `docs/modules/content-review.md`), không đổi nội dung học viên thấy tới khi admin duyệt trong app. Tool đọc và tool ghi đều làm việc trên bản nháp (nội dung đang chạy cộng các mục chờ), nên Claude tạo file rồi tạo bài trong file đó vẫn được dù file chưa duyệt.

## Dùng khi nào

Người dùng thêm connector `https://codewithphuong.jacons-corp.com/mcp` trên claude.ai (Customize, Connectors, Add custom connector, Connect), đăng nhập GitHub, rồi nhờ Claude soạn bài. Lần đầu tool báo `sub=… chưa được cấp quyền`; admin lấy `sub` đó và cấp bằng CLI trên VPS hoặc API admin. Đụng vào module này khi thêm tool mới (thêm hàm trong `content_ops.py` và một `@mcp.tool` trong `mcp_server.py`), đổi domain (phải đổi `PUBLIC_BASE_URL` và `AllowedResources` bên identity-service cùng lúc), hoặc đổi cách cấp quyền.

## Cách hoạt động

Luồng một request:

| Bước | Việc | Kết quả khi sai | file:dòng |
| --- | --- | --- | --- |
| 1 | `McpGate` nhận request trước SDK; chỉ nhận `POST` | GET/DELETE trả 405 `Allow: POST` (không mở luồng SSE treo worker) | backend/app/mcp_server.py:249-254 |
| 2 | `PUBLIC_BASE_URL` chưa đặt | 503 `mcp_not_configured` | backend/app/mcp_server.py:255-258 |
| 3 | `verify_bearer`: header `Bearer`, chữ ký RS256 theo `kid`, `iss`, `aud == <PUBLIC_BASE_URL>/mcp`, `exp` (leeway 30s) | 401 + `WWW-Authenticate: Bearer resource_metadata="…"` | backend/app/mcp_server.py:259-265, backend/app/mcp_auth.py:169-202 |
| 4 | Không tải được JWKS (khoá công khai) của identity-service và không còn khoá cũ dùng được | 503 `auth_unavailable`, không lẫn thành 401 (claude.ai coi 401 là token hỏng và bắt đăng nhập lại) | backend/app/mcp_server.py:266-269, backend/app/mcp_auth.py:89-90 |
| 5 | Claims đặt vào `ContextVar`, SDK xử lý JSON-RPC (stateless, JSON response) | | backend/app/mcp_server.py:270-274 |
| 6 | Mỗi tool gọi `authorize_sub`: `sub` phải có dòng `mcp_access` chưa thu hồi, và user đích còn role admin | tool trả lỗi kèm `sub` và lệnh cấp quyền | backend/app/mcp_server.py:69-78, backend/app/mcp_auth.py:205-218 |

Cổng 401 chạy trước SDK vì claude.ai chỉ hiện nút Connect khi thấy `resource_metadata` trên một 401. Discovery (RFC 9728, tài liệu mô tả "resource này tin authorization server nào") nằm ở `/.well-known/oauth-protected-resource` và `/.well-known/oauth-protected-resource/mcp`, trả `resource`, `authorization_servers = [IDENTITY_ISSUER]`, `scopes_supported = ["content"]` (backend/app/mcp_auth.py:221-236). Route `/mcp` là ASGI thô gắn thẳng vào router, không qua FastAPI (backend/app/main.py:64-66).

Chuỗi `<PUBLIC_BASE_URL>/mcp` phải giống nhau ở ba nơi: `resource` trong PRM, `aud` mà backend kiểm, và phần tử trong `OAuth2:AllowedResources` của identity-service. Lệch thì claude.ai báo `invalid_target` hoặc 401 mãi.

Cache JWKS tự viết thay vì dùng `PyJWKClient`, vì client có sẵn tải lại mỗi lần gặp `kid` lạ nên ai cũng ép được server gọi identity-service liên tục:

```python
want = age is None or age >= self._max_age or kid not in self._keys
may = self._last_attempt is None or now - self._last_attempt >= self._min_refresh
if want and may:
    self._try_refresh(now)
```
(backend/app/mcp_auth.py:141-145)

Mọi lần tải (thành công hay lỗi) cách nhau ít nhất 60s; khoá sống 1 giờ, identity chết thì dùng tiếp khoá cũ thêm tối đa 1 giờ (backend/app/mcp_auth.py:95-101).

Quyền cấp/thu hồi:

| Cách | Lệnh / endpoint | file:dòng |
| --- | --- | --- |
| Bảng | `mcp_access(sub PK, user_id → users, label, created_at, revoked_at)`; migration `0005_mcp_access.py` | backend/app/tables.py:187-201, backend/migrations/versions/0005_mcp_access.py:1 |
| CLI | `python -m app.mcp_access list`, `allow <sub> --as <email admin> [--label]`, `revoke <sub>` (không cần token, chạy trên VPS) | backend/app/mcp_access.py:97-134 |
| API admin | `GET/POST /api/admin/mcp-access`, `DELETE /api/admin/mcp-access/{sub}` (204; 404 nếu không có quyền đang hiệu lực) | backend/app/admin_api.py:136-178 |

`allow` từ chối email không phải admin, `sub` rỗng/dài hơn 100/có khoảng trắng; cấp lại `sub` đã thu hồi thì bỏ cờ thu hồi (backend/app/mcp_access.py:49-78).

12 tool (project = theme, module = topic, file = file code, lesson = bài):

| Nhóm | Tool | file:dòng |
| --- | --- | --- |
| Đọc | `list_projects`, `get_project`, `get_lesson`, `get_authoring_guide` (luật + một bài mẫu thật) | backend/app/mcp_server.py:132-183 |
| Ghi (đều có `dry_run`) | `create_project` (kèm module đầu), `update_project`, `create_module` (lồng được), `update_module`, `create_file`, `update_file`, `create_lesson`, `update_lesson` | backend/app/mcp_server.py:190-239 |

Không có tool xoá. Hàm biến đổi nội dung là hàm thuần (dict vào, dict ra, không đụng DB) ở `backend/app/content_ops.py`; lỗi nghiệp vụ là `ContentOpError` và được đổi thành `ToolError` để Claude đọc được.

Đường ghi dùng chung với admin PUT (vào hàng chờ, không ghi nội dung đang chạy):

```python
before = review.draft_content(session)
base = admin_version(before)
after = op(before)
errors = validation_errors(after)
...
author = f"mcp:{sub} ({user.email})" if user.email else f"mcp:{sub}"
result = review.submit(session, base, after, author)
```
(backend/app/mcp_server.py:96-116, rút gọn)

Luật nội dung được kiểm trước khi giữ khoá (nội dung sai không chặn ai); `review.submit` lấy `pg_advisory_xact_lock` (cùng khoá với admin PUT, xem `docs/modules/content-admin.md`), so `base` với hash bản nháp hiện tại, diff với nội dung đang chạy thành các mục và upsert dòng `pending` với `author = mcp:<sub> (<email>)` (backend/app/review.py:399-434). Vì `admin_version` (của bản nháp) đổi sau mỗi lần gửi, màn Admin đang cầm `base_version` cũ sẽ nhận 409 chứ không ghi đè bài của Claude. Tool trả `{ok, version, pending, message}` với câu "Đã gửi vào hàng chờ duyệt — admin cần duyệt trong app thì học viên mới thấy"; `dry_run` báo hợp lệ rồi hướng dẫn gọi lại để gửi vào hàng chờ. Gửi duyệt đổi cha của module có sẵn bị từ chối (`unsupported_move`) và đổi thành `ToolError` (backend/app/mcp_server.py:117-119). Lỗi validate trả tối đa 50 dòng (backend/app/mcp_server.py:49, 81-84). Mỗi lần ghi log email admin, `sub`, tên tool, version trước và sau (backend/app/mcp_server.py:122).

Env và deploy:

| Thứ | Giá trị | file:dòng |
| --- | --- | --- |
| `PUBLIC_BASE_URL` | `https://<DOMAIN>`; thiếu thì MCP tắt (PRM 404, `/mcp` 503) | backend/app/mcp_auth.py:50-52, deploy/deploy.sh:112-113 |
| `IDENTITY_ISSUER` | mặc định `https://identity.jacons-corp.com`; deploy.sh ghi lại mỗi lần, idempotent | backend/app/mcp_auth.py:32,55-56, deploy/deploy.sh:112-113 |
| nginx | `location = /mcp` (body ≤80k, `proxy_buffering off`) và `location ^~ /.well-known/oauth-protected-resource` (không có `^~` thì rơi vào SPA `try_files`) | deploy/nginx/smart-coding-study.conf:78-96 |
| smoke test | PRM chứa `https://<DOMAIN>/mcp`; POST `/mcp` không token trả 401 có `resource_metadata`; sai thì `rollback_site` | deploy/deploy.sh:159-164 |
| hướng dẫn kết nối | mục "Kết nối Claude (MCP)" | backend/README.md:83-101 |

Phía identity-service (repo khác, PR riêng): thêm `https://codewithphuong.jacons-corp.com/mcp` vào `OAuth2:AllowedResources`. Chỉ đổi config, luồng của các app khác không đổi. Tại thời điểm chưng cất PR đó (identity-service #5) chưa được merge/deploy theo STATUS.md, nên connector thật chưa chạy được end-to-end (chưa xác minh).

## Ranh giới & đánh đổi

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| OAuth qua identity-service, backend chỉ verify JWT | app key tĩnh, key trong URL, tự viết authorization server | xem `docs/DECISIONS.md` mục "MCP: đăng nhập OAuth qua identity-service" |
| Quyền nằm ở bảng `mcp_access`, kiểm mỗi tool call | tin JWT hợp lệ là đủ | ai có GitHub cũng đăng nhập identity-service được; JWT sống 60 phút nên không thu hồi được; bảng rỗng = không ai ghi được (fail-closed) |
| Chưa cấp quyền thì tool trả `isError` kèm `sub` | HTTP 403 | claude.ai hiện thông báo của tool cho người dùng; 403 thì không |
| Stateless + JSON response, GET/DELETE trả 405 | luồng SSE, phiên trong RAM | không giữ phiên; GET qua SDK mở SSE treo mãi, chiếm worker |
| Ghi đi chung đường (`review.submit`) và khoá với admin PUT, vào hàng chờ | đường ghi riêng cho MCP; ghi thẳng vào nội dung đang chạy | một bộ luật, một khoá, 409 cho admin cầm version cũ; Claude không thể làm lộ bài chưa duyệt cho học viên |
| Không giữ khoá suốt lần tải JWKS | single-flight | tải tối đa 1 lần/60s, timeout 5s; chưa đo thấy nghẽn (DEVIATIONS.md) |
| Tắt chống DNS rebinding của SDK | `allowed_hosts` theo domain | endpoint đòi Bearer, trình duyệt không tự gắn token cho trang lạ; Host thật sau nginx khác nhau giữa môi trường (backend/app/mcp_server.py:280-287). PLAN ban đầu định khai `allowed_hosts`, code không làm |

Không làm: tool xoá, tự duyệt (duyệt là việc của admin trong app, MCP không có tool approve), màn quản lý quyền MCP trong app, sửa `AUTH_OPEN_AS`/token `user_sessions` thành đường vào `/mcp` (hai hệ xác thực tách hẳn; bật `AUTH_OPEN_AS` `/mcp` vẫn 401).

## Giới hạn đã biết

- Đổi mật khẩu trong app KHÔNG thu hồi quyền MCP: quyền gắn tài khoản identity (GitHub), không gắn mật khẩu app; cắt bằng `revoke` (DEVIATIONS.md, quyết định của orchestrator).
- Backlog (STATUS.md): key lạ trong module/file/project bị bỏ lặng lẽ; module/file con lồng sẵn không qua kiểm id toàn cục; `update_*` không kiểm kiểu giá trị (lỗi pydantic khó đọc); `allow` sub đang hiệu lực cho email khác đổi user im lặng; email không giới hạn độ dài; `list` không phân trang; `lock_timeout` 15s giữ connection DB khi ghi đồng thời; README chưa nhắc `PUBLIC_BASE_URL`/`IDENTITY_ISSUER` khi chạy local; nhánh `IntegrityError` của `allow` chưa có test.
- Test khoá ghi giả lập bằng một lần ghi chen giữa validate và khoá (cùng session); chưa có race thật hai connection (fixture DB test rollback theo transaction, connection độc lập sẽ commit vào DB dùng chung và gây đỏ lẻ tẻ).
- identity-service vẫn khai `scopes_supported: ["expense"]` cứng; không chặn luồng, chỉ gây nhầm.
- Chưa xác minh: kết nối thật từ claude.ai (chờ merge và deploy identity-service PR #5, STATUS.md "Next action"). Đã có E2E bằng uvicorn thật + JWKS giả và smoke qua nginx production.

## Nguồn

backend/app/mcp_auth.py:1-236; backend/app/mcp_server.py:1-289; backend/app/review.py:390-436; backend/app/mcp_access.py:1-138; backend/app/content_ops.py:14-360; backend/app/admin_api.py:136-178; backend/app/tables.py:187-201; backend/app/main.py:55-66; backend/migrations/versions/0005_mcp_access.py; deploy/deploy.sh:112-113,159-164; deploy/nginx/smart-coding-study.conf:78-96; backend/README.md:83-101; planning/crew/2026-10-11-mcp-content/PLAN.md (mục Thiết kế, INV-01..07), STATUS.md, DEVIATIONS.md, reviews/SEAM.md.
