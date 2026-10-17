# mcp

> MCP server (`POST /mcp`) để Claude trên claude.ai đọc và tạo/sửa nội dung học; đăng nhập OAuth qua identity-service, backend chỉ là resource server; mọi lần ghi vào hàng chờ duyệt chung đường với admin PUT, admin duyệt thì học viên mới thấy.

## Là gì

Trước run này nội dung học chỉ sửa được qua màn Admin hoặc CLI. Module này cho phép người dùng chat với Claude trên claude.ai để tạo project, module, file và bài. Claude gọi 22 tool qua giao thức MCP (Model Context Protocol: chuẩn để chatbot gọi công cụ bên ngoài) tại `/mcp`. Backend không tự phát token và không giữ secret: người dùng đăng nhập GitHub ở identity-service (dịch vụ đăng nhập riêng của chủ repo, đã chạy cho các app khác), identity-service ký JWT (chuỗi token có chữ ký), còn backend chỉ kiểm chữ ký và kiểm xem tài khoản đó có được cấp quyền không. Quyền nằm ở bảng `mcp_access` và kiểm lại ở mỗi tool call, nên thu hồi có hiệu lực ngay dù JWT còn hạn. Mọi lần ghi dùng đúng khoá, cách so phiên bản và hàm `review.submit` của admin PUT: bản sửa chỉ vào hàng chờ duyệt (`content_changes`, xem `docs/modules/content-review.md`), không đổi nội dung học viên thấy tới khi admin duyệt trong app. Tool đọc và tool ghi đều làm việc trên bản nháp (nội dung đang chạy cộng các mục chờ), nên Claude tạo file rồi tạo bài trong file đó vẫn được dù file chưa duyệt. Ngoài 12 tool nội dung còn 10 tool `sd_*` cho chế độ System Design (xem `docs/modules/sd-study.md`): 3 tool chấm bài thực chiến (đọc/ghi dữ liệu của học viên, feedback hiện ngay) và 7 tool quản lý tài liệu đọc của tab Design (tạo, thay, sửa theo đoạn, đổi trạng thái, xoá mềm). Cả hai nhóm KHÔNG đi qua hàng chờ duyệt: tài liệu SD không có bước admin duyệt trong app, nên tài liệu đang `published` mà Claude sửa thì học viên thấy ngay.

## Dùng khi nào

Người dùng thêm connector `https://codewithphuong.jacons-corp.com/mcp` trên claude.ai (Customize, Connectors, Add custom connector, Connect), đăng nhập GitHub, rồi nhờ Claude soạn bài. Lần đầu tool báo `sub=… chưa được cấp quyền`; admin lấy `sub` đó và cấp bằng CLI trên VPS hoặc API admin. Đụng vào module này khi thêm tool mới (thêm hàm trong `content_ops.py` và một `@mcp.tool` trong `mcp_server.py`), đổi domain (phải đổi `PUBLIC_BASE_URL` và `AllowedResources` bên identity-service cùng lúc), hoặc đổi cách cấp quyền.

## Cách hoạt động

Luồng một request:

| Bước | Việc | Kết quả khi sai | file:dòng |
| --- | --- | --- | --- |
| 1 | `McpGate` nhận request trước SDK; chỉ nhận `POST` | GET/DELETE trả 405 `Allow: POST` (không mở luồng SSE treo worker) | backend/app/mcp_server.py:403-408 |
| 2 | `PUBLIC_BASE_URL` chưa đặt | 503 `mcp_not_configured` | backend/app/mcp_server.py:409-412 |
| 3 | `verify_bearer`: header `Bearer`, chữ ký RS256 theo `kid`, `iss`, `aud == <PUBLIC_BASE_URL>/mcp`, `exp` (leeway 30s) | 401 + `WWW-Authenticate: Bearer resource_metadata="…"` | backend/app/mcp_server.py:413-418, backend/app/mcp_auth.py:169-202 |
| 4 | Không tải được JWKS (khoá công khai) của identity-service và không còn khoá cũ dùng được | 503 `auth_unavailable`, không lẫn thành 401 (claude.ai coi 401 là token hỏng và bắt đăng nhập lại) | backend/app/mcp_server.py:419-423, backend/app/mcp_auth.py:89-90 |
| 5 | Claims đặt vào `ContextVar`, SDK xử lý JSON-RPC (stateless, JSON response) | | backend/app/mcp_server.py:424-428 |
| 5b | Body tối đa 2MB: middleware `_limit_body` so `Content-Length` với `_body_limit("/mcp")` = `MAX_BODY_BYTES` (2MB), quá thì 413; không có `Content-Length` mà có body chunked thì 411. Các route khác vẫn 64KB (admin 4MB). Cổng JWT (bước 1-4) chạy trong `McpGate`, SDK mới đọc body, nên khách chưa xác thực không bắt server đọc được chừng này; nginx `location = /mcp` cho tới 2100k để chính backend trả 413 | backend/app/main.py:76-79, 91-94; backend/app/mcp_server.py:52, 439; deploy/nginx/smart-coding-study.conf:78-83 |
| 6 | Mỗi tool gọi `authorize_sub`: `sub` phải có dòng `mcp_access` chưa thu hồi, và user đích còn role admin | tool trả lỗi kèm `sub` và lệnh cấp quyền | backend/app/mcp_server.py:76-92, backend/app/mcp_auth.py:205-218 |

Cổng 401 chạy trước SDK vì claude.ai chỉ hiện nút Connect khi thấy `resource_metadata` trên một 401. Discovery (RFC 9728, tài liệu mô tả "resource này tin authorization server nào") nằm ở `/.well-known/oauth-protected-resource` và `/.well-known/oauth-protected-resource/mcp`, trả `resource`, `authorization_servers = [IDENTITY_ISSUER]`, `scopes_supported = ["content"]` (backend/app/mcp_auth.py:221-236). Route `/mcp` là ASGI thô gắn thẳng vào router, không qua FastAPI (backend/app/main.py:67-72).

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

12 tool nội dung (project = theme, module = topic, file = file code, lesson = bài):

| Nhóm | Tool | file:dòng |
| --- | --- | --- |
| Đọc | `list_projects`, `get_project`, `get_lesson`, `get_authoring_guide` (luật + một bài mẫu thật) | backend/app/mcp_server.py:152-203 |
| Ghi (đều có `dry_run`) | `create_project` (kèm module đầu), `update_project`, `create_module` (lồng được), `update_module`, `create_file`, `update_file`, `create_lesson`, `update_lesson` | backend/app/mcp_server.py:210-259 |

3 tool chấm bài System Design (dữ liệu học viên, không qua hàng chờ duyệt):

| Tool | Việc | file:dòng |
|---|---|---|
| `sd_list_attempts` | hàng đợi lần thử cần chấm, cũ nhất trước; mặc định `status='auto'` (mới chỉ có điểm từ khoá), `limit` bị kẹp 1..50; mặc định bỏ bài của doc đã `archived`, `include_archived=true` để xem cả (không thì bài nộp còn đó mà Claude không thấy); trả `learner_id` chứ không trả email | backend/app/mcp_server.py:280-297, backend/app/sd/attempts.py:194-226 |
| `sd_get_attempt` | một lần thử đầy đủ: `answer`, đề, các ý rubric (chữ, không từ khoá), điểm từ khoá, đáp án mẫu; luôn kèm `answer_notice` | backend/app/mcp_server.py:299-302, backend/app/sd/attempts.py:229-270 |
| `sd_submit_feedback` | ghi bản chấm sâu: `verdicts` đúng bằng số ý rubric (theo thứ tự, `{ok, note}`) + nhận xét chung ≤4000 ký tự; đã có bản `reviewed` thì từ chối trừ khi `replace=true` | backend/app/mcp_server.py:305-313, backend/app/sd/attempts.py:273-309 |

7 tool quản lý tài liệu System Design (chạy qua `_sd_doc`: `_authorized` mỗi lần gọi, actor ghi log là `mcp:<sub>`, `SdDocError` đổi thành `ToolError` "Không thực hiện được, chưa ghi gì"; nghiệp vụ ở `backend/app/sd/docs.py`, xem mục 8 của `docs/modules/sd-study.md`):

| Tool | Việc | Annotation | file:dòng |
|---|---|---|---|
| `sd_list_docs(include_archived=False)` | id, title, status, số section/card/task, `has_markdown`; mặc định ẩn doc `archived` | đọc | backend/app/mcp_server.py:333-337 |
| `sd_get_doc(doc_id)` | meta, `revision`, mục lục, task, markdown gốc (`null` nếu nhập trước 0008) | đọc | backend/app/mcp_server.py:339-343 |
| `sd_create_doc(markdown, doc_id?, status=draft, dry_run)` | tạo; từ chối nếu id đã có (kể cả `archived`); `status` chỉ `draft`/`published` | ghi, không destructive | backend/app/mcp_server.py:345-355 |
| `sd_replace_doc(doc_id, markdown, base_revision?, dry_run)` | thay toàn bộ markdown, giữ status; `base_revision` chống ghi đè bản vừa bị sửa | destructive, idempotent | backend/app/mcp_server.py:357-367 |
| `sd_edit_doc(doc_id, edits, dry_run)` | sửa theo đoạn (`old_text` phải xuất hiện đúng 1 lần, ≤50 edit); cần markdown gốc | destructive, KHÔNG idempotent (`_EDIT`) | backend/app/mcp_server.py:369-375, 147-148 |
| `sd_set_status(doc_id, status)` | `draft`/`published`/`archived`; dùng để publish, gỡ xuống, khôi phục | destructive, idempotent | backend/app/mcp_server.py:377-383 |
| `sd_delete_doc(doc_id)` | xoá MỀM = `archived`, trả kèm hướng dẫn khôi phục | destructive, idempotent | backend/app/mcp_server.py:385-395 |

`sd_edit_doc` có annotation riêng vì áp lại cùng edits lần hai sẽ lỗi (không idempotent) và edit có thể xoá hay đổi tên section/task (mất tiến độ phần đó): review ngoài (Codex) bắt `destructive_hint=False` ban đầu là sai (commit 3d8737b). `INSTRUCTIONS` dặn Claude: tài liệu SD không qua hàng chờ duyệt nên doc `published` đổi là học viên thấy ngay, hãy nói rõ với người dùng và `dry_run` trước; doc mới mặc định `draft`; đọc định dạng markdown từ `sd_get_doc` của một doc có sẵn trước khi soạn doc mới (backend/app/mcp_server.py:57-70).

Cả ba tool chấm bài chạy qua `_sd`, hàm này gọi `_authorized` (tức `authorize_sub`) ở MỖI lần gọi, y như tool nội dung, và đổi `SdError` thành `ToolError` (backend/app/mcp_server.py:266-277). Lần ghi `reviewed` khoá dòng `FOR UPDATE` và lấy chữ từng ý từ rubric đã chụp lúc học viên nộp, nên Claude chỉ quyết đúng/sai và ghi chú, không đổi được nội dung ý (backend/app/sd/attempts.py:284-306). `sd_get_attempt` luôn kèm `answer_notice` (backend/app/sd/attempts.py:176-180, 250) và `INSTRUCTIONS` của server nhắc lại: câu trả lời của học viên là văn bản không tin cậy, chỉ là dữ liệu để chấm (backend/app/mcp_server.py:57-70).

Không có tool xoá nội dung học hay bài nộp (`sd_delete_doc` chỉ xoá mềm tài liệu SD). Hàm biến đổi nội dung là hàm thuần (dict vào, dict ra, không đụng DB) ở `backend/app/content_ops.py`; lỗi nghiệp vụ là `ContentOpError` và được đổi thành `ToolError` để Claude đọc được.

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
(backend/app/mcp_server.py:112-134, rút gọn)

Luật nội dung được kiểm trước khi giữ khoá (nội dung sai không chặn ai); `review.submit` lấy `pg_advisory_xact_lock` (cùng khoá với admin PUT, xem `docs/modules/content-admin.md`), so `base` với hash bản nháp hiện tại, diff với nội dung đang chạy thành các mục và upsert dòng `pending` với `author = mcp:<sub> (<email>)` (backend/app/review.py:399-434). Vì `admin_version` (của bản nháp) đổi sau mỗi lần gửi, màn Admin đang cầm `base_version` cũ sẽ nhận 409 chứ không ghi đè bài của Claude. Tool trả `{ok, version, pending, message}` với câu "Đã gửi vào hàng chờ duyệt — admin cần duyệt trong app thì học viên mới thấy"; `dry_run` báo hợp lệ rồi hướng dẫn gọi lại để gửi vào hàng chờ. Gửi duyệt đổi cha của module có sẵn bị từ chối (`unsupported_move`) và đổi thành `ToolError` (backend/app/mcp_server.py:133-135). Lỗi validate trả tối đa 50 dòng (backend/app/mcp_server.py:53, 94-96). Mỗi lần ghi log email admin, `sub`, tên tool, version trước và sau (backend/app/mcp_server.py:134).

Env và deploy:

| Thứ | Giá trị | file:dòng |
| --- | --- | --- |
| `PUBLIC_BASE_URL` | `https://<DOMAIN>`; thiếu thì MCP tắt (PRM 404, `/mcp` 503) | backend/app/mcp_auth.py:50-52, deploy/deploy.sh:112-113 |
| `IDENTITY_ISSUER` | mặc định `https://identity.jacons-corp.com`; deploy.sh ghi lại mỗi lần, idempotent | backend/app/mcp_auth.py:32,55-56, deploy/deploy.sh:112-113 |
| nginx | `location = /mcp` (body ≤2100k, lớn hơn trần 2MB của backend nên backend trả 413, `proxy_buffering off`) và `location ^~ /.well-known/oauth-protected-resource` (không có `^~` thì rơi vào SPA `try_files`) | deploy/nginx/smart-coding-study.conf:78-96 |
| smoke test | PRM chứa `https://<DOMAIN>/mcp`; POST `/mcp` không token trả 401 có `resource_metadata`; sai thì `rollback_site` | deploy/deploy.sh:159-164 |
| hướng dẫn kết nối | mục "Kết nối Claude (MCP)" | backend/README.md:83-101 |

Phía identity-service (repo khác, PR riêng): thêm `https://codewithphuong.jacons-corp.com/mcp` vào `OAuth2:AllowedResources`. Chỉ đổi config, luồng của các app khác không đổi. PR đó (identity-service #5, commit `85625e2`) đã merge và deploy ngày 2026-10-11.

## Ranh giới & đánh đổi

| Chọn | Thay vì | Vì sao |
| --- | --- | --- |
| OAuth qua identity-service, backend chỉ verify JWT | app key tĩnh, key trong URL, tự viết authorization server | xem `docs/DECISIONS.md` mục "MCP: đăng nhập OAuth qua identity-service" |
| Quyền nằm ở bảng `mcp_access`, kiểm mỗi tool call | tin JWT hợp lệ là đủ | ai có GitHub cũng đăng nhập identity-service được; JWT sống 60 phút nên không thu hồi được; bảng rỗng = không ai ghi được (fail-closed) |
| Chưa cấp quyền thì tool trả `isError` kèm `sub` | HTTP 403 | claude.ai hiện thông báo của tool cho người dùng; 403 thì không |
| Stateless + JSON response, GET/DELETE trả 405 | luồng SSE, phiên trong RAM | không giữ phiên; GET qua SDK mở SSE treo mãi, chiếm worker |
| Ghi đi chung đường (`review.submit`) và khoá với admin PUT, vào hàng chờ | đường ghi riêng cho MCP; ghi thẳng vào nội dung đang chạy | một bộ luật, một khoá, 409 cho admin cầm version cũ; Claude không thể làm lộ bài chưa duyệt cho học viên |
| Tool tài liệu SD ghi thẳng, kể cả đổi doc `published`; lớp chặn là bước "Needs approval" của claude.ai | thêm hàng chờ duyệt riêng cho tài liệu SD | user chọn: Claude được publish/gỡ/sửa doc đang published; mỗi tool ghi hiện cho người dùng duyệt trước khi chạy ở phía claude.ai, backend không tự thêm bước nào (xem `docs/DECISIONS.md`). Backend vẫn chỉ cho admin đã cấp quyền |
| Trần body `/mcp` 2MB, chỉ cho `/mcp` | nâng trần chung | doc SD tới 1MB cộng JSON escape; route khác giữ 64KB/4MB |
| Không giữ khoá suốt lần tải JWKS | single-flight | tải tối đa 1 lần/60s, timeout 5s; chưa đo thấy nghẽn (DEVIATIONS.md) |
| Tắt chống DNS rebinding của SDK | `allowed_hosts` theo domain | endpoint đòi Bearer, trình duyệt không tự gắn token cho trang lạ; Host thật sau nginx khác nhau giữa môi trường (backend/app/mcp_server.py:437-440). PLAN ban đầu định khai `allowed_hosts`, code không làm |

Tool `sd_*` ghi thẳng, không vào hàng chờ: bản chấm là phản hồi cho riêng một học viên, không phải nội dung chung cần admin duyệt. MCP là đường của admin đã được cấp quyền (đích phải còn là admin), không phải đường của học viên; học viên chỉ có route `/api/sd` luôn lọc theo `user.id` (backend/app/mcp_auth.py:205-218, backend/app/sd/attempts.py:154-155).

Không làm: tool xoá cứng, tự duyệt (duyệt là việc của admin trong app, MCP không có tool approve), màn quản lý quyền MCP trong app, sửa `AUTH_OPEN_AS`/token `user_sessions` thành đường vào `/mcp` (hai hệ xác thực tách hẳn; bật `AUTH_OPEN_AS` `/mcp` vẫn 401).

## Giới hạn đã biết

- Tool tài liệu SD (run 2026-10-17-sd-docs-mcp, STATUS.md/SEAM.md): trần 2MB so theo byte JSON thô, nên doc 1MB toàn ký tự điều khiển (mỗi ký tự thành 6 byte `\u0001`) bị 413 dù hợp lệ — chỉ ảnh hưởng input thù địch, lỗi theo hướng từ chối; chưa có test 411 cho `/mcp` chunked; `sd_edit_doc` so `old_text` thô, không chuẩn hoá NFC; lỗi quyền vẫn trả `sub` và lệnh CLI cấp quyền (cố ý: admin cần `sub` để cấp quyền, DEVIATIONS.md); `sd_delete_doc` không có purge (xoá cứng) nên doc `archived` nằm lại DB.
- Đổi mật khẩu trong app KHÔNG thu hồi quyền MCP: quyền gắn tài khoản identity (GitHub), không gắn mật khẩu app; cắt bằng `revoke` (DEVIATIONS.md, quyết định của orchestrator).
- Backlog (STATUS.md): key lạ trong module/file/project bị bỏ lặng lẽ; module/file con lồng sẵn không qua kiểm id toàn cục; `update_*` không kiểm kiểu giá trị (lỗi pydantic khó đọc); `allow` sub đang hiệu lực cho email khác đổi user im lặng; email không giới hạn độ dài; `list` không phân trang; `lock_timeout` 15s giữ connection DB khi ghi đồng thời; README chưa nhắc `PUBLIC_BASE_URL`/`IDENTITY_ISSUER` khi chạy local; nhánh `IntegrityError` của `allow` chưa có test.
- Test khoá ghi giả lập bằng một lần ghi chen giữa validate và khoá (cùng session); chưa có race thật hai connection (fixture DB test rollback theo transaction, connection độc lập sẽ commit vào DB dùng chung và gây đỏ lẻ tẻ).
- identity-service vẫn khai `scopes_supported: ["expense"]` cứng; không chặn luồng, chỉ gây nhầm.
- Rủi ro dư prompt injection của `sd_*` (run 2026-10-12-system-design-mode, DEVIATIONS.md): `answer` của học viên đi vào ngữ cảnh của Claude. Đã có `answer_notice`, `INSTRUCTIONS`, docstring tool và `replace=false` mặc định để không đè bản đã chấm, nhưng `sd_submit_feedback` không buộc `attempt_id` với lần vừa đọc và không có token một lần. Quyết định chấp nhận vì công cụ là của admin nội bộ (số admin = 1); xem `docs/DECISIONS.md`.
- Kết nối thật từ claude.ai đã chạy ngày 2026-10-17: log production cho thấy request từ dải IP Anthropic `160.79.106.x` nhận 401 rồi 200 sau khi đăng nhập, tool trả "chưa được cấp quyền" kèm `sub`, admin cấp bằng `python -m app.mcp_access allow` (issue #24). Ngoài ra có E2E bằng uvicorn thật + JWKS giả và smoke qua nginx production.

## Nguồn

backend/app/mcp_auth.py:1-236; backend/app/mcp_server.py:1-443; backend/app/sd/attempts.py:176-309; backend/app/sd/docs.py:1-294; backend/app/main.py:76-94; planning/crew/2026-10-17-sd-docs-mcp/PLAN.md, STATUS.md, DEVIATIONS.md, reviews/SEAM.md; backend/app/review.py:390-436; backend/app/mcp_access.py:1-138; backend/app/content_ops.py:14-360; backend/app/admin_api.py:136-178; backend/app/tables.py:187-201; backend/app/main.py:55-66; backend/migrations/versions/0005_mcp_access.py; deploy/deploy.sh:112-113,159-164; deploy/nginx/smart-coding-study.conf:78-96; backend/README.md:83-101; planning/crew/2026-10-11-mcp-content/PLAN.md (mục Thiết kế, INV-01..07), STATUS.md, DEVIATIONS.md, reviews/SEAM.md.
