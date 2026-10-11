"""Hình dạng nội dung học: MỘT bộ model dùng cho cả hai đầu.

- `SourceContent`: kiểm `content.json` lúc nạp (`load_content.validate`) — có thêm `judge` mỗi bài.
- `ContentPayload`: `response_model` của `GET /content` — không có `judge`.

Khớp từng key/kiểu với `Content.fromJson` ở `mobile/lib/domain/{models,content}.dart`. Dart kiểm kiểu
nghiêm (`v is String`, `v is int`), nên model dùng `strict=True`: `"1"` không thành `1`, `1.0` không thành `1`.
`extra="forbid"`: key lạ là lỗi soạn, không lặng lẽ đi vào DB.
"""

from __future__ import annotations

from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field, StrictInt, StrictStr


class _Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class Example(_Strict):
    caption: StrictStr
    input: StrictStr
    output: StrictStr
    note: StrictStr | None  # bắt buộc có key (có thể null) — đúng hợp đồng /content


class Challenge(_Strict):
    statement: StrictStr
    motivation: StrictStr
    small: Example
    project: Example


class Block(_Strict):
    id: StrictStr
    label: StrictStr
    title: StrictStr
    prompt: StrictStr
    indent_level: StrictInt
    accepted_answers: list[StrictStr]
    expected_output: StrictStr
    explanation: StrictStr
    hints: list[StrictStr]
    vocab: list[StrictStr]


class Exercise(_Strict):
    id: StrictStr
    title: StrictStr
    class_name: StrictStr | None  # bắt buộc có key; null = hàm rời, khác null = method của class
    function_name: StrictStr
    params: list[StrictStr]
    template: StrictStr
    challenge: Challenge
    blocks: list[Block]


class CodeFile(_Strict):
    id: StrictStr
    name: StrictStr
    exercise_ids: list[StrictStr]


class Topic(_Strict):
    """Module; `modules` là sub-module (đệ quy, có thể rỗng)."""

    id: StrictStr
    name: StrictStr
    description: StrictStr
    files: list[CodeFile]
    modules: list[Topic]


class DiagramAttribute(_Strict):
    name: StrictStr
    type: StrictStr
    group: Literal["core", "support"]


class DiagramClass(_Strict):
    name: StrictStr
    file: StrictStr
    attributes: list[DiagramAttribute]
    methods: list[StrictStr]


class DiagramRelation(_Strict):
    """`via`: method của `from` tác động lên `to`.

    Chỉ nhận đúng key `from` (không populate_by_name): `from_` là key lạ → bị chặn ngay ở schema,
    không lọt xuống bước kiểm quan hệ với endpoint None.
    """

    from_: StrictStr = Field(alias="from")
    to: StrictStr
    kind: Literal["association", "aggregation", "composition", "dependency"]
    label: StrictStr
    via: list[StrictStr]


class ClassDiagram(_Strict):
    classes: list[DiagramClass]
    relations: list[DiagramRelation]


class Theme(_Strict):
    id: StrictStr
    name: StrictStr
    description: StrictStr
    tags: list[StrictStr]
    diagram: ClassDiagram
    topics: list[Topic]


class ContentPayload(_Strict):
    """Đúng shape `GET /content`."""

    version: StrictStr
    themes: list[Theme]
    exercises: dict[str, Exercise]


class Judge(_Strict):
    solution: StrictStr
    cases: list[Any]


class SourceExercise(Exercise):
    judge: Judge


class SourceContent(_Strict):
    """Đúng shape `content.json`: như payload công khai + `judge` mỗi bài; `version` tuỳ chọn (tính lại khi nạp)."""

    version: StrictStr | None = None
    themes: list[Theme]
    exercises: dict[str, SourceExercise]
