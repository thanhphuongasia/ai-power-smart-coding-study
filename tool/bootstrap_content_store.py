#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import os
import shutil
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def _as_list(value: Any) -> List[Any]:
    if isinstance(value, list):
        return value
    return []


def _create_published_entry(entry_id: str, payload: Dict[str, Any], published_at: str) -> Dict[str, Any]:
    return {
        "id": entry_id,
        "draft": payload,
        "published": payload,
        "updatedAt": published_at,
        "publishedAt": published_at,
    }


def build_store_from_seed(seed: Dict[str, Any]) -> Dict[str, Any]:
    exported_at = str(seed.get("exportedAt") or _now_iso())
    content_version = int(seed.get("contentVersion") or 1)

    tracks = _as_list(seed.get("tracks"))
    exercises = _as_list(seed.get("exercises"))
    topics = _as_list(seed.get("topics"))
    domains = _as_list(seed.get("domains"))
    skills = _as_list(seed.get("skills"))

    def to_entries(items: List[Any]) -> List[Dict[str, Any]]:
        entries: List[Dict[str, Any]] = []
        for item in items:
            if not isinstance(item, dict):
                continue
            entry_id = str(item.get("id") or "").strip()
            if not entry_id:
                continue
            entries.append(_create_published_entry(entry_id, item, exported_at))
        return entries

    return {
        "schemaVersion": 2,
        "contentVersion": content_version,
        "lastPublishedAt": exported_at,
        "tracks": to_entries(tracks),
        "exercises": to_entries(exercises),
        "topics": to_entries(topics),
        "domains": to_entries(domains),
        "skills": to_entries(skills),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Bootstrap app-api content-store.json from seed_content.json (schema v2).")
    parser.add_argument(
        "--seed",
        default=os.path.join("strapi", "seed", "seed_content.json"),
        help="Path to seed_content.json",
    )
    parser.add_argument(
        "--out",
        default=os.path.join("app-api", "data", "content-store.json"),
        help="Path to output content-store.json",
    )
    parser.add_argument(
        "--no-backup",
        action="store_true",
        help="Do not create a .bak backup of the existing out file",
    )
    args = parser.parse_args()

    with open(args.seed, "r", encoding="utf-8") as f:
        seed = json.load(f)

    store = build_store_from_seed(seed)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    if os.path.exists(args.out) and not args.no_backup:
        backup_path = args.out + ".bak"
        shutil.copyfile(args.out, backup_path)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(store, f, ensure_ascii=False, indent=2)
        f.write("\n")

    print(f"Wrote {args.out}")
    print(
        "Counts:",
        f"tracks={len(store['tracks'])}",
        f"exercises={len(store['exercises'])}",
        f"topics={len(store['topics'])}",
        f"domains={len(store['domains'])}",
        f"skills={len(store['skills'])}",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

