# DEVIATIONS (append-only)

- Plan crew mặc định: worktree/branch mới · Thực tế: PR #4 đang mở trên branch cũ · Quyết định: dùng lại worktree + branch, run dir mới · Duyệt: user (mục tiêu /crew nêu rõ)
- Plan AC T-02: editor bàn phím đóng ≥45% chiều cao màn · Thực tế: không khả thi (360x640 chỉ còn ~280dp cho đề+editor sau header/Run/2 thanh gợi ý), và đo thật lộ lỗi editor 173.5dp < 200 cũ · Quyết định: AC mới = khung editor ≥200dp mọi size + cao hơn vùng đề bài + không overflow; ý định 'editor lấy phần lớn' giữ nguyên · Duyệt: orchestrator (AC số do orchestrator đặt sai; báo user ở P4)
- Plan: T-01b sửa bởi worker · Thực tế: worker chạm giới hạn lượt 2 lần, để lại widgets.dart ở bản phá tạm (button: true) và 2 test chỉ kiểm 'có Semantics' · Quyết định: orchestrator khôi phục từ bản cp, tự viết 2 test isSemantics + maxLines ScreenHeader (nguyên nhân gốc T-02 tìm ra), giao re-review độc lập · Duyệt: orchestrator
