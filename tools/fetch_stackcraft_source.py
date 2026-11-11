#!/usr/bin/env python3
"""Recover the locked, private StackCraft source from a ZIP; never run its code."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import struct
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import zipfile

REPOSITORY = "https://github.com/zhuanggenhua/CardLoop"
COMMIT = "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
SUBTREE = "Assets/StackCraft"
PROJECT = Path(__file__).resolve().parents[1]
LOCK_PATH = PROJECT / "docs/source-lock.json"
# The GitHub repository API advertises this archive_url template. No user URL,
# authentication headers, credential files or alternate mirrors are supported.
ARCHIVE_URL = f"https://api.github.com/repos/zhuanggenhua/CardLoop/zipball/{COMMIT}"
ALLOWED_URLS = frozenset((ARCHIVE_URL,
    f"https://codeload.github.com/zhuanggenhua/CardLoop/legacy.zip/{COMMIT}",
    f"https://codeload.github.com/zhuanggenhua/CardLoop/zip/{COMMIT}"))
MAX_ARCHIVE_BYTES = 512 * 1024 * 1024
MAX_DIRECTORY_BYTES = 16 * 1024 * 1024
MAX_TOTAL_BYTES = 2 * 1024 * 1024 * 1024
MAX_MEMBER_BYTES = 256 * 1024 * 1024
MAX_MEMBERS = 30000
MAX_RATIO = 1000
CHUNK = 1024 * 1024


class RecoveryError(ValueError):
    pass


def safe_parts(name: str, directory: bool = False) -> tuple[str, ...]:
    if not isinstance(name, str) or not name or any(c in name for c in '\\:<>"|?*'):
        raise RecoveryError(f"Unsafe archive/lock path: {name!r}")
    if directory and name.endswith("/"):
        name = name[:-1]
    parts = name.split("/")
    devices = {"CON", "PRN", "AUX", "NUL", *(f"COM{i}" for i in range(1, 10)),
               *(f"LPT{i}" for i in range(1, 10))}
    if any(not p or p in (".", "..") or p.endswith((".", " ")) or
           any(ord(c) < 32 or ord(c) == 127 for c in p) or
           p.split(".")[0].upper() in devices for p in parts):
        raise RecoveryError(f"Unsafe archive/lock path: {name!r}")
    return tuple(parts)


def validate_lock(lock: dict) -> dict[str, dict]:
    for key, expected in (("repository", REPOSITORY), ("commit", COMMIT), ("directory", SUBTREE)):
        if lock.get(key) != expected:
            raise RecoveryError(f"Lock {key} does not match this tool's fixed source")
    files = lock.get("files", [])
    if not files or len(files) != lock.get("file_count") or len(files) > MAX_MEMBERS:
        raise RecoveryError("Invalid source-lock file count")
    result, portable_names = {}, set()
    for item in files:
        name = item["path"]
        safe_parts(name)
        size, digest = item["bytes"], item["sha256"]
        if type(size) is not int or not 0 <= size <= MAX_MEMBER_BYTES:
            raise RecoveryError(f"Invalid locked size: {name}")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise RecoveryError(f"Invalid locked digest: {name}")
        if name.casefold() in portable_names:
            raise RecoveryError(f"Duplicate/case-colliding locked path: {name}")
        result[name] = item
        portable_names.add(name.casefold())
    for name in result:
        if any(str(p) in result for p in PurePosixPath(name).parents if str(p) != "."):
            raise RecoveryError(f"File/directory collision in lock: {name}")
    if sum(x["bytes"] for x in files) > MAX_TOTAL_BYTES:
        raise RecoveryError("Locked source exceeds safety budget")
    return result


def digest(path: Path) -> str:
    result = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(CHUNK), b""):
            result.update(data)
    return result.hexdigest()


def no_symlink_ancestors(path: Path) -> None:
    for part in (path, *path.parents):
        if part.is_symlink():
            raise RecoveryError(f"Symlink destination component refused: {part}")


def private_destination(path: Path, relative_files=()) -> Path:
    # abspath normalizes without following a symlink, unlike Path.resolve().
    path = Path(os.path.abspath(path))
    no_symlink_ancestors(path)
    ancestor = path
    while not ancestor.exists():
        ancestor = ancestor.parent
    if not ancestor.is_dir():
        raise RecoveryError("Destination or an ancestor is not a directory")
    try:
        repository = subprocess.run(["git", "-C", str(ancestor), "rev-parse", "--show-toplevel"],
                                    capture_output=True, text=True)
        if repository.returncode == 0:
            repo = Path(repository.stdout.strip()).resolve()
            relative = path.relative_to(repo).as_posix()
            tracked = subprocess.run(["git", "-C", str(repo), "ls-files", "-z", "--", relative],
                                     capture_output=True, check=True)
            candidates = {relative + "/", *(relative + "/" + name for name in relative_files)}
            ignored = subprocess.run(["git", "-C", str(repo), "check-ignore", "--no-index", "--stdin", "-z"],
                                     input="\0".join(sorted(candidates)).encode() + b"\0", capture_output=True)
            ignored_paths = {value.decode() for value in ignored.stdout.split(b"\0") if value}
            if tracked.stdout or ignored.returncode != 0 or ignored_paths != candidates:
                raise RecoveryError("Destination inside Git must be ignored and contain no tracked files")
        elif repository.returncode != 128 or "not a git repository" not in repository.stderr.lower():
            raise RecoveryError("Could not establish whether the destination is safely outside Git")
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        raise RecoveryError("Git is required to check private destination safety") from exc
    return path


def existing_files(destination: Path, expected: dict[str, dict]) -> set[str]:
    no_symlink_ancestors(destination)
    if not destination.exists():
        return set()
    if not destination.is_dir():
        raise RecoveryError("Destination must be a directory")
    found = set()
    def fail_walk(error):
        raise error
    for folder, directories, files in os.walk(destination, followlinks=False, onerror=fail_walk):
        for name in directories + files:
            path = Path(folder) / name
            mode = path.lstat().st_mode
            if stat.S_ISLNK(mode) or not (stat.S_ISREG(mode) or stat.S_ISDIR(mode)):
                raise RecoveryError(f"Non-regular destination entry refused: {path}")
            relative = path.relative_to(destination).as_posix()
            if stat.S_ISDIR(mode):
                if relative in expected:
                    raise RecoveryError(f"Directory conflicts with a locked file: {relative}")
                continue
            item = expected.get(relative)
            if item is None:
                raise RecoveryError(f"Unexpected existing destination file: {relative}")
            if path.stat().st_size != item["bytes"] or digest(path) != item["sha256"]:
                raise RecoveryError(f"Existing file differs; refusing to overwrite: {relative}")
            found.add(relative)
    return found


def check_zip_envelope(path: Path) -> None:
    """Bound central-directory allocation before zipfile constructs member objects."""
    size = path.stat().st_size
    if size > MAX_ARCHIVE_BYTES:
        raise RecoveryError("ZIP exceeds compressed-size budget")
    with path.open("rb") as stream:
        stream.seek(max(0, size - 65557))
        tail = stream.read(65557)
    position = tail.rfind(b"PK\x05\x06")
    if position < 0 or len(tail) - position < 22:
        raise RecoveryError("Not a supported ordinary ZIP archive")
    _, disk, start_disk, disk_entries, entries, central_size, central_offset, comment = struct.unpack(
        "<4s4H2LH", tail[position:position + 22])
    absolute_end = size - len(tail) + position
    if len(tail) != position + 22 + comment:
        raise RecoveryError("Malformed ZIP end record or trailing data")
    if disk or start_disk or disk_entries != entries or entries == 65535 or central_offset == 0xffffffff:
        raise RecoveryError("Split/ZIP64 archives are not supported")
    if entries > MAX_MEMBERS or central_size > MAX_DIRECTORY_BYTES:
        raise RecoveryError("ZIP central directory exceeds safety budget")
    if central_offset + central_size != absolute_end:
        raise RecoveryError("Malformed ZIP central-directory bounds")


def select_members(archive: zipfile.ZipFile, expected: dict[str, dict]) -> dict[str, zipfile.ZipInfo]:
    members = archive.infolist()
    if len(members) > MAX_MEMBERS:
        raise RecoveryError("ZIP has too many entries")
    seen, directories, regular, total = set(), set(), {}, 0
    roots, selected = set(), {}
    for entry in members:
        # orig_filename preserves an embedded NUL that ZipInfo.filename truncates.
        if entry.orig_filename != entry.filename:
            raise RecoveryError("ZIP contains a truncated/NUL member name")
        parts = safe_parts(entry.filename, entry.is_dir())
        normalized = "/".join(parts).casefold()
        if normalized in seen:
            raise RecoveryError(f"Duplicate/case-colliding ZIP member: {entry.filename}")
        seen.add(normalized)
        mode = entry.external_attr >> 16
        kind = stat.S_IFMT(mode)
        if kind not in (0, stat.S_IFREG, stat.S_IFDIR) or (kind == stat.S_IFDIR) != entry.is_dir() and kind:
            raise RecoveryError(f"Link/special or inconsistent ZIP member: {entry.filename}")
        if entry.flag_bits & 1 or entry.compress_type not in (zipfile.ZIP_STORED, zipfile.ZIP_DEFLATED):
            raise RecoveryError("Encrypted or unsupported ZIP compression")
        if entry.file_size > MAX_MEMBER_BYTES or entry.file_size > MAX_RATIO * max(1, entry.compress_size):
            raise RecoveryError(f"ZIP member exceeds expansion budget: {entry.filename}")
        total += entry.file_size
        if total > MAX_TOTAL_BYTES:
            raise RecoveryError("ZIP exceeds total expansion budget")
        if entry.is_dir():
            if entry.file_size:
                raise RecoveryError("ZIP directory has data")
            directories.add(normalized)
        else:
            regular[normalized] = entry
        for offset in (0, 1):
            if tuple(parts[offset:offset + 2]) != ("Assets", "StackCraft"):
                continue
            root = parts[:offset]
            roots.add(root)
            suffix = parts[offset + 2:]
            if entry.is_dir():
                break
            name = "/".join(suffix)
            if name not in expected:
                raise RecoveryError(f"Unexpected file inside StackCraft: {name}")
            if entry.file_size != expected[name]["bytes"]:
                raise RecoveryError(f"Archive size differs from lock: {name}")
            if name in selected:
                raise RecoveryError(f"Ambiguous StackCraft member: {name}")
            selected[name] = entry
            break
    for name in regular.keys() | directories:
        if any(str(parent) in regular for parent in PurePosixPath(name).parents if str(parent) != "."):
            raise RecoveryError(f"ZIP file/directory path collision: {name}")
    if len(roots) != 1:
        raise RecoveryError("Expected exactly one Assets/StackCraft tree, optionally under one wrapper")
    missing = expected.keys() - selected.keys()
    if missing:
        raise RecoveryError(f"Archive is missing {len(missing)} locked files; first: {min(missing)}")
    return selected


def recover(archive_path: Path, destination: Path, lock: dict) -> dict:
    expected = validate_lock(lock)
    destination = private_destination(destination, expected)
    original = existing_files(destination, expected)
    check_zip_envelope(archive_path)
    ancestor = destination.parent
    while not ancestor.exists():
        ancestor = ancestor.parent
    # Sibling staging keeps publication on the same filesystem. Everything is
    # checked before the destination changes. No extract()/extractall() calls.
    with zipfile.ZipFile(archive_path) as archive, tempfile.TemporaryDirectory(
            prefix=".stackcraft-recovery-", dir=ancestor) as temporary:
        selected = select_members(archive, expected)
        stage = Path(temporary) / "source"
        stage.mkdir(mode=0o700)
        for name, entry in sorted(selected.items()):
            path = stage.joinpath(*safe_parts(name))
            path.parent.mkdir(parents=True, exist_ok=True)
            written, hashed = 0, hashlib.sha256()
            with archive.open(entry) as stream, path.open("xb") as output:
                while data := stream.read(min(CHUNK, expected[name]["bytes"] - written + 1)):
                    written += len(data)
                    if written > expected[name]["bytes"]:
                        raise RecoveryError(f"Inflated file exceeds locked size: {name}")
                    hashed.update(data)
                    output.write(data)
            if written != expected[name]["bytes"] or hashed.hexdigest() != expected[name]["sha256"]:
                raise RecoveryError(f"Archive SHA-256/size differs from lock: {name}")
        # Recheck after staging, because another process may have changed output.
        current = existing_files(destination, expected)
        no_symlink_ancestors(destination)
        destination.parent.mkdir(parents=True, exist_ok=True)
        if not destination.exists():
            stage.rename(destination)
        else:
            for name in sorted(expected.keys() - current):
                target = destination.joinpath(*safe_parts(name))
                no_symlink_ancestors(target)
                target.parent.mkdir(parents=True, exist_ok=True)
                # An atomic exclusive link cannot overwrite a file created by
                # a concurrent writer. Stage and destination share a filesystem.
                os.link(stage / name, target, follow_symlinks=False)
        final = existing_files(destination, expected)
        if final != expected.keys():
            raise RecoveryError("Final source verification failed")
    return {"status": "verified", "commit": COMMIT, "files": len(expected),
            "already_present": len(original), "restored": len(expected) - len(original)}


class OfficialRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, newurl):
        if newurl not in ALLOWED_URLS:
            raise RecoveryError("Archive redirect outside the fixed official GitHub source refused")
        return super().redirect_request(request, response, code, message, headers, newurl)


def download_archive(target: Path) -> None:
    opener = urllib.request.build_opener(OfficialRedirects())
    request = urllib.request.Request(ARCHIVE_URL, headers={"User-Agent": "AbyssalGuild-source-recovery"})
    started = time.monotonic()
    try:
        with opener.open(request, timeout=30) as response, target.open("xb") as output:
            if response.geturl() not in ALLOWED_URLS:
                raise RecoveryError("Unexpected archive response URL")
            length = response.headers.get("Content-Length")
            if length is not None and (not length.isdecimal() or int(length) > MAX_ARCHIVE_BYTES):
                raise RecoveryError("Download exceeds compressed-size budget or has invalid length")
            total = 0
            while data := response.read(CHUNK):
                total += len(data)
                if total > MAX_ARCHIVE_BYTES or time.monotonic() - started > 300:
                    raise RecoveryError("Download exceeds byte/time budget")
                output.write(data)
    except urllib.error.HTTPError as exc:
        raise RecoveryError(f"Official archive returned HTTP {exc.code}; no authentication, retries or mirrors attempted. "
                            "Use --archive with a legally obtained ZIP instead.") from exc
    except urllib.error.URLError as exc:
        raise RecoveryError("Official archive network/TLS request failed; network permissions were not changed. "
                            "Use --archive with a legally obtained ZIP instead.") from exc


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise RecoveryError(f"Duplicate JSON key in source lock: {key}")
        result[key] = value
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--archive", type=Path, help="Offline ZIP from the locked repository (recommended)")
    source.add_argument("--download", action="store_true", help="Explicit unauthenticated official GitHub ZIP download")
    parser.add_argument("--output", type=Path, default=PROJECT / "source/StackCraft",
                        help="Private destination; inside a Git repository it must be ignored")
    parser.add_argument("--acknowledge-license", action="store_true", required=True,
                        help="Confirm you are entitled to use the source privately; grants no redistribution rights")
    args = parser.parse_args(argv)
    try:
        lock = json.loads(LOCK_PATH.read_text(), object_pairs_hook=unique_object)
        expected = validate_lock(lock)
        destination = private_destination(args.output, expected)
        existing_files(destination, expected)  # Fail before any network request.
        if args.archive:
            result = recover(args.archive, destination, lock)
        else:
            with tempfile.TemporaryDirectory(prefix="stackcraft-download-") as temporary:
                archive = Path(temporary) / "source.zip"
                download_archive(archive)
                result = recover(archive, destination, lock)
        print(json.dumps(result, sort_keys=True))
        print("Private source only. No Unity execution or redistribution permission.")
        return 0
    except (RecoveryError, OSError, KeyError, TypeError, json.JSONDecodeError, zipfile.BadZipFile,
            RuntimeError, NotImplementedError, subprocess.SubprocessError) as exc:
        print(f"Recovery refused: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
