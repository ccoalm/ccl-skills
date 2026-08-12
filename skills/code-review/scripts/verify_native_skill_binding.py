#!/usr/bin/env python3
"""Verify controller-selected native review skills without copying their bodies."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys

from review_gate import GateError, MAX_PROFILE_BYTES, _hash_skill_package

MAX_LEGACY_PROFILE_BYTES = 245_000


def fail(message: str) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(2)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--review-profile-file", required=True)
    parser.add_argument("--skill-registry-root")
    parser.add_argument("--installed-skill-registry-root")
    parser.add_argument("--review-skill", action="append", default=[])
    args = parser.parse_args()

    profile_path = Path(args.review_profile_file)
    registry_root = Path(args.skill_registry_root) if args.skill_registry_root else None
    installed_registry_root = (
        Path(args.installed_skill_registry_root)
        if args.installed_skill_registry_root
        else None
    )
    if not profile_path.is_file() or profile_path.is_symlink():
        fail("review profile must be a readable regular file")
    profile_size = profile_path.stat().st_size
    if profile_size > MAX_LEGACY_PROFILE_BYTES:
        fail("review profile exceeds the wrapper input bound")
    if registry_root is not None and (
        not registry_root.is_absolute()
        or not registry_root.is_dir()
        or registry_root.is_symlink()
    ):
        fail("skill registry root must be an absolute regular directory")
    if installed_registry_root is not None and (
        not installed_registry_root.is_absolute()
        or not installed_registry_root.is_dir()
        or installed_registry_root.is_symlink()
    ):
        fail("installed skill registry root must be an absolute regular directory")

    try:
        profile = json.loads(profile_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        fail(f"cannot read review profile: {exc}")
    if not isinstance(profile, dict):
        fail("review profile must be an object")
    if profile.get("skill_delivery") != "native-installed":
        selected_hint = profile.get("selected_skills")
        if isinstance(selected_hint, list) and any(
            not isinstance(item, dict) or item.get("name") != "code-review"
            for item in selected_hint
        ):
            fail("review profile selects owners without native-installed delivery")
        if args.review_skill or registry_root is not None or installed_registry_root is not None:
            fail("review profile does not require native-installed skill delivery")
        print(json.dumps({"skills": [], "native_required": False}, separators=(",", ":")))
        return
    if profile_size > MAX_PROFILE_BYTES:
        fail("native-installed review profile exceeds the controller bound")

    selected = profile.get("selected_skills")
    if not isinstance(selected, list):
        fail("review profile selected_skills must be a list")
    selected_by_name: dict[str, str] = {}
    for item in selected:
        if not isinstance(item, dict) or set(item) != {"name", "content_sha256"}:
            fail("review profile selected_skills entry is invalid")
        name = item.get("name")
        digest = item.get("content_sha256")
        if not isinstance(name, str) or not isinstance(digest, str) or len(digest) != 64:
            fail("review profile selected_skills entry is invalid")
        if name in selected_by_name:
            fail("review profile selected_skills contains a duplicate")
        selected_by_name[name] = digest

    requested = list(dict.fromkeys(args.review_skill))
    if requested != args.review_skill:
        fail("review skill arguments contain a duplicate")
    expected = [name for name in selected_by_name if name != "code-review"]
    if requested != expected:
        fail("review skill arguments do not match the controller profile")

    if expected and registry_root is None:
        fail("native review skills require a skill registry root")

    for name in requested:
        try:
            assert registry_root is not None
            actual = _hash_skill_package(registry_root / name, name)
        except (GateError, OSError) as exc:
            fail(f"cannot verify native review skill {name}: {exc}")
        if actual != selected_by_name[name]:
            fail(f"native review skill hash mismatch: {name}")
        if installed_registry_root is not None:
            try:
                # Host installs may advance independently of the candidate.
                # Validate package safety/presence, but bind by selected name.
                _hash_skill_package(installed_registry_root / name, name)
            except (GateError, OSError) as exc:
                fail(f"cannot verify installed native review skill {name}: {exc}")

    print(
        json.dumps(
            {"skills": requested, "native_required": True}, separators=(",", ":")
        )
    )


if __name__ == "__main__":
    main()
