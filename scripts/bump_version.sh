#!/bin/bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
if [[ "${1:-}" == current ]]; then
    shift
    exec python3 "$script_dir/version_tool.py" current "$@"
fi
exec python3 "$script_dir/version_tool.py" bump "$@"
