"""Read-only, streaming check of a downloaded game's official pkg_version list."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import time


def verify(game: Path, executable: str, manifest: Path | None = None) -> dict:
    game = game.resolve(strict=True)
    manifest = manifest or game / "pkg_version"
    if not manifest.is_file() or manifest.is_symlink():
        raise ValueError("official-pkg-version-missing")
    failures = []
    count = 0
    total_bytes = 0
    seen = set()
    started = time.monotonic()
    with manifest.open(encoding="utf-8-sig") as source:
        while line := source.readline(1_048_577):
            if len(line) > 1_048_576:
                raise ValueError("oversized-manifest-entry")
            if not line.strip():
                continue
            item = json.loads(line)
            name = item["remoteName"].replace("\\", "/")
            relative = PurePosixPath(name)
            if relative.is_absolute() or ".." in relative.parts or ":" in name or name.casefold() in seen:
                raise ValueError("unsafe-or-duplicate-manifest-path")
            if not re.fullmatch(r"[0-9a-fA-F]{32}", item["md5"]):
                raise ValueError("invalid-manifest-md5")
            seen.add(name.casefold())
            count += 1
            file = game.joinpath(*relative.parts)
            expected_size = int(item["fileSize"])
            cursor = file
            while cursor != game:
                if cursor.is_symlink():
                    raise ValueError("symlink-in-game-path")
                cursor = cursor.parent
            if not file.is_file() or file.stat().st_size != expected_size:
                failures.append({"path": name, "reason": "missing-or-wrong-size"})
                continue
            digest = hashlib.md5(usedforsecurity=False)
            with file.open("rb") as handle:
                while block := handle.read(4 * 1024 * 1024):
                    digest.update(block)
                    total_bytes += len(block)
            if digest.hexdigest() != item["md5"].lower():
                failures.append({"path": name, "reason": "md5-mismatch"})
    if count == 0 or executable.casefold() not in seen:
        raise ValueError("manifest-does-not-cover-game-executable")
    return {
        "gameDirectory": str(game), "manifestFiles": count, "verifiedReadBytes": total_bytes,
        "failedFiles": len(failures), "examples": failures[:20],
        "elapsedSeconds": round(time.monotonic() - started, 2), "complete": not failures,
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("game", type=Path)
    parser.add_argument("--executable", required=True)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    result = verify(args.game, args.executable, args.manifest)
    print(json.dumps(result, ensure_ascii=False), flush=True)
    raise SystemExit(0 if result["complete"] else 1)
