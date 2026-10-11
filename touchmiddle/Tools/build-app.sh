#!/bin/bash
set -euo pipefail

# Builds a fresh bundle only. It never opens the app, changes login items,
# grants permissions, or replaces an existing destination.
# Ad-hoc signing is local signing; it is not notarization or a promise that
# Accessibility authorization survives future changes to the executable.

usage() {
    cat <<'USAGE'
Usage: build-app.sh [--output /absolute/path/TouchMiddle.app]

Default destination: ~/Applications/TouchMiddle.app
The destination must not exist. SwiftPM build and package scratch use /tmp.
The script builds release, packages, signs ad-hoc, and verifies the new app.
It does not launch the app or create a login item.
USAGE
}

output="${TOUCHMIDDLE_OUTPUT:-$HOME/Applications/TouchMiddle.app}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi
            output="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown argument: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ "$output" != /* || "$output" != *.app ]]; then
    printf 'Output must be an absolute path ending in .app: %s\n' "$output" >&2
    exit 2
fi
if [[ -e "$output" || -L "$output" ]]; then
    printf 'Refusing to replace existing output: %s\n' "$output" >&2
    exit 3
fi

tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
package_dir="$(cd -- "$tools_dir/.." && pwd -P)"
for command in xcrun codesign plutil python3; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command unavailable: %s\n' "$command" >&2
        exit 4
    fi
done

scratch="$(mktemp -d /tmp/touchmiddle-build.XXXXXX)"
cleanup() {
    case "$scratch" in
        /tmp/touchmiddle-build.*) rm -rf -- "$scratch" ;;
        *) printf 'Refusing unexpected scratch cleanup path: %s\n' "$scratch" >&2 ;;
    esac
}
trap cleanup EXIT

xcrun swift build --package-path "$package_dir" --scratch-path "$scratch/swiftpm" \
    --configuration release --product TouchMiddle
binary_dir="$(xcrun swift build --package-path "$package_dir" \
    --scratch-path "$scratch/swiftpm" --configuration release --show-bin-path)"
if [[ ! -x "$binary_dir/TouchMiddle" ]]; then
    printf 'Release executable unavailable: %s\n' "$binary_dir/TouchMiddle" >&2
    exit 5
fi

staged_app="$scratch/TouchMiddle.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/TouchMiddle" "$staged_app/Contents/MacOS/TouchMiddle"
cp "$tools_dir/Info.plist" "$staged_app/Contents/Info.plist"
printf 'APPL????' > "$staged_app/Contents/PkgInfo"
plutil -lint "$staged_app/Contents/Info.plist"
codesign --force --sign - --identifier com.chunghan.TouchMiddle --timestamp=none "$staged_app"
codesign --verify --strict --verbose=2 "$staged_app"

# copytree creates the destination directory exclusively and refuses existing
# files/directories/symlinks, including a destination that appeared mid-build.
python3 - "$staged_app" "$output" <<'PY'
import os
import shutil
import sys

source, destination = sys.argv[1:]
if os.path.lexists(destination):
    raise SystemExit(f"Refusing to replace existing output: {destination}")
os.makedirs(os.path.dirname(destination), exist_ok=True)
try:
    shutil.copytree(source, destination, symlinks=True)
except FileExistsError:
    raise SystemExit(f"Refusing to replace existing output: {destination}")
except OSError as error:
    raise SystemExit(f"Packaging failed; output may be incomplete at {destination}: {error}")
PY

codesign --verify --strict --verbose=2 "$output"
printf 'Built and verified: %s\n' "$output"
codesign -d --verbose=2 --requirements - "$output" 2>&1
