#!/usr/bin/env bash
# Build the pinned Eternal Terminal checkout without changing installed binaries.
set -euo pipefail

BASE=a8367415783a64405c62c70b755b4c09b410532b
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -lt 2 ]]; then
  printf 'Usage: %s ET_SOURCE BUILD_DIR [additional cmake options...]\n' "$0" >&2
  printf '       %s --fetch WORK_DIR [additional cmake options...]\n' "$0" >&2
  exit 2
fi
PATCH="$ROOT/tools/et-reconnect-memory.patch"
FETCH=0
if [[ $1 == --fetch ]]; then
  FETCH=1
  mkdir -p "$2"
  WORK=$(cd "$2" && pwd)
  SOURCE="$WORK/source"
  BUILD="$WORK/build"
else
  SOURCE=$(cd "$1" && pwd)
  BUILD=$2
fi
shift 2
mkdir -p "$BUILD"
mkdir "$BUILD/.ezet-build-lock" 2>/dev/null || {
  printf 'Another ET build is running in %s\n' "$BUILD" >&2; exit 1;
}
trap 'rmdir "$BUILD/.ezet-build-lock"' EXIT
if [[ $FETCH == 1 ]]; then
  if [[ ! -d "$SOURCE" ]]; then
    git init "$SOURCE"
    git -C "$SOURCE" remote add origin https://github.com/MisterTea/EternalTerminal.git
  fi
  [[ -e "$SOURCE/.git" ]] || { printf 'Not an ET checkout: %s\n' "$SOURCE" >&2; exit 1; }
  if ! git -C "$SOURCE" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$SOURCE" fetch --depth 1 origin "$BASE"
    git -C "$SOURCE" checkout --detach FETCH_HEAD
  fi
fi
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
# Disabled dependency managers need no checkout. Keep all other submodules at
# the commits recorded by this ET revision.
while IFS= read -r module; do
  case "$module" in external/vcpkg|external/sentry-native) continue ;; esac
  if [[ ! -d "$SOURCE/$module" || -z $(ls -A "$SOURCE/$module") ]]; then
    git -C "$SOURCE" submodule update --init --recursive -- "$module"
  fi
done < <(git -C "$SOURCE" config -f .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{print $2}')
PLATFORM_OPTIONS=()
if [[ $(uname -s) == Darwin ]]; then
  if command -v brew >/dev/null 2>&1; then
    PLATFORM_OPTIONS+=("-DCMAKE_PREFIX_PATH=$(brew --prefix)")
  fi
  PLATFORM_OPTIONS+=("-DCMAKE_OSX_SYSROOT=$(xcrun --show-sdk-path)")
fi
cmake -S "$SOURCE" -B "$BUILD" \
  -DDISABLE_VCPKG=ON -DDISABLE_SENTRY=ON -DDISABLE_TELEMETRY=ON \
  -DBUILD_TESTING=ON -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -DET_RECOVERY_BUFFER_MIB=64 ${PLATFORM_OPTIONS[@]+"${PLATFORM_OPTIONS[@]}"} "$@"
cmake --build "$BUILD" --target et etserver etterminal et-test -j "${ET_BUILD_JOBS:-4}"
"$BUILD/et-test" '[RecoveryMemory],[BackedIO],[ClientConnection],[Connection]' --reporter compact
{
  printf 'source_base=%s\n' "$BASE"
  printf 'patch_sha256=%s\n' "$(cmake -E sha256sum "$PATCH" | awk '{print $1}')"
  awk '/^ET_RECOVERY_BUFFER_MIB:STRING=/ {sub(/^[^=]*=/, ""); print "recovery_buffer_mib=" $0}' "$BUILD/CMakeCache.txt"
} > "$BUILD/ezet-et-build.info"
printf 'Built and tested: %s\n' "$BUILD"
