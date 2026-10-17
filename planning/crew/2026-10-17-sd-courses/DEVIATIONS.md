# DEVIATIONS — 2026-10-17-sd-courses

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| T-04: đổi kiểu listDocs/sdDocsProvider sang SdDocsIndex (gợi ý) | Giữ List<SdDocSummary>, gắn SdCourse vào từng doc (courseId + course) | Chấp nhận: đổi kiểu provider làm vỡ test/sd_path_screen_test.dart ngoài ownership; hợp đồng API không đổi | orchestrator |
| External T-01 Medium: `skills or []` nuốt giá trị sai kiểu | Chỉ None → []; test "" và 0 | Chấp nhận | orchestrator |
| T-03: "test_sd_learner.py xanh, không sửa assert" | Assert khoá đúng `{"items": []}` mâu thuẫn hợp đồng (luôn có key `courses`) | Sửa 1 assert thành `{"items": [], "courses": []}` (thêm file vào owned T-03); key mới là thêm, tương thích ngược | orchestrator |
| Review T-01 Minor 1 (validate position sau khoá), T-04 Minor 1 (parse courses quá chặt) | Sửa: validate trước khoá; correction task T-04b nới parse course | Chấp nhận | orchestrator |
| Review T-01 Minor 3–6, T-04 Minor 2, 4, 5 | Không sửa | Backlog | orchestrator |
