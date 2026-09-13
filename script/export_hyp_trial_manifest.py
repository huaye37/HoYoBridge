"""Read only the isolated HYP cached manifests for one exact installed directory.

Requires the existing pinned YAAGL Python/protobuf environment. No network access,
no game/database writes, no URL/password/token fields queried or printed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sqlite3

import manifest_pb2
import zstandard


def export(sophon: Path, game: Path):
    windows_path = "Z:" + str(game.resolve(strict=True)).replace("/", "\\")
    database = sophon / "sophon_db"
    with sqlite3.connect((database / "chunk.db").as_uri() + "?mode=ro", uri=True) as chunks:
        depots = chunks.execute(
            "SELECT DISTINCT package_id,build_id,depot_id FROM depot_file_data WHERE install_dir=?",
            (windows_path,),
        ).fetchall()
    if not depots or len({(p, b) for p, b, _ in depots}) != 1:
        raise ValueError("missing-or-ambiguous-active-game-build")
    files = {}
    with sqlite3.connect((database / "chunk_manifest.db").as_uri() + "?mode=ro", uri=True) as manifests:
        for package, build, depot in depots:
            rows = manifests.execute(
                "SELECT depot_manifest_id,depot_manifest_md5,depot_manifest_compressed_size,"
                "depot_manifest_uncompressed_size,depot_manifest_encryption,depot_manifest_compression "
                "FROM depot_manifest WHERE package_id=? AND build_id=? AND depot_id=?",
                (package, build, depot),
            ).fetchall()
            if len(rows) != 1:
                raise ValueError("ambiguous-depot-manifest")
            name, md5, compressed_size, size, encryption, compression = rows[0]
            if Path(name).name != name or encryption != 0 or compression != 1 or not 0 < size <= 128 * 1024 * 1024:
                raise ValueError("unsupported-cached-manifest")
            cached = sophon / "manifest" / name
            if cached.is_symlink() or cached.stat().st_size != compressed_size:
                raise ValueError("invalid-cached-manifest-size")
            data = cached.read_bytes()
            decoded = zstandard.ZstdDecompressor().decompress(data, max_output_size=size)
            if len(decoded) != size:
                raise ValueError("decoded-size-mismatch")
            # HYP records the checksum of the uncompressed protobuf, not its zstd envelope.
            if hashlib.md5(decoded).hexdigest() != md5.lower():
                raise ValueError("cached-manifest-checksum-mismatch")
            manifest = manifest_pb2.Manifest()
            manifest.ParseFromString(decoded)
            for file in manifest.files:
                if file.flags == 64:
                    continue
                if file.flags != 0 or file.size < 0:
                    raise ValueError("unsupported-file-entry")
                entry = {"remoteName": file.filename, "md5": file.md5, "fileSize": file.size}
                if file.filename in files and files[file.filename] != entry:
                    raise ValueError("conflicting-file-entry")
                files[file.filename] = entry
    for entry in files.values():
        print(json.dumps(entry, ensure_ascii=False))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("sophon", type=Path)
    parser.add_argument("game", type=Path)
    args = parser.parse_args()
    export(args.sophon.resolve(strict=True), args.game)
