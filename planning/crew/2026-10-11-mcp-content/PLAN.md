# MCP server cho claude.ai — sửa nội dung học qua chat, đăng nhập qua identity-service

Run: `planning/crew/2026-10-11-mcp-content/` · branch `crew/2026-10-11-mcp-content` (worktree) · kết thúc: merge main + deploy VPS.
Thêm một thay đổi nhỏ ở repo `identity-service` (branch + PR riêng, deploy lại identity-service).

## Context

User muốn chat với Claude trên claude.ai để Claude tạo project, tạo/sửa bài học trong app. Hiện tại
nội dung chỉ sửa được qua màn Admin (ghi cả cây bằng `PUT /api/admin/content`) hoặc CLI. User chọn
"an toàn nhất, theo cách các app khác làm" và muốn **tận dụng identity-service**.

Đã kiểm:
- `https://identity.jacons-corp.com` **đang chạy** với `origin/main` (PR #4 "oauth2-as").
- `/.well-known/oauth-authorization-server` có `authorization_endpoint`, `token_endpoint` và
  `registration_endpoint` (DCR), `code_challenge_methods_supported: ["S256"]`,
  `token_endpoint_auth_methods_supported: ["none"]`.
- Đây đúng là bộ OAuth 2.1 mà claude.ai cần, và connector của expense-tracker đã chạy E2E thật trên đó.

Luồng: người dùng đăng nhập bằng **GitHub** qua identity-service. Identity-service phát JWT RS256
với `aud` = URL resource (RFC 8707), `sub` = id user bên identity. Backend app này chỉ là **resource
server**: verify JWT qua JWKS, không giữ secret, không phát token.

Không còn "app key" tĩnh. Thứ admin cấp/thu hồi giờ là **quyền MCP của một tài khoản identity**
(bảng `mcp_access`: `sub` → user admin của app), quản lý qua API admin + CLI đúng lựa chọn của user.
Thu hồi có hiệu lực **ngay request kế tiếp**, kể cả khi JWT còn hạn, vì mỗi tool call đều kiểm lại.

Không có nháp/publish: lưu là học viên thấy ngay. Mỗi tool ghi có `dry_run=true` để kiểm mà không ghi.

## Thiết kế

- **identity-service** (repo khác): thêm `"https://codewithphuong.jacons-corp.com/mcp"` vào
  `OAuth2:AllowedResources` (appsettings.json) + 1 dòng docs. PR riêng, deploy bằng `deploy/deploy.sh`
  của repo đó. Đây là thay đổi config, không đụng code. Luồng fishing-rod/moneyflow/expense không đổi.
- **Discovery** (backend app này): `/.well-known/oauth-protected-resource` và
  `/.well-known/oauth-protected-resource/mcp` trả `resource = <PUBLIC_BASE_URL>/mcp`,
  `authorization_servers = ["https://identity.jacons-corp.com"]`, `scopes_supported: ["content"]`,
  `bearer_methods_supported: ["header"]`.
- **Verify JWT** (`mcp_auth.py`): PyJWT + `PyJWKClient` (cache khoá, timeout). Chỉ RS256, kiểm `iss`,
  `aud == <base>/mcp`, `exp` (leeway 30s). Lỗi bất kỳ → `401` + `WWW-Authenticate: Bearer
  resource_metadata="…"`. Cổng này chạy ở tầng HTTP **trước** khi SDK MCP parse body. Lấy JWKS là
  blocking nên chạy trong threadpool. Không bao giờ dùng `AUTH_OPEN_AS`.
- **Phân quyền**: JWT hợp lệ nhưng `sub` chưa được cấp (hoặc đã thu hồi, hoặc user đích không còn
  admin) → tool trả `isError` kèm `sub` để admin biết mà cấp. Chọn cách này thay vì 403 vì claude.ai
  hiện thông báo của tool cho người dùng đọc được, còn 403 thì không.
- **`/mcp`**: `mcp` SDK chính thức (FastMCP, stateless, JSON response), mount vào FastAPI; khai
  `allowed_hosts` cho domain. Body ≤64KB (middleware có sẵn).
- **Tool** (project = theme, lesson = exercise):
  - Đọc: `list_projects`, `get_project`, `get_lesson` (đủ cả judge), `get_authoring_guide` (luật nội
    dung + một bài mẫu thật).
  - Ghi (đều có `dry_run`): `create_project`, `update_project`, `create_module` (lồng được),
    `update_module`, `create_file`, `update_file`, `create_lesson`, `update_lesson`.
  - Không có xoá (để backlog).
  - Mọi lần ghi đi **một đường**: `lock_content` → `export_content` → hàm thuần `content_ops` →
    `validation_errors` → `load_content(validated=True)` → commit, giống `_save`
    (backend/app/admin_api.py:93). Lỗi validate trả `isError` + danh sách lỗi (≤200) để Claude tự sửa.
    Log ghi email admin + `sub` + tên tool.
- **Quản lý quyền**: `GET/POST/DELETE /api/admin/mcp-access` và CLI
  `python -m app.mcp_access list | allow <sub> --as <email> [--label] | revoke <sub>`.
- **Env mới** (`/etc/smart-coding-study.env` qua deploy.sh): `PUBLIC_BASE_URL`,
  `IDENTITY_ISSUER=https://identity.jacons-corp.com`.

Concern:
- JWT không thu hồi được ở phía identity (sống 60 phút). Bù lại bằng bảng `mcp_access` kiểm mỗi request.
- Ai có GitHub cũng đăng nhập được identity-service và lấy token cho resource này. Chặn bằng allowlist
  `mcp_access` (fail-closed: bảng rỗng thì không ai ghi được).
- Validate cả cây trong khi giữ khoá ghi: chấp nhận được với 1 admin (`lock_timeout` 15s).
- Redeploy identity-service chạm 3 app khác: chỉ đổi config. Sau deploy curl lại metadata + JWKS.

## Sổ bất biến

```text
INV-01 · Ghi qua MCP đổi admin_version → màn Admin cầm base_version cũ nhận 409, không ghi đè im lặng
         phải khớp: backend/app/admin_api.py:93-110 · backend/app/mcp_server.py (đường ghi) · backend/app/load_content.py:298
         vỡ thì thấy gì: Claude tạo bài, admin bấm Lưu trên app (version cũ) → bài của Claude biến mất
INV-02 · Bài tạo qua MCP qua đúng validation_errors như admin PUT và hiện trong GET /content
         phải khớp: backend/app/load_content.py:217 · backend/app/content_ops.py · backend/app/content_api.py:184
         vỡ thì thấy gì: tool báo thành công nhưng app không thấy bài / app parse lỗi
INV-03 · /mcp chỉ nhận JWT hợp lệ của identity-service; không bao giờ rơi về user AUTH_OPEN_AS hay token user_sessions
         phải khớp: backend/app/auth.py:163-177 · backend/app/mcp_auth.py · backend/app/mcp_server.py
         vỡ thì thấy gì: bật AUTH_OPEN_AS hoặc gửi token đăng nhập app → /mcp vẫn chạy tool
INV-04 · Thu hồi mcp_access / user đích mất role admin → tool ghi bị từ chối ngay request kế tiếp dù JWT còn hạn
         phải khớp: backend/app/mcp_auth.py (kiểm quyền) · backend/app/mcp_access.py · backend/app/admin_api.py
         vỡ thì thấy gì: DELETE mcp-access xong Claude vẫn tạo được bài
INV-05 · /mcp chưa xác thực → 401 + WWW-Authenticate resource_metadata TRƯỚC khi SDK parse body
         phải khớp: backend/app/mcp_server.py (cổng) · backend/app/main.py (mount)
         vỡ thì thấy gì: claude.ai không hiện nút Connect ("Couldn't reach the MCP server")
INV-06 · Một chuỗi resource duy nhất: PRM.resource == aud backend kiểm == phần tử AllowedResources của identity-service
         phải khớp: backend/app/mcp_auth.py (PRM + verify) · identity-service src/IdentityService.Api/appsettings.json (OAuth2.AllowedResources) · deploy/deploy.sh (PUBLIC_BASE_URL)
         vỡ thì thấy gì: đăng nhập GitHub xong claude.ai báo invalid_target, hoặc 401 mãi sau khi có token
INV-07 · Token của app/resource khác (aud=fishing-rod, aud=moneyflow …/mcp) bị /mcp từ chối
         phải khớp: backend/app/mcp_auth.py (verify aud)
         vỡ thì thấy gì: token lấy từ connector expense dùng được để sửa nội dung học
```

## Task (role · tier · model)

| ID | Việc | Role · tier · model | Wave |
|---|---|---|---|
| T-01 | `mcp_auth.py`: PRM + verify JWT + bảng `mcp_access` + migration + test | orchestrator · L4 · session | 1 |
| T-02 | `content_ops.py` hàm thuần tạo/sửa project/module/file/bài + test | crew-impl-standard · T2 · sonnet | 1 |
| T-06 | identity-service: thêm resource vào AllowedResources + docs (repo khác, PR riêng) | orchestrator · L1 · session | 1 |
| T-03 | Quản lý quyền: API admin + CLI `mcp_access` + test | crew-impl-standard · T2 · sonnet | 2 |
| T-04 | `/mcp`: cổng 401 + SDK mount + 12 tool + test | orchestrator · L4 · session | 2 |
| T-05 | Deploy: nginx location, env mới, README "Kết nối Claude" | crew-impl-light · T1 · haiku | 3 |

Review: mọi task app có `crew-review` (T2). T-01 và T-04 (L4) có thêm `crew-review-external` với
`EXTERNAL_AGENT_TIMEOUT=360` (project rule). Cuối run có reviewer mối nối. Checkpoint: full pytest
sau wave 2.

### T-01 · L4 · orchestrator
- Objective: PRM endpoints, verify JWT identity-service, model `McpAccess` + migration `0005_mcp_access.py`, hàm `authorize_sub(session, sub) -> CurrentUser | None`.
- Owned: `backend/app/mcp_auth.py`, `backend/app/tables.py`, `backend/migrations/versions/0005_mcp_access.py`, `backend/requirements.txt`, `backend/tests/test_mcp_auth.py`
- Forbidden: `mobile/**`, `backend/content/**`, `backend/app/auth.py`
- Acceptance: JWT ký bằng khoá RSA sinh trong test (JWKS giả) — đúng → claims; sai `aud`/`iss`/hết hạn/HS256/`alg=none`/chữ ký sai → từ chối. PRM đúng field. `authorize_sub`: chưa cấp / revoked / user không còn admin → None.
- Validation: `cd backend && .venv/bin/pytest -q tests/test_mcp_auth.py`
- Evidence: `git diff --stat -- <owned>`
- Thứ tự: verify JWT (rủi ro nhất) trước, rồi bảng + authorize_sub, rồi PRM.

### T-02 · L3 · crew-impl-standard
- Objective: `content_ops.py` thuần (dict in → dict out, không DB): tóm tắt/cây project, lấy bài, create/update project/module (lồng)/file/lesson. Id trùng hoặc không tồn tại → `ContentOpError` có thông điệp rõ.
- Owned: `backend/app/content_ops.py`, `backend/tests/test_content_ops.py`
- Forbidden: mọi file khác
- Acceptance: op hợp lệ trên `content.json` thật cho `validation_errors == []`; không đổi phần cây ngoài phạm vi; update chỉ đổi field được truyền.
- Validation: `cd backend && .venv/bin/pytest -q tests/test_content_ops.py`
- Evidence: `git diff --stat -- backend/app/content_ops.py backend/tests/test_content_ops.py`
- Thứ tự: create_lesson + update_lesson trước (khó nhất).

### T-06 · L1 · orchestrator (repo identity-service, worktree riêng từ origin/main)
- Objective: cho phép resource `https://codewithphuong.jacons-corp.com/mcp`.
- Owned: `src/IdentityService.Api/appsettings.json`, `docs/04_integration.md`
- Forbidden: mọi file `.cs`
- Acceptance: `dotnet test` xanh; sau deploy, authorize với resource mới không trả `invalid_target`; metadata + JWKS vẫn 200.
- Validation: `dotnet test` (trong worktree identity-service)
- Evidence: `git diff --stat -- <owned>`

### T-03 · L3 · crew-impl-standard (sau T-01)
- Objective: cấp/xem/thu hồi quyền MCP.
- Owned: `backend/app/mcp_access.py` (service + CLI), `backend/app/admin_api.py`, `backend/tests/test_mcp_access.py`
- Forbidden: `backend/app/mcp_auth.py`, `backend/app/tables.py`, `mobile/**`
- Acceptance: API chỉ cho admin (401/403); `allow` từ chối email không phải admin; revoke xong `authorize_sub` → None; CLI in kết quả, không cần token.
- Validation: `cd backend && .venv/bin/pytest -q tests/test_mcp_access.py tests/test_admin_api.py`
- Evidence: `git diff --stat -- <owned>`

### T-04 · L4 · orchestrator (sau T-01, T-02)
- Objective: `/mcp` Streamable HTTP với 12 tool, cổng 401 trước SDK, ghi qua một đường dưới khoá.
- Owned: `backend/app/mcp_server.py`, `backend/app/main.py`, `backend/requirements.txt`, `backend/tests/test_mcp.py`
- Forbidden: `backend/app/load_content.py`, `backend/app/content_rules.py`, `mobile/**`
- Acceptance: không token / token sai → 401 + header đúng; initialize, tools/list, tools/call qua TestClient; create_lesson → bài có trong GET /content; dry_run không đổi version; nội dung sai → isError + lỗi; sub chưa cấp → isError có sub; AUTH_OPEN_AS bật vẫn 401.
- Validation: `cd backend && .venv/bin/pytest -q tests/test_mcp.py`
- Evidence: `git diff --stat -- <owned>`
- Thứ tự: spike mount SDK + cổng 401 trước (rủi ro tương thích mcp 2.x / Python 3.14), rồi tool.

### T-05 · L1 · crew-impl-light (sau T-04)
- Objective: nginx proxy `/mcp` và `/.well-known/oauth-protected-resource` vào uvicorn; deploy.sh ghi `PUBLIC_BASE_URL`, `IDENTITY_ISSUER` vào env file; README mục "Kết nối Claude".
- Owned: `deploy/nginx/smart-coding-study.conf`, `deploy/deploy.sh`, `backend/README.md`
- Forbidden: `backend/app/**`, `mobile/**`
- Acceptance: README có URL connector + cách cấp quyền bằng CLI; deploy.sh idempotent.
- Validation: `bash -n deploy/deploy.sh`
- Evidence: `git diff --stat -- <owned>`

## Verification (e2e — orchestrator tự chạy)

1. Full suite: `cd backend && .venv/bin/pytest -q` (tuần tự — DB test dùng chung).
2. Local uvicorn + JWT tự ký (JWKS giả): `/mcp` không token → 401 + `resource_metadata`; token đúng + sub đã cấp → `create_lesson` → `GET /content` có bài (INV-02).
3. Mối nối: lấy `base_version` từ `GET /api/admin/content` → tạo bài qua MCP → `PUT` bằng version cũ → **409** (INV-01).
4. Thu hồi quyền → tool ghi bị từ chối (INV-04); bật `AUTH_OPEN_AS` → `/mcp` vẫn 401 (INV-03); token `aud` khác → 401 (INV-07).
5. Sau deploy cả hai bên: curl domain thật (401 + PRM), metadata/JWKS identity vẫn 200, fishing-rod/moneyflow không đổi.
6. Cấp quyền cho tài khoản GitHub của user: tra `sub` trong DB identity trên VPS (chỉ đọc), chạy CLI `allow`. Sau đó user thêm connector `https://codewithphuong.jacons-corp.com/mcp` trên claude.ai → Connect → GitHub → nhờ Claude `list_projects` (INV-06 thật).

Backlog đã biết: tool xoá; màn quản lý quyền MCP trong app Flutter; identity-service vẫn khai `scopes_supported: ["expense"]` cứng ở Program.cs (không chặn luồng, chỉ gây nhầm).
