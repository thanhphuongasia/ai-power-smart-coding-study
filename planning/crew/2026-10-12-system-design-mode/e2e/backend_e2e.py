"""E2E backend (qua HTTP thật): uvicorn + Postgres riêng. Chạy từ thư mục backend của worktree:

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

DB = "smart_coding_study_sd_e2e_test"
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
    check("E1 import 200", r.status_code == 200, f"{r.json().get('sections')} section, {r.json().get('cards')} card")
    d = doc()
    first = d["sections"][0]
    check("E1 section 1 mở, section 2 khoá", d["sections"][0]["unlocked"] and not d["sections"][1]["unlocked"])
    check("E1 PUT đánh dấu đọc", read(first).json()["done"] is True)
    d2 = doc()  # request mới hoàn toàn
    check("E1 tiến độ còn ở request mới", d2["sections"][0]["done"] and d2["sections"][1]["unlocked"])

    # E2: sửa 1 card ở section 1 rồi nhập lại
    sec1_first_text = next(c["body"] for c in first["cards"] if c["kind"] == "text")
    edited = MD.replace(sec1_first_text.split("\n")[0], sec1_first_text.split("\n")[0] + " (đã sửa)", 1)
    check("E2 nhập lại 200", imp(edited).status_code == 200 and edited != MD)
    d3 = doc()
    s1 = d3["sections"][0]
    check("E2 section chứa card sửa hết done", s1["done"] is False)
    check("E2 các card khác còn đọc", len(s1["read"]) == len(s1["cards"]) - 1, f"{len(s1['read'])}/{len(s1['cards'])}")
    imp(MD)  # khôi phục bản gốc (card gốc quay lại cùng id)
    check("E2 khôi phục thì section done lại (id theo nội dung)", doc()["sections"][0]["done"] is True)

    # E3: đọc hết Phase 1 rồi nộp 2 lần
    for sec in doc()["sections"]:
        read(sec)
    d4 = doc()
    check("E3 Phase 2 mở", d4["phase2_unlocked"] is True and d4["context"] != [])
    T = f"/api/sd/docs/{DOC}/tasks/api-design/attempts"
    a1 = httpx.post(BASE + T, json={"answer": "Có /holds để giữ ghế, trả 409 Conflict khi ghế đã bị giữ."}, headers=H["ann"])
    a2 = httpx.post(BASE + T, json={"answer": "POST /bookings dùng Idempotency-Key; tìm chuyến theo date, from, origin; hold ghế; 409 conflict"}, headers=H["ann"])
    check("E3 hai lần thử 201", a1.status_code == 201 and a2.status_code == 201)
    hist = get("ann", T)
    check("E3 lịch sử còn cả hai, mới nhất trước", [i["n"] for i in hist.json()["items"]] == [2, 1], hist.text[:80])
    raw = (get("ann", f"/api/sd/docs/{DOC}").text + hist.text + a1.text + get("ann", "/api/sd/docs").text).lower()
    leaked = [k for k in ("keywords", "rubric", "auto_result", "idempoten\"") if k in raw]
    check("E3 JSON thô không lộ rubric/từ khoá", not leaked, str(leaked))

    # E4: cô lập và khoá
    check("E4 bob không thấy lần thử của ann", get("bob", T).json() == {"items": []})
    bob_post = httpx.post(BASE + T, json={"answer": "x" * 30}, headers=H["bob"])
    check("E4 bob chưa đọc xong thì task khoá 409", bob_post.status_code == 409, bob_post.text[:60])
    locked_put = read(doc("bob")["sections"][1], "bob")
    check("E4 section khoá ghi tiến độ bị 409", locked_put.status_code == 409)
finally:
    server.terminate()
    server.wait(10)
    with admin_engine.connect() as c:
        c.execute(text(f'drop database if exists "{DB}" with (force)'))

print("\nKẾT QUẢ:", "TẤT CẢ OK" if not fails else f"{len(fails)} FAIL: {fails}")
sys.exit(1 if fails else 0)
