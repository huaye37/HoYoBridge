"""Offline tests: no upstream import, API request or real game directory."""

import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import patch

from download_genshin_cn_full import acquire_download_lock, write_marker


class MarkerTests(unittest.TestCase):
    def test_inherited_lock_survives_parent_handle_close(self):
        with tempfile.TemporaryDirectory(prefix="mgb-lock-test-") as directory:
            cache = Path(directory)
            with acquire_download_lock(cache) as parent:
                child = acquire_download_lock(cache, parent.fileno())
            with child:
                with self.assertRaisesRegex(RuntimeError, "download-already-running"):
                    acquire_download_lock(cache)
            with acquire_download_lock(cache):
                pass

    def test_unrelated_inherited_file_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix="mgb-lock-test-") as directory:
            cache = Path(directory)
            with acquire_download_lock(cache), tempfile.TemporaryFile() as unrelated:
                with self.assertRaisesRegex(RuntimeError, "invalid-inherited-download-lock"):
                    acquire_download_lock(cache, unrelated.fileno())

    def test_atomic_commit_is_private(self):
        with tempfile.TemporaryDirectory(prefix="mgb-marker-test-") as directory:
            marker = Path(directory) / ".mgb-managed-cn-download"
            write_marker(marker, "schema=1\nstate=downloading\n")
            write_marker(marker, "schema=1\nstate=complete\nversion=7.1.0\n")
            self.assertIn("state=complete", marker.read_text())
            self.assertEqual(stat.S_IMODE(marker.stat().st_mode), 0o600)
            self.assertEqual(list(marker.parent.iterdir()), [marker])

    def test_failed_commit_keeps_interrupted_marker(self):
        with tempfile.TemporaryDirectory(prefix="mgb-marker-test-") as directory:
            marker = Path(directory) / ".mgb-managed-cn-download"
            write_marker(marker, "schema=1\nstate=downloading\n")
            before = marker.read_bytes()
            with patch.object(os, "replace", side_effect=OSError("disk disconnected")):
                with self.assertRaises(OSError):
                    write_marker(marker, "schema=1\nstate=complete\nversion=7.1.0\n")
            self.assertEqual(marker.read_bytes(), before)
            self.assertEqual(list(marker.parent.iterdir()), [marker])


if __name__ == "__main__":
    unittest.main()
