#!/bin/bash
set -euo pipefail

# Builds a fresh bundle only. It never opens the app, changes login items,
# grants permissions, or replaces an existing destination.
# A configured local certificate keeps the signing identity across rebuilds.
# Neither local certificate signing nor ad-hoc signing is notarization.

usage() {
    cat <<'USAGE'
Usage: build-app.sh [--output /absolute/path/TouchMiddle.app]
                    [--signing-identity SHA1 | --ad-hoc]

Default destination: ~/Applications/TouchMiddle.app
The destination must not exist. SwiftPM build and package scratch use /tmp.
Uses TOUCHMIDDLE_SIGNING_IDENTITY or the current user's local Signing/identity.json.
Without local configuration, preserves the original ad-hoc build mode.
An unavailable configured identity is an error, never an ad-hoc fallback.
--ad-hoc explicitly selects a portable build without a local certificate.
The script builds release, packages, signs, and verifies the new app.
It does not launch the app or create a login item.
USAGE
}

output="${TOUCHMIDDLE_OUTPUT:-$HOME/Applications/TouchMiddle.app}"
signing_identity="${TOUCHMIDDLE_SIGNING_IDENTITY:-}"
signing_mode=auto
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)
            if [[ $# -lt 2 ]]; then usage >&2; exit 2; fi
            output="$2"
            shift 2
            ;;
        --signing-identity)
            if [[ $# -lt 2 || "$signing_mode" != auto ]]; then usage >&2; exit 2; fi
            signing_identity="$2"
            signing_mode=certificate
            shift 2
            ;;
        --ad-hoc)
            if [[ "$signing_mode" != auto ]]; then usage >&2; exit 2; fi
            signing_identity=-
            signing_mode=adhoc
            shift
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
for command in xcrun codesign plutil python3 security; do
    if ! command -v "$command" >/dev/null 2>&1; then
        printf 'Required command unavailable: %s\n' "$command" >&2
        exit 4
    fi
done

if [[ -z "$signing_identity" ]]; then
    signing_identity="$(python3 - <<'PY'
import json
from pathlib import Path
path = Path.home() / 'Library/Application Support/TouchMiddle/Signing/identity.json'
if path.is_symlink():
    raise SystemExit('Linked signing configuration is not allowed; refusing ad-hoc fallback')
try:
    content = path.read_text()
except FileNotFoundError:
    print('-')
else:
    identity = json.loads(content)['identitySHA1']
    if not isinstance(identity, str) or len(identity) != 40 or any(c not in '0123456789abcdefABCDEF' for c in identity):
        raise SystemExit('Invalid local signing identity; refusing ad-hoc fallback')
    print(identity.upper())
PY
)"
fi
if [[ "$signing_mode" == certificate && "$signing_identity" == - ]]; then
    printf 'Use --ad-hoc to request ad-hoc signing explicitly.\n' >&2
    exit 6
fi
if [[ "$signing_identity" != - ]]; then
    if [[ ! "$signing_identity" =~ ^[0-9A-Fa-f]{40}$ ]]; then
        printf 'Signing identity must be a certificate SHA-1 fingerprint.\n' >&2
        exit 6
    fi
    signing_identity="$(printf '%s' "$signing_identity" | tr '[:lower:]' '[:upper:]')"
    if ! security find-identity -p codesigning | python3 -c \
        'import sys; identity=sys.argv[1]; sys.exit(0 if identity in sys.stdin.read() else 1)' "$signing_identity"; then
        printf 'Configured signing identity unavailable; refusing ad-hoc fallback.\n' >&2
        exit 6
    fi
fi
printf 'Signing identity: %s\n' "$signing_identity"

python3 "$package_dir/../scripts/version_tool.py" check

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
cp "$package_dir/../LICENSE" "$staged_app/Contents/Resources/LICENSE"
printf 'APPL????' > "$staged_app/Contents/PkgInfo"
plutil -lint "$staged_app/Contents/Info.plist"
python3 "$package_dir/../scripts/version_tool.py" check --app "$staged_app"
codesign --force --sign "$signing_identity" --identifier com.chunghan.TouchMiddle --timestamp=none "$staged_app"
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
