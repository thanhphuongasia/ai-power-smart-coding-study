"""Bảng Postgres chứa nội dung học. Nguồn soạn là `content/content.json`; `load_content.py` nạp
vào đây (thay toàn bộ), `/content` và `/run` đọc ra. Sửa trực tiếp bảng sẽ bị lần nạp sau ghi đè.

Thứ tự hiển thị lưu ở cột `position` (theme, topic, file, bài trong file, ô trong bài).
Module lồng nhau = `topics.parent_id`; `topics.position` là thứ tự duyệt trước (preorder) trong theme,
nên con luôn đứng sau cha và thứ tự anh em giữ đúng như `content.json`.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, UniqueConstraint, func
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
