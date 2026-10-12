"""Bảng Postgres chứa nội dung học — DB là nguồn chính. Mọi lần ghi đi qua `load_content.py` (thay toàn
bộ, có kiểm luật): seed từ `content/content.json` khi DB rỗng, hoặc admin lưu qua `/api/admin/content`.
`/content` và `/run` đọc ra.

Thứ tự hiển thị lưu ở cột `position` (theme, topic, file, bài trong file, ô trong bài).
Module lồng nhau = `topics.parent_id`; `topics.position` là thứ tự duyệt trước (preorder) trong theme,
nên con luôn đứng sau cha và thứ tự anh em giữ đúng như `content.json`.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint, func, text
from sqlalchemy.dialects.postgresql import ARRAY, JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Theme(Base):
    __tablename__ = "themes"
    __table_args__ = (UniqueConstraint("position", name="uq_themes_position"),)

    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    position: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(Text)
    description: Mapped[str] = mapped_column(Text)
    tags: Mapped[list[str]] = mapped_column(ARRAY(Text))
    # Sơ đồ class của project (soạn tay trong content.json): {classes, relations}.
    diagram: Mapped[dict] = mapped_column(JSONB)


class Topic(Base):
    __tablename__ = "topics"
    __table_args__ = (UniqueConstraint("theme_id", "position", name="uq_topics_theme_position"),)

    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    theme_id: Mapped[str] = mapped_column(ForeignKey("themes.id", ondelete="CASCADE"), index=True)
    # NULL = module cấp 1 của theme; khác NULL = sub-module.
    parent_id: Mapped[str | None] = mapped_column(
        ForeignKey("topics.id", ondelete="CASCADE"), index=True, nullable=True
    )
    position: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(Text)
    description: Mapped[str] = mapped_column(Text)


class CodeFile(Base):
    __tablename__ = "code_files"
    __table_args__ = (UniqueConstraint("topic_id", "position", name="uq_code_files_topic_position"),)

    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    topic_id: Mapped[str] = mapped_column(ForeignKey("topics.id", ondelete="CASCADE"), index=True)
    position: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(Text)


class Exercise(Base):
    """Một bài. Có thể nằm ở nhiều file (`file_exercises`), vd split-chunks dùng ở 2 theme.

    `judge_solution`/`judge_cases` chỉ dùng cho `/run`, KHÔNG bao giờ trả ra `/content`.
    """

    __tablename__ = "exercises"

    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    title: Mapped[str] = mapped_column(Text)
    # NULL = hàm rời; khác NULL = bài là method `function_name` của class này.
    class_name: Mapped[str | None] = mapped_column(String(100), nullable=True)
    function_name: Mapped[str] = mapped_column(String(100))
    params: Mapped[list[str]] = mapped_column(ARRAY(Text))
    template: Mapped[str] = mapped_column(Text)
    challenge: Mapped[dict] = mapped_column(JSONB)
    judge_solution: Mapped[str] = mapped_column(Text)
    judge_cases: Mapped[list] = mapped_column(JSONB)


class FileExercise(Base):
    __tablename__ = "file_exercises"
    __table_args__ = (UniqueConstraint("file_id", "position", name="uq_file_exercises_file_position"),)

    file_id: Mapped[str] = mapped_column(ForeignKey("code_files.id", ondelete="CASCADE"), primary_key=True)
    exercise_id: Mapped[str] = mapped_column(
        ForeignKey("exercises.id", ondelete="CASCADE"), primary_key=True, index=True
    )
    position: Mapped[int] = mapped_column(Integer)


class Block(Base):
    """Một ô TODO của bài."""

    __tablename__ = "blocks"
    __table_args__ = (
        UniqueConstraint("exercise_id", "label", name="uq_blocks_exercise_label"),
        UniqueConstraint("exercise_id", "position", name="uq_blocks_exercise_position"),
    )

    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    exercise_id: Mapped[str] = mapped_column(ForeignKey("exercises.id", ondelete="CASCADE"), index=True)
    position: Mapped[int] = mapped_column(Integer)
    label: Mapped[str] = mapped_column(String(10))
    title: Mapped[str] = mapped_column(Text)
    prompt: Mapped[str] = mapped_column(Text)
    indent_level: Mapped[int] = mapped_column(Integer)
    accepted_answers: Mapped[list[str]] = mapped_column(ARRAY(Text))
    expected_output: Mapped[str] = mapped_column(Text)
    explanation: Mapped[str] = mapped_column(Text)
    hints: Mapped[list[str]] = mapped_column(ARRAY(Text))
    vocab: Mapped[list[str]] = mapped_column(ARRAY(Text))


class ContentMeta(Base):
    """Khoá–giá trị cho thông tin của lần nạp, hiện chỉ có `version`."""

    __tablename__ = "content_meta"

    key: Mapped[str] = mapped_column(String(50), primary_key=True)
    value: Mapped[str] = mapped_column(Text)


# --- Người dùng và tiến độ -------------------------------------------------------------------
# Không nằm trong vòng thay toàn bộ của load_content: nạp lại nội dung KHÔNG được đụng các bảng này.


class User(Base):
    __tablename__ = "users"
    __table_args__ = (UniqueConstraint("email", name="uq_users_email"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(254))
    # argon2id; mật khẩu thô không bao giờ được lưu.
    password_hash: Mapped[str] = mapped_column(Text)
    # Tập con của {"learner", "admin"}.
    roles: Mapped[list[str]] = mapped_column(ARRAY(Text))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserSession(Base):
    """Phiên đăng nhập. Chỉ lưu sha256 của token: lộ bảng này không dùng được token."""

    __tablename__ = "user_sessions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class UserProgress(Base):
    """Tiến độ một bài của một user.

    `exercise_id` là chuỗi, KHÔNG FK tới exercises: load_content xoá-rồi-ghi toàn bộ nội dung, FK
    cascade sẽ xoá sạch tiến độ mỗi lần nạp lại / admin lưu.
    """

    __tablename__ = "user_progress"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    exercise_id: Mapped[str] = mapped_column(String(100), primary_key=True)
    # Chỉ server ghi (khi /run trả passed cho user đã đăng nhập).
    passed: Mapped[bool] = mapped_column(Boolean, default=False)
    drafts: Mapped[dict] = mapped_column(JSONB, default=dict)
    hints_used: Mapped[dict] = mapped_column(JSONB, default=dict)
    solution_viewed: Mapped[list] = mapped_column(JSONB, default=list)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class UserState(Base):
    """Trạng thái học không gắn với một bài: lịch ôn (review) và số hoạt động theo ngày (activity)."""

    __tablename__ = "user_state"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    review: Mapped[dict] = mapped_column(JSONB, default=dict)
    activity: Mapped[dict] = mapped_column(JSONB, default=dict)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class McpAccess(Base):
    """Tài khoản identity-service (`sub` của JWT) được phép sửa nội dung qua `/mcp`, thay mặt `user_id`.

    Không có dòng (hoặc `revoked_at` khác null, hoặc user đích không còn admin) = không có quyền —
    kiểm ở mỗi tool call, nên thu hồi có hiệu lực ngay dù JWT còn hạn.
    """

    __tablename__ = "mcp_access"

    sub: Mapped[str] = mapped_column(String(100), primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    label: Mapped[str] = mapped_column(Text, default="", server_default="")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class ContentChange(Base):
    """Một thay đổi nội dung CHỜ DUYỆT (hoặc đã duyệt/bỏ — giữ làm lịch sử), xem `app.review`.

    Mỗi dòng là một mục (project/module/file/bài) so với live. Tối đa một dòng `pending` cho mỗi mục
    (partial unique index). Không FK tới bảng nội dung: `load_content` xoá-rồi-ghi toàn bộ live.
    """

    __tablename__ = "content_changes"
    __table_args__ = (
        CheckConstraint("kind IN ('project','module','file','exercise')", name="ck_content_changes_kind"),
        CheckConstraint("action IN ('create','update','delete')", name="ck_content_changes_action"),
        CheckConstraint("status IN ('pending','approved','rejected')", name="ck_content_changes_status"),
        Index(
            "uq_content_changes_pending_item", "kind", "item_id", unique=True, postgresql_where=text("status = 'pending'")
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    kind: Mapped[str] = mapped_column(String(20))
    item_id: Mapped[str] = mapped_column(String(100))
    action: Mapped[str] = mapped_column(String(10))
    # Mục trên live lúc gửi (null nếu create) / mục đề xuất (null nếu delete) — shape ở app.review.items.
    before: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    after: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    status: Mapped[str] = mapped_column(String(10), index=True)
    author: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    decided_by: Mapped[str | None] = mapped_column(Text, nullable=True)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


# --- Chế độ học System Design ----------------------------------------------------------------
# Tài liệu SD đi đường riêng (không qua load_content, không qua hàng chờ duyệt): admin nhập .md
# qua /api/admin/sd. Tiến độ và lần thử của học viên KHÔNG có FK tới bảng nội dung SD (chỉ FK
# users): nhập lại tài liệu xoá-rồi-ghi section/task, FK cascade sẽ xoá sạch tiến độ.


class SdDoc(Base):
    __tablename__ = "sd_docs"
    __table_args__ = (CheckConstraint("status IN ('draft','published')", name="ck_sd_docs_status"),)

    # Slug của tài liệu, ổn định giữa các lần nhập lại.
    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    title: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(10), default="draft", server_default="draft")
    # Các card của phần "Bối cảnh" (Phase 2): [{id, kind, title, body}].
    context: Mapped[list] = mapped_column(JSONB, default=list)
    created_by: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SdSection(Base):
    """Một section của tài liệu. `cards` là danh sách [{id, kind, title, body}], id = hash nội dung."""

    __tablename__ = "sd_sections"
    __table_args__ = (UniqueConstraint("doc_id", "position", name="uq_sd_sections_doc_position"),)

    doc_id: Mapped[str] = mapped_column(ForeignKey("sd_docs.id", ondelete="CASCADE"), primary_key=True)
    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    position: Mapped[int] = mapped_column(Integer)
    chapter: Mapped[str] = mapped_column(Text)
    chapter_position: Mapped[int] = mapped_column(Integer)
    title: Mapped[str] = mapped_column(Text)
    cards: Mapped[list] = mapped_column(JSONB, default=list)


class SdTask(Base):
    """Một task thực chiến. `rubric` = [{text, keywords}] CHỈ server đọc, không bao giờ ra client."""

    __tablename__ = "sd_tasks"
    __table_args__ = (UniqueConstraint("doc_id", "position", name="uq_sd_tasks_doc_position"),)

    doc_id: Mapped[str] = mapped_column(ForeignKey("sd_docs.id", ondelete="CASCADE"), primary_key=True)
    id: Mapped[str] = mapped_column(String(100), primary_key=True)
    position: Mapped[int] = mapped_column(Integer)
    name: Mapped[str] = mapped_column(Text)
    prompt: Mapped[str] = mapped_column(Text)
    hints: Mapped[list] = mapped_column(JSONB, default=list)
    rubric: Mapped[list] = mapped_column(JSONB, default=list)
    # Section chứa đáp án mẫu (id section, không FK).
    ref_section_id: Mapped[str | None] = mapped_column(String(100), nullable=True)


class SdProgress(Base):
    """Các card đã đọc của một user trong một section. Không FK tới nội dung SD (xem đầu mục)."""

    __tablename__ = "sd_progress"

    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), primary_key=True)
    doc_id: Mapped[str] = mapped_column(String(100), primary_key=True)
    section_id: Mapped[str] = mapped_column(String(100), primary_key=True)
    read_cards: Mapped[list] = mapped_column(JSONB, default=list)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class SdAttempt(Base):
    """Một lần nộp bài thực chiến. Mỗi lần nộp một dòng, không ghi đè: `n` đếm theo (user, doc, task).

    `auto_result` do server chấm từ khoá ngay khi nộp. `status='reviewed'` + `feedback` do Claude ghi
    qua MCP; khi có bản reviewed thì app hiện bản đó.
    """

    __tablename__ = "sd_attempts"
    __table_args__ = (
        UniqueConstraint("user_id", "doc_id", "task_id", "n", name="uq_sd_attempts_user_task_n"),
        CheckConstraint("status IN ('auto','reviewed')", name="ck_sd_attempts_status"),
        CheckConstraint("n >= 1", name="ck_sd_attempts_n"),
        # Bản reviewed phải có feedback và thời điểm chấm; unique ở trên đã phục vụ lịch sử theo (user, doc, task).
        CheckConstraint(
            "status = 'auto' OR (feedback IS NOT NULL AND reviewed_at IS NOT NULL)", name="ck_sd_attempts_reviewed"
        ),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    doc_id: Mapped[str] = mapped_column(String(100))
    task_id: Mapped[str] = mapped_column(String(100))
    n: Mapped[int] = mapped_column(Integer)
    answer: Mapped[str] = mapped_column(Text)
    # {hits: [bool theo từng ý rubric], score: int}
    auto_result: Mapped[dict] = mapped_column(JSONB, default=dict)
    status: Mapped[str] = mapped_column(String(10), default="auto", server_default="auto", index=True)
    feedback: Mapped[str | None] = mapped_column(Text, nullable=True)
    # [{text, ok, note}] theo từng ý rubric, do người/Claude chấm.
    verdicts: Mapped[list | None] = mapped_column(JSONB, nullable=True)
    reviewed_by: Mapped[str | None] = mapped_column(Text, nullable=True)
    reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
