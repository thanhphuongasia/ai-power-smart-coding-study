# Plan: thay áo The Coach + responsive web (issue #29)

## Context
Issue #29: https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/29 (issue cha của run, dùng lại, PR sẽ `Closes #29`).
Mockup đã duyệt: https://claude.ai/artifact/5XXRz2EUjngiuZB56HXHF6.
Đã chốt: sáng mặc định (tối vẫn chọn được qua `ThemeModeButton`), font Nunito, web ≥700px bỏ bottom nav → drawer bấm ☰, ≥900px màn luyện chia đôi, gõ ít hơn (chữ mờ gợi ý + dải từ gợi ý). Không đổi backend/API/AdminController/domain.

P0: working tree đang ở nhánh `ci/deploy-vps-on-merge` (HEAD ff51593, không phải main) và `project.pbxproj` sửa dở (không liên quan). Worktree sẽ tạo từ **main** (`git worktree add "$WT" -b "$BR" main`), không từ HEAD hiện tại. PR #26 (màn Soạn bài tập) chưa merge; không chạm cùng file nhưng `widgets.dart` được cả hai dùng (xem INV-05).

## Phát hiện từ khảo sát (quyết định dựa trên đây)
- Chưa có `Scaffold.drawer`, chưa có breakpoint nào; màn chi tiết (theme/topic/exercise) mở trên root navigator nên **không có AppShell** → ☰ không thể chỉ đặt trong shell. Cách làm: `showAppDrawer(context)` mở bằng `showGeneralDialog` (trượt từ trái), dùng được từ mọi màn, chưa mở thì **không có widget nào trong cây** (tránh trùng `find.text` ở test 800x600 của `content_gate_test`).
- Theme mode hiện mặc định `ThemeMode.system` (`app/theme_mode.dart:9`), không lưu; test `phase2_screens_test.dart:54-68` giả định vòng system → light → dark.
- Nunito chưa có; `pubspec.yaml` chỉ khai IBM Plex Sans + JetBrains Mono; không có package `google_fonts` (không thêm).
- Màn luyện: `DefaultTabController` + 3 tab (`exercise_screen.dart:281`); `ChallengeTab`/`SolutionTab` gọi `DefaultTabController.of` (`challenge_tab.dart:131`, `solution_tab.dart:74`); chạm ô mở route `CellEditorPage` (`code_tab.dart:121`). Chấm từng ô tại client bằng `_isDone` (`code_tab.dart:77`); `/run` chỉ ở `CodeTab._run`.
- `code_input.dart` đã có chip gợi ý + vocab nhưng vocab chỉ hiện theo ngữ cảnh, **chưa có ghost text** (chỉ có placeholder phủ bằng Stack ở `:299-325`). `code_input` dùng `ColorScheme`, `code_tab` dùng `palette`: hai nguồn màu.
- Không có `integration_test/`; mọi test là widget test ở 375x667, 412x915, 420x900, mặc định 800x600. Nhánh <700/<900 phải giữ y hệt để test cũ qua.
- `admin_exercise_editor_test` (PR #26) tìm `ElevatedButton` dưới `exercise-apply` và `OutlinedButton` dưới `block-add` → `PrimaryButton`/`GhostButton` phải vẫn là hai widget đó.

## Quyết định thiết kế
1. **Breakpoint một nguồn**: `AppBreakpoint { nav = 700, split = 900 }` trong `theme.dart`. Mọi so sánh bề rộng dùng nó, đo bằng `LayoutBuilder`/`MediaQuery.sizeOf`.
2. **Token**: thêm vào `AppPalette` các vai trò mới (success/successDark, primaryDark cho độ sâu nút, flame, codeSurface/codeInk luôn tối ở cả hai theme) + `AppGradients` cho thẻ chủ đề. Giữ `copyWith`/`lerp` đủ trường.
3. **Nút nổi khối**: `PrimaryButton`/`GhostButton` vẫn bọc `ElevatedButton`/`OutlinedButton`, chỉ thêm bóng cứng bằng `DecoratedBox`/style.
4. **Màn tab ≥700px**: `AppShell` không `NavigationBar`, có top bar mỏng (☰ + tên app + `ThemeModeButton`). Màn con dùng `ScreenHeader` có ☰ khi ≥700px; màn luyện tự đặt ☰ vì header riêng.
5. **Drawer**: nền tối cố định, ô tìm bài (lọc theo tên), 4 mục điều hướng (badge ôn tập), mục lục chủ đề → bài có dấu tích, hàng đổi giao diện sáng/tối ở chân.
6. **Màn luyện ≥900px**: cột trái `ChallengeTab`/`SolutionTab` (tab Đề / Lời giải), cột phải `CodeTab` có dải bước A/B/C và editor ô đang làm **inline** (không mở route). <900px giữ nguyên 3 tab + route `CellEditorPage`. Dải bước và editor inline sống trong `CodeTab` (không lộ state private ra `exercise_screen`).
7. **Gõ ít**: ghost text dựng bằng `buildTextSpan` của controller hiển thị (chỉ phủ hiển thị, không ghi `controller.text`); chấp nhận bằng chạm chip hoặc Tab. Dải vocab của ô hiện luôn (không phụ thuộc ngữ cảnh). Giữ ≤2 dòng/ô, 3 gợi ý.
8. **Nunito**: orchestrator tải 4 TTF (Regular/SemiBold/Bold/ExtraBold, ~0,5MB, giấy phép OFL) từ Google Fonts/GitHub google/fonts vào `mobile/assets/fonts/` ở P2 trước khi dispatch (bạn đã chọn Nunito). Nếu chỉ có bản variable (không có static), T-01 thử `FontVariation('wght')`; nếu không chạy được thì **dừng, hỏi bạn** quay lại IBM Plex Sans.
9. **Không làm** (ghi Backlog): lưu lựa chọn sáng/tối qua `shared_preferences`, màn Cài đặt riêng, vẽ lại `_LessonPath` (chỉ đổi màu qua token), nút micro.

## Tasks (làm trong `$WT/mobile`; mọi task có validation `flutter test <file>` + `flutter analyze`)
Forbidden chung: `lib/domain/**`, `lib/features/admin/**`, `lib/app/router.dart`, backend, `ios/**`.

**Wave 1 (song song)**
- **T-01** · T2 · crew-impl-standard · sonnet · L2 — token, font, nút, thẻ.
  Owned: `lib/app/theme.dart`, `lib/shared/widgets.dart`, `pubspec.yaml`, `test/theme_test.dart` (+ font đã tải sẵn ở `assets/fonts/`).
  Acceptance: `AppBreakpoint`, token mới ở `dark` và `light` (palette The Coach: primary #4A86E8…), `kSansFamily='Nunito'` + `AppText` theo mockup, `SurfaceCard`/`PrimaryButton`/`GhostButton` kiểu nổi khối và thẻ gradient (INV-05), `theme_test` cập nhật.
- **T-04** · T2 · crew-impl-standard · sonnet · L2 — gõ ít.
  Owned: `lib/features/exercise/code_input.dart`, `lib/features/exercise/completion_engine.dart`, `test/code_input_test.dart`, `test/completion_engine_test.dart`.
  Acceptance: tham số tuỳ chọn `answers`/`ghost` (mặc định tắt = hành vi cũ), ghost text không đổi `controller.text`, Tab/chạm chip nhận gợi ý, hàm vocab luôn hiện, dải vocab; mọi Key cũ (`suggestion-*`, `symbol-*`, `code-input-*`) giữ; khối code nền `codeSurface` khi token có (nếu T-01 chưa xong thì dùng palette hiện có, đổi sang token ở wave sau).

**Wave 2 (song song, sau checkpoint wave 1)**
- **T-02** · T2 · crew-impl-standard · sonnet · L2 — shell + drawer + mặc định sáng.
  Owned: `lib/features/shell/app_shell.dart`, `lib/features/shell/app_drawer.dart` (mới; gồm `AppDrawer`, `showAppDrawer`, `AppMenuButton`), `lib/app/theme_mode.dart`, `test/phase2_screens_test.dart`, `test/app_drawer_test.dart` (mới).
  Acceptance: `<700` giữ `NavigationBar` Key `bottom-nav`; `≥700` không có, có top bar + ☰; drawer đủ nội dung (decision 5), điều hướng bằng `go_router`; `ThemeModeController` mặc định `light`, vòng light → dark → system → light, `phase2` sửa theo.
- **T-05a** · T2 · crew-impl-standard · sonnet · L3 — editor inline + dải bước.
  Owned: `lib/features/exercise/code_tab.dart`, `lib/features/exercise/cell_editor_page.dart`, `test/code_tab_test.dart`, `test/cell_editor_test.dart` (mới nếu cần).
  Acceptance: tách `CellEditorBody` (không `Scaffold`) dùng chung bởi route và inline; `CodeTab(inlineEditor: bool)`, mặc định false = hành vi cũ y hệt; dải bước A/B/C (`step-<L>`); inline dùng cùng `_isDone`/`_onCellChanged`/`saveDraft` (INV-06); nối `answers` của T-04.

**Wave 3 (song song, sau checkpoint wave 2)**
- **T-03** · T2 · crew-impl-standard · sonnet — Home + ☰ ở màn con.
  Owned: `lib/features/browse/home_screen.dart`, `lib/shared/widgets.dart` (chỉ `ScreenHeader` thêm ☰ khi ≥700), `test/browse_screens_test.dart`, `test/phase2_screens_test.dart`? **không** (thuộc T-02) → thêm test mới `test/home_reskin_test.dart`.
  Acceptance: thẻ "Tiếp tục" nổi khối, thẻ **ôn tập đến hạn** (lấy `dueCardsProvider`, chạm → `/review`), thẻ chủ đề gradient; mọi Key Home cũ giữ.
- **T-06** · T1 · crew-impl-light · haiku — màu màn chủ đề/chủ đề nhỏ.
  Owned: `lib/features/browse/theme_detail_screen.dart`, `lib/features/browse/topic_detail_screen.dart`, `lib/features/browse/exercise_row.dart`, `test/browse_reskin_test.dart` (mới).
  Acceptance: header gradient gọn, `Colors.white/black` ở topic_detail (4 chỗ) đổi sang token, không đổi hình học `_HexPainter`/`_LessonPath`; Key `browse_screens_test` giữ.
- **T-05b** · T2 · crew-impl-standard · sonnet · L3 — chia đôi màn luyện.
  Owned: `lib/features/exercise/exercise_screen.dart`, `lib/features/exercise/challenge_tab.dart`, `lib/features/exercise/solution_tab.dart`, `test/exercise_screen_test.dart`, `test/exercise_split_test.dart` (mới).
  Acceptance: `≥900` chia 42/58, ẩn `TabBar`, `ChallengeTab`/`SolutionTab` không gọi `DefaultTabController.of` (callback `onGoCode` hoặc ẩn nút), `CodeTab(inlineEditor: true)`, ☰ trong header; `<900` y hệt cũ (text `Code n/m`, `exercise-tabs`).

Checkpoint sau mỗi wave: `flutter analyze` + `flutter test` toàn bộ, commit trong worktree. Commit checkpoint trước wave 2 và 3 (rule never-checkout). Review `crew-review` (T2) sau mỗi task, không external (không phải L4). Cuối cùng một reviewer mối nối + `verify-seam.sh`.

## Sổ bất biến
- INV-01 · Mọi Key test cũ còn đủ ở bề rộng test cũ (`bottom-nav` <700, `continue-card`, `theme-*`, `topic-*`, `exercise-*`, `cell-*`, `editor-*`, `suggestion-*`, `symbol-*`, `exercise-tabs`, text `Code n/m`)
  phải khớp: `app_shell.dart` · `home_screen.dart` · `code_tab.dart` · `exercise_screen.dart` · `code_input.dart`
  vỡ thì thấy gì: test cũ đỏ vì `find` rỗng.
- INV-02 · Bottom nav và ☰/drawer không cùng lúc: <700 có `NavigationBar` và không `AppMenuButton`; ≥700 ngược lại, ở cả tab và màn con
  phải khớp: `app_shell.dart` · `app_drawer.dart` · `widgets.dart` (`ScreenHeader`) · `exercise_screen.dart`
  vỡ thì thấy gì: ở 800px không có cách điều hướng, hoặc hiện cả hai.
- INV-03 · Ngưỡng 700/900 chỉ định nghĩa ở `AppBreakpoint`, mọi nơi dùng đúng nó
  phải khớp: `theme.dart` · `app_shell.dart` · `widgets.dart` · `exercise_screen.dart`
  vỡ thì thấy gì: nav đổi ở 700 nhưng màn luyện đổi ở 720 (hai nơi lệch), ☰ có mà không có drawer.
- INV-04 · Ghost text/chip gợi ý chỉ phủ hiển thị; `controller.text` chỉ đổi khi người dùng chạm/Tab/gõ
  phải khớp: `code_input.dart` · `code_tab.dart` (`_isDone`, `saveDraft`) · `cell_editor_page.dart`
  vỡ thì thấy gì: draft lưu chứa chữ gợi ý, ô báo "đúng" khi chưa gõ gì.
- INV-05 · `PrimaryButton`/`GhostButton` vẫn render `ElevatedButton`/`OutlinedButton`, `onPressed == null` khi vô hiệu
  phải khớp: `widgets.dart` · `test/admin_exercise_editor_test.dart` (trên PR #26)
  vỡ thì thấy gì: test Soạn bài tập đỏ sau khi hai PR gặp nhau, hoặc nút vô hiệu vẫn bấm được.
- INV-06 · "Ô đúng" chỉ có MỘT nơi quyết định: route (<900) và inline (≥900) cùng đi qua `_isDone`/`_onCellChanged`/`saveDraft`/`_run`
  phải khớp: `code_tab.dart` · `cell_editor_page.dart` (`CellEditorBody`)
  vỡ thì thấy gì: ≥900 báo đúng nhưng Run đỏ (hoặc ngược lại), tiến độ chia đôi lệch giữa hai layout.
- INV-07 · Sáng là mặc định và tối vẫn đủ token: `themeModeProvider` mặc định light; `main.dart`, `content_gate.dart`, `auth_gate.dart` cùng đọc nó; mọi trường palette có ở cả `dark` và `light`
  phải khớp: `theme_mode.dart` · `theme.dart` · `content_gate.dart:76-98` · `auth_gate.dart:92-94`
  vỡ thì thấy gì: màn chờ/đăng nhập tối nhưng app sáng (hoặc ngược lại), chữ tối trên nền tối ở một theme.
- INV-08 · Khối code (editor, preview, lời giải, ghép thử) dùng `codeSurface/codeInk` ở cả hai theme
  phải khớp: `theme.dart` · `code_input.dart` · `code_tab.dart` · `solution_tab.dart`
  vỡ thì thấy gì: theme sáng có khối code nền trắng chữ nhạt khó đọc, hoặc hai khối code lệch màu nhau.
Khái niệm "ô đang làm": hiện ở `CodeTab._open` (accordion) và dải bước `step-*`. Quan hệ: **dải bước suy ra từ `_open`/`progress`** (nằm trong `CodeTab`, không có bản thứ hai ở `exercise_screen`); test: đổi ô ở inline thì `step-*` đổi theo.

## E2E (orchestrator tự chạy trước khi trình commit)
1. `flutter analyze` + `flutter test` toàn bộ xanh.
2. Test mới theo bề rộng 400, 800, 1280, **bắt đầu từ Home** (không mở thẳng route): ≥700 không có `bottom-nav`; ☰ → drawer → chạm một bài (2 chạm) vào được bài; ≥900 chia đôi, gõ vào ô inline bằng chip → ô đúng → `step-*` đổi → Run; 400: cùng luồng qua route `CellEditorPage`; sáng ↔ tối không overflow.
3. `flutter build web` + chụp ba bề rộng (cần bạn chọn trình duyệt kết nối nếu dùng Chrome; nếu không, ghi rõ "chưa xem bằng mắt" trong PR).

## Review & kết thúc
Mỗi task: `crew-review` (11 mã NFR). Sau cùng: reviewer mối nối chỉ nhận contract + sổ INV, ghi `reviews/SEAM.md`, chạy `verify-seam.sh`. PR từ nhánh `crew/<date>-issue29-reskin` vào main, `Closes #29`, không tự merge. Backlog: persist theme mode, màn Cài đặt, vẽ lại lộ trình, micro.
