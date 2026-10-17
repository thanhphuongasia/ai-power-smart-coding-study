"""CLI nhập tài liệu SD từ file .md: `main(argv)` chạy trên session test (không đóng, không chạm DATABASE_URL)."""

from __future__ import annotations

import contextlib

import pytest
from sqlalchemy import select

from app import db
from app.sd import import_file
from app.tables import SdDoc, SdSection
from tests.test_sd_admin import MINI  # noqa: F401


@pytest.fixture()
def cli(db_session, monkeypatch):
    monkeypatch.setattr(db, "SessionLocal", lambda: contextlib.nullcontext(db_session))
    return import_file.main


def _write(tmp_path, text: str, name: str = "doc.md"):
    p = tmp_path / name
    p.write_text(text, encoding="utf-8")
    return str(p)


def test_create_stores_doc_and_source_md(cli, db_session, tmp_path, capsys):
    path = _write(tmp_path, MINI)
    assert cli([path, "--id", "mini-cli", "--mode", "create"]) == 0
    out = capsys.readouterr().out
    assert out.startswith("mini-cli status=draft ") and "dry_run" not in out
    doc = db_session.get(SdDoc, "mini-cli")
    assert doc is not None and doc.source_md == MINI
    assert db_session.scalars(select(SdSection).where(SdSection.doc_id == "mini-cli")).first() is not None


def test_replace_unknown_id_exits_1(cli, tmp_path, capsys):
    path = _write(tmp_path, MINI)
    assert cli([path, "--id", "khong-co", "--mode", "replace"]) == 1
    assert "không có tài liệu" in capsys.readouterr().err


def test_dry_run_writes_nothing(cli, db_session, tmp_path, capsys):
    path = _write(tmp_path, MINI)
    assert cli([path, "--id", "dry-cli", "--dry-run"]) == 0
    assert capsys.readouterr().out.rstrip().endswith("dry_run")
    db_session.expire_all()
    assert db_session.get(SdDoc, "dry-cli") is None


def test_parse_error_exits_1_and_prints_errors(cli, tmp_path, capsys):
    path = _write(tmp_path, "không có tiêu đề H1\n")
    assert cli([path, "--id", "bad-cli"]) == 1
    captured = capsys.readouterr()
    assert captured.out == "" and captured.err.strip()


def test_unreadable_file_exits_1(cli, tmp_path, capsys):
    assert cli([str(tmp_path / "missing.md")]) == 1
    assert "không đọc được file" in capsys.readouterr().err


def test_non_utf8_file_exits_1(cli, tmp_path, capsys):
    p = tmp_path / "latin.md"
    p.write_bytes(b"# Caf\xe9\n")  # latin-1, không phải UTF-8 hợp lệ
    assert cli([str(p)]) == 1
    assert "không đọc được file" in capsys.readouterr().err


def test_replace_existing_keeps_status_and_updates_source(cli, db_session, tmp_path):
    assert cli([_write(tmp_path, MINI, "a.md"), "--id", "rep-cli", "--mode", "create", "--status", "published"]) == 0
    edited = MINI.replace("Đoạn hai.", "Đoạn hai đã sửa.")
    assert cli([_write(tmp_path, edited, "b.md"), "--id", "rep-cli", "--mode", "replace"]) == 0
    db_session.expire_all()
    doc = db_session.get(SdDoc, "rep-cli")
    assert doc.status == "published" and doc.source_md == edited
