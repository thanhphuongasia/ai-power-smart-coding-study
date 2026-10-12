"""E2E hotfix #35 — task không khoá tuần tự. E2E backend (qua HTTP thật): uvicorn + Postgres riêng. Chạy từ thư mục backend của worktree:

    cd <worktree>/backend && <venv>/bin/python ../planning/crew/2026-10-12-system-design-mode/e2e/backend_e2e.py

Các bước (mỗi bước in OK/FAIL kèm bằng chứng):
 E1 nhập .md → học viên đọc 1 section → request MỚI vẫn thấy tiến độ
 E2 sửa 1 card rồi nhập lại → tiến độ card khác còn, section chứa card sửa hết done (INV-01)
 E3 đọc hết Phase 1, nộp 2 lần thử Task API → cả hai còn trong lịch sử; JSON thô không có từ khoá rubric (INV-02)
 E4 học viên khác không thấy lần thử của người kia (INV-06), task chưa mở bị 409
"""
import json, os, subprocess, sys, time

import httpx
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

DB = "smart_coding_study_hf_e2e_test"
URL = f"postgresql+psycopg://localhost:5432/{DB}"
PORT = 8791
BASE = f"http://127.0.0.1:{PORT}"
MD = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../../backend/content/sd/airline-reservation.md"), encoding="utf-8").read()
DOC = "design-an-airline-reservation-system"
fails = []


def check(name, ok, evidence=""):
    print(("OK   " if ok else "FAIL ") + name + (f"  [{evidence}]" if evidence else ""))
    if not ok:
        fails.append(name)


admin_engine = create_engine(make_url(URL).set(database="postgres"), isolation_level="AUTOCOMMIT")
with admin_engine.connect() as c:
    c.execute(text(f'drop database if exists "{DB}" with (force)'))
    c.execute(text(f'create database "{DB}"'))
env = {**os.environ, "DATABASE_URL": URL, "CODE_RUNNER": os.environ.get("CODE_RUNNER", "judge0")}
env.pop("AUTH_OPEN_AS", None)
subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], env=env, check=True, capture_output=True)

from app.auth import hash_password  # noqa: E402
from app.tables import User  # noqa: E402
from sqlalchemy.orm import Session  # noqa: E402

eng = create_engine(URL)
with Session(eng) as s:
    for name, roles in (("admin", ["learner", "admin"]), ("ann", ["learner"]), ("bob", ["learner"])):
        s.add(User(email=f"{name}@e2e.test", password_hash=hash_password("pw-e2e-correct-horse"), roles=roles))
    s.commit()

server = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app", "--port", str(PORT), "--log-level", "warning"], env=env)
try:
    for _ in range(60):
        try:
            if httpx.get(BASE + "/openapi.json", timeout=1).status_code == 200:
                break
        except Exception:
            time.sleep(0.5)

    def login(name):
        r = httpx.post(BASE + "/api/auth/login", json={"email": f"{name}@e2e.test", "password": "pw-e2e-correct-horse"})
        return {"Authorization": "Bearer " + r.json()["token"]}

    H = {n: login(n) for n in ("admin", "ann", "bob")}

    def get(who, path):
        return httpx.get(BASE + path, headers=H[who])

    def doc(who="ann"):
        return get(who, f"/api/sd/docs/{DOC}").json()

    def read(sec, who="ann", cards=None):
        ids = cards if cards is not None else [c["id"] for c in sec["cards"]]
        return httpx.put(BASE + f"/api/sd/docs/{DOC}/sections/{sec['id']}/progress", json={"read_cards": ids}, headers=H[who])

    imp = lambda md, **kw: httpx.post(BASE + "/api/admin/sd/docs", json={"markdown": md, **kw}, headers=H["admin"], timeout=30)

    r = imp(MD, status="published")
    check("H0 import 200", r.status_code == 200)
    d = doc()
    tasks = d["tasks"]
    ids = [t["id"] for t in tasks]
    check("H1 Phase 1 chưa xong: mọi task khoá", all(not t["unlocked"] for t in tasks), f"{len(tasks)} task")
    codes = [httpx.post(BASE + f"/api/sd/docs/{DOC}/tasks/{i}/attempts", json={"answer": "x" * 30}, headers=H["ann"]).status_code for i in ids]
    check("H1 POST attempt mọi task = 409", set(codes) == {409}, str(codes))
    for sec in d["sections"]:
        read(sec)
    d = doc()
    tasks = d["tasks"]
    check("H2 Phase 1 xong: Phase 2 mở", d["phase2_unlocked"] is True)
    check("H2 mọi task mở ngay (không tuần tự)", all(t["unlocked"] for t in tasks), str([t["unlocked"] for t in tasks]))
    check("H2 prompt có ở mọi task mở", all(t.get("prompt") for t in tasks))
    third = ids[2]
    r3 = httpx.post(BASE + f"/api/sd/docs/{DOC}/tasks/{third}/attempts", json={"answer": "x" * 30}, headers=H["ann"])
    check("H3 làm task thứ 3 trước task 1 = 201", r3.status_code == 201, r3.text[:80])
    d = doc()
    check("H3 chỉ task 3 done", [t["done"] for t in d["tasks"]] == [i == third for i in ids], str([t["done"] for t in d["tasks"]]))
    last = ids[-1]
    r6 = httpx.post(BASE + f"/api/sd/docs/{DOC}/tasks/{last}/attempts", json={"answer": "x" * 30}, headers=H["ann"])
    check("H3 task cuối cũng 201", r6.status_code == 201)
    # bob chưa đọc: vẫn khoá
    check("H4 bob chưa đọc Phase 1: 409", httpx.post(BASE + f"/api/sd/docs/{DOC}/tasks/{third}/attempts", json={"answer": "x" * 30}, headers=H["bob"]).status_code == 409)
    # INV-01: nhập lại làm mất done một section -> task khoá lại, nội dung bị ẩn
    sec1_first_text = next(c["body"] for c in doc()["sections"][0]["cards"] if c["kind"] == "text")
    edited = MD.replace(sec1_first_text.split("\n")[0], sec1_first_text.split("\n")[0] + " (đã sửa)", 1)
    imp(edited)
    d = doc()
    check("H5 nhập lại làm mất done: Phase 2 + mọi task khoá lại", (not d["phase2_unlocked"]) and all(not t["unlocked"] for t in d["tasks"]))
    check("H5 POST khi Phase 2 khoá lại = 409", httpx.post(BASE + f"/api/sd/docs/{DOC}/tasks/{third}/attempts", json={"answer": "x" * 30}, headers=H["ann"]).status_code == 409)
finally:
    server.terminate()
    server.wait(10)
    with admin_engine.connect() as c:
        c.execute(text(f'drop database if exists "{DB}" with (force)'))

print("\nKẾT QUẢ:", "TẤT CẢ OK" if not fails else f"{len(fails)} FAIL: {fails}")
sys.exit(1 if fails else 0)
