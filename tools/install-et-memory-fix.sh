#!/usr/bin/env bash
# Install tested Linux binaries, preserving the existing systemd configuration.
set -euo pipefail
if [[ $# != 1 || $EUID != 0 ]]; then
  printf 'Usage: sudo %s BUILD_DIR\n' "$0" >&2
  exit 2
fi
BUILD=$(cd "$1" && pwd)
for name in et etserver etterminal; do
  [[ -x "$BUILD/$name" && -f "/usr/local/bin/$name" ]] || {
    printf 'Missing executable: %s\n' "$name" >&2
    exit 1
  }
done
systemctl cat et.service >/dev/null
BACKUP=$(mktemp -d /usr/local/lib/ezet-et-backup.XXXXXXXX)
for name in et etserver etterminal; do
  cp -a "/usr/local/bin/$name" "$BACKUP/$name"
done
rollback() {
  for name in et etserver etterminal; do
    cp -a "$BACKUP/$name" "/usr/local/bin/$name.rollback"
    mv -f "/usr/local/bin/$name.rollback" "/usr/local/bin/$name"
  done
  systemctl restart et.service
}
trap 'rollback' ERR
for name in et etserver etterminal; do
  install -m 755 "$BUILD/$name" "/usr/local/bin/$name.new"
  mv -f "/usr/local/bin/$name.new" "/usr/local/bin/$name"
done
systemctl restart et.service
systemctl is-active --quiet et.service
trap - ERR
printf 'Installed memory fix. Previous binaries: %s\n' "$BACKUP"
systemctl show et.service -p MainPID -p MemoryCurrent -p NRestarts
