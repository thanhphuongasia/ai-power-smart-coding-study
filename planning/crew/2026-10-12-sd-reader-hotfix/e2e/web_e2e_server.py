"""Backend + web build cùng một origin (không cần CORS):

    cd <worktree>/backend && DATABASE_URL=postgresql+psycopg://localhost:5432/smart_coding_study_hf_web_test \
      AUTH_OPEN_AS=ann@e2e.test PYTHONPATH=.:../planning/crew/2026-10-12-sd-reader-hotfix/e2e \
      <venv>/bin/python -m uvicorn web_e2e_server:app --port 8791
"""
import os

from fastapi.staticfiles import StaticFiles

from app.main import app

WEB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../../mobile/build/web")
app.mount("/", StaticFiles(directory=WEB, html=True), name="web")
