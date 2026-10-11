# Deviations — 2026-10-11-content-api-postgres

| Plan nói gì | Thực tế là gì | Quyết định | Ai duyệt |
|---|---|---|---|
| merge.dart không thuộc task nào | Bị định dạng lại bằng dart format (chỉ whitespace) trong lúc T-03 chạy; worker nói không đụng | Orchestrator khôi phục bản HEAD bằng git show (không có thay đổi logic) | orchestrator |
| T-07 owned không gồm mobile/macos/Flutter/GeneratedPluginRegistrant.swift | flutter pub add shared_preferences tự sinh lại file này (đăng ký plugin macOS) | Chấp nhận (file sinh tự động, cần cho build macOS) | orchestrator |
| Checkpoint: suite mobile luôn xanh giữa các wave | T-06 xoá backend/app/exercises.json trước T-09 → mobile/test/judge_contract_test.dart đỏ (không thấy file) | Chấp nhận đỏ tạm; T-09 thay test này bằng content_contract_test đọc content.json (đã có trong contract T-09) | orchestrator |
