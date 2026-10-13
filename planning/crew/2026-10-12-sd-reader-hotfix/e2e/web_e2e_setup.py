"""Dựng môi trường e2e cho app web thật (xem web_e2e_server.py): DB riêng, nội dung code, user ann, tài liệu SD đã publish.

    cd <worktree>/backend && PYTHONPATH=. <venv>/bin/python ../planning/crew/2026-10-12-sd-reader-hotfix/e2e/web_e2e_setup.py
"""
import os, subprocess, sys

from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

DB = "smart_coding_study_hf_web_test"
URL = f"postgresql+psycopg://localhost:5432/{DB}"
env = {**os.environ, "DATABASE_URL": URL}
admin = create_engine(make_url(URL).set(database="postgres"), isolation_level="AUTOCOMMIT")
with admin.connect() as c:
    c.execute(text(f'drop database if exists "{DB}" with (force)'))
    c.execute(text(f'create database "{DB}"'))
subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], env=env, check=True, capture_output=True)
subprocess.run([sys.executable, "-m", "app.load_content", "--force"], env=env, check=True, capture_output=True)

from app.auth import hash_password
from app.sd.parser import parse_markdown
from app.tables import SdDoc, SdSection, SdTask, User

md = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../../backend/content/sd/airline-reservation.md"), encoding="utf-8").read()
doc = parse_markdown(md)
with Session(create_engine(URL)) as s:
    for name, roles in (("ann", ["learner"]), ("admin", ["learner", "admin"])):
        s.add(User(email=f"{name}@e2e.test", password_hash=hash_password("pw-e2e-correct-horse"), roles=roles))
    s.add(SdDoc(id="airline", title=doc["title"], status="published", context=doc["context"], created_by="admin@e2e.test"))
    s.flush()
    s.add_all(SdSection(doc_id="airline", **sec) for sec in doc["sections"])
    s.add_all(SdTask(doc_id="airline", **t) for t in doc["tasks"])
    s.commit()
print("ready:", DB)
