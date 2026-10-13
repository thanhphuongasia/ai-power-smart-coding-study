# sd-study

> Chế độ học System Design: admin nhập một file `.md`, app chia thành chapter/section/card cho học viên đọc (Phase 1) rồi cho viết thiết kế cho từng task thực chiến (Phase 2), chấm từ khoá ngay và để Claude chấm sâu qua MCP. Dành cho học viên (tab Design) và admin (API nhập tài liệu, tool MCP chấm bài).

## Là gì

Chế độ code của app dạy bằng bài tập có test; System Design không có đáp án máy chấm được, nên cần một đường học riêng. Admin viết một tài liệu markdown theo quy ước cố định, nhập qua API; backend cắt tài liệu thành các "card" (một đoạn, một bảng, một khối code, một trích dẫn). Học viên lướt đọc từng section theo thứ tự (Phase 1), xong hết thì mở phần Bối cảnh và toàn bộ task thực chiến cùng lúc (Phase 2, làm task nào trước cũng được): tự viết lời giải, nộp, thấy ngay điểm theo từ khoá, rồi nhờ Claude chấm sâu hơn. Toàn bộ dữ liệu đi đường riêng — bảng `sd_*`, API `/api/sd` và `/api/admin/sd` — không dùng `load_content` hay hàng chờ duyệt của chế độ code, và việc "ai được mở gì" do server tính, app chỉ vẽ lại. SRS (lặp lại ngắt quãng) cho card System Design chưa làm; issue #31 vẫn mở vì phần đó.

## Dùng khi nào

Admin nhập hoặc nhập lại tài liệu bằng `POST /api/admin/sd/docs` (hiện chưa có màn admin trong app, STATUS.md). Học viên vào từ tab thứ 5 "Design" của app, chọn tài liệu, đi theo lộ trình. Claude (qua claude.ai, đã được cấp quyền `mcp_access`) gọi 3 tool `sd_*` để chấm. Đụng vào module này khi đổi quy ước markdown (sửa `parser.py` và mọi tài liệu đã nhập, vì id card/section/task sinh từ nội dung/tên), thêm kiểu chấm mới (cắm một `Evaluator`), hoặc thêm tab điều hướng (3 nơi phải khớp index, xem phần Flutter).

## Cách hoạt động

### 1. Quy ước markdown (backend/app/sd/parser.py)

Tài liệu mẫu: `backend/content/sd/airline-reservation.md` (9 section, 26 card, 6 task; là fixture của test và demo).

| Dạng trong file | Thành |
|---|---|
| `# Tên` (đúng một lần) | tên tài liệu; id tài liệu = slug của tên (hoặc `id` admin truyền) |
| `## Bối cảnh` | các card bối cảnh của Phase 2; `###`/`####` trong đó chỉ là tiêu đề cho khối sau nó |
| `## Thực chiến` | mỗi `###` là một task: nhãn `Đề:`, `Gợi ý:`, `Rubric:`, `Đáp án mẫu: <section>` |
| `##` khác | chapter; nội dung ngay dưới `##` (trước `###` đầu) thành section mang tên chapter |
| `###` | section; `####` là tiêu đề cho các card sau nó |
| mỗi khối: đoạn/danh sách, bảng, khối code rào, `>` | một card (`text`, `table`, `code`, `diagram` nếu rào ```` ```mermaid ````, `callout`) |
| dòng rubric `- ý cần có :: từ khoá 1, từ khoá 2` | một ý chấm: chữ để hiển thị + từ khoá để khớp |

Nguồn của bảng: backend/app/sd/parser.py:3-17, 47-56, 207-253, 422-455. Gặp sai quy ước, parser gom lỗi kèm số dòng (tối đa 50) và admin nhận 422 (backend/app/sd/parser.py:517-519, backend/app/sd/admin.py:60-63).

### 2. Mô hình dữ liệu: 5 bảng `sd_*`, không FK từ tiến độ/lần thử tới nội dung

| Bảng | Khoá | Chứa | Ràng buộc đáng nhớ |
|---|---|---|---|
| `sd_docs` | `id` (slug) | tên, `status` (`draft`/`published`), `context` (card bối cảnh, JSONB) | CHECK status — backend/app/tables.py:241-255 |
| `sd_sections` | `(doc_id, id)` | `position`, `chapter`, `title`, `cards` JSONB `[{id, kind, title, body}]` | FK `doc_id` → `sd_docs` CASCADE — backend/app/tables.py:258-270 |
| `sd_tasks` | `(doc_id, id)` | `prompt`, `hints`, `rubric` JSONB `[{text, keywords}]`, `ref_section_id` | rubric chỉ server đọc — backend/app/tables.py:273-287 |
| `sd_progress` | `(user_id, doc_id, section_id)` | `read_cards` (list id card đã đọc) | chỉ FK `users`; KHÔNG FK tới nội dung — backend/app/tables.py:290-301 |
| `sd_attempts` | `id`; unique `(user_id, doc_id, task_id, n)` | `answer`, `auto_result`, `status` (`auto`/`reviewed`), `feedback`, `verdicts`, `reviewed_by/at` | CHECK: `reviewed` phải có feedback và `reviewed_at` — backend/app/tables.py:304-336 |

Migration `0007` (sau `0006`), downgrade xoá cả 5 bảng: backend/migrations/versions/0007_system_design.py:22-97. Lý do không FK: nhập lại tài liệu xoá rồi ghi lại section/task; FK cascade sẽ xoá sạch tiến độ và lần thử (backend/app/tables.py:236-238).

Id ổn định giữa các lần nhập lại, vì tiến độ bám theo chúng:

| Id | Sinh từ | Hệ quả khi đổi |
|---|---|---|
| `card.id` | `sha1(kind + nội dung chuẩn hoá)[:8]`; văn bản gộp khoảng trắng, code/diagram chỉ bỏ khoảng trắng cuối dòng — backend/app/sd/parser.py:100-106 | sửa một card chỉ đổi id card đó; section khác giữ nguyên |
| `section.id`, `task.id` | slug của TÊN (trùng tên thì hậu tố `-2`, `-3`); tên không còn chữ/số ASCII thì `x-` + hash — backend/app/sd/parser.py:67-73, 491, 515 | đổi tên section mất tiến độ đọc section đó; đổi tên task mất số lần thử (BK-1) |
| mọi văn bản | chuẩn hoá Unicode NFC ngay sau kiểm ký tự xấu — backend/app/sd/parser.py:371-373 | file lưu NFC hay NFD (sao chép từ macOS hay ra NFD) cho cùng id |

Trần của parser (50 chương, 200 section, 200 card/section, 3000 card/tài liệu, 12 task, file ≤1MB) nằm ở backend/app/sd/parser.py:28-45 và backend/app/sd/admin.py:37. Parser dùng một lượt qua các dòng, không regex lồng nhau, và kiểm trần trước khi nối chuỗi (rule `.claude/rules/engineering/hostile-input-budget.md`, xem `docs/DECISIONS.md`).

### 3. API

Admin (`require_admin` ở cấp router, nên route thêm sau không thể quên kiểm quyền — backend/app/sd/admin.py:35):

| Route | Việc |
|---|---|
| `POST /api/admin/sd/docs` | nhập/nhập lại; trả `{id, sections, cards, tasks, cards_added, cards_removed, ...}` — backend/app/sd/admin.py:57-124 |
| `GET /api/admin/sd/docs` | danh sách kèm đếm — backend/app/sd/admin.py:127-150 |
| `PUT /api/admin/sd/docs/{id}/status` | `draft` ↔ `published` — backend/app/sd/admin.py:153-172 |

Nhập lại chạy trong MỘT transaction dưới `pg_advisory_xact_lock` theo id tài liệu, xoá rồi ghi section/task, không chạm `sd_progress`/`sd_attempts` (backend/app/sd/admin.py:65-93). Tài liệu mới mặc định `draft`; chưa `published` thì học viên nhận 404 (backend/app/sd/learner.py:40-44).

Học viên (`current_user`; mọi truy vấn tiến độ/lần thử lọc theo `user.id` của phiên):

| Route | Việc |
|---|---|
| `GET /api/sd/docs` | tài liệu đã publish + tiến độ của tôi — backend/app/sd/learner.py:117-140 |
| `GET /api/sd/docs/{id}` | section (kèm `read`, `done`, `unlocked`), `context` chỉ khi Phase 2 mở, task (kèm `unlocked`, `done`, `attempts`) — backend/app/sd/learner.py:143-156 |
| `PUT .../sections/{sid}/progress` | chỉ THÊM card đã đọc (hợp, không bớt); id lạ bị bỏ qua; section khoá → 409 `section_locked` — backend/app/sd/learner.py:159-205 |
| `POST .../tasks/{tid}/attempts` | nộp bài: 201, hoặc 409 `task_locked`, 429 `attempt_limit` — backend/app/sd/attempts.py:85-140 |
| `GET .../tasks/{tid}/attempts` | lịch sử của tôi, mới nhất trước, `limit` ≤50 — backend/app/sd/attempts.py:143-160 |

### 4. Luật khoá/mở do server tính

```python
# backend/app/sd/learner.py:48-70 (rút gọn)
out, prev_done = [], True
for s in sections:
    ...
    done = bool(ids) and len(read) == len(ids)
    out.append({..., "done": done, "unlocked": prev_done})
    prev_done = done
```

| Đối tượng | Mở khi | Xong khi |
|---|---|---|
| section | là section đầu, hoặc section liền trước `done` | mọi card HIỆN HÀNH đều đã đọc (card đã bị sửa/xoá khi nhập lại không còn tính) |
| Phase 2 (bối cảnh + task) | mọi section `done` | — |
| task | Phase 2 mở (mọi task mở cùng lúc, không khoá tuần tự: làm task nào trước cũng được) — backend/app/sd/learner.py:77 | có ≥1 lần thử (`attempts >= 1`) — backend/app/sd/learner.py:84 |

Đề, gợi ý và `ref_section_id` của task chỉ lộ khi task đã mở, tức khi Phase 2 mở (backend/app/sd/learner.py:86-89). `POST` lần thử dùng lại `_tasks_state` nên task nào cũng nộp được (201) khi Phase 2 mở và 409 `task_locked` khi chưa (backend/app/sd/attempts.py:102-104). Rubric và từ khoá không bao giờ có mặt trong response học viên. Client chỉ được mở khoá cục bộ qua `next_section_id` mà PUT progress trả về.

### 5. Lần thử và hai lớp chấm

| | Chấm từ khoá (`auto`) | Chấm sâu (`reviewed`) |
|---|---|---|
| Ai | server, ngay khi nộp, bằng `KeywordEvaluator` | Claude qua MCP, ghi `sd_submit_feedback` |
| Cách | mỗi ý rubric trúng nếu BẤT KỲ từ khoá nào có trong câu trả lời; không phân biệt hoa/thường và dấu tiếng Việt — backend/app/sd/evaluator.py:17-34 | đọc `answer` + đề + rubric + đáp án mẫu, trả `{ok, note}` cho TỪNG ý theo thứ tự, thêm nhận xét chung ≤4000 ký tự — backend/app/sd/attempts.py:273-309 |
| Điểm | `round(100 * trúng / số ý)` | tính lại từ `ok` của verdicts |

Quy tắc xoay quanh một dòng `sd_attempts` mỗi lần nộp (không ghi đè): `n` tăng dần theo (user, doc, task) và cấp dưới `pg_advisory_xact_lock` (unique chỉ là lưới an toàn cuối); câu trả lời ≤8KB, không NUL/surrogate; tối đa 20 lần/task/24 giờ (backend/app/sd/attempts.py:32-34, 96-125). Rubric được CHỤP vào `auto_result.texts` lúc nộp, nên nhập lại làm đổi rubric cũng không đổi cách diễn giải điểm cũ (backend/app/sd/attempts.py:132-134). `attempt_view` trả MỘT bản duy nhất: `reviewed` thắng `auto`, trường `source` cho biết là bản nào (backend/app/sd/attempts.py:53-75). `Evaluator` là `Protocol` cắm qua dependency `get_evaluator` (cùng mẫu `CodeRunner`), nên bộ chấm mới không sửa mã cũ (backend/app/sd/evaluator.py:23-39).

Ba tool MCP (xem `docs/modules/mcp.md`): `sd_list_attempts` (hàng đợi, cũ nhất trước, mặc định `status='auto'`), `sd_get_attempt`, `sd_submit_feedback` (backend/app/mcp_server.py:270-296). Điểm riêng so với các tool nội dung: không qua hàng chờ duyệt, feedback hiện cho học viên ngay (backend/app/mcp_server.py:251-253). `submit_feedback` khoá dòng `FOR UPDATE`, từ chối ghi đè bản `reviewed` nếu không có `replace=true`, và lấy chữ của từng ý từ rubric đã chụp (Claude chỉ quyết đúng/sai + ghi chú, không đổi được nội dung ý) — backend/app/sd/attempts.py:284-306. `sd_get_attempt` luôn kèm `answer_notice` nhắc rằng `answer` là văn bản không tin cậy (backend/app/sd/attempts.py:176-180, 250).

### 6. Phía Flutter

| Phần | Việc | Toạ độ (Dart) |
|---|---|---|
| Tab thứ 5 "Design" | thêm cuối ở BA nơi phải khớp index: branch router, destination của `NavigationBar`, mục drawer (thêm cuối để không đổi key `drawer-nav-$i`) | mobile/lib/app/router.dart:30-72, mobile/lib/features/shell/app_shell.dart:37-76, mobile/lib/features/shell/app_drawer.dart:80-87 |
| Route | `/design` (danh sách), `/design/:docId` (lộ trình), `.../read?section=`, `.../context`, `.../tasks/:taskId`; id được mã hoá bằng `Uri.encodeComponent` | mobile/lib/app/router.dart |
| Model + repository | parse JSON; id rỗng, `.`, `..` bị chặn ngay bằng `ArgumentError`; lỗi HTTP của server (`SdApiException`) hiện ngay, không bị Riverpod thử lại ngầm | mobile/lib/domain/sd_models.dart, mobile/lib/data/sd_repository.dart:17-60, 185-203 |
| `DuoPath` | lộ trình kiểu Duolingo: banner xanh lá "CHAPTER i · k/n SECTION", đĩa tròn 3D zigzag, node hiện tại xanh dương có quầng + bóng "BẮT ĐẦU", khoá xám, xong xanh lá + tick; chỉ nhận trạng thái, không tự tính khoá | mobile/lib/features/system_design/duo_path.dart:1-30, mobile/lib/features/system_design/sd_path_screen.dart:31-35 |
| Màn đọc | thanh trên navy (nút quay lại `sd-reader-back` và nút mục lục `sd-reader-menu`) + thanh tiến độ, tờ giấy trắng chữ serif (Source Serif 4, bundle trong `pubspec.yaml`), luôn trắng cả dark mode; thẻ nào có mép dưới đi qua mép dưới vùng nhìn thấy thì tính là đã đọc; gom bằng debounce 800ms thành một PUT mỗi section; lỗi 5xx/mạng thì backoff 2s, 4s… tối đa 30s, quá 5 lần liên tiếp thì dừng tới khi mở lại màn; 409/4xx thì dừng, không báo lỗi; mở lại nhảy tới card chưa đọc. Vuốt snap theo card và menu mục lục: xem phần 7 | mobile/lib/features/system_design/reader_screen.dart:26-33, 270-395, 569-582, 691-719 |
| Bối cảnh / Task | node "Bối cảnh" rồi các task; màn task có đề, gợi ý, ô viết với bộ đếm byte, lịch sử lần thử, ✓/✗ từng ý, "Xem đáp án mẫu", nút "Làm mới" để lấy bản chấm sâu | mobile/lib/features/system_design/context_screen.dart, mobile/lib/features/system_design/task_screen.dart:612-640 |
| Bản nháp | lưu cục bộ bằng `SharedPreferences`, khoá `sd-draft:<email>:<docId>:<taskId>` (đổi tài khoản trên cùng máy không thấy nháp người trước); ghi sau debounce 400ms, xoá sau khi nộp thành công | mobile/lib/features/system_design/task_screen.dart:30-38, 218-287 |

### 7. Màn đọc: vuốt snap theo card và menu mục lục

Trước hotfix #35 một cú vuốt trôi theo quán tính nhiều card, và vì "đã đọc" tính theo mép dưới đi qua viewport nên card bị bỏ qua cũng bị đánh dấu. Bây giờ `SingleChildScrollView` của màn đọc dùng physics riêng, và có thêm menu nhảy tới section.

| | Cách hoạt động | Toạ độ |
|---|---|---|
| Bảng mốc | `_anchors()` đo layout thật mỗi lần gọi: offset để đỉnh card chạm đỉnh viewport; card đầu section lấy đỉnh tiêu đề section, card đầu tài liệu lấy 0; kèm cờ `sectionStart`. Vuốt snap và menu dùng chung bảng này | mobile/lib/features/system_design/reader_screen.dart:287-323 |
| Fling | vận tốc ≥ 300 px/s thì đích là mốc kế tiếp theo chiều vuốt (hết mốc thì tới biên nội dung), nhưng không xa hơn 0,9 chiều cao viewport so với vị trí hiện tại; card cao hơn màn hình được đọc bằng nhiều lần vuốt. Mô phỏng ease-out 0,2-0,4 giây tới đúng đích | mobile/lib/features/system_design/card_snap_physics.dart:14-18, 59-90, 94-121 |
| Kéo chậm | vận tốc dưới ngưỡng, hoặc đang kéo quá biên: nhường cho physics mặc định (cuộn tự do) | mobile/lib/features/system_design/card_snap_physics.dart:41-44 |
| Đánh dấu đã đọc | luật cũ giữ nguyên (mép dưới đi qua mép dưới viewport); physics chặn việc bỏ qua nên card chưa hiện không bị đánh dấu | mobile/lib/features/system_design/reader_screen.dart:329-350 |
| Menu | nút `sd-reader-menu` mở bottom sheet trắng nhóm theo chapter. Trạng thái xong lấy từ server (`done` ban đầu và kết quả PUT, tập `_doneNotified`), khoá lấy từ `_unlocked` (`unlocked` ban đầu và `next_section_id`); không tự đếm card ở client | mobile/lib/features/system_design/reader_screen.dart:380-420, mobile/lib/features/system_design/reader_menu.dart:25-103 |
| Nhảy | chạm section mở: đóng sheet rồi `animateTo` mốc `sectionStart` của section đó; chạm section khoá: SnackBar "Hoàn thành section trước để mở khoá", không nhảy. `_menuJumps` > 0 trong lúc cuộn thì `_evaluate` không đánh dấu card nào; xong thì `_startIndex` đặt về card đầu section đích rồi đánh giá lại | mobile/lib/features/system_design/reader_screen.dart:149-151, 338, 424-450 |

```dart
// mobile/lib/features/system_design/reader_screen.dart:325
late final _snapPhysics = SdCardSnapPhysics(anchors: _snapOffsets);
```

## Ranh giới & đánh đổi

| Chọn | Thay vì | Vì sao |
|---|---|---|
| Bảng `sd_*` riêng, ngoài `load_content` và hàng chờ duyệt | nhét vào cây nội dung code | nội dung SD là tài liệu đọc, không phải bài chấm bằng test; nhập lại không được phá tiến độ (xem `docs/DECISIONS.md`) |
| Server tính `done`/`unlocked` | client tự suy từ số card đã đọc | một nguồn sự thật; tránh app mở khoá mà PUT bị 409 hoặc ngược lại |
| Chấm từ khoá ngay + chấm sâu qua MCP | gọi LLM trực tiếp từ backend | không giữ API key LLM, không tốn tiền mỗi lần nộp; Claude chat đã sẵn có qua MCP |
| Nhóm id theo nội dung (card) và theo tên (section/task) | id tự tăng / UUID | card sửa nhẹ vẫn giữ tiến độ các card khác; đổi tên là hành vi hiếm, hậu quả đã ghi rõ |
| Vuốt snap bằng `ScrollPhysics` tuỳ biến trên `SingleChildScrollView` | `PageView` (mỗi card một trang) | card cao hơn màn hình sẽ không đọc trọn được trong một trang; physics chặn mỗi cú vuốt ≤0,9 viewport nên card dài vẫn đọc bằng nhiều lần vuốt (xem `docs/DECISIONS.md`) |
| Mọi task Phase 2 mở cùng lúc | khoá tuần tự task sau chỉ mở khi task trước có lần thử | người học muốn làm task nào trước cũng được; Phase 2 vẫn chỉ mở khi Phase 1 xong; đổi một dòng ở server, client chỉ theo (xem `docs/DECISIONS.md`) |

Không làm: màn admin trong app; SRS cho card; LLM chấm trực tiếp; tool xoá hay tự duyệt trong MCP; học viên đọc bài của học viên khác (học viên chỉ có route `/api/sd`, luôn lọc theo `user.id`; MCP là đường của admin đã được cấp quyền, đích phải còn là admin — backend/app/mcp_auth.py:205-218, backend/app/mcp_server.py:74-83).

### Các bất biến của run và cách đã được kiểm

| Mã | Bất biến | Test / kiểm | Toạ độ |
|---|---|---|---|
| INV-01 | Nhập lại cùng tài liệu không xoá tiến độ của card không đổi (kể cả khi file lưu NFD) | `tests/test_sd_admin.py` (nhập lại, NFD, slug Hán/Hàn/Cyrillic); reviewer mối nối bắt vỡ ở NFD rồi sửa | backend/app/sd/parser.py:73, 373; backend/app/sd/admin.py:88-91; backend/app/sd/learner.py:48-70 |
| INV-02 | Response học viên không chứa rubric/từ khoá/điểm nội bộ | `tests/test_sd_learner.py`, `tests/test_sd_attempts.py`; 422 không echo input | backend/app/sd/learner.py:73-92; backend/app/sd/attempts.py:53-75 |
| INV-03 | Bản reviewed thắng auto; API và app hiện cùng một bản | `tests/test_sd_attempts.py`, `tests/test_sd_mcp.py`, `mobile/test/sd_task_flow_test.dart` | backend/app/sd/attempts.py:53-75; backend/app/mcp_server.py:286-296 |
| INV-04 | Khoá/xong chỉ tính ở server; `DuoPath` chỉ vẽ | `tests/test_sd_learner.py`, `mobile/test/duo_path_test.dart` | backend/app/sd/learner.py:48-92 |
| INV-05 | Tab Design không đổi hành vi 4 tab cũ | `mobile/test/app_drawer_test.dart`, `mobile/test/issue29_e2e_test.dart`, `mobile/test/phase2_screens_test.dart` | mobile/lib/app/router.dart:30-72 |
| INV-06 | Câu trả lời học viên A không đọc được bởi B | mọi query ở route học viên lọc `user.id`; MCP qua `authorize_sub` mỗi lần | backend/app/sd/learner.py:104; backend/app/sd/attempts.py:154-155; backend/app/mcp_server.py:77 |

Reviewer mối nối trả lời đủ 6 mã "còn đúng" với `file:dòng` (`planning/crew/2026-10-12-system-design-mode/reviews/SEAM.md`), sau khi INV-01 từng vỡ ở bản đầu.

## Giới hạn đã biết

- Backlog của run (STATUS.md): F3 màn đọc dựng cả tài liệu một lần (1000 card ≈ 12k element, mở ≈411ms ở debug test; trần server 3000 card; đổi sang sliver sẽ phá cách đo hình học của "đã đọc"); BK-1 `task.id` là slug tên task; BK-2 nhập lại làm Phase 1 mất `done` thì Phase 2 khoá lại, app báo "Task này chưa mở" sai lý do và ẩn lịch sử dù server vẫn cho GET lịch sử; BK-3 màn đọc tăng thanh tiến độ cục bộ sau 409 dù server không ghi; BK-4 node "Bối cảnh" không bao giờ `done` nếu tài liệu không có task.
- Oracle ✓/✗ từng ý: học viên thấy ý nào trúng nên có thể dò từ khoá bằng cách thử (bisect), giới hạn bởi 20 lần/ngày/task; hệ quả của thiết kế feedback, chấp nhận (DEVIATIONS.md).
- Rủi ro dư prompt injection: `answer` đi vào ngữ cảnh của Claude; đã có `answer_notice`, `INSTRUCTIONS`, docstring tool và `replace=false` mặc định, nhưng `sd_submit_feedback` không buộc `attempt_id` với lần vừa đọc và không có token một lần (DEVIATIONS.md, cố ý: số admin = 1).
- id lần thử (`attempt_id`) là toàn cục và lộ cho học viên qua `attempt_view`; khoá advisory dùng `hashtext` 32-bit (va chạm chỉ gây tuần tự hoá thừa, không sai dữ liệu).
- Chưa có màn admin trong app để nhập `.md` (hiện gọi API); `GET /api/sd/docs` đọc card của mọi tài liệu để tính `done` (đo lại khi có tài liệu lớn).
- "Bối cảnh `done`" ở client suy ra từ `tasksDone > 0` vì server không có field riêng.
- Vuốt snap chỉ được kiểm bằng widget test (`tester.fling`, `mobile/test/sd_reader_test.dart`); chưa thử trên thiết bị thật, và Chrome desktop không mô phỏng được fling. Cuộn bằng con lăn/trackpad trên web không có code riêng nên giữ hành vi mặc định của Flutter; chưa xác minh bằng test hay chạy thật.
- Section vẫn khoá tuần tự (section sau chỉ mở khi section trước `done`); chỉ task Phase 2 là không khoá tuần tự. Menu nhảy được tới mọi section đã mở khoá, kể cả section đã xong.
- Test đua nhau thật giữa nhập lại và PUT progress chưa có (hạ tầng test dùng một connection); nhập đồng thời và chấm đồng thời có test nhiều luồng (`tests/test_sd_concurrency.py`). Chưa chạy trên thiết bị thật; app đã chạy trên web Chrome 390px.

### Cách chạy test và e2e

| Việc | Lệnh |
|---|---|
| Backend | `cd backend && TEST_DATABASE_URL=postgresql+psycopg://localhost:5432/<db_test_riêng> python -m pytest -q tests/test_sd_*.py` — tên DB phải kết thúc `_test` (conftest từ chối tên khác); DB dùng chung hay đỏ lẻ tẻ khi phiên khác nâng migration |
| Flutter | `cd mobile && flutter test` (các file `test/sd_*_test.dart`, `test/duo_path_test.dart`) |
| E2E HTTP | `planning/crew/2026-10-12-system-design-mode/e2e/backend_e2e.py` (15/15, kết quả ở `backend_e2e.out`) |
| E2E app web thật | dựng DB + tài liệu bằng `e2e/web_e2e_setup.py`, `flutter build web --dart-define=API_URL=http://127.0.0.1:8791`, chạy `e2e/web_e2e_server.py` (backend và web cùng origin, `AUTH_OPEN_AS` mở sẵn một user) rồi điều khiển Chrome khung 390px; kịch bản và ảnh chụp ở `e2e/web_e2e.md`, `e2e/screens/` |

Kết quả lúc chưng cất: backend 805 passed, 2 skipped; Flutter 741 passed (STATUS.md). E2E web thật bắt được một lỗi widget test không thấy: bảng trong màn đọc rộng hơn khung điện thoại và cắt cột phải; đã sửa ở `block_renderer.dart` (bảng co theo bề rộng, chữ xuống dòng).

## Nguồn

backend/app/sd/parser.py:1-520; backend/app/sd/admin.py:1-172; backend/app/sd/learner.py:1-205; backend/app/sd/attempts.py:1-309; backend/app/sd/evaluator.py:1-39; backend/app/tables.py:235-336; backend/migrations/versions/0007_system_design.py:1-97; backend/app/mcp_server.py:54-83, 251-296; backend/app/mcp_auth.py:205-218; backend/app/main.py:37-39, 68-70; backend/content/sd/airline-reservation.md; mobile/lib/domain/sd_models.dart; mobile/lib/data/sd_repository.dart; mobile/lib/app/router.dart; mobile/lib/features/shell/app_shell.dart; mobile/lib/features/shell/app_drawer.dart; mobile/lib/features/system_design/*.dart; .claude/rules/engineering/hostile-input-budget.md:1-30; planning/crew/2026-10-12-system-design-mode/PLAN.md, STATUS.md, DEVIATIONS.md, reviews/SEAM.md, e2e/web_e2e.md; hotfix #35: planning/crew/2026-10-12-sd-reader-hotfix/PLAN.md, DEVIATIONS.md, commit d11fb5f, b88ef84, f3561a8, 7de557b.
