#!/usr/bin/env python3
"""Local version operations. No Git mutations or installed-app changes."""
import argparse
from datetime import datetime
from pathlib import Path
import os
import plistlib
import re
import sys
import tempfile
from zoneinfo import ZoneInfo

ROOT = Path(__file__).resolve().parent.parent
PLIST = Path("touchmiddle/Tools/Info.plist")
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
MARKERS = {
    Path("README.md"): rf"(?m)^目前原始碼版本：`({VERSION})`；build：`([1-9][0-9]*)`。$",
    Path("touchmiddle/README.txt"): rf"\ATouchMiddle ({VERSION}) —",
    Path("CHANGELOG.md"): rf"(?m)^## v({VERSION})（",
}


def source(root):
    data = plistlib.loads((root / PLIST).read_bytes())
    version = data.get("CFBundleShortVersionString")
    build = data.get("CFBundleVersion")
    if not isinstance(version, str) or not re.fullmatch(VERSION, version):
        raise ValueError("Info.plist App 版本必須為無前導零的 X.Y.Z")
    if not isinstance(build, str) or not re.fullmatch(r"[1-9][0-9]*", build):
        raise ValueError("Info.plist build 必須為正整數字串")
    return data, version, build


def check(root, app=None):
    _, version, build = source(root)
    texts = {}
    for path, pattern in MARKERS.items():
        text = (root / path).read_text(encoding="utf-8")
        matches = list(re.finditer(pattern, text))
        if not matches or (path.name != "CHANGELOG.md" and len(matches) != 1):
            raise ValueError(f"{path} 缺少或重複版本標記")
        match = matches[0]
        if match[1] != version:
            raise ValueError(f"{path} 版本 {match[1]} 與來源 {version} 不一致")
        if path.name == "README.md" and match[2] != build:
            raise ValueError(f"README.md build {match[2]} 與來源 {build} 不一致")
        if path.name == "CHANGELOG.md":
            end = matches[1].start() if len(matches) > 1 else len(text)
            builds = re.findall(r"(?m)^- Build：([1-9][0-9]*)$", text[match.start():end])
            if builds != [build]:
                raise ValueError(f"CHANGELOG.md 最新 build 與來源 {build} 不一致")
        texts[path] = (text, match)
    if app is not None:
        bundle = plistlib.loads((app / "Contents/Info.plist").read_bytes())
        for key, expected in (("CFBundleShortVersionString", version), ("CFBundleVersion", build)):
            if bundle.get(key) != expected:
                raise ValueError(f"App bundle {key}={bundle.get(key)!r} 與來源 {expected} 不一致")
    return version, build, texts


def replace_group(text, match, group, value):
    return text[:match.start(group)] + value + text[match.end(group):]


def bump(root, kind, summary, dry_run=False):
    version, build, texts = check(root)
    if not summary.strip() or any(c in summary for c in "\r\n"):
        raise ValueError("摘要必須為非空的單行文字")
    parts = list(map(int, version.split(".")))
    index = {"major": 0, "minor": 1, "patch": 2}[kind]
    parts[index] += 1
    parts[index + 1:] = [0] * (2 - index)
    new_version = ".".join(map(str, parts))
    new_build = str(int(build) + 1)
    updates = {}
    # Preserve plist formatting and unrelated fields; do not reserialize it.
    plist_text = (root / PLIST).read_text(encoding="utf-8")
    for key, old, new in (("CFBundleShortVersionString", version, new_version),
                          ("CFBundleVersion", build, new_build)):
        pattern = rf"(<key>{key}</key>\s*<string>){re.escape(old)}(</string>)"
        plist_text, count = re.subn(pattern, lambda m: m[1] + new + m[2], plist_text)
        if count != 1:
            raise ValueError(f"Info.plist {key} 無法唯一更新")
    updates[PLIST] = plist_text
    for path, (text, match) in texts.items():
        if path.name == "CHANGELOG.md":
            date = datetime.now(ZoneInfo("Asia/Taipei")).date().isoformat()
            entry = (f"## v{new_version}（{date}）\n\n> {summary}\n\n"
                     f"- Build：{new_build}\n- 驗證結果：待補。\n- 未驗證事項：待補。\n\n")
            # Keep every historical release, including beta entries, below
            # the new current version rather than inserting after a beta.
            first_release = re.search(r"(?m)^## v", text).start()
            updates[path] = text[:first_release] + entry + text[first_release:]
        else:
            # Replace from the right so original match offsets remain valid.
            if path.name == "README.md":
                text = replace_group(text, match, 2, new_build)
            updates[path] = replace_group(text, match, 1, new_version)
    print(f"{version} / build {build} → {new_version} / build {new_build}")
    if dry_run:
        print("dry-run：未改檔")
        return
    # Stage all files first. Each replacement is atomic; this is not a
    # multi-file filesystem transaction. Errors remain visible to the caller.
    staged = []
    try:
        for path, text in updates.items():
            target = root / path
            with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as temp:
                staged.append((Path(temp.name), target))
                temp.write(text.encode("utf-8"))
            os.chmod(temp.name, target.stat().st_mode & 0o777)
        for temp, target in staged:
            os.replace(temp, target)
        check(root)
    finally:
        for temp, _ in staged:
            temp.unlink(missing_ok=True)
    print("版本已同步；未 commit、tag、push 或安裝 App")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("current")
    checker = sub.add_parser("check")
    checker.add_argument("--app", type=Path, help="核對指定 App bundle")
    bumper = sub.add_parser("bump")
    bumper.add_argument("kind", choices=("major", "minor", "patch"))
    bumper.add_argument("summary")
    bumper.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        if args.command == "current":
            _, version, build = source(ROOT)
            print(f"{version} / build {build}")
        elif args.command == "check":
            version, build, _ = check(ROOT, args.app)
            print(f"版本一致：{version} / build {build}")
        else:
            bump(ROOT, args.kind, args.summary, args.dry_run)
    except (OSError, ValueError, plistlib.InvalidFileException) as error:
        print(f"版本操作失敗：{error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
