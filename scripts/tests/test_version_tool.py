"""Exercise CLI against disposable repositories, never the live source files."""
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
FILES = ("scripts/version_tool.py", "scripts/bump_version.sh",
         "scripts/check_version_consistency.sh", "touchmiddle/Tools/Info.plist",
         "README.md", "touchmiddle/README.txt", "CHANGELOG.md")


class VersionToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name in FILES:
            target = self.root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
        self.plist = self.root / "touchmiddle/Tools/Info.plist"
        self.original = plistlib.loads(self.plist.read_bytes())

    def run_cli(self, script, *args):
        return subprocess.run(["bash", str(self.root / "scripts" / script), *args],
                              cwd="/tmp", capture_output=True, text=True)

    def snapshot(self):
        return {name: (self.root / name).read_bytes() for name in FILES}

    def test_bump_algorithms_and_history(self):
        parts = list(map(int, self.original["CFBundleShortVersionString"].split(".")))
        for kind, index in (("patch", 2), ("minor", 1), ("major", 0)):
            with self.subTest(kind=kind):
                before = self.snapshot()
                old_log = (self.root / "CHANGELOG.md").read_text()
                result = self.run_cli("bump_version.sh", kind, "測試摘要")
                self.assertEqual(result.returncode, 0, result.stderr)
                data = plistlib.loads(self.plist.read_bytes())
                expected = parts.copy()
                expected[index] += 1
                expected[index + 1:] = [0] * (2 - index)
                self.assertEqual(data["CFBundleShortVersionString"], ".".join(map(str, expected)))
                self.assertEqual(data["CFBundleVersion"], str(int(self.original["CFBundleVersion"]) + 1))
                self.assertEqual(data["CFBundleIdentifier"], self.original["CFBundleIdentifier"])
                self.assertTrue((self.root / "CHANGELOG.md").read_text().endswith(old_log[old_log.index("## v"):]))
                self.assertEqual(self.run_cli("check_version_consistency.sh").returncode, 0)
                for name, content in before.items():
                    (self.root / name).write_bytes(content)

    def test_dry_run_does_not_write(self):
        before = self.snapshot()
        self.assertEqual(self.run_cli("bump_version.sh", "minor", "摘要", "--dry-run").returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_drift_blocks_check_and_bump_without_writes(self):
        for name in ("README.md", "touchmiddle/README.txt", "CHANGELOG.md"):
            with self.subTest(path=name):
                path = self.root / name
                original = path.read_text()
                if name == "README.md":
                    changed = original.replace(f'目前原始碼版本：`{self.original["CFBundleShortVersionString"]}`',
                                               '目前原始碼版本：`99.99.99`', 1)
                elif name == "CHANGELOG.md":
                    changed = original.replace(
                        f'## v{self.original["CFBundleShortVersionString"]}（',
                        '## v99.99.99（', 1)
                else:
                    changed = original.replace(self.original["CFBundleShortVersionString"], "99.99.99", 1)
                path.write_text(changed)
                before = self.snapshot()
                self.assertNotEqual(self.run_cli("check_version_consistency.sh").returncode, 0)
                self.assertNotEqual(self.run_cli("bump_version.sh", "patch", "摘要").returncode, 0)
                self.assertEqual(before, self.snapshot())
                path.write_text(original)

    def test_invalid_source_is_rejected(self):
        for key, value in (("CFBundleShortVersionString", "01.2.3"),
                           ("CFBundleShortVersionString", "0.2.1-beta.1"),
                           ("CFBundleVersion", "0")):
            data = self.original.copy()
            data[key] = value
            self.plist.write_bytes(plistlib.dumps(data))
            self.assertNotEqual(self.run_cli("check_version_consistency.sh").returncode, 0)

    def test_bundle_version_and_build_are_checked(self):
        app = self.root / "Sample.app"
        (app / "Contents").mkdir(parents=True)
        target = app / "Contents/Info.plist"
        target.write_bytes(plistlib.dumps(self.original))
        self.assertEqual(self.run_cli("check_version_consistency.sh", "--app", str(app)).returncode, 0)
        for key, value in (("CFBundleShortVersionString", "99.0.0"), ("CFBundleVersion", "999")):
            data = self.original.copy()
            data[key] = value
            target.write_bytes(plistlib.dumps(data))
            self.assertNotEqual(self.run_cli("check_version_consistency.sh", "--app", str(app)).returncode, 0)
        data = self.original.copy()
        data["TMPrereleaseIdentifier"] = "beta.999"
        target.write_bytes(plistlib.dumps(data))
        self.assertNotEqual(self.run_cli("check_version_consistency.sh", "--app", str(app)).returncode, 0)

    def test_prerelease_identifier_is_validated(self):
        for value in ("", "beta.01", "beta..1", "beta.1+build", 1):
            data = self.original.copy()
            data["TMPrereleaseIdentifier"] = value
            self.plist.write_bytes(plistlib.dumps(data))
            self.assertNotEqual(self.run_cli("check_version_consistency.sh").returncode, 0)
        for value in ("beta.1", "beta.10", "rc.1", "0", "1a"):
            data = self.original.copy()
            data["TMPrereleaseIdentifier"] = value
            self.plist.write_bytes(plistlib.dumps(data))
            self.assertEqual(self.run_cli("check_version_consistency.sh").returncode, 0)

    def test_invalid_arguments_do_not_write(self):
        before = self.snapshot()
        for args in (("patch", ""), ("patch", "摘要\n多行"), ("unknown", "摘要"), ("patch",)):
            self.assertNotEqual(self.run_cli("bump_version.sh", *args).returncode, 0)
        self.assertEqual(before, self.snapshot())

    def test_missing_marker_and_build_drift(self):
        path = self.root / "README.md"
        original = path.read_text()
        for text in (original.replace("目前原始碼版本：", "缺少標記："),
                     original.replace(f'build：`{self.original["CFBundleVersion"]}`', 'build：`999`')):
            path.write_text(text)
            self.assertNotEqual(self.run_cli("check_version_consistency.sh").returncode, 0)

    def test_changelog_build_drift(self):
        path = self.root / "CHANGELOG.md"
        path.write_text(path.read_text().replace(f'- Build：{self.original["CFBundleVersion"]}', '- Build：999', 1))
        self.assertNotEqual(self.run_cli("check_version_consistency.sh").returncode, 0)


if __name__ == "__main__":
    unittest.main()
