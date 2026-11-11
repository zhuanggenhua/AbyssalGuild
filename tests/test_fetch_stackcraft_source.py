import hashlib
import importlib.util
import io
import json
from pathlib import Path
import stat
import struct
import subprocess
import tempfile
import unittest
from unittest import mock
import urllib.error
import urllib.request
import warnings
import zipfile

SPEC = importlib.util.spec_from_file_location("fetch_stackcraft_source", Path(__file__).parents[1] / "tools/fetch_stackcraft_source.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.archive = self.root / "input.zip"
        self.destination = self.root / "private/StackCraft"
        self.contents = {"Scripts/A.cs": b"alpha", "Sounds/theme.wav": b"synthetic audio bytes"}
        self.lock = {"repository": MODULE.REPOSITORY, "commit": MODULE.COMMIT,
                     "directory": MODULE.SUBTREE, "file_count": len(self.contents),
                     "files": [{"path": p, "bytes": len(b), "sha256": hashlib.sha256(b).hexdigest()}
                               for p, b in self.contents.items()]}
        self.prefix = "CardLoop-" + MODULE.COMMIT + "/Assets/StackCraft/"

    def make_zip(self, additions=(), contents=None, prefix=None):
        contents = self.contents if contents is None else contents
        prefix = self.prefix if prefix is None else prefix
        with warnings.catch_warnings(), zipfile.ZipFile(self.archive, "w", zipfile.ZIP_DEFLATED) as archive:
            warnings.simplefilter("ignore", UserWarning)
            for name, data in contents.items():
                archive.writestr(prefix + name, data)
            for name, data in additions:
                archive.writestr(name, data)

    def recover(self):
        return MODULE.recover(self.archive, self.destination, self.lock)

    def assert_refused(self):
        with self.assertRaises((MODULE.RecoveryError, zipfile.BadZipFile)):
            self.recover()
        self.assertFalse(self.destination.exists())
        self.assertFalse(list(self.root.glob(".stackcraft-recovery-*")))

    def test_exact_recovery_idempotence_and_source_unchanged(self):
        self.make_zip(additions=[("CardLoop-" + MODULE.COMMIT + "/README.md", b"Not extracted")])
        before = self.archive.read_bytes()
        result = self.recover()
        self.assertEqual(result["restored"], 2)
        self.assertEqual(result["files"], 2)
        for name, data in self.contents.items():
            self.assertEqual((self.destination / name).read_bytes(), data)
        self.assertEqual(self.recover()["restored"], 0)
        self.assertEqual(self.archive.read_bytes(), before)
        self.assertFalse((self.destination / "README.md").exists())

    def test_unwrapped_repository_and_api_wrapper(self):
        for prefix in ("Assets/StackCraft/", "zhuanggenhua-CardLoop-a11a89b/Assets/StackCraft/"):
            with self.subTest(prefix=prefix):
                self.make_zip(prefix=prefix)
                self.assertEqual(self.recover()["files"], 2)

    def test_matching_partial_destination_is_completed_without_overwrite(self):
        self.make_zip()
        existing = self.destination / "Scripts/A.cs"
        existing.parent.mkdir(parents=True)
        existing.write_bytes(self.contents["Scripts/A.cs"])
        inode = existing.stat().st_ino
        result = self.recover()
        self.assertEqual((result["already_present"], result["restored"]), (1, 1))
        self.assertEqual(existing.stat().st_ino, inode)

    def test_different_existing_file_is_preserved(self):
        self.make_zip()
        existing = self.destination / "Scripts/A.cs"
        existing.parent.mkdir(parents=True)
        existing.write_bytes(b"wrong")
        with self.assertRaisesRegex(MODULE.RecoveryError, "refusing to overwrite"):
            self.recover()
        self.assertEqual(existing.read_bytes(), b"wrong")
        self.assertFalse((self.destination / "Sounds").exists())

    def test_unexpected_existing_file_refused(self):
        self.make_zip()
        self.destination.mkdir(parents=True)
        (self.destination / "extra").write_text("keep")
        with self.assertRaisesRegex(MODULE.RecoveryError, "Unexpected existing"):
            self.recover()
        self.assertEqual((self.destination / "extra").read_text(), "keep")

    def test_existing_directory_at_locked_file_path_refused_before_writes(self):
        self.make_zip()
        (self.destination / "Scripts/A.cs").mkdir(parents=True)
        with self.assertRaisesRegex(MODULE.RecoveryError, "Directory conflicts"):
            self.recover()
        self.assertFalse((self.destination / "Sounds").exists())

    def test_sha_mismatch_does_not_change_matching_partial_destination(self):
        self.make_zip(contents={**self.contents, "Sounds/theme.wav": b"X" * len(self.contents["Sounds/theme.wav"])})
        existing = self.destination / "Scripts/A.cs"
        existing.parent.mkdir(parents=True)
        existing.write_bytes(b"alpha")
        with self.assertRaisesRegex(MODULE.RecoveryError, "SHA-256"):
            self.recover()
        self.assertEqual(existing.read_bytes(), b"alpha")
        self.assertFalse((self.destination / "Sounds").exists())

    def test_size_mismatch(self):
        self.make_zip(contents={**self.contents, "Scripts/A.cs": b"bad"})
        self.assert_refused()

    def test_missing_locked_file(self):
        self.make_zip(contents={"Scripts/A.cs": b"alpha"})
        self.assert_refused()

    def test_extra_source_file(self):
        self.make_zip(additions=[(self.prefix + "unlocked.txt", b"extra")])
        self.assert_refused()

    def test_unexpected_other_source_tree(self):
        self.make_zip(additions=[("Other/Assets/StackCraft/", b"")])
        self.assert_refused()

    def test_paths_cannot_escape_even_outside_selected_tree(self):
        for name in ("../escape", "/absolute", "C:/absolute", "x\\..\\escape", "x//empty", "x/./dot", "x/NUL.txt", "x/trailing."):
            with self.subTest(name=name):
                self.make_zip(additions=[(name, b"no")])
                self.assert_refused()

    def test_duplicate_and_case_colliding_names(self):
        for name in (self.prefix + "Scripts/A.cs", self.prefix + "scripts/a.cs"):
            with self.subTest(name=name):
                self.make_zip(additions=[(name, b"alpha")])
                self.assert_refused()

    def test_file_directory_collision(self):
        self.make_zip(additions=[("Elsewhere", b"file"), ("Elsewhere/nested", b"child")])
        self.assert_refused()

    def test_symlink_and_special_zip_entries(self):
        for mode in (stat.S_IFLNK, stat.S_IFIFO, stat.S_IFSOCK):
            with self.subTest(mode=mode):
                entry = zipfile.ZipInfo("elsewhere/link")
                entry.create_system = 3
                entry.external_attr = (mode | 0o777) << 16
                self.make_zip(additions=[(entry, b"/outside")])
                self.assert_refused()

    def test_symlink_destination_and_parent(self):
        self.make_zip()
        outside = self.root / "outside"
        outside.mkdir()
        (self.root / "private").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(MODULE.RecoveryError, "Symlink"):
            self.recover()
        self.assertEqual(list(outside.iterdir()), [])

    def test_symlink_inside_destination(self):
        self.make_zip()
        self.destination.mkdir(parents=True)
        (self.destination / "Scripts").symlink_to(self.root, target_is_directory=True)
        with self.assertRaisesRegex(MODULE.RecoveryError, "Non-regular"):
            self.recover()

    def test_compressed_size_member_count_and_directory_budgets(self):
        self.make_zip()
        for name, value in (("MAX_ARCHIVE_BYTES", 1), ("MAX_MEMBERS", 1), ("MAX_DIRECTORY_BYTES", 1),
                            ("MAX_TOTAL_BYTES", 1), ("MAX_MEMBER_BYTES", 1)):
            with self.subTest(name=name), mock.patch.object(MODULE, name, value):
                self.assert_refused()

    def test_high_expansion_ratio_in_unselected_entry_refused(self):
        self.make_zip(additions=[("unused/bomb", b"0" * 100000)])
        with mock.patch.object(MODULE, "MAX_RATIO", 100):
            self.assert_refused()

    def test_unsupported_compression(self):
        self.make_zip()
        with zipfile.ZipFile(self.archive, "a") as archive:
            archive.writestr("unused/bzip", b"data", compress_type=zipfile.ZIP_BZIP2)
        self.assert_refused()

    def test_corrupted_archive_and_trailing_data(self):
        for contents in (b"not zip", b"PK\x05\x06", b"<html>Sign in</html>"):
            self.archive.write_bytes(contents)
            self.assert_refused()
        self.make_zip()
        self.archive.write_bytes(self.archive.read_bytes() + b"trailing")
        self.assert_refused()

    def test_crc_corruption_not_published(self):
        with zipfile.ZipFile(self.archive, "w", zipfile.ZIP_STORED) as archive:
            for name, data in self.contents.items():
                archive.writestr(self.prefix + name, data)
        content = self.archive.read_bytes().replace(b"alpha", b"WRONG", 1)
        self.archive.write_bytes(content)
        self.assert_refused()

    def test_split_and_zip64_end_records_refused(self):
        for offset, fmt, value in ((4, "<H", 1), (10, "<H", 65535), (16, "<L", 0xffffffff)):
            self.make_zip()
            data = bytearray(self.archive.read_bytes())
            end = data.rfind(b"PK\x05\x06")
            struct.pack_into(fmt, data, end + offset, value)
            self.archive.write_bytes(data)
            self.assert_refused()

    def test_lock_metadata_cannot_choose_other_repository(self):
        self.make_zip()
        for key in ("repository", "commit", "directory"):
            with self.subTest(key=key), mock.patch.dict(self.lock, {key: "untrusted"}):
                self.assert_refused()

    def test_lock_duplicate_paths_and_invalid_types(self):
        self.make_zip()
        variants = [dict(self.lock["files"][0]), {"path": "../escape", "bytes": 1, "sha256": "0" * 64},
                    {"path": "ok", "bytes": True, "sha256": "0" * 64},
                    {"path": "ok", "bytes": 1, "sha256": "not a digest"}]
        for entry in variants:
            with self.subTest(entry=entry), mock.patch.dict(self.lock, {"files": [self.lock["files"][0], entry]}):
                self.assert_refused()

    def test_git_destination_must_be_ignored_not_tracked(self):
        self.make_zip()
        repository = self.root / "repository"
        repository.mkdir()
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        self.destination = repository / "public"
        with self.assertRaisesRegex(MODULE.RecoveryError, "must be ignored"):
            self.recover()
        (repository / ".gitignore").write_text("private/\n")
        self.destination = repository / "private/StackCraft"
        self.assertEqual(self.recover()["files"], 2)
        subprocess.run(["git", "-C", str(repository), "add", "-f", "private/StackCraft/Scripts/A.cs"], check=True)
        with self.assertRaisesRegex(MODULE.RecoveryError, "no tracked files"):
            self.recover()

    def test_ignoring_only_a_probe_filename_is_not_sufficient(self):
        self.make_zip()
        repository = self.root / "repository"
        repository.mkdir()
        subprocess.run(["git", "init", "-q", str(repository)], check=True)
        (repository / ".gitignore").write_text(".stackcraft-private-probe\n")
        self.destination = repository / "public"
        with self.assertRaisesRegex(MODULE.RecoveryError, "must be ignored"):
            self.recover()

    def test_cli_requires_source_choice_and_license_acknowledgment(self):
        with mock.patch("sys.stderr", new_callable=io.StringIO):
            for arguments in ([], ["--archive", str(self.archive)]):
                with self.assertRaises(SystemExit) as error:
                    MODULE.main(arguments)
                self.assertEqual(error.exception.code, 2)

    def test_offline_cli_does_not_use_network(self):
        self.make_zip()
        lock_file = self.root / "lock.json"
        lock_file.write_text(json.dumps(self.lock))
        with mock.patch.object(MODULE, "LOCK_PATH", lock_file), mock.patch.object(MODULE, "download_archive") as network, \
                mock.patch("sys.stdout", new_callable=io.StringIO):
            result = MODULE.main(["--archive", str(self.archive), "--output", str(self.destination), "--acknowledge-license"])
        self.assertEqual(result, 0)
        network.assert_not_called()


class DownloadTests(unittest.TestCase):
    def test_redirects_only_allow_fixed_https_archive_urls(self):
        handler = MODULE.OfficialRedirects()
        request = urllib.request.Request(MODULE.ARCHIVE_URL)
        for url in ("http://codeload.github.com/insecure", "https://example.org/source.zip",
                    MODULE.ARCHIVE_URL + "?token=secret", "https://github.com/login"):
            with self.subTest(url=url), self.assertRaises(MODULE.RecoveryError):
                handler.redirect_request(request, None, 302, "Found", {}, url)
        allowed = next(url for url in MODULE.ALLOWED_URLS if "legacy.zip" in url)
        self.assertEqual(handler.redirect_request(request, None, 302, "Found", {}, allowed).full_url, allowed)

    def response(self, data, url=MODULE.ARCHIVE_URL, headers=None):
        response = io.BytesIO(data)
        response.geturl = lambda: url
        response.headers = headers or {}
        return response

    def test_download_uses_only_official_url_and_no_auth_header(self):
        with tempfile.TemporaryDirectory() as temp, mock.patch.object(MODULE.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = self.response(b"zip bytes")
            target = Path(temp) / "download.zip"
            MODULE.download_archive(target)
            self.assertEqual(target.read_bytes(), b"zip bytes")
            request = build.return_value.open.call_args.args[0]
            self.assertEqual(request.full_url, MODULE.ARCHIVE_URL)
            self.assertNotIn("Authorization", request.headers)

    def test_auth_network_and_wrong_destination_fail_clearly(self):
        cases = [(urllib.error.HTTPError(MODULE.ARCHIVE_URL, 403, "Forbidden", {}, None), "HTTP 403"),
                 (urllib.error.URLError("blocked"), "network/TLS")]
        for error, message in cases:
            with self.subTest(message=message), tempfile.TemporaryDirectory() as temp, \
                    mock.patch.object(MODULE.urllib.request, "build_opener") as build:
                build.return_value.open.side_effect = error
                with self.assertRaisesRegex(MODULE.RecoveryError, message):
                    MODULE.download_archive(Path(temp) / "download.zip")
                self.assertEqual(build.return_value.open.call_count, 1)
        with tempfile.TemporaryDirectory() as temp, mock.patch.object(MODULE.urllib.request, "build_opener") as build:
            build.return_value.open.return_value = self.response(b"data", url="https://example.org")
            with self.assertRaisesRegex(MODULE.RecoveryError, "Unexpected archive response"):
                MODULE.download_archive(Path(temp) / "download.zip")

    def test_download_size_and_time_limits(self):
        for headers, limit, times in (({"Content-Length": "9"}, 3, [0]), ({}, 3, [0, 1]), ({}, 20, [0, 301])):
            with self.subTest(headers=headers, limit=limit, times=times), tempfile.TemporaryDirectory() as temp, \
                    mock.patch.object(MODULE.urllib.request, "build_opener") as build, \
                    mock.patch.object(MODULE, "MAX_ARCHIVE_BYTES", limit), \
                    mock.patch.object(MODULE.time, "monotonic", side_effect=times):
                build.return_value.open.return_value = self.response(b"123456789", headers=headers)
                with self.assertRaises(MODULE.RecoveryError):
                    MODULE.download_archive(Path(temp) / "download.zip")


if __name__ == "__main__":
    unittest.main()
