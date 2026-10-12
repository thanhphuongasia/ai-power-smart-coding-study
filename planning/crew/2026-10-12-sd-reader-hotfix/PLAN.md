# /crew — Hotfix #35: màn đọc System Design (vuốt từng card, menu mục lục) và task không khoá tuần tự

Run: `planning/crew/2026-10-12-sd-reader-hotfix/` · Branch `crew/2026-10-12-sd-reader-hotfix` · base **`origin/main` @ 632f5a3**
Issue cha: **#35** (đã có, dùng lại) · PR mới, body `Closes #35` · **không merge**.

## Context

PR #32 (chế độ học System Design) đã merge và deploy; user dùng thử trên điện thoại, ba điểm khó dùng:
1. Một cú vuốt trôi thẳng rất xa, bỏ qua nhiều card (và vì "đã đọc" tính theo mép dưới đi qua viewport nên card bị bỏ qua cũng bị đánh dấu đã đọc). Muốn: **mỗi lần vuốt chỉ sang đúng một card kế tiếp**.
2. Màn đọc chỉ có nút quay lại. Muốn: **hamburger menu** mở danh sách chapter/section để nhảy về section cần đọc lại.
3. Task Phase 2 khoá tuần tự ("Làm task trước để mở khoá"). Muốn: **không khoá task sau**; Phase 2 vẫn chỉ mở khi Phase 1 xong.

## P0/P1 — phát hiện

| Phát hiện | Hệ quả |
|---|---|
| Thư mục gốc đang ở `ci/deploy-vps-on-merge`, cũ hơn `origin/main` 52 commit; `pbxproj` sửa dở | Worktree base `origin/main`; không chạm pbxproj; sau `worktree add` chạy `git branch --unset-upstream` rồi `push -u`; kiểm `gh pr view` trước MỌI lần push (đã dính "push sau merge" 3 lần) |
| PR #33 (docs) đã merge → `docs/modules/sd-study.md` có trong main | Hotfix được sửa docs; **docs làm TRƯỚC khi mở PR** (không đợi P5 sau PR, vì user merge rất nhanh) |
| Màn đọc: `SingleChildScrollView` + `ScrollController` mặc định; `_evaluate` đánh dấu card có mép dưới ≤ mép dưới viewport (`reader_screen.dart` ~276-300); thanh trên chỉ có `_TopBar` + nút back (`Key('sd-reader-back')`) | T-03 thay physics bằng bản "snap theo card"; T-04 thêm menu |
| Khoá task nằm ở `_tasks_state` (`backend/app/sd/learner.py:73-92`, `unlocked = phase2 and prev_done`), `attempts.py` dùng lại hàm đó | Đổi MỘT chỗ ở server, client và test chỉ cần theo; không đổi schema, **không migration** |
| Migration head 0007, không PR nào khác mở | Không có rủi ro hai head |

## Quyết định thiết kế

1. **Snap theo card bằng `ScrollPhysics` tuỳ biến** (file mới `card_snap_physics.dart`), không đổi sang `PageView` (card cao hơn viewport sẽ không đọc được trọn). Quy tắc fling: vận tốc ≥ ngưỡng → đích là mốc card kế tiếp (hoặc trước đó nếu vuốt ngược), **nhưng không bao giờ xa hơn ~0,9 chiều cao viewport so với vị trí hiện tại** ⇒ không bỏ qua nội dung chưa từng hiện; card cao hơn viewport được đọc bằng nhiều lần vuốt. Kéo chậm/giữ tay (không phải fling) vẫn cuộn tự do. Cuộn bằng con lăn/trackpad trên web giữ tự do.
2. Luật "đã đọc" giữ nguyên (mép dưới đi qua mép dưới viewport) vì physics đã chặn việc bỏ qua; test chứng minh một fling chỉ đánh dấu những card thật sự hiện ra.
3. **Menu** = `showModalBottomSheet` trắng (hằng màu tờ giấy, không dùng palette): nhóm theo chapter, mỗi section một dòng với trạng thái **xong** (✓), **đang đọc**, **khoá**. Trạng thái xong/khoá lấy từ server (`SdSection` ban đầu + kết quả PUT), **không** tự đếm card ở client. Chạm section mở → đóng sheet và `animateTo` đầu section; chạm section khoá → SnackBar, không nhảy.
4. **Task**: `unlocked = phase2` cho mọi task; `done = attempts >= 1` giữ nguyên; `prompt/hints/ref` vẫn chỉ trả khi task mở. Client không còn thông báo 'Làm task trước để mở khoá'.
5. Docs: cập nhật `docs/modules/sd-study.md` (luật mở khoá, vuốt, menu), thêm quyết định mới **ở cuối** `docs/DECISIONS.md` (append-only), sửa toạ độ file:dòng bị lệch; chạy `verify-distill.sh`.

## Sổ bất biến

```text
INV-01 · Mở khoá/xong của section và task chỉ do server tính; menu mục lục và lộ trình chỉ vẽ
         phải khớp: backend/app/sd/learner.py · mobile/lib/features/system_design/reader_menu.dart · mobile/lib/features/system_design/sd_path_screen.dart
         vỡ thì thấy gì: menu cho nhảy tới section server đang khoá, hoặc hiện ✓ cho section server chưa tính done; hoặc node task mở ở app mà POST attempt trả 409
INV-02 · Một cú vuốt không làm lộ hay đánh dấu đã đọc nội dung mà người đọc chưa thấy
         phải khớp: mobile/lib/features/system_design/card_snap_physics.dart · mobile/lib/features/system_design/reader_screen.dart
         vỡ thì thấy gì: vuốt nhanh một lần rồi PUT progress chứa cả chục card chưa từng hiện trên màn; section "xong" mà chưa đọc
INV-03 · Mọi task Phase 2 mở khi và chỉ khi Phase 1 xong, cùng một quy tắc ở path, màn task, POST attempt, nút 'Bắt đầu'
         phải khớp: backend/app/sd/learner.py · backend/app/sd/attempts.py · mobile/lib/features/system_design/sd_path_screen.dart · mobile/lib/features/system_design/task_screen.dart
         vỡ thì thấy gì: task khoá khi Phase 1 đã xong; hoặc POST attempt 201 khi Phase 1 chưa xong
INV-04 · Menu nhảy section và vuốt snap dùng cùng bảng mốc card/section; nhảy xong thì vuốt tiếp vẫn sang đúng card kế
         phải khớp: mobile/lib/features/system_design/reader_menu.dart · mobile/lib/features/system_design/card_snap_physics.dart · mobile/lib/features/system_design/reader_screen.dart
         vỡ thì thấy gì: chọn section từ menu rồi vuốt một lần thì nhảy sai card, kẹt, hoặc không vuốt được
```

## Task contract

Chung: worktree `$WT` = `/Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-10-12-sd-reader-hotfix`. Backend validation: `cd $WT/backend && TEST_DATABASE_URL=postgresql+psycopg://localhost:5432/smart_coding_study_hf_test /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study/backend/.venv/bin/python -m pytest -q <test>` (worktree không có `.venv`; DB test riêng). Mobile validation: `cd $WT/mobile && flutter pub get && flutter test <test>`. Forbidden chung: `mobile/ios/**`, `backend/migrations/**`, `backend/app/tables.py`, theme.dart, pubspec.yaml, router.dart, mọi file ngoài danh sách owned. Evidence = `git diff --stat -- <owned>`. Worker không commit; chỉ `dart format` đúng file của mình; cấm `git stash/checkout/reset/restore/clean`. Gate: `verify-task.sh` với `--owned` đúng danh sách, `--optional planning/` và các file của worker song song, ghi output ra file rồi lấy `$?` (không `| tail` trong chuỗi `&&`).

| ID | Role · tier · model | Objective | Owned files | Acceptance | Validation (1 lệnh) |
|---|---|---|---|---|---|
| T-01 | `crew-impl-standard` · T2 · sonnet | Server: mọi task mở khi Phase 1 xong | `backend/app/sd/learner.py`, `backend/tests/test_sd_learner.py`, `backend/tests/test_sd_attempts.py` | `_tasks_state`: `unlocked = phase2` cho mọi task; `done = attempts>=1`; prompt/hints/ref chỉ khi mở; POST attempt cho task bất kỳ khi Phase 2 mở → 201, khi Phase 2 chưa mở → 409 `task_locked`; docstring module cập nhật; test sửa theo (mutant: khôi phục `prev_done` → đỏ; mutant: bỏ `phase2` → đỏ) (INV-01, INV-03) | pytest `tests/test_sd_learner.py tests/test_sd_attempts.py` |
| T-02 | `crew-impl-standard` · T2 · sonnet | Client theo luật mới: không còn khoá task tuần tự | `mobile/lib/features/system_design/sd_path_screen.dart`, `task_screen.dart`, `context_screen.dart`, `mobile/test/sd_path_screen_test.dart`, `mobile/test/sd_task_flow_test.dart` | Task chỉ khoá khi Phase 2 khoá (thông báo 'Đọc xong Phase 1 để mở Thực chiến'); không còn chuỗi 'Làm task trước để mở khoá'; node `current` vẫn đúng một (node mở chưa xong đầu tiên theo thứ tự section…, bối cảnh, task); 'Task tiếp theo' và nút 'Bắt đầu' dùng dữ liệu server; fixture test: mọi task mở khi Phase 2 mở, kiểm làm task thứ 3 trước task thứ 2 (INV-01, INV-03) | `flutter test test/sd_path_screen_test.dart test/sd_task_flow_test.dart` |
| T-03 | `crew-impl-standard` · T2 · sonnet | Vuốt từng card (snap physics) | `mobile/lib/features/system_design/card_snap_physics.dart` (mới), `reader_screen.dart`, `mobile/test/sd_reader_test.dart` | Fling tiến → card kế (tối đa ~0,9 viewport); fling lùi → card trước; kéo chậm vẫn tự do; card cao hơn viewport đọc trọn bằng nhiều lần vuốt, không bỏ nội dung; một fling chỉ đánh dấu những card thật sự hiện ra (PUT chỉ chứa chúng); biên đầu/cuối, vận tốc nhỏ, nhảy mở màn `?section=`; bảng mốc card dựng lại khi layout đổi (INV-02, INV-04). Mutant: physics mặc định → test fling đỏ | `flutter test test/sd_reader_test.dart` |
| T-04 | `crew-impl-standard` · T2 · sonnet (sau T-03) | Hamburger menu mục lục | `mobile/lib/features/system_design/reader_menu.dart` (mới), `reader_screen.dart`, `mobile/test/sd_reader_menu_test.dart` (mới), `mobile/test/sd_reader_test.dart` | Nút `Key('sd-reader-menu')` trên thanh trên (giữ nút back); sheet trắng cuộn được (tới 200 section) nhóm theo chapter, trạng thái xong/đang đọc/khoá lấy từ server; chạm section mở → đóng sheet + cuộn tới đầu section; section khoá → SnackBar, không nhảy; đích tap ≥48dp, semantics; sau khi nhảy vuốt snap vẫn đúng (INV-01, INV-04). Mutant: cho nhảy section khoá → đỏ | `flutter test test/sd_reader_menu_test.dart test/sd_reader_test.dart` |
| T-05 | `crew-distill` · T2 · sonnet (sau T-01..T-04) | Docs trước khi mở PR | `docs/modules/sd-study.md`, `docs/DECISIONS.md` (chỉ append), `docs/ARCHITECTURE.md` (nếu toạ độ lệch) | Luật mở khoá task mới, vuốt snap, menu; quyết định mới ở CUỐI DECISIONS; toạ độ file:dòng đúng; `verify-distill.sh` exit 0 | `CLAUDE_PROJECT_DIR=$WT ~/.claude/scripts/verify-distill.sh` |

Thứ tự: **T-01 ∥ T-02 ∥ T-03** (file rời nhau) → T-04 (cùng `reader_screen.dart` với T-03) → T-05. Checkpoint: full `pytest` backend và full `flutter test` sau T-04. Rủi ro cao làm sớm: T-03 (physics).

## Review

`crew-review` cho T-01, T-02, T-03, T-04 (T2, không phải L4 nên không bắt buộc review ngoài; vẫn bắt reviewer chạy mutant trên **bản sao ngoài git**, cấm `git stash`). Sau mọi task: reviewer mối nối trả lời INV-01..04 vào `reviews/SEAM.md` (không nhận danh sách file) + `verify-seam.sh`. Tên bất biến chỉ `INV-NN`, PLAN không nhắc mã INV của docs.

## E2E (orchestrator tự chạy trước khi mở PR)

1. Backend HTTP thật (uvicorn + Postgres riêng): Phase 1 chưa xong → POST attempt mọi task 409; Phase 1 xong → POST task thứ 3 trước task thứ 1 trả 201, danh sách task không còn khoá.
2. App web thật cùng origin (cách đã dùng ở run trước: `StaticFiles` + `phone.html` 390px + Chrome): Home → Design → tài liệu → lộ trình Phase 2: các task đều mở; mở màn đọc → bấm hamburger → danh sách chapter/section đúng trạng thái → chọn section → nhảy đúng; section khoá không nhảy; chụp ảnh vào `e2e/screens/`.
3. Vuốt fling thật không mô phỏng được trên Chrome desktop → bằng chứng là widget test dùng `tester.fling`; ghi rõ giới hạn "chưa thử trên thiết bị thật" vào PR.

## Ngoài phạm vi (ghi, không sửa)

Dựng tài liệu lười/sliver (Backlog F3 cũ), BK-1..BK-4, SRS cho card SD, màn admin nhập `.md`. Production đã có tài liệu airline (nhập tay sau PR #32): hotfix không cần migration hay nhập lại.
