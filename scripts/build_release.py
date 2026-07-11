#!/usr/bin/env python3
"""Build a deterministic, Factorio-ready release archive from info.json."""

from __future__ import annotations

import hashlib
import json
import re
import shutil
import sys
import zipfile
from pathlib import Path, PurePosixPath
from typing import NoReturn

ROOT = Path(__file__).resolve().parents[1]
INFO_PATH = ROOT / "info.json"
DIST_DIR = ROOT / "dist"

EXCLUDED_TOP_LEVEL = {
    ".git",
    ".github",
    ".idea",
    ".vscode",
    "dist",
    "scripts",
    "tests",
    "__pycache__",
}
EXCLUDED_FILES = {
    ".DS_Store",
    ".gitattributes",
    ".gitignore",
}
REQUIRED_FILES = {
    "info.json",
    "data.lua",
}
NAME_PATTERN = re.compile(r"^[A-Za-z0-9_-]+$")
VERSION_PATTERN = re.compile(r"^\d+\.\d+\.\d+$")
FIXED_ZIP_TIMESTAMP = (2020, 1, 1, 0, 0, 0)


def fail(message: str) -> NoReturn:
    raise SystemExit(f"ERROR: {message}")


def load_metadata() -> dict[str, object]:
    if not INFO_PATH.is_file():
        fail("Missing info.json")

    try:
        metadata = json.loads(INFO_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"Invalid info.json: {exc}")

    for field in ("name", "version", "title", "factorio_version"):
        value = metadata.get(field)
        if not isinstance(value, str) or not value.strip():
            fail(f"info.json field '{field}' must be a non-empty string")

    name = str(metadata["name"])
    version = str(metadata["version"])

    if not NAME_PATTERN.fullmatch(name):
        fail("info.json name may contain only letters, digits, underscores and hyphens")
    if not VERSION_PATTERN.fullmatch(version):
        fail("info.json version must use MAJOR.MINOR.PATCH format")

    return metadata


def should_package(path: Path) -> bool:
    relative = path.relative_to(ROOT)

    if not path.is_file():
        return False
    if relative.parts[0] in EXCLUDED_TOP_LEVEL:
        return False
    if relative.name in EXCLUDED_FILES:
        return False
    if relative.suffix.lower() in {".zip", ".pyc", ".pyo"}:
        return False

    return True


def collect_files() -> list[Path]:
    files = sorted(
        (path for path in ROOT.rglob("*") if should_package(path)),
        key=lambda path: path.relative_to(ROOT).as_posix(),
    )
    packaged_names = {path.relative_to(ROOT).as_posix() for path in files}

    missing = sorted(REQUIRED_FILES - packaged_names)
    if missing:
        fail(f"Required mod files are missing: {', '.join(missing)}")

    return files


def add_file_to_zip(
    archive: zipfile.ZipFile,
    source: Path,
    archive_path: PurePosixPath,
) -> None:
    info = zipfile.ZipInfo(str(archive_path), date_time=FIXED_ZIP_TIMESTAMP)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = 0o100644 << 16
    archive.writestr(info, source.read_bytes())


def validate_archive(archive_path: Path, folder_name: str) -> None:
    expected_prefix = f"{folder_name}/"
    expected_info = f"{folder_name}/info.json"

    with zipfile.ZipFile(archive_path, mode="r") as archive:
        names = archive.namelist()
        bad_entries = [name for name in names if not name.startswith(expected_prefix)]

        if bad_entries:
            fail(
                "Archive contains entries outside the required top-level folder: "
                + ", ".join(bad_entries)
            )
        if expected_info not in names:
            fail(f"Archive does not contain {expected_info}")
        if len(names) != len(set(names)):
            fail("Archive contains duplicate file names")

        bad_file = archive.testzip()
        if bad_file is not None:
            fail(f"Archive integrity check failed at {bad_file}")


def build_archive(
    metadata: dict[str, object], files: list[Path]
) -> tuple[Path, Path]:
    name = str(metadata["name"])
    version = str(metadata["version"])
    folder_name = f"{name}_{version}"
    archive_path = DIST_DIR / f"{folder_name}.zip"
    checksum_path = DIST_DIR / f"{folder_name}.zip.sha256"

    if DIST_DIR.exists():
        shutil.rmtree(DIST_DIR)
    DIST_DIR.mkdir(parents=True)

    with zipfile.ZipFile(
        archive_path,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for source in files:
            relative = PurePosixPath(source.relative_to(ROOT).as_posix())
            add_file_to_zip(archive, source, PurePosixPath(folder_name) / relative)

    validate_archive(archive_path, folder_name)

    digest = hashlib.sha256(archive_path.read_bytes()).hexdigest()
    checksum_path.write_text(
        f"{digest}  {archive_path.name}\n",
        encoding="utf-8",
    )

    return archive_path, checksum_path


def main() -> int:
    metadata = load_metadata()
    files = collect_files()
    archive_path, checksum_path = build_archive(metadata, files)

    print(f"Mod name: {metadata['name']}")
    print(f"Version: {metadata['version']}")
    print(f"Factorio version: {metadata['factorio_version']}")
    print(f"Packaged files: {len(files)}")
    print(f"Created: {archive_path.relative_to(ROOT)}")
    print(f"Created: {checksum_path.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except OSError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1) from exc
