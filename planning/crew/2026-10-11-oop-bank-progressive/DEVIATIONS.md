# Deviations — append-only
- Plan crew mặc định: worktree + PR · Thực tế: thẳng trên main (memory work-directly-on-main) · Duyệt: user
- verify-task T-01 exit 4 vì mobile/ios/ci_scripts/ci_post_clone.sh · Thực tế: file được sửa + stage lúc 22:43 bởi người/phiên khác (không phải worker, không có trong baseline) · Quyết định: coi là nhiễu ngoài (giới hạn đã biết của baseline), owned 3 file đều có diff; commit chỉ theo path để không kéo file user đã stage · Duyệt: orchestrator
- DB test mặc định smart_coding_study_test bị phiên mcp-content (worktree crew-2026-10-11-mcp-content, 0005_mcp_access.py) nâng lên 0005 → pytest mặc định lỗi môi trường · Quyết định: chạy với TEST_DATABASE_URL DB sạch scs_progressive_verify_test, không đụng DB dùng chung · Duyệt: orchestrator
