import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from verify_hyp_installation import verify


class VerificationTests(unittest.TestCase):
    def test_complete_and_same_size_corruption(self):
        with tempfile.TemporaryDirectory() as directory:
            game = Path(directory)
            data = b"sample-executable"
            (game / "BH3.exe").write_bytes(data)
            (game / "pkg_version").write_text(json.dumps({
                "remoteName": "BH3.exe", "fileSize": len(data),
                "md5": hashlib.md5(data).hexdigest(),
            }))
            self.assertTrue(verify(game, "BH3.exe")["complete"])
            (game / "BH3.exe").write_bytes(b"x" * len(data))
            self.assertEqual(verify(game, "BH3.exe")["failedFiles"], 1)
            (game / "BH3.exe").unlink()
            self.assertEqual(verify(game, "BH3.exe")["failedFiles"], 1)

    def test_escape_is_rejected_without_reading_outside_game(self):
        with tempfile.TemporaryDirectory() as directory:
            game = Path(directory)
            (game / "pkg_version").write_text(json.dumps({
                "remoteName": "../BH3.exe", "fileSize": 0, "md5": "0" * 32,
            }))
            with self.assertRaisesRegex(ValueError, "unsafe-or-duplicate"):
                verify(game, "BH3.exe")

    def test_external_manifest_does_not_require_pkg_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "game"
            game.mkdir()
            (game / "BH3.exe").write_bytes(b"sample")
            manifest = root / "full.jsonl"
            manifest.write_text(json.dumps({
                "remoteName": "BH3.exe", "fileSize": 6,
                "md5": hashlib.md5(b"sample").hexdigest(),
            }))
            result = verify(game, "BH3.exe", manifest)
            self.assertTrue(result["complete"])
            self.assertEqual(result["verifiedReadBytes"], 6)


if __name__ == "__main__":
    unittest.main()
