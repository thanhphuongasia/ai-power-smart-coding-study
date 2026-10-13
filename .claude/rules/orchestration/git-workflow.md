# PR base cho repo này: luôn `dev`, không phải branch gốc lúc P0

Ghi đè một điểm trong `~/.claude/rules/orchestration/git-workflow.md` (base rule của
`/crew`): base rule đó lấy "branch gốc lúc P0" (branch đang checkout khi bắt đầu run)
làm base cho `gh pr create`. Ở repo này, **base luôn phải là `dev`**, bất kể lúc bắt đầu
run đang đứng ở branch nào — không dùng branch gốc lúc P0 làm base.

## Vì sao

`main` của repo này tự động deploy lên production ngay khi có push (xem `CLAUDE.md`
mục Deploy). Nếu P0 chạy khi đang đứng ở `main` (rất dễ xảy ra — đó thường là nhánh mặc
định sau khi clone/pull), PR theo rule gốc sẽ nhắm thẳng `main`, và merge nó sẽ tự động
đẩy lên production ngay — đúng loại sự cố đã xảy ra ngày 2026-10-13 (xem `CLAUDE.md`).

## Áp dụng

Ở P2 của `/crew` (bước tạo worktree + branch), sau khi tính `BR`/`WT` theo rule gốc,
thêm bước: branch mới (`crew/<date>-<slug>`) checkout ra **từ `origin/dev`** (fetch
trước), không phải từ HEAD hiện tại của thư mục đang đứng:

```bash
git fetch origin dev --quiet
git worktree add "$WT" -b "$BR" origin/dev
```

Ở P4 bước `gh pr create`, đặt `--base dev` tường minh, không suy ra từ branch gốc:

```bash
gh pr create --base dev --head "$BR" ...
```

Các phần còn lại của `git-workflow.md` gốc (worktree riêng/phiên, không `checkout -b`
trên thư mục dùng chung, commit/push/PR ở P4, không bao giờ `gh pr merge` tự động) giữ
nguyên, không đổi gì thêm.

## Giới hạn đã biết

- Rule này chỉ đổi NGUỒN base (`origin/dev` thay vì HEAD cục bộ) và `--base` của PR —
  không tự tạo `dev` nếu chưa tồn tại. `dev` đã được tạo thủ công 2026-10-13 từ `main`
  lúc đó; nếu `dev` bị xoá, phải tạo lại trước khi `/crew` chạy được ở repo này.
- Không có script kiểm — nếu một phiên `/crew` lỡ mở PR nhắm `main`, phải tự phát hiện
  bằng mắt (`gh pr view <n> --json baseRefName`) và `gh pr edit <n> --base dev` sửa lại.
