#!/bin/bash
set -euo pipefail

# Local candidate only: no publishing, signing identity, or notarization.
if [[ $# != 2 || "$1" != --output || "$2" != /* ]]; then
    printf 'Usage: bash package-beta.sh --output /absolute/new/directory\n' >&2
    exit 2
fi
output="$2"
if [[ -e "$output" || -L "$output" ]]; then
    printf 'Refusing existing output: %s\n' "$output" >&2
    exit 3
fi
if [[ "$(uname -m)" != arm64 ]]; then
    printf 'This beta packaging script requires an Apple Silicon Mac.\n' >&2
    exit 4
fi
tools_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
repo_dir="$(cd -- "$tools_dir/../.." && pwd -P)"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$tools_dir/Info.plist")"
if [[ "$version" != 0.2.1 ]]; then
    printf 'Expected app version 0.2.1; update beta metadata before packaging.\n' >&2
    exit 5
fi
name=TouchMiddle-0.2.1-beta.1-macos-arm64
scratch="$(mktemp -d /tmp/touchmiddle-beta.XXXXXX)"
cleanup() {
    case "$scratch" in
        /tmp/touchmiddle-beta.*) rm -rf -- "$scratch" ;;
        *) printf 'Unexpected scratch path; refusing cleanup.\n' >&2 ;;
    esac
}
trap cleanup EXIT
mkdir "$scratch/$name"
bash "$tools_dir/build-app.sh" --ad-hoc --output "$scratch/$name/TouchMiddle.app"
archs="$(lipo -archs "$scratch/$name/TouchMiddle.app/Contents/MacOS/TouchMiddle")"
if [[ "$archs" != arm64 ]]; then
    printf 'Unexpected executable architecture: %s\n' "$archs" >&2
    exit 6
fi
cp "$repo_dir/LICENSE" "$scratch/$name/LICENSE"
cp "$repo_dir/docs/INSTALL.md" "$scratch/$name/INSTALL.md"
cp "$repo_dir/docs/SIGNING.md" "$scratch/$name/SIGNING.md"
cp "$repo_dir/touchmiddle/README.txt" "$scratch/$name/OPERATION.txt"
cp "$repo_dir/docs/RELEASE-0.2.1-beta.1.md" "$scratch/$name/RELEASE-NOTES.md"
ditto -c -k --norsrc --keepParent "$scratch/$name" "$scratch/$name.zip"
(
    cd "$scratch"
    shasum -a 256 "$name.zip" > SHA256SUMS.txt
)
mkdir -p -- "$(dirname -- "$output")"
mkdir -- "$output"
cp "$scratch/$name.zip" "$scratch/SHA256SUMS.txt" "$output/"
printf 'Packaged local candidate: %s/%s.zip\n' "$output" "$name"
