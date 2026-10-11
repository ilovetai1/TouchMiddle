#!/usr/bin/env python3
"""Verify that different builds satisfy each other's real code requirements.

This checks signature continuity; it does not grant or prove TCC permissions.
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


def run(*args: str) -> str:
    result = subprocess.run(args, capture_output=True, text=True, check=False)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout + result.stderr


def inspect(path: Path) -> dict[str, str]:
    run("codesign", "--verify", "--strict", str(path))
    description = run("codesign", "--display", "--verbose=4", "-r-", str(path))
    requirement = re.search(r"^(?:# )?designated => (.+)$", description, re.MULTILINE)
    code_hash = re.search(r"^CDHash=(.+)$", description, re.MULTILINE)
    if not requirement or not code_hash:
        raise RuntimeError(f"Missing signature fields: {path}")
    return {"path": str(path), "requirement": requirement[1], "cdhash": code_hash[1]}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("first", type=Path)
    parser.add_argument("second", type=Path)
    parser.add_argument("--require-code-change", action="store_true")
    args = parser.parse_args()
    first, second = inspect(args.first.resolve()), inspect(args.second.resolve())
    if any("cdhash" in build["requirement"] for build in (first, second)):
        raise RuntimeError("Ad-hoc requirement is tied to one code hash; cannot retain identity across code changes")
    if args.require_code_change and first["cdhash"] == second["cdhash"]:
        raise RuntimeError("Code hashes are identical; this does not exercise a changed build")
    for origin, target in ((first, second), (second, first)):
        run("codesign", "--verify", "--strict", "-R", "=" + origin["requirement"], target["path"])
    print(json.dumps({"signatureContinuity": "PASS", "differentCodeHashes": first["cdhash"] != second["cdhash"],
                      "builds": [first, second], "tccPermission": "not_checked"}, indent=2))


if __name__ == "__main__":
    try:
        main()
    except RuntimeError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        sys.exit(1)
