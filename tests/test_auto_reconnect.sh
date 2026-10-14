#!/usr/bin/env bash
# Auto-reconnect: ezet attaches again when the ET server restarted or an SSH
# connection dropped, and leaves a detach, a failed first attempt or a disabled
# setting alone. Fake et/ssh replay a plan of "<seconds> <exit status>" lines.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.ssh/config.d" "$tmp/bin"
: > "$tmp/.ssh/config"
cat > "$tmp/.ssh/config.d/ezet" <<'HOSTS'
Host etbox
    HostName 192.0.2.20
    # ezet: et-port 32020
Host sshbox
    HostName 192.0.2.21
    Port 30021
HOSTS

# Pops the first line of a plan file.
cat > "$tmp/bin/pop-plan" <<'POP'
#!/usr/bin/env bash
set -eu
line=$(awk 'NR==1 {print; exit}' "$1")
awk 'NR>1' "$1" > "$1.rest" && mv "$1.rest" "$1"
printf '%s\n' "${line:-0 0}"
POP

cat > "$tmp/bin/et" <<'FAKE_ET'
#!/usr/bin/env bash
set -eu
case "${1:-}" in --help|--version) exit 0 ;; esac
printf 'et\n' >> "$PLAN_DIR/calls"
read -r seconds status <<<"$("$PLAN_DIR/../bin/pop-plan" "$PLAN_DIR/et")"
sleep "$seconds"
exit "$status"
FAKE_ET

cat > "$tmp/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = -V ]; then printf '%s\n' 'OpenSSH_9.9'; exit 0; fi
for arg in "$@"; do [ "$arg" = -G ] && exec /usr/bin/ssh "$@"; done
if [ "${*: -2}" = "sh -s" ]; then
  script=$(cat)
  case "$script" in
    *etserver*)
      printf 'probe\n' >> "$PLAN_DIR/calls"
      "$PLAN_DIR/../bin/pop-plan" "$PLAN_DIR/etserver" ;;
    *) printf '%s\n' '__DT_CONNECTED__' '__DT_TMUX__=/usr/bin/tmux' '__DT_TMUX_SOCKET__=ezet-3.7c' '__DT_NOW__=1700000000' ;;
  esac
  exit 0
fi
for arg in "$@"; do
  if [ "$arg" = -t ]; then
    printf 'ssh\n' >> "$PLAN_DIR/calls"
    read -r seconds status <<<"$("$PLAN_DIR/../bin/pop-plan" "$PLAN_DIR/ssh")"
    sleep "$seconds"
    exit "$status"
  fi
done
printf 'unexpected ssh call: %s\n' "$*" >&2
exit 99
FAKE_SSH
chmod +x "$tmp/bin/pop-plan" "$tmp/bin/et" "$tmp/bin/ssh"

# run <host> <et plan> <etserver answers> <ssh plan> [ENV=VALUE...]
# Leaves the call sequence in $calls, the output in $out and the status in $status.
run() {
  local host="$1"
  mkdir -p "$tmp/plan"
  printf '%s' "$2" > "$tmp/plan/et"
  printf '%s' "$3" > "$tmp/plan/etserver"
  printf '%s' "$4" > "$tmp/plan/ssh"
  : > "$tmp/plan/calls"
  shift 4
  status=0
  out=$(env HOME="$tmp" PATH="$tmp/bin:/usr/bin:/bin" PLAN_DIR="$tmp/plan" NO_COLOR=1 \
    EZET_NO_MULTIPLEX=1 EZET_RECONNECT_DELAYS=0 EZET_RECONNECT_MIN_SESSION=1 "$@" \
    "$ROOT/bin/ezet" "$host" work 2>&1 </dev/null) || status=$?
  calls=$(tr '\n' ' ' < "$tmp/plan/calls")
}

fail() { printf 'FAIL %s\n  calls: %s\n  status: %s\n%s\n' "$1" "$calls" "$status" "$out" >&2; exit 1; }

# The ET server restarted under a running session: attach again, then stop
# once a session ends while the server keeps running.
run etbox $'3 0\n0 0\n' $'up 0\nup 99999\n' ''
[ "$calls" = "et probe et probe " ] || fail 'restart reattaches'
[ "$status" -eq 0 ] || fail 'restart status'
printf '%s\n' "$out" | grep -q 'RECONNECT .*ET server restarted' || fail 'restart message'

# A plain detach: the server has been up longer than the session.
run etbox $'1 0\n' $'up 99999\n' ''
[ "$calls" = "et probe " ] || fail 'detach stays detached'
if printf '%s\n' "$out" | grep -q RECONNECT; then fail 'detach message'; fi

# The ET server is not running at all: keep trying until it is back.
run etbox $'3 0\n0 0\n' $'none\nup 99999\n' ''
[ "$calls" = "et probe et probe " ] || fail 'server down reattaches'
printf '%s\n' "$out" | grep -q 'ET server is down' || fail 'server down message'

# The client failed after a working session (no route after wake, say).
run etbox $'2 1\n0 1\n0 0\n' $'up 99999\n' ''
[ "$calls" = "et et et probe " ] || fail 'connection errors retry'
printf '%s\n' "$out" | grep -q 'connection lost' || fail 'connection error message'

# A first attempt that fails at once is reported, not retried.
run etbox $'0 1\n' '' '' EZET_RECONNECT_MIN_SESSION=10
[ "$calls" = "et " ] || fail 'first failure not retried'
[ "$status" -eq 1 ] || fail 'first failure status'

# Turned off: no probe, no retry.
run etbox $'3 0\n' $'up 0\n' '' EZET_AUTO_RECONNECT=0
[ "$calls" = "et " ] || fail 'disabled'

# SSH: 255 after a working session reattaches; a normal exit does not.
run sshbox '' '' $'2 255\n0 0\n'
[ "$calls" = "ssh ssh " ] || fail 'ssh drop reattaches'
printf '%s\n' "$out" | grep -q 'connection lost' || fail 'ssh drop message'
run sshbox '' '' $'2 0\n'
[ "$calls" = "ssh " ] || fail 'ssh exit stays closed'

# Waits come from EZET_RECONNECT_DELAYS and the last one repeats.
eval "$(awk '/^reconnect_delay\(\) \{/,/^\}/' "$ROOT/bin/ezet")"
export EZET_RECONNECT_DELAYS="1 2 5"
[ "$(reconnect_delay 0)$(reconnect_delay 1)$(reconnect_delay 2)$(reconnect_delay 7)" = 1255 ] || {
  printf 'FAIL reconnect_delay\n' >&2; exit 1; }

printf 'auto-reconnect tests passed\n'
