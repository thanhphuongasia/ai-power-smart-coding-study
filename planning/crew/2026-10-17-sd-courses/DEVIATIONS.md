# DEVIATIONS — 2026-10-17-sd-courses

| Plan nói | Thực tế | Quyết định | Ai duyệt |
|---|---|---|---|
| T-04: đổi kiểu listDocs/sdDocsProvider sang SdDocsIndex (gợi ý) | Giữ List<SdDocSummary>, gắn SdCourse vào từng doc (courseId + course) | Chấp nhận: đổi kiểu provider làm vỡ test/sd_path_screen_test.dart ngoài ownership; hợp đồng API không đổi | orchestrator |
