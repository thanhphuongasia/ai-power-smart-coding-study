"""Nhập tài liệu System Design: parser (quy ước md, id card ổn định) và API admin."""

from __future__ import annotations

import os

import pytest
from sqlalchemy import select

from app.sd.parser import MdError, parse_markdown, slugify
from app.tables import SdDoc, SdProgress, SdSection, SdTask
from tests.conftest import BACKEND_DIR
from tests.test_auth import add_user, bearer, client_for, fresh_throttle, login  # noqa: F401

SAMPLE = os.path.join(BACKEND_DIR, "content", "sd", "airline-reservation.md")
ADMIN = "sd-admin@example.com"


@pytest.fixture(scope="module")
def sample_md() -> str:
    with open(SAMPLE, encoding="utf-8") as f:
        return f.read()


MINI = """# Mini

## Chương một

### Mục A

Đoạn một.

Đoạn hai.

## Thực chiến

### Task A

Đề: Làm gì đó.

Rubric:
- Có A :: alpha, Beta

Đáp án mẫu: Mục A
"""


# --- parser ---------------------------------------------------------------------------------


def test_sample_parses_into_expected_shape(sample_md):
    doc = parse_markdown(sample_md)
    assert doc["title"] == "Design an Airline Reservation System"
    assert len(doc["sections"]) == 9 and len({s["chapter_position"] for s in doc["sections"]}) == 4
    assert [s["position"] for s in doc["sections"]] == list(range(9))
    assert len(doc["context"]) >= 4 and {c["kind"] for c in doc["context"]} >= {"text", "table", "callout"}
    assert [t["id"] for t in doc["tasks"]] == [
        "api-design", "database-design", "high-level-architecture",
        "detailed-components-design", "trade-off-discussion", "failure-scenario-discussion",
    ]
    section_ids = {s["id"] for s in doc["sections"]}
    assert all(t["ref_section_id"] in section_ids for t in doc["tasks"])
    api = doc["tasks"][0]
    assert api["rubric"][1] == {"text": "Đặt vé dùng Idempotency-Key để gọi lại không bị trừ tiền hai lần", "keywords": ["idempoten"]}
    assert all(k == k.lower() for t in doc["tasks"] for r in t["rubric"] for k in r["keywords"])


def test_card_ids_are_content_hashes_and_survive_edits_elsewhere():
    before = parse_markdown(MINI)["sections"][0]["cards"]
    after = parse_markdown(MINI.replace("Đoạn hai.", "Đoạn hai đã sửa."))["sections"][0]["cards"]
    assert before[0]["id"] == after[0]["id"] and before[1]["id"] != after[1]["id"]
    # đổi tiêu đề/khoảng trắng không đổi id
    spaced = parse_markdown(MINI.replace("Đoạn một.", "Đoạn   một.  "))["sections"][0]["cards"]
    assert spaced[0]["id"] == before[0]["id"]


def test_identical_blocks_in_one_section_get_distinct_ids():
    cards = parse_markdown(MINI.replace("Đoạn hai.", "Đoạn một."))["sections"][0]["cards"]
    assert len({c["id"] for c in cards}) == 2


def test_headings_inside_code_fences_are_not_structure():
    md = MINI.replace("Đoạn hai.", "```md\n### Không phải section\n```")
    doc = parse_markdown(md)
    assert [s["title"] for s in doc["sections"]] == ["Mục A"]
    assert [c["kind"] for c in doc["sections"][0]["cards"]] == ["text", "code"]


def test_chapter_body_without_h3_becomes_section_named_after_chapter():
    doc = parse_markdown("# T\n\n## Gộp\n\nNội dung trực tiếp.\n")
    assert [(s["chapter"], s["title"], s["id"]) for s in doc["sections"]] == [("Gộp", "Gộp", "gop")]


def test_slugify_vietnamese():
    assert slugify("Đề bài và yêu cầu") == "de-bai-va-yeu-cau"
    assert slugify("!!!") == "item"


@pytest.mark.parametrize(
    "md, needle",
    [
        ("## C\n\n### S\n\nx\n", "thiếu tên tài liệu"),
        ("# T\n\nlạc\n\n## C\n\n### S\n\nx\n", "trước chương đầu tiên"),
        ("# T\n# U\n\n## C\n\n### S\n\nx\n", "một tiêu đề"),
        ("# T\n", "không có chương nào"),
        ("# T\n\n## C\n", "không có nội dung"),
        ("# T\n\n## C\n\n### S\n\n### R\n\nx\n", "không có card nào"),
        ("# T\n\n## C\n\n### S\n\n```py\nx = 1\n", "không có dòng đóng"),
        ("# T\n\n## C\n\n### S\n\nx\x00y\n", "NUL"),
        (MINI.replace("- Có A :: alpha, Beta", "- Có A"), "Rubric"),
        (MINI.replace("- Có A :: alpha, Beta", "- Có A :: "), "Rubric"),
        (MINI.replace("Rubric:\n- Có A :: alpha, Beta\n", ""), "thiếu «Rubric:»"),
        (MINI.replace("Đề: Làm gì đó.\n", ""), "thiếu «Đề:»"),
        (MINI.replace("Đáp án mẫu: Mục A", "Đáp án mẫu: Không có"), "không khớp section"),
    ],
)
def test_bad_documents_report_what_is_wrong(md, needle):
    with pytest.raises(MdError) as e:
        parse_markdown(md)
    assert any(needle in m for m in e.value.errors), e.value.errors


# --- trần và hiệu năng: đầu vào xấu nhất ≤1MB phải xử lý tuyến tính và bị từ chối nhanh --------


def _timed(md):
    import time

    start = time.perf_counter()
    try:
        return parse_markdown(md), time.perf_counter() - start
    except MdError as exc:
        return exc, time.perf_counter() - start


@pytest.mark.parametrize(
    "md, needle",
    [
        ("# T\n\n## Bối cảnh\n\n" + "x\n\n" * 300_000 + "## C\n\n### S\n\nx\n", "quá 100 card"),  # 300k khối TRÙNG ở bối cảnh
        ("# T\n\n## C\n\n### S\n\n" + "x\n\n" * 300_000, "quá 200 card"),  # 300k khối trùng trong một section
        ("# T\n\n## C\n\n" + "### s\n\nx\n\n" * 90_000, "quá 200 section"),
        ("# T\n\n" + "## c\n\n### s\n\nx\n\n" * 50_000, "quá 50 chương"),
        ("# T\n\n## C\n\n### S\n\nx\n\n## Thực chiến\n\n" + "### t\n\nĐề: a\n\n" * 60_000, "quá 12 task"),
    ],
)
def test_hostile_one_megabyte_documents_are_rejected_fast(md, needle):
    assert len(md) <= 1_000_000
    result, seconds = _timed(md)
    assert isinstance(result, MdError) and any(needle in e for e in result.errors), result
    assert seconds < 3, f"{seconds:.1f}s: parser phải tuyến tính"


def test_total_card_budget_across_sections_is_enforced():
    md = "# T\n\n## C\n\n" + "".join(f"### s{i}\n\n" + "".join(f"p{i}-{j}\n\n" for j in range(150)) for i in range(25))
    result, _ = _timed(md)
    assert isinstance(result, MdError) and any("quá" in e and "card" in e for e in result.errors)


def test_many_duplicate_blocks_below_the_cap_still_get_distinct_ids():
    cards = parse_markdown("# T\n\n## C\n\n### S\n\n" + "x\n\n" * 150)["sections"][0]["cards"]
    assert len(cards) == 150 and len({c["id"] for c in cards}) == 150


def test_suffix_id_never_collides_with_an_existing_slug():
    md = "# T\n\n## C\n\n### Foo\n\na\n\n### Foo\n\nb\n\n### Foo 2\n\nc\n"
    ids = [s["id"] for s in parse_markdown(md)["sections"]]
    assert len(set(ids)) == 3


def test_renaming_a_section_changes_its_id_but_editing_text_does_not():
    """Quy ước đã ghi ở docstring parser: id section theo TÊN. Test này giữ cho thay đổi sau có chủ đích."""
    base = parse_markdown(MINI)["sections"][0]
    renamed = parse_markdown(MINI.replace("### Mục A", "### Mục B").replace("Đáp án mẫu: Mục A", "Đáp án mẫu: Mục B"))["sections"][0]
    edited = parse_markdown(MINI.replace("Đoạn một.", "Đoạn một sửa."))["sections"][0]
    assert base["id"] != renamed["id"] and base["id"] == edited["id"]


def test_keywords_are_lowercased_and_deduped():
    doc = parse_markdown(MINI.replace("alpha, Beta", "Alpha, alpha, BETA"))
    assert doc["tasks"][0]["rubric"][0]["keywords"] == ["alpha", "beta"]


# --- API admin ------------------------------------------------------------------------------


@pytest.fixture()
def admin(db_session, client_for):
    add_user(db_session, email=ADMIN, roles=("learner", "admin"))
    client = client_for(db_session)
    return client, bearer(login(client, email=ADMIN).json()["token"])


def _import(client, h, md, **extra):
    return client.post("/api/admin/sd/docs", json={"markdown": md, **extra}, headers=h)


def test_import_creates_doc_sections_tasks(admin, db_session, sample_md):
    client, h = admin
    r = _import(client, h, sample_md)
    assert r.status_code == 200, r.json()
    body = r.json()
    assert body["id"] == "design-an-airline-reservation-system" and body["status"] == "draft"
    assert (body["chapters"], body["sections"], body["tasks"]) == (4, 9, 6)
    assert body["cards_added"] == body["cards"] and body["cards_removed"] == 0
    assert db_session.get(SdDoc, body["id"]).created_by == ADMIN
    assert len(db_session.scalars(select(SdSection).where(SdSection.doc_id == body["id"])).all()) == 9
    assert len(db_session.scalars(select(SdTask).where(SdTask.doc_id == body["id"])).all()) == 6


def test_reimport_keeps_unchanged_cards_and_reader_progress(admin, db_session, sample_md):
    """Nhập lại không xoá tiến độ: sd_progress không FK vào nội dung, card không đổi giữ id."""
    client, h = admin
    doc_id = _import(client, h, sample_md).json()["id"]
    user_id = add_user(db_session, email="reader@example.com").id
    db_session.add(SdProgress(user_id=user_id, doc_id=doc_id, section_id="requirements", read_cards=["a1b2c3d4"]))
    db_session.flush()

    again = _import(client, h, sample_md).json()
    assert (again["cards_added"], again["cards_removed"]) == (0, 0)

    edited = sample_md.replace("Chương trình khách hàng thân thiết", "Chương trình tích điểm")
    changed = _import(client, h, edited).json()
    assert (changed["cards_added"], changed["cards_removed"]) == (1, 1)
    row = db_session.get(SdProgress, (user_id, doc_id, "requirements"))
    assert row is not None and row.read_cards == ["a1b2c3d4"]


def test_reimport_without_status_keeps_published(admin, sample_md):
    client, h = admin
    doc_id = _import(client, h, sample_md, status="published").json()["id"]
    assert _import(client, h, sample_md).json()["status"] == "published"
    assert client.put(f"/api/admin/sd/docs/{doc_id}/status", json={"status": "draft"}, headers=h).json() == {
        "id": doc_id, "status": "draft",
    }


def test_list_docs_counts(admin, sample_md):
    client, h = admin
    doc_id = _import(client, h, sample_md).json()["id"]
    (item,) = client.get("/api/admin/sd/docs", headers=h).json()["items"]
    assert item["id"] == doc_id and (item["sections"], item["tasks"]) == (9, 6) and item["cards"] > 9


def test_invalid_markdown_is_422_with_errors_and_writes_nothing(admin, db_session):
    client, h = admin
    r = _import(client, h, "# T\n\n## C\n")
    assert r.status_code == 422 and any("không có nội dung" in e for e in r.json()["errors"])
    assert db_session.scalars(select(SdDoc)).all() == []


@pytest.mark.parametrize(
    "payload",
    [
        {"markdown": MINI, "status": "weird"},
        {"markdown": MINI, "id": "Bad Slug"},
        {"markdown": MINI, "extra": 1},
        {"markdown": 5},
        {},
    ],
)
def test_bad_request_bodies_are_422(admin, payload):
    client, h = admin
    assert client.post("/api/admin/sd/docs", json=payload, headers=h).status_code == 422


def test_markdown_over_one_megabyte_is_rejected(admin):
    client, h = admin
    big = "# T\n\n## C\n\n### S\n\n" + ("x" * 1_000_001)
    assert _import(client, h, big).status_code == 422


def test_nul_in_markdown_is_422_not_500(admin):
    client, h = admin
    r = _import(client, h, MINI.replace("Đoạn một.", "a\x00b"))
    assert r.status_code == 422 and any("NUL" in e for e in r.json()["errors"])


def test_status_route_rejects_malformed_doc_id(admin):
    client, h = admin
    assert client.put("/api/admin/sd/docs/Bad%20Id/status", json={"status": "draft"}, headers=h).status_code == 422


def test_status_of_unknown_doc_is_404(admin):
    client, h = admin
    assert client.put("/api/admin/sd/docs/nope/status", json={"status": "published"}, headers=h).status_code == 404


@pytest.mark.parametrize("roles, expected", [((), 401), (("learner",), 403)])
def test_only_admin_may_import_and_403_comes_before_422(db_session, client_for, roles, expected):
    client = client_for(db_session)
    h = {}
    if roles:
        add_user(db_session, email="learner@example.com", roles=roles)
        h = bearer(login(client, email="learner@example.com").json()["token"])
    r = client.post("/api/admin/sd/docs", content=b"{not json", headers={**h, "Content-Type": "application/json"})
    assert r.status_code == expected
    assert client.get("/api/admin/sd/docs", headers=h).status_code == expected
    assert client.put("/api/admin/sd/docs/x/status", json={"status": "draft"}, headers=h).status_code == expected
