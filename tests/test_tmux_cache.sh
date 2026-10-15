#!/usr/bin/env bash
# ezet remembers which tmux each host's session query settled on and hands it
# to the next query, which then skips the slow shell probes (the remote side is
# covered by test_tmux_discovery.py). A fake ssh records the script it is sent
# and answers like the real one would.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.ssh/config.d" "$tmp/bin"
printf 'Include %s/.ssh/config.d/ezet\n' "$tmp" > "$tmp/.ssh/config"
printf '%s\n' 'Host box' '    HostName 192.0.2.30' > "$tmp/.ssh/config.d/ezet"

# FAKE_TMUX: the tmux the remote picks. FAKE_PROBE: auto (probe unless ezet
# sent a remembered tmux, as the real script does), yes, no, or notmux.
cat > "$tmp/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = -V ]; then printf '%s\n' 'OpenSSH_9.9'; exit 0; fi
for arg in "$@"; do [ "$arg" = -G ] && exec /usr/bin/ssh "$@"; done
[ "${*: -2}" = "sh -s" ] || { printf 'unexpected ssh call: %s\n' "$*" >&2; exit 99; }
script=$(cat)
printf '%s' "$script" > "$FAKE_DIR/script"
printf '%s\n' '__DT_CONNECTED__'
if [ "$FAKE_PROBE" = notmux ]; then printf '%s\n' '__DT_NO_TMUX__'; exit 0; fi
printf '%s\n' "__DT_TMUX__=$FAKE_TMUX" '__DT_TMUX_SOCKET__=ezet-3.7c'
case "$FAKE_PROBE" in
  yes) printf '%s\n' '__DT_TMUX_PROBED__' ;;
  auto) case "$script" in "known_tmux="*) ;; *) printf '%s\n' '__DT_TMUX_PROBED__' ;; esac ;;
esac
printf '%s\n' "__DT_NOW__=$FAKE_NOW"
FAKE_SSH
chmod +x "$tmp/bin/ssh"

cache="$tmp/.cache/ezet/tmux-box"

# query <tmux> <probe> <now>: one non-interactive session query for box.
query() {
  env -u XDG_CACHE_HOME HOME="$tmp" PATH="$tmp/bin:/usr/bin:/bin" NO_COLOR=1 EZET_NO_MULTIPLEX=1 \
    FAKE_DIR="$tmp" FAKE_TMUX="$1" FAKE_PROBE="$2" FAKE_NOW="$3" \
    "$ROOT/bin/ezet" box </dev/null >/dev/null 2>&1 || true
}
fail() { printf 'FAIL %s\n  cache: %s\n  script starts: %s\n' "$1" "$(cat "$cache" 2>/dev/null || printf '(none)')" "$(head -c 80 "$tmp/script")" >&2; exit 1; }
sent() { head -n 1 "$tmp/script"; }

# Nothing remembered yet: the full script goes out, and its answer is kept.
query /opt/t/tmux auto 1700000000
case "$(sent)" in known_tmux=*) fail 'first query sends no memory' ;; esac
[ "$(cat "$cache")" = '1700000000 /opt/t/tmux' ] || fail 'full probe is remembered'

# Next time the remembered tmux is handed over, and a quick answer keeps the
# time of the full probe.
query /opt/t/tmux auto 1700000500
[ "$(sent)" = "known_tmux='/opt/t/tmux' known_at=1700000000" ] || fail 'memory is sent'
[ "$(cat "$cache")" = '1700000000 /opt/t/tmux' ] || fail 'quick answer keeps the probe time'

# A quick answer that settled on another tmux (newer one in a standard place)
# is remembered, still with the time of the last full probe.
query /usr/local/bin/tmux no 1700000600
[ "$(cat "$cache")" = '1700000000 /usr/local/bin/tmux' ] || fail 'changed pick keeps the probe time'

# A new full probe restarts the day.
query /usr/local/bin/tmux yes 1700090000
[ "$(cat "$cache")" = '1700090000 /usr/local/bin/tmux' ] || fail 'full probe restarts the day'

# A host without tmux leaves the memory alone.
query /usr/local/bin/tmux notmux 1700090100
[ "$(cat "$cache")" = '1700090000 /usr/local/bin/tmux' ] || fail 'failed query keeps memory'

# Damaged or hostile memory is never sent; the full script runs instead.
for bad in "1700000000 /opt/t/tmux'; touch $tmp/pwned; '" 'soon /opt/t/tmux' '1700000000 relative/tmux' \
  '1700000000' '' '12345678901234567 /opt/t/tmux'; do
  printf '%s\n' "$bad" > "$cache"
  query /opt/t/tmux auto 1700000000
  case "$(sent)" in known_tmux=*) fail "bad memory was sent: $bad" ;; esac
  [ ! -e "$tmp/pwned" ] || fail 'memory reached the shell'
done

printf 'tmux cache tests passed\n'
