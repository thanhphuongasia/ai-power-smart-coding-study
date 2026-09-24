# STATUS — 2026-09-24-flutter-demo-core

Worktree: /Users/phuongmacbook/Developer/Personal/Projects/ai-power-coding-study.worktrees/crew-2026-09-24-flutter-demo-core
Branch:   crew/2026-09-24-flutter-demo-core
Issue:    #3 — https://github.com/thanhphuongasia/ai-power-smart-coding-study/issues/3
State: done — PR mở, chờ user merge

| Task | Trạng thái |
|---|---|
| T-00 scaffold | done (commit e49a942, 72420bc) |
| T-01 domain+seed+checker | done — re-review vòng 2 PASS; commit 05ef6dc |
| T-02 theme+widgets | done — review PASS với Minor; commit 05ef6dc |
| T-03 autocomplete | done — review vòng 3 PASS; committed |
| T-04 session | done — review PASS với Minor; commit (session) |
| T-05 browse | done — vòng 2 PASS với Minor; committed |
| T-02b DS fixes (Minor T-02) | done — re-review vòng 2 PASS với Minor; committed |
| T-06 block list+cell+router | done — T-06b (layout bàn phím 360x640) + vòng 2 PASS với Minor; commit e644d9d |
| T-04b start() idempotent (timer reset mỗi block — lỗi mối nối T-04↔T-06) | done — re-review T-04 vòng 2 PASS; committed |

Next action: user review + merge PR. Sau merge: dọn worktree (git worktree remove + git branch -d). Phase 2 theo issue riêng.
E2E orchestrator: analyze sạch, 168 test pass, app_flow_test pass, INV-04 grep sạch (accent chỉ trong _showHintSheet), web build + ảnh chụp OK (Chrome headless không xuống <500px — đo layout 360 bằng widget test).

## Backlog
- T-02 Minor: PrimaryButton/HintButton ElevatedButton còn elevation mặc định (widgets.dart:266,335) → T-02b ở checkpoint
- T-02 Minor: SurfaceCard mặc định nền surface thay vì surfaceRaised (widgets.dart:22) → T-02b ở checkpoint
- T-03 Minor: thiếu test ghép dòng 2 chunks.append — gộp vào T-03b
- T-04 Minor: run() không bounds-check blockIndex (session_controller.dart:250)
- T-04 Minor: doc session_providers.dart:22 chưa nêu caller phải ref.watch (đã đưa vào contract T-06)
- T-02b: focus ring 2px mới cho input, chưa cho nút
- T-05 Minor: completedBlocksIn/totalBlocksIn nằm trong home_screen.dart, theme_detail import ngang (nên chuyển lib/domain)
- T-06 Minor: router.dart:38 int.parse(index) không try/catch
- T-06 Minor: code block đã xong lặp giữa block_list_screen.dart:199 và cell_screen.dart:348
- T-06 Minor: chưa có test e2e 'quay lại Cell thấy draft cũ' (INV-05)
- UI Minor: nút hint hiện 'Gợi ý (3/3)' khó hiểu (còn 3?); Home 'Block 2/5' vs Block list 'đang làm dở Block 3'
- T-01 Minor: exerciseById/locateExercise lặp vòng duyệt 4 cấp (seed.dart:388-417)
- T-02 Minor: chưa có focus ring 2px primary trong buildAppTheme

## Seam gate
reviews/SEAM.md: INV-01..05 CÒN ĐÚNG; verify-seam.sh exit 0.

## Audit model (từ .jsonl subagent)
sonnet-5: crew-impl-standard (T-01, T-04, T-05, T-06 + correction) và mọi crew-review · haiku-4-5: crew-impl-light (T-02, T-01b, T-01c, T-02b, T-04b) · opus-5-5: T-03, T-03b, T-03c (override đã khai trong plan).

## Backlog bổ sung
- SEAM Minor: biến lặp khai trong CHÍNH block 2 dòng (vd `i` ở overlap-chunks-b2) không được gợi ý ở dòng 2 — nên cho engine quét cả text đang gõ, không chỉ block trước
