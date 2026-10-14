#!/usr/bin/env bash
# SSH multiplexing: enabled when the expanded control socket path fits, kept for
# EZET_SSH_PERSIST, and a master opened before the machine last woke is closed
# before the next ssh. The functions are evaluated straight from bin/ezet.
# shellcheck disable=SC2016  # the bash -c bodies are single-quoted on purpose
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# Unix socket paths are short, so stay out of a long $TMPDIR.
tmp=$(mktemp -d /tmp/ezmux.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"

cat > "$tmp/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -eu
[ "${1:-}" = -V ] && { printf '%s\n' 'OpenSSH_9.9'; exit 0; }
control=""
prev=""
for arg in "$@"; do
  case "$prev:$arg" in -o:ControlPath=*) control="${arg#ControlPath=}" ;; esac
  prev="$arg"
done
for arg in "$@"; do
  if [ "$arg" = -G ]; then
    [ -z "$control" ] || printf 'controlpath %s\n' "${control//%C/2fe96e4641955581babe8992e837f186c203da85}"
    exit 0
  fi
done
printf '%s\n' "$*" >> "$SSH_LOG"
FAKE_SSH
chmod +x "$tmp/bin/ssh"
export PATH="$tmp/bin:$PATH" SSH_LOG="$tmp/ssh.log"

section=$(awk '/^EZET_CONTROL_DIR=/,/^remote_ssh\(\) \{/' "$ROOT/bin/ezet" | sed '$d')
remote=$(awk '/^remote_ssh\(\) \{/,/^\}/' "$ROOT/bin/ezet")

# mux <control dir> [ENV=VALUE...]: prints "SSH_MUX_ON options..."
mux() {
  local dir="$1"
  shift
  env "$@" EZET_CONTROL_DIR="$dir" bash -c '
    set -euo pipefail
    SSH_CONNECT_OPTIONS=(-o ConnectTimeout=5)
    eval "$1"
    setup_multiplexing
    printf "%s %s\n" "$SSH_MUX_ON" "${SSH_CONNECT_OPTIONS[*]}"' _ "$section"
}

fail() { printf 'FAIL %s\n%s\n' "$1" "${2:-}" >&2; exit 1; }

out=$(mux "$tmp/cm")
case "$out" in "1 "*ControlMaster=auto*"ControlPersist=30m"*ServerAliveInterval=15*) ;; *) fail 'short path enables mux' "$out" ;; esac
[ -d "$tmp/cm" ] || fail 'control dir created'

long="$tmp/$(printf 'x%.0s' $(seq 1 60))"
out=$(mux "$long")
[ "${out%% *}" = 0 ] || fail 'long path disables mux' "$out"
[ ! -d "$long" ] || fail 'long path creates nothing'

out=$(mux "$tmp/cm" EZET_NO_MULTIPLEX=1)
[ "${out%% *}" = 0 ] || fail 'EZET_NO_MULTIPLEX' "$out"

out=$(mux "$tmp/cm" EZET_SSH_PERSIST=5m)
case "$out" in *ControlPersist=5m*) ;; *) fail 'persist 5m' "$out" ;; esac
out=$(mux "$tmp/cm" EZET_SSH_PERSIST='1 day')
case "$out" in *ControlPersist=30m*) ;; *) fail 'bad persist falls back' "$out" ;; esac

# stale <seconds the wake is after the socket was made>: runs drop_stale_ssh_master
# against a real socket and prints what reached ssh.
socket="$tmp/cm/2fe96e4641955581babe8992e837f186c203da85"
stale() {
  : > "$SSH_LOG"
  EZET_CONTROL_DIR="$tmp/cm" WAKE_OFFSET="$1" bash -c '
    set -euo pipefail
    SSH_CONNECT_OPTIONS=(-o ConnectTimeout=5)
    host=box
    eval "$1"
    setup_multiplexing
    sock="$2"
    last_wake_time() { echo $(( $(date -r "$sock" +%s 2>/dev/null || echo 0) + WAKE_OFFSET )); }
    drop_stale_ssh_master' _ "$section" "$socket"
  cat "$SSH_LOG"
}

python3 -c 'import socket, sys; socket.socket(socket.AF_UNIX).bind(sys.argv[1])' "$socket"
[ -S "$socket" ] || fail 'test socket'
case "$(stale 100)" in *"-O exit box"*) ;; *) fail 'master from before the last wake is closed' "$(stale 100)" ;; esac
[ -z "$(stale -100)" ] || fail 'master opened after the last wake is kept'
rm -f "$socket"
[ -z "$(stale 100)" ] || fail 'no socket, nothing to close'

# remote_ssh adds the shared options in front of the caller's arguments.
: > "$SSH_LOG"
EZET_CONTROL_DIR="$tmp/cm" bash -c '
  set -euo pipefail
  SSH_CONNECT_OPTIONS=(-o ConnectTimeout=5)
  host=box
  eval "$1"; eval "$2"
  setup_multiplexing
  remote_ssh -n box true' _ "$section" "$remote"
case "$(cat "$SSH_LOG")" in "-o ConnectTimeout=5 -o ControlMaster=auto"*"-n box true") ;; *) fail 'remote_ssh options' "$(cat "$SSH_LOG")" ;; esac

# Where kern.waketime does not exist (Linux), sysctl fails; under errexit and
# pipefail that must not stop ezet.
mkdir -p "$tmp/nosysctl"
printf '#!/bin/sh\nexit 255\n' > "$tmp/nosysctl/sysctl"
chmod +x "$tmp/nosysctl/sysctl"
: > "$SSH_LOG"
PATH="$tmp/nosysctl:$PATH" EZET_CONTROL_DIR="$tmp/cm" bash -c '
  set -euo pipefail
  SSH_CONNECT_OPTIONS=(-o ConnectTimeout=5)
  host=box
  eval "$1"; eval "$2"
  setup_multiplexing
  remote_ssh -n box true' _ "$section" "$remote" || fail 'remote_ssh without kern.waketime'
grep -q -- "-n box true" "$SSH_LOG" || fail 'remote_ssh without kern.waketime still runs ssh' "$(cat "$SSH_LOG")"

printf 'ssh mux tests passed\n'
