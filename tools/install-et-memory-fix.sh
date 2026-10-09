#!/usr/bin/env bash
# Install tested binaries under an explicit prefix; optionally restart systemd.
set -euo pipefail
if [[ $# -lt 1 ]]; then
  printf 'Usage: %s BUILD_DIR [--prefix PREFIX] [--service SYSTEMD_UNIT]\n' "$0" >&2
  exit 2
fi
BUILD=$(cd "$1" && pwd)
shift
PREFIX=/usr/local
SERVICE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix|--service)
      [[ $# -ge 2 && -n $2 ]] || { printf 'Missing value for %s\n' "$1" >&2; exit 2; }
      if [[ $1 == --prefix ]]; then PREFIX=$2; else SERVICE=$2; fi
      shift 2 ;;
    *) printf 'Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
done
case "$PREFIX" in /*) ;; *) printf 'PREFIX must be an absolute path\n' >&2; exit 2 ;; esac
for name in et etserver etterminal; do
  [[ -f "$BUILD/$name" && -x "$BUILD/$name" ]] || {
    printf 'Missing executable: %s\n' "$name" >&2
    exit 1
  }
done
if [[ -n $SERVICE ]]; then
  command -v systemctl >/dev/null
  systemctl cat "$SERVICE" >/dev/null
fi
mkdir -p "$PREFIX/bin" "$PREFIX/lib/ezet"
PREFIX=$(cd "$PREFIX" && pwd)
BINDIR="$PREFIX/bin"
mkdir "$PREFIX/lib/ezet/.install-lock" 2>/dev/null || {
  printf 'Another ET install is running under %s\n' "$PREFIX" >&2; exit 1;
}
STAGE=""
cleanup() {
  [[ -z $STAGE ]] || rm -rf "$STAGE"
  rmdir "$PREFIX/lib/ezet/.install-lock"
}
trap cleanup EXIT
STAGE=$(mktemp -d "$BINDIR/.et-install.XXXXXXXX")
for name in et etserver etterminal; do
  install -m 755 "$BUILD/$name" "$STAGE/$name"
  if [[ -e "$BINDIR/$name" && ! -f "$BINDIR/$name" ]]; then
    printf 'Refusing to replace non-file %s\n' "$BINDIR/$name" >&2; exit 1
  fi
done
"$STAGE/et" --version >/dev/null
BACKUP=$(mktemp -d "$PREFIX/lib/ezet/et-backup.XXXXXXXX")
for name in et etserver etterminal; do
  if [[ -e "$BINDIR/$name" || -L "$BINDIR/$name" ]]; then
    cp -a "$BINDIR/$name" "$BACKUP/$name"
  fi
done
rollback() {
  local status=$?
  trap - ERR
  for name in et etserver etterminal; do
    if [[ -e "$BACKUP/$name" || -L "$BACKUP/$name" ]]; then
      cp -a "$BACKUP/$name" "$STAGE/$name.rollback"
      mv -f "$STAGE/$name.rollback" "$BINDIR/$name"
    else
      rm -f "$BINDIR/$name"
    fi
  done
  [[ -z $SERVICE ]] || systemctl restart "$SERVICE" || true
  printf 'Install failed; previous binaries restored from %s\n' "$BACKUP" >&2
  exit "$status"
}
trap 'rollback' ERR
for name in et etserver etterminal; do
  mv -f "$STAGE/$name" "$BINDIR/$name"
done
if [[ -n $SERVICE ]]; then
  systemctl restart "$SERVICE"
  systemctl is-active --quiet "$SERVICE"
fi
trap - ERR
printf 'Installed: %s. Previous binaries: %s\n' "$BINDIR" "$BACKUP"
[[ -z $SERVICE ]] || systemctl show "$SERVICE" -p MainPID -p MemoryCurrent -p NRestarts
