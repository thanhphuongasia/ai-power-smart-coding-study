"""Chấm câu trả lời thực chiến theo rubric.

`Evaluator` là interface (cùng mẫu `CodeRunner` ở `app/runner.py`): hôm nay chỉ có `KeywordEvaluator`
(khớp từ khoá, chấm sơ ngay khi nộp). Chấm sâu hơn đi đường khác: Claude đọc câu trả lời qua MCP rồi ghi
feedback (`app/sd/attempts.submit_feedback`), nên không có bản gọi LLM trực tiếp ở đây.

Khớp từ khoá không phân biệt hoa/thường và không phân biệt dấu tiếng Việt (người học gõ "khoa" cho
"khoá" vẫn khớp). Đổi lại từ khoá ngắn có thể khớp thừa, nên rubric nên dùng từ khoá đủ đặc trưng.
"""

from __future__ import annotations

import unicodedata
from typing import Protocol


def fold(text: str) -> str:
    """Hạ chữ thường, bỏ dấu, đ→d."""
    t = unicodedata.normalize("NFKD", text.replace("đ", "d").replace("Đ", "D"))
    return "".join(c for c in t if not unicodedata.combining(c)).lower()


class Evaluator(Protocol):
    def evaluate(self, answer: str, rubric: list[dict]) -> dict:
        """Trả `{"hits": [bool theo từng ý rubric], "score": 0..100}`."""
        ...


class KeywordEvaluator:
    def evaluate(self, answer: str, rubric: list[dict]) -> dict:
        text = fold(answer)
        hits = [any(fold(k) in text for k in item["keywords"]) for item in rubric]
        score = round(100 * sum(hits) / len(hits)) if hits else 0
        return {"hits": hits, "score": score}


def get_evaluator() -> Evaluator:
    """Dependency FastAPI: test ghi đè để cắm bản giả."""
    return KeywordEvaluator()
