#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/.ssh/config.d" "$tmp/bin"
: > "$tmp/.ssh/config"

# Generate help inside the stub: a very large page must not exceed exec's
# environment/argv limit.
cat > "$tmp/bin/et" <<'FAKE_ET'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" >> "$EZET_ET_LOG"
if [ "${1:-}" = --help ]; then
  if [ -n "${EZET_HELP_COUNT_FILE:-}" ]; then
    count=0
    [ -f "$EZET_HELP_COUNT_FILE" ] && count=$(awk 'NR==1 {print; exit}' "$EZET_HELP_COUNT_FILE")
    printf '%s\n' "$((count + 1))" > "$EZET_HELP_COUNT_FILE"
  fi
  case "${EZET_HELP_KIND:-supported}" in
    supported) printf '%s\n' '  --close-on-hangup  terminate the remote session' ;;
    old) printf '%s\n' '  --version  print version' ;;
    failed) printf '%s\n' '--close-on-hangup' >&2; exit 7 ;;
    long) printf '%s\n' '--close-on-hangup'; awk 'BEGIN { for (i=0; i<200000; i++) print "help text" }' ;;
  esac
  exit 0
fi
exit 0
FAKE_ET
chmod +x "$tmp/bin/et"

cat > "$tmp/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -eu
if [ "${1:-}" = -V ]; then printf '%s\n' 'OpenSSH_9.9'; exit 0; fi
exec /usr/bin/ssh "$@"
FAKE_SSH
chmod +x "$tmp/bin/ssh"

cat > "$tmp/.ssh/config.d/ezet" <<'HOSTS'
# ezet: close-on-hangup yes
Host plain
    HostName 192.0.2.10
    Port 30010
    # ezet: et-port 32010
Host opted
    HostName 192.0.2.11
    Port 30011
    # ezet: et-port 32011
    # ezet: close-on-hangup yes
Host duplicate
    HostName 192.0.2.12
    Port 30012
    # ezet: et-port 32012
    # ezet: close-on-hangup yes
    # ezet: close-on-hangup yes
Host malformed
    HostName 192.0.2.13
    Port 30013
    # ezet: et-port 32013
    # ezet: close-on-hangup no
Host mixed
    HostName 192.0.2.14
    Port 30014
    # ezet: et-port 32014
    # EZET: CLOSE-ON-HANGUP YES
Host wildcard
    HostName 192.0.2.15
    Port 30015
    # ezet: et-port 32015
Host internal
    HostName 192.0.2.16
    # ezet: close-on-hangup yes
Host *
    # ezet: close-on-hangup yes
Match all
    # ezet: close-on-hangup yes
HOSTS

run_host() {
  local name="$1" kind="$2" log="$tmp/$1-$2.log"
  : > "$log"
  if ! EZET_ET_LOG="$log" EZET_HELP_KIND="$kind" HOME="$tmp" \
    PATH="$tmp/bin:/usr/bin:/bin" EZET_NO_MULTIPLEX=1 \
    "$ROOT/bin/ezet" "$name" probe >/dev/null 2>&1; then
    printf 'ezet failed for %s (%s)\n' "$name" "$kind" >&2
    return 1
  fi
  printf '%s\n' "$log"
}

has_close_flag() {
  awk '$0 == "--close-on-hangup" { found=1 } END { exit !found }' "$1"
}

assert_flag() {
  local name="$1" kind="$2" want="$3" log
  log=$(run_host "$name" "$kind")
  if [ "$want" = yes ]; then
    has_close_flag "$log" || { printf 'expected close flag: %s/%s\n' "$name" "$kind" >&2; exit 1; }
  elif has_close_flag "$log"; then
    printf 'unexpected close flag: %s/%s\n' "$name" "$kind" >&2
    exit 1
  fi
}

# Only the exact marker in an ezet-owned literal Host block opts in.
assert_flag plain supported no
assert_flag opted supported yes
assert_flag duplicate supported no
assert_flag malformed supported no
assert_flag mixed supported no
assert_flag wildcard supported no
assert_flag internal supported yes

# A supported marker remains off for old clients or a failed help probe.
assert_flag opted old no
assert_flag opted failed no
assert_flag opted long yes

# The real ET call receives the exact option ordering, including -p.
opted_log="$tmp/opted-supported.log"
awk 'BEGIN { n=0 } { a[++n]=$0 } END {
  if (a[n-5]!="--close-on-hangup" || a[n-4]!="-p" || a[n-3]!="32011" ||
      a[n-2]!="opted" || a[n-1]!="-c" || index(a[n], "new-session") == 0) exit 1
}' "$opted_log"

# The helper section is evaluated directly from bin/ezet, then exercised in one
# shell process. Probe results are cached, but the per-host option is reset.
helper_count="$tmp/helper-count"
helper_section=$(awk '/^# ── ET client options/{on=1} on && /^doctor_file_mode\(\) \{/{exit} on' "$ROOT/bin/ezet")
(
  EZET_HOSTS_FILE="$tmp/.ssh/config.d/ezet"
  EZET_HELP_COUNT_FILE="$helper_count"
  EZET_HELP_KIND=supported
  EZET_ET_LOG="$tmp/helper-et.log"
  PATH="$tmp/bin:/usr/bin:/bin"
  export EZET_HOSTS_FILE EZET_HELP_COUNT_FILE EZET_HELP_KIND EZET_ET_LOG PATH
  eval "$helper_section"
  et_client_options opted
  [ "${#ET_OPTIONS[@]}" -eq 1 ]
  et_client_options plain
  [ "${#ET_OPTIONS[@]}" -eq 0 ]
  et_client_options opted
  [ "${#ET_OPTIONS[@]}" -eq 1 ]
  [ "$(awk 'NR==1 {print; exit}' "$helper_count")" = 1 ]
)

# Doctor reports local capability plus the opt-in policy; it does not claim to
# have checked the selected host or the remote server.
doctor_supported=$(HOME="$tmp" PATH="$tmp/bin:/usr/bin:/bin" EZET_ET_LOG="$tmp/doctor.log" EZET_HELP_KIND=supported \
  "$ROOT/bin/ezet" --doctor 2>&1 || true)
printf '%s\n' "$doctor_supported" | grep -q 'et client supports --close-on-hangup'
printf '%s\n' "$doctor_supported" | grep -q 'explicit per-host opt-in'
if printf '%s\n' "$doctor_supported" | grep -Eiq 'remote server|selected host'; then
  printf 'doctor must not claim remote or selected-host validation\n' >&2
  exit 1
fi
doctor_old=$(HOME="$tmp" PATH="$tmp/bin:/usr/bin:/bin" EZET_ET_LOG="$tmp/doctor.log" EZET_HELP_KIND=old \
  "$ROOT/bin/ezet" --doctor 2>&1 || true)
printf '%s\n' "$doctor_old" | grep -q 'et client lacks --close-on-hangup'

# Editing a connection setting clears the opt-in, while an alias-only rename
# preserves it. Drive the real form so update_host's boolean reaches its caller.
edit_tmp="$tmp/edit"
mkdir -p "$edit_tmp/.ssh/config.d"
printf 'Include %s/.ssh/config.d/ezet\n' "$edit_tmp" > "$edit_tmp/.ssh/config"
printf '%s\n' \
  'Host editme sibling' \
  '    HostName 192.0.2.60' \
  '    User u' \
  '    Port 30001' \
  '    # ezet: et-port 32001' \
  '    # ezet: close-on-hangup yes' > "$edit_tmp/.ssh/config.d/ezet"
export edit_tmp EZET_BIN="$ROOT/bin/ezet"

expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(edit_tmp) NO_COLOR=1 $env(EZET_BIN)
expect "SSH HOSTS*"
send "e"
expect -re {ADDRESS +▸}
send "30002 u@192.0.2.61\r"
expect -re {ET PORT +▸}
send "\r"
expect -re {ALIAS +▸}
send "\r"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

if grep -q 'close-on-hangup' "$edit_tmp/.ssh/config.d/ezet"; then
  if ! awk '
    /^Host / { block=$2 }
    /close-on-hangup yes/ { if (block=="editme") bad=1; if (block=="sibling") found=1 }
    END { exit bad || !found }
  ' "$edit_tmp/.ssh/config.d/ezet"; then
    printf 'changing connection settings must clear target marker and preserve sibling marker\n' >&2
    exit 1
  fi
else
  printf 'changing connection settings unexpectedly removed sibling marker\n' >&2
  exit 1
fi

printf '%s\n' \
  'Host editme sibling' \
  '    HostName 192.0.2.60' \
  '    User u' \
  '    Port 30001' \
  '    # ezet: et-port 32001' \
  '    # ezet: close-on-hangup yes' > "$edit_tmp/.ssh/config.d/ezet"
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(edit_tmp) NO_COLOR=1 $env(EZET_BIN)
expect "SSH HOSTS*"
send "e"
expect -re {ADDRESS +▸}
send "\r"
expect -re {ET PORT +▸}
send "\r"
expect -re {ALIAS +▸}
send "renamed\r"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

if ! grep -q '^Host renamed$' "$edit_tmp/.ssh/config.d/ezet" || \
   ! grep -q '^Host sibling$' "$edit_tmp/.ssh/config.d/ezet" || \
   [ "$(grep -c 'close-on-hangup yes' "$edit_tmp/.ssh/config.d/ezet")" -ne 2 ]; then
  printf 'alias-only rename must preserve close-on-hangup\n' >&2
  exit 1
fi

printf 'ezet ET option regression test: PASS\n'
