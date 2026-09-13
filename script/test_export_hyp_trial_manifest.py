"""Run with the pinned YAAGL Python environment and sophon_server on PYTHONPATH."""
import contextlib
import hashlib
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

import manifest_pb2
import zstandard

from export_hyp_trial_manifest import export


class ExportTests(unittest.TestCase):
    def test_uncompressed_checksum_and_corruption_rejection(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            game = root / "game"
            game.mkdir()
            database = root / "sophon_db"
            database.mkdir()
            cache = root / "manifest"
            cache.mkdir()
            windows_path = "Z:" + str(game.resolve()).replace("/", "\\")
            with sqlite3.connect(database / "chunk.db") as connection:
                connection.execute("CREATE TABLE depot_file_data(package_id,build_id,depot_id,install_dir)")
                connection.execute("INSERT INTO depot_file_data VALUES(?,?,?,?)", ("p", "b", "d", windows_path))
            manifest = manifest_pb2.Manifest()
            file = manifest.files.add()
            file.filename, file.md5, file.size = "BH3.exe", hashlib.md5(b"game").hexdigest(), 4
            decoded = manifest.SerializeToString()
            compressed = zstandard.ZstdCompressor().compress(decoded)
            cached = cache / "test_manifest"
            cached.write_bytes(compressed)
            with sqlite3.connect(database / "chunk_manifest.db") as connection:
                connection.execute("CREATE TABLE depot_manifest(package_id,build_id,depot_id,depot_manifest_id,"
                                   "depot_manifest_md5,depot_manifest_compressed_size,depot_manifest_uncompressed_size,"
                                   "depot_manifest_encryption,depot_manifest_compression)")
                connection.execute("INSERT INTO depot_manifest VALUES(?,?,?,?,?,?,?,?,?)", (
                    "p", "b", "d", cached.name, hashlib.md5(decoded).hexdigest(),
                    len(compressed), len(decoded), 0, 1,
                ))
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                export(root, game)
            self.assertEqual(json.loads(output.getvalue())["remoteName"], "BH3.exe")
            # A compressed-payload checksum must not accidentally be accepted.
            with sqlite3.connect(database / "chunk_manifest.db") as connection:
                connection.execute("UPDATE depot_manifest SET depot_manifest_md5=?", (hashlib.md5(compressed).hexdigest(),))
            with self.assertRaisesRegex(ValueError, "checksum-mismatch"):
                export(root, game)


if __name__ == "__main__":
    unittest.main()
