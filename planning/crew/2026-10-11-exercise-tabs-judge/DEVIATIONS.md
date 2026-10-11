# Deviations — 2026-10-11-exercise-tabs-judge

| Plan nói gì | Thực tế là gì | Quyết định | Ai duyệt |
|---|---|---|---|
| T-05 AC1: test cũ code_input_test xanh không sửa assertion | Seed mới của T-03 (chạy song song) đổi số block split-chunks 5→3, 4 dòng `_splitChunks[2]/[3]` gãy (RangeError) | Orchestrator đổi chỉ số [2]→[0], [3]→[1] (cùng nội dung lời giải `for`/`append`), không đổi assertion | orchestrator (không đổi AC) |
