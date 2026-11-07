#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/Scripts/build-app.sh"
open "$ROOT/dist/CursorLimitsTray.app" --args "$@"
