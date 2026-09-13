#!/usr/bin/env python3
"""Pinned YAAGL full-install wrapper for the first controlled CN game download."""

from __future__ import annotations

import argparse
import atexit
import concurrent.futures
import fcntl
import hashlib
import os
from pathlib import Path, PurePosixPath
import signal
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import urlsplit


EXPECTED_COMMIT = "ca78abc29c2fc236261d088c6907d28cab6e9476"
EXPECTED_MANIFEST_PREFIX_SHA256 = (
    "ea1f952ad03a4218f39f3c89567aac56d03b1bd88252f116f1781249cd7b0485"
)
EXPECTED_CHUNK_PREFIX_SHA256 = (
    "50e6250f134337b5da80c513ad8cd1c5afc92f58bdeb280dc65863827071d2eb"
)
EXPECTED_CDN_HOST = "autopatchcn.yuanshen.com"
DEFAULT_TARGET = Path.home() / "Games" / "MacGameBridge" / "Genshin Impact"
MINIMUM_FREE_BYTES = 20_000_000_000
MARKER_NAME = ".mgb-managed-cn-download"
EXPECTED_BUNDLED_UPSTREAM_FILES = {
    "sophon_server/sophon_api.py": (
        48_809,
        "ff341725bee502008dbc9d12d9c3f69c61f9291331f5a349361a91951b075f42",
    ),
    "sophon_server/manifest_pb2.py": (
        1_934,
        "06e5dc449d5fa6bbef1159533e1321e3e6fdccd9716c1cd9cc7a28d6d137c7b5",
    ),
    "sophon_server/manifest_ldiff_pb2.py": (
        2_977,
        "29a23dc5b84ac4f0114217c4255bede52edcfe098bd08d9f0dc10c3c34c56a9c",
    ),
    "hpatchz/hpatchz": (
        501_680,
        "b7caf045b1fd02c2333d1206215b2331c23961df2236cea33c06a4c811344bea",
    ),
}


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def write_marker(marker: Path, contents: str) -> None:
    # Never truncate the previous state: a crash must leave either the old marker
    # or the complete new one, not an empty file that looks like an imported game.
    descriptor, temporary = tempfile.mkstemp(prefix=".mgb-marker-", dir=marker.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, marker)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def acquire_download_lock(cache: Path, inherited_fd: int | None = None):
    lock_path = cache / ".download.lock"
    if inherited_fd is not None:
        handle = os.fdopen(os.dup(inherited_fd), "r+b")
    else:
        handle = lock_path.open("a+b")
    try:
        inherited = os.fstat(handle.fileno())
        expected = lock_path.stat()
        if (inherited.st_dev, inherited.st_ino) != (expected.st_dev, expected.st_ino):
            raise RuntimeError("invalid-inherited-download-lock")
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError as error:
        handle.close()
        raise RuntimeError("download-already-running") from error
    except Exception:
        handle.close()
        raise
    return handle


def md5_file(path: Path) -> str:
    digest = hashlib.md5(usedforsecurity=False)
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while block := handle.read(1024 * 1024):
            digest.update(block)
    return digest.hexdigest()


def validate_prefix(raw: str, expected_path_sha256: str) -> None:
    parsed = urlsplit(raw)
    if (
        parsed.scheme != "https"
        or parsed.hostname != EXPECTED_CDN_HOST
        or parsed.port is not None
        or parsed.username is not None
        or parsed.password is not None
        or parsed.query
        or parsed.fragment
        or not parsed.path.startswith("/")
        or sha256_bytes(parsed.path.encode("utf-8")) != expected_path_sha256
    ):
        raise RuntimeError("download-prefix-rejected")


def validate_relative_path(raw: str) -> None:
    path = PurePosixPath(raw)
    if (
        not raw
        or path.is_absolute()
        or "\\" in raw
        or ":" in raw
        or any(part in ("", ".", "..") for part in path.parts)
        or any(ord(character) < 32 for character in raw)
    ):
        raise RuntimeError("manifest-path-rejected")


def ensure_private_directory(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    if path.is_symlink() or not path.is_dir():
        raise RuntimeError("unsafe-directory")
    os.chmod(path, 0o700)


def verify_upstream(root: Path) -> None:
    bundle_marker = root / ".mgb-pinned-upstream"
    if bundle_marker.is_file():
        if bundle_marker.read_text(encoding="utf-8") != f"revision={EXPECTED_COMMIT}\n":
            raise RuntimeError("upstream-marker-mismatch")
        for relative_path, (expected_size, expected_sha256) in (
            EXPECTED_BUNDLED_UPSTREAM_FILES.items()
        ):
            path = root / relative_path
            if (
                not path.is_file()
                or path.stat().st_size != expected_size
                or sha256_file(path) != expected_sha256
            ):
                raise RuntimeError("bundled-upstream-mismatch")
        return

    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    if result.stdout.strip() != EXPECTED_COMMIT:
        raise RuntimeError("upstream-commit-mismatch")
    subprocess.run(
        ["git", "-C", str(root), "diff", "--quiet", "--", "sophon_server/sophon_api.py"],
        check=True,
    )


class Progress:
    def __init__(self, total_bytes: int, completed_bytes: int) -> None:
        self.total_bytes = total_bytes
        self.completed_bytes = completed_bytes
        self.initial_completed_bytes = completed_bytes
        self.started_at = time.monotonic()
        self.last_print = 0.0
        self.lock = threading.Lock()

    def file_download_start(self, filename: str) -> None:
        del filename

    def file_download_skipped(self, filename: str, reason: str) -> None:
        del filename, reason

    def file_download_complete(self, filename: str, file_size: int) -> None:
        del filename, file_size

    def file_download_error(self, filename: str, error: str = "") -> None:
        del filename, error

    def chunk_download_progress(
        self,
        filename: str,
        total_chunks: int,
        current_chunk: object,
        progress_percent: float,
        current_byte: int,
        total_bytes: int,
        chunk_size: int,
    ) -> None:
        del filename, total_chunks, current_chunk, progress_percent, current_byte, total_bytes
        with self.lock:
            self.completed_bytes += chunk_size
            now = time.monotonic()
            if now - self.last_print < 1.0:
                return
            self.last_print = now
            elapsed = max(now - self.started_at, 0.001)
            speed = max((self.completed_bytes - self.initial_completed_bytes) / elapsed, 0.0)
            remaining = max(self.total_bytes - self.completed_bytes, 0)
            eta = int(remaining / speed) if speed > 0 else -1
            percent = (
                self.completed_bytes * 100.0 / self.total_bytes if self.total_bytes else 100.0
            )
            print(
                f"PROGRESS percent={percent:.3f} "
                f"downloaded={self.completed_bytes} total={self.total_bytes} "
                f"bytes_per_second={int(speed)} eta_seconds={eta}",
                flush=True,
            )


def scrub_api_cache(cache: Path) -> None:
    for name in ("getGameBranches.json", "getBuild.json"):
        path = cache / name
        try:
            path.unlink()
        except FileNotFoundError:
            pass


def run(args: argparse.Namespace) -> None:
    upstream = Path(os.environ.get("MGB_YAAGL_ROOT", "")).expanduser().resolve()
    if not upstream.is_dir():
        raise RuntimeError("missing-pinned-upstream")
    verify_upstream(upstream)
    server_root = upstream / "sophon_server"
    sys.path.insert(0, str(server_root))

    import sophon_api  # type: ignore[import-not-found]

    sophon_api.RUN_MEMORY_HACK = False
    sophon_api.EXPORT_JSON_FILES = False
    sophon_api.WORKER_CNT = args.workers
    sophon_api.debuglog = lambda *args, **kwargs: None

    if args.check_version_only:
        with tempfile.TemporaryDirectory(prefix="mgb-version-check-") as temporary:
            temporary_root = Path(temporary)
            check_options = sophon_api.Options()
            check_options.gamedir = temporary_root / "game"
            check_options.tempdir = temporary_root / "cache"
            check_options.do_install = True
            check_options.install_reltype = "cn"
            check_options.game_type = "hk4e"
            check_options.ignore_conditions = False
            check_options.predownload = False
            check_options.dry_run = False
            check_options.disallow_download = False
            check_client = sophon_api.SophonClient()
            check_client.initialize(check_options)
            check_client.retrieve_API_keys()
            print(f"AVAILABLE version={check_client.branches_json['tag']}", flush=True)
        return

    target = args.target.expanduser().resolve()
    cache = target.parent / ".MacGameBridge-Genshin-CN-download-cache"
    ensure_private_directory(target.parent)
    marker = target / MARKER_NAME
    if target.exists() and any(target.iterdir()) and not marker.is_file():
        raise RuntimeError("nonempty-target-not-owned-by-macgamebridge")
    is_resume = marker.is_file()
    ensure_private_directory(target)
    ensure_private_directory(cache)
    atexit.register(scrub_api_cache, cache)

    lock_handle = acquire_download_lock(
        cache, sys.stdin.fileno() if args.operation_lock_stdin else None
    )

    stop_event = threading.Event()

    def request_stop(signum: int, frame: object) -> None:
        del signum, frame
        stop_event.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)

    options = sophon_api.Options()
    options.gamedir = target
    options.tempdir = cache
    options.do_install = True
    options.install_reltype = "cn"
    options.game_type = "hk4e"
    options.ignore_conditions = is_resume
    options.predownload = False
    options.dry_run = False
    options.disallow_download = False

    client = sophon_api.SophonClient()
    client.initialize(options)
    try:
        client.retrieve_API_keys()
        available_version = client.branches_json["tag"]
        print(f"AVAILABLE version={available_version}", flush=True)
        client.di_chunks.getBuild_json = client.get_getBuild_json(True)
        manifests = client.di_chunks.getBuild_json["data"]["manifests"]
        selected = [item for item in manifests if item.get("matching_field") == "game"]
        if len(selected) != 1:
            raise RuntimeError("game-category-ambiguous")
        category = selected[0]
        validate_prefix(
            category["manifest_download"]["url_prefix"],
            EXPECTED_MANIFEST_PREFIX_SHA256,
        )
        validate_prefix(
            category["chunk_download"]["url_prefix"],
            EXPECTED_CHUNK_PREFIX_SHA256,
        )
        client._select_category(client.di_chunks, "game")
    finally:
        scrub_api_cache(cache)

    write_marker(marker, "schema=1\nstate=downloading\n")

    files = list(client.di_chunks.manifest.files)
    for file_info in files:
        validate_relative_path(file_info.filename.rstrip("/"))

    total_download = sum(chunk.compressed_size for item in files for chunk in item.chunks)
    total_installed = sum(item.size for item in files if item.flags == 0)
    stat = os.statvfs(target)
    available = stat.f_bavail * stat.f_frsize
    required = total_installed + MINIMUM_FREE_BYTES
    if available < required:
        raise RuntimeError(
            f"insufficient-capacity required={required} available={available}"
        )

    completed_download = 0
    pending = []
    for item in files:
        if item.flags == 64:
            continue
        destination = target / item.filename
        if destination.is_file() and destination.stat().st_size == item.size:
            if md5_file(destination) == item.md5:
                completed_download += sum(chunk.compressed_size for chunk in item.chunks)
                continue
            destination.unlink()
        pending.append(item)

    print(
        f"SUMMARY files={len(files)} pending_files={len(pending)} "
        f"download_bytes={total_download} installed_bytes={total_installed} "
        f"available_bytes={available} target={target}",
        flush=True,
    )
    if args.preflight_only:
        return

    progress = Progress(total_download, completed_download)
    basename_locks: dict[str, threading.Lock] = {}
    basename_locks_guard = threading.Lock()

    def download_file(file_info: object) -> None:
        if stop_event.is_set():
            raise RuntimeError("cancelled")
        basename = Path(file_info.filename).name
        with basename_locks_guard:
            file_lock = basename_locks.setdefault(basename, threading.Lock())
        with file_lock:
            last_error: Exception | None = None
            for _ in range(5):
                try:
                    if stop_event.is_set():
                        raise RuntimeError("cancelled")
                    client.download_game_file(
                        file_info,
                        install_progress_handler=progress,
                        cancel_event=stop_event,
                    )
                    return
                except Exception as error:  # noqa: BLE001
                    last_error = error
                    time.sleep(1)
            raise RuntimeError("file-download-failed") from last_error

    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as executor:
        futures = [executor.submit(download_file, item) for item in pending]
        for future in concurrent.futures.as_completed(futures):
            future.result()

    if stop_event.is_set():
        raise RuntimeError("cancelled")
    client.update_config_ini_version()
    write_marker(
        marker,
        "schema=1\nstate=complete\n"
        f"version={client.installed_ver}\n"
        f"files={len(files)}\n"
        f"installed_bytes={total_installed}\n",
    )
    print(f"COMPLETE target={target} version={client.installed_ver}", flush=True)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=Path, default=DEFAULT_TARGET)
    parser.add_argument("--workers", type=int, default=4, choices=range(1, 9))
    parser.add_argument("--preflight-only", action="store_true")
    parser.add_argument("--check-version-only", action="store_true")
    parser.add_argument("--operation-lock-stdin", action="store_true", help=argparse.SUPPRESS)
    return parser.parse_args()


if __name__ == "__main__":
    try:
        run(parse_args())
    except Exception as error:  # noqa: BLE001
        print(f"FAILED code={error}", file=sys.stderr, flush=True)
        raise SystemExit(1) from None
