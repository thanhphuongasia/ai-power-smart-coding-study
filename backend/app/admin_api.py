"""API quản trị nội dung (chỉ admin) dưới `/api/admin`. DB là nguồn chính của nội dung."""

from __future__ import annotations

from fastapi import APIRouter

router = APIRouter(prefix="/api/admin")
