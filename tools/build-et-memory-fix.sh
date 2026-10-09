#!/usr/bin/env bash
# Build the pinned Eternal Terminal checkout without changing installed binaries.
set -euo pipefail

BASE=a8367415783a64405c62c70b755b4c09b410532b
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -lt 2 ]]; then
  printf 'Usage: %s ET_SOURCE BUILD_DIR [additional cmake options...]\n' "$0" >&2
  exit 2
fi
SOURCE=$(cd "$1" && pwd)
BUILD=$2
shift 2
PATCH="$ROOT/tools/et-reconnect-memory.patch"
if git -C "$SOURCE" apply --reverse --check "$PATCH" 2>/dev/null; then
  printf 'Memory fix is already applied.\n'
else
  [[ $(git -C "$SOURCE" rev-parse HEAD) == "$BASE" ]] || {
    printf 'Expected Eternal Terminal commit %s\n' "$BASE" >&2
    exit 1
  }
  git -C "$SOURCE" apply --check "$PATCH"
  git -C "$SOURCE" apply "$PATCH"
fi
cmake -S "$SOURCE" -B "$BUILD" \
  -DDISABLE_VCPKG=ON -DDISABLE_SENTRY=ON -DDISABLE_TELEMETRY=ON \
  -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DET_RECOVERY_BUFFER_MIB=8 "$@"
cmake --build "$BUILD" --target et etserver etterminal et-test -j "${ET_BUILD_JOBS:-4}"
"$BUILD/et-test" '[RecoveryMemory],[BackedIO],[ClientConnection],[Connection]' --reporter compact
