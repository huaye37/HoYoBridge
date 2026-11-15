#!/usr/bin/env bash
set -euo pipefail
# Never publishes anything. Use a dedicated directory containing signed release ZIPs.
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="${1:?Usage: bash script/prepare_appcast.sh RELEASE_DIRECTORY HTTPS_DOWNLOAD_PREFIX}"
DOWNLOAD_PREFIX="${2:?Provide an immutable HTTPS release download prefix}"
[[ -d "$RELEASE_DIR" && "$DOWNLOAD_PREFIX" == https://* ]] || exit 2
# Match notes to the actual archive version, not the caller's directory name.
python3 - "$ROOT_DIR" "$RELEASE_DIR" <<'PY'
import pathlib
import plistlib
import re
import shutil
import sys
import zipfile

root, release = map(pathlib.Path, sys.argv[1:])
archives = sorted(release.glob("*.zip"))
if not archives:
    sys.exit("发布目录没有 ZIP 文件。")
notes_to_copy = []
for archive in archives:
    with zipfile.ZipFile(archive) as package:
        candidates = [name for name in package.namelist()
                      if re.fullmatch(r"[^/]+\.app/Contents/Info\.plist", name)]
        if len(candidates) != 1:
            sys.exit(f"无法确定应用版本：{archive.name}")
        info = plistlib.loads(package.read(candidates[0]))
    version = info.get("CFBundleShortVersionString", "")
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){1,3}", version):
        sys.exit(f"无效的发布版本：{version!r}")
    notes = root / "docs" / "releases" / f"v{version}.md"
    if not notes.is_file():
        sys.exit(f"缺少中文发布日志：{notes}")
    content = notes.read_text(encoding="utf-8")
    title = content.splitlines()[0] if content.splitlines() else ""
    if (not re.search(rf"(?<![\d.]){re.escape(version)}(?![\d.])", title)
            or not re.search(r"[\u4e00-\u9fff]", content)
            or not re.search(r"^[-*] \S", content, re.M)):
        sys.exit(f"发布日志必须包含对应版本、中文说明和变更条目：{notes}")
    # HTML takes precedence in Sparkle; don't silently publish a stale sidecar.
    if archive.with_suffix(".html").exists() or archive.with_suffix(".txt").exists():
        sys.exit(f"请移走旧的 HTML/TXT 发布说明，仅从 {notes.name} 生成：{archive.name}")
    notes_to_copy.append((notes, archive.with_suffix(".md")))
for source, destination in notes_to_copy:
    shutil.copyfile(source, destination)
    print(f"附带中文发布日志：{source.name}")
PY
TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_appcast"
[[ -x "$TOOL" ]] || { echo 'Resolve Swift packages first.' >&2; exit 2; }
KEY_TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
SIGN_TOOL="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
EXPECTED_KEY="${MGB_SPARKLE_PUBLIC_KEY:-11DmpJkJzf0x4UdHl65GWxNMwMyu702GStGKU6p18Lw=}"
ACTUAL_KEY="$("$KEY_TOOL" --account hoyobridge-updates -p)"
[[ "$ACTUAL_KEY" == "$EXPECTED_KEY" ]] || { echo 'Sparkle signing key does not match the configured public key.' >&2; exit 1; }
"$TOOL" --account hoyobridge-updates --maximum-deltas 0 --embed-release-notes \
  --download-url-prefix "$DOWNLOAD_PREFIX" "$RELEASE_DIR"
"$SIGN_TOOL" --account hoyobridge-updates --verify "$RELEASE_DIR/appcast.xml"
python3 - "$ROOT_DIR" "$RELEASE_DIR/appcast.xml" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

root, feed = map(pathlib.Path, sys.argv[1:])
ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
items = ET.parse(feed).findall("./channel/item")
if not items:
    sys.exit("更新目录没有版本条目。")
for item in items:
    version = item.findtext("sparkle:shortVersionString", namespaces=ns)
    version = version or item.findtext("sparkle:version", namespaces=ns)
    notes = root / "docs" / "releases" / f"v{version}.md"
    description = item.find("description")
    if (not notes.is_file() or description is None
            or description.get(f"{{{ns['sparkle']}}}format") != "markdown"
            or (description.text or "").strip() != notes.read_text(encoding="utf-8").strip()):
        sys.exit(f"版本 {version} 的更新弹窗日志缺失或与中文源文件不一致，请重新生成。")
print("已验证更新弹窗日志与中文版本文件一致。")
PY
echo 'Appcast generated locally. Verify signatures and hosted download links before publishing.'
