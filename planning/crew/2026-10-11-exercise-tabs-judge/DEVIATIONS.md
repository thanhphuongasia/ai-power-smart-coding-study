# Deviations — 2026-10-11-exercise-tabs-judge

| Plan nói gì | Thực tế là gì | Quyết định | Ai duyệt |
|---|---|---|---|
| T-05 AC1: test cũ code_input_test xanh không sửa assertion | Seed mới của T-03 (chạy song song) đổi số block split-chunks 5→3, 4 dòng `_splitChunks[2]/[3]` gãy (RangeError) | Orchestrator đổi chỉ số [2]→[0], [3]→[1] (cùng nội dung lời giải `for`/`append`), không đổi assertion | orchestrator (không đổi AC) |
| T-06 owned seed.dart: xoá seedCompletedBlocks | test/seed_test.dart (T-03) còn tham chiếu seedCompletedBlocks, xoá thì gãy compile file ngoài owned | Giữ lại; chuyển việc xoá (seed.dart + seed_test.dart) sang T-10 | orchestrator (không đổi AC) |
