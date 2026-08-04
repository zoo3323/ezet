#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EZET_BIN="$ROOT/bin/ezet"
tmp=$(mktemp -d)
legacy_tmp=$(mktemp -d)
trap 'rm -rf "$tmp" "$legacy_tmp"' EXIT
mkdir -p "$tmp/.ssh"
mkdir -p "$legacy_tmp/.ssh"

export EZET_TEST_HOME="$tmp"
export EZET_TEST_BIN="$EZET_BIN"

# Do not assume CI has Eternal Terminal: use a stub that records the real arguments.
fake_et_bin="$tmp/fake-et-bin"
fake_et_log="$tmp/fake-et.log"
mkdir -p "$fake_et_bin"
export EZET_FAKE_ET_LOG="$fake_et_log"
cat > "$fake_et_bin/et" <<'FAKE_ET'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$@" > "$EZET_FAKE_ET_LOG"
FAKE_ET
chmod +x "$fake_et_bin/et"

# The external form "port user@ip" must store the SSH port and the optional ET port.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "ADD HOST*step 1 of 2*"
expect "ADDRESS*"
send "30001 user@203.0.113.10\r"
expect {
  -re {ADD HOST +step 2 of 3} { }
  "Invalid address*" { exit 10 }
  timeout { exit 12 }
}
expect {
  -re {ET PORT +▸} { send "32022\r" }
  timeout { exit 13 }
}
expect -re {ALIAS +▸}
send "host-ext\r"
expect "Added*"
send "q"
expect eof
EXPECT

resolved=$(ssh -F "$tmp/.ssh/config" -G host-ext 2>/dev/null)
awk '$1=="hostname" && $2=="203.0.113.10" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="user" && $2=="user" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="port" && $2=="30001" {ok=1} END {exit !ok}' <<< "$resolved"
awk '
  $1=="#" && tolower($2)=="ezet:" && tolower($3)=="et-port" && $4=="32022" {ok=1}
  END {exit !ok}
' "$tmp/.ssh/config.d/ezet"

# The plain form "user@ip" must not ask for a port or write a Port entry.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "\033\[B\r"
expect "ADDRESS*"
send "user@192.0.2.20\r"
expect {
  -re {ALIAS +▸} { send "host-a\r" }
  "ET PORT*" { exit 30 }
  timeout { exit 31 }
}
expect "Added*"
send "q"
expect eof
EXPECT

awk '
  tolower($1)=="host" || tolower($1)=="match" {
    if (active) exit
    active=(tolower($1)=="host" && $2=="host-a")
  }
  active && tolower($1)=="port" {bad=1}
  END {exit bad}
' "$tmp/.ssh/config.d/ezet"

# An external SSH host with its own ET port must pick Eternal Terminal.
dryrun=$(HOME="$tmp" PATH="$fake_et_bin:/usr/bin:/bin" EZET_DRYRUN=1 "$EZET_BIN" host-ext probe 2>&1)
case "$dryrun" in
  *"via et (port 32022)"*) ;;
  *) printf 'expected external host with ET port to use et, got: %s\n' "$dryrun" >&2; exit 20 ;;
esac

HOME="$tmp" PATH="$fake_et_bin:/usr/bin:/bin" EZET_NO_MULTIPLEX=1 \
  "$EZET_BIN" host-ext probe >/dev/null 2>&1
awk '
  NR==1 && $0=="-p" {port_flag=1}
  NR==2 && $0=="32022" {port=1}
  NR==3 && $0=="host-ext" {host=1}
  NR==4 && $0=="-c" {command_flag=1}
  NR==5 && $0=="'\''tmux'\'' new-session -A -s '\''probe'\''" {command=1}
  END {exit !(port_flag && port && host && command_flag && command)}
' "$fake_et_log"

# External hosts written by older versions carry no ET metadata; they keep using SSH.
printf '\nHost legacy-ext\n    HostName 203.0.113.11\n    User user\n    Port 30003\n' \
  >> "$tmp/.ssh/config.d/ezet"
dryrun=$(HOME="$tmp" PATH="$fake_et_bin:/usr/bin:/bin" EZET_DRYRUN=1 "$EZET_BIN" legacy-ext probe 2>&1)
case "$dryrun" in
  *"via ssh"*) ;;
  *) printf 'expected external host without ET port to keep using ssh, got: %s\n' "$dryrun" >&2; exit 21 ;;
esac

# Only the selected Host may be deleted, and only after confirmation.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "d"
expect {
  "Really delete*" { send "y\r" }
  timeout { exit 40 }
}
expect "Deleted*"
send "q"
expect eof
EXPECT

awk '
  tolower($1)=="host" {
    for (i=2; i<=NF; i++) {
      if ($i=="host-ext") deleted_still_exists=1
      if ($i=="host-a") survivor_exists=1
    }
  }
  END {exit deleted_still_exists || !survivor_exists}
' "$tmp/.ssh/config.d/ezet"

# Editing a Host must be able to change address, external port and alias together.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "e"
expect "EDIT HOST*step 1 of 3*"
expect -re {ADDRESS +▸}
send "30002 user@198.51.100.20\r"
expect -re {ET PORT +▸}
send "32023\r"
expect -re {ALIAS +▸}
send "host-edit\r"
expect "Changed*"
send "q"
expect eof
EXPECT

resolved=$(ssh -F "$tmp/.ssh/config" -G host-edit 2>/dev/null)
awk '$1=="hostname" && $2=="198.51.100.20" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="user" && $2=="user" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="port" && $2=="30002" {ok=1} END {exit !ok}' <<< "$resolved"
awk '
  $1=="#" && tolower($2)=="ezet:" && tolower($3)=="et-port" && $4=="32023" {ok=1}
  END {exit !ok}
' "$tmp/.ssh/config.d/ezet"

# Entering "-" while editing clears only the ET port and keeps the external SSH setup.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "e"
expect -re {ADDRESS +▸}
send "\r"
expect {
  -re {Enter = keep 32023} { }
  timeout { exit 24 }
}
expect -re {ET PORT +▸}
send -- "-\r"
expect -re {ALIAS +▸}
send "\r"
expect "Changed*"
send "q"
expect eof
EXPECT

if awk '
  tolower($1)=="host" || tolower($1)=="match" {
    if (active) exit
    active=(tolower($1)=="host" && $2=="host-edit")
  }
  active && $1=="#" && tolower($2)=="ezet:" && tolower($3)=="et-port" {found=1}
  END {exit !found}
' "$tmp/.ssh/config.d/ezet"; then
  printf 'editing with - must remove the ET port metadata\n' >&2
  exit 22
fi
dryrun=$(HOME="$tmp" PATH="$fake_et_bin:/usr/bin:/bin" EZET_DRYRUN=1 "$EZET_BIN" host-edit probe 2>&1)
case "$dryrun" in
  *"via ssh"*) ;;
  *) printf 'expected host with removed ET port to use ssh, got: %s\n' "$dryrun" >&2; exit 23 ;;
esac

# A Windows host is added as a plain Host too, with no per-host connection mode.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "\033\[B\033\[B\r"
expect "ADDRESS*"
send "user@198.51.100.7\r"
expect -re {ALIAS +▸}
send "host-b\r"
expect "Added*"
send "q"
expect eof
EXPECT

if grep -Eiq '^[[:space:]]*#[[:space:]]*ezet:[[:space:]]*mode[[:space:]]*=' "$tmp/.ssh/config.d/ezet"; then
  printf 'per-host connection mode metadata must not be written\n' >&2
  exit 60
fi

# ↑ on the first host moves to the search row, typing filters immediately, and ↓
# comes back down into the filtered list.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
expect "Search  host name or address*"
expect {
  -re {HOST +USER +ADDRESS +VIA} {}
  timeout { exit 80 }
}
send "\033\[A"
expect -re {› Search}
send "host-b"
expect "SSH HOSTS (1/3)*"
expect -re {› Search  host-b}
send "\033\[B"
expect -re {› host-b}
send "q"
expect eof
EXPECT

# `o` enters reorder mode; moving the selected host down must persist the whole
# order to its own file and apply it to the host list on the next run.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
expect "e edit*d delete*o reorder*"
send "o"
expect "HOST ORDER*"
send "\033\[B"
expect "HOST ORDER*"
send "\r"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

expected_order=$(printf 'legacy-ext\nhost-edit\nhost-b')
actual_order=$(sed -n '1,$p' "$tmp/.ssh/config.d/ezet.order")
if [ "$actual_order" != "$expected_order" ]; then
  printf 'host order was not persisted as expected\nexpected:\n%s\nactual:\n%s\n' \
    "$expected_order" "$actual_order" >&2
  exit 61
fi

order_view=$(printf '\n' | HOME="$tmp" NO_COLOR=1 "$EZET_BIN" 2>&1 || true)
if ! awk '
  /legacy-ext/ && !first  {first=NR}
  /host-edit/  && !second {second=NR}
  /host-b/     && !third  {third=NR}
  END {exit !(first && second && third && first < second && second < third)}
' <<< "$order_view"; then
  printf 'saved host order was not applied on the next run\n%s\n' "$order_view" >&2
  exit 62
fi

# SSH stub used to exercise the remote tmux query, connect and rename paths.
fake_bin="$tmp/fake-bin"
fake_ssh_log="$tmp/fake-ssh.log"
mkdir -p "$fake_bin"
real_ssh=$(command -v ssh)
export EZET_FAKE_PATH="$fake_bin:/usr/bin:/bin"
export EZET_REAL_SSH="$real_ssh"
export EZET_FAKE_SSH_LOG="$fake_ssh_log"

cat > "$fake_bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -eu

for arg in "$@"; do
  if [ "$arg" = -G ]; then
    exec "$EZET_REAL_SSH" "$@"
  fi
done

printf 'REMOTE' >> "$EZET_FAKE_SSH_LOG"
for arg in "$@"; do printf '\t%s' "$arg" >> "$EZET_FAKE_SSH_LOG"; done
printf '\n' >> "$EZET_FAKE_SSH_LOG"

case "${EZET_FAKE_SSH_MODE:-sessions}" in
  sessions)
    printf '%s\n' \
      '__DT_CONNECTED__' \
      '__DT_TMUX__=/usr/bin/tmux' \
      '__DT_NOW__=1700000000' \
      '__DT_SESSION__|work|1||1699999900|1699993000|bash|/home/user/work/app'
    ;;
  empty)
    printf '%s\n' \
      '__DT_CONNECTED__' \
      '__DT_TMUX__=/usr/bin/tmux' \
      '__DT_NOW__=1700000000'
    ;;
  multi)
    printf '%s\n' \
      '__DT_CONNECTED__' \
      '__DT_TMUX__=/usr/bin/tmux' \
      '__DT_NOW__=1700000000' \
      '__DT_SESSION__|alpha|1||1699999900|1699993000|bash|/home/user/work/app' \
      '__DT_SESSION__|bravo|1||1699999900|1699993000|bash|/home/user'
    ;;
  hostile)
    # Hostile remote: session names mix in '|', arithmetic injection (now[$(...)])
    # and ANSI escapes.
    printf '%s\n' '__DT_CONNECTED__' '__DT_TMUX__=/usr/bin/tmux' '__DT_NOW__=1700000000'
    printf '__DT_SESSION__|we|ird|2|attached|now[$(touch %s)]|age[$(touch %s)]|bash|/srv/app\n' "$EZET_PWN_MARK" "$EZET_PWN_MARK"
    printf '__DT_SESSION__|\033[31mred\033[0m|1||1699999900|1699993000|bash|/srv/x\n'
    ;;
  notmux)
    printf "%s\n" "__DT_CONNECTED__" "__DT_NO_TMUX__"
    ;;
  windows)
    # Real Windows cmd behaviour: it runs only the first of several lines and fails,
    # yet exits 0. (Its error text is localised, so detection must rely on the
    # missing marker rather than on matching a string.)
    printf '%s\n' "'valid_tmux_path' is not recognized as an internal or external command" >&2
    exit 0
    ;;
  timeout)
    printf '%s\n' 'ssh: connect to host 198.51.100.7 port 22: Operation timed out' >&2
    exit 255
    ;;
esac
FAKE_SSH
chmod +x "$fake_bin/ssh"

# An interactive run starts on the alternate screen and swaps the host list and the
# tmux dashboard in place. On exit it must return to the original screen.
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) TERM=xterm-256color NO_COLOR=1 EZET_FAKE_SSH_MODE=sessions EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN)
expect -exact "\033\[?1049h"
expect "SSH HOSTS*"
send "\r"
expect "\033\[2J\033\[H"
expect "SSH auth check*"
expect "Fetched tmux sessions*"
expect "\033\[2J\033\[H"
expect "work*"
expect "← back*"
expect "e edit*q quit*"
expect "New Session"
expect "SSH Direct"
send "\r"
expect -exact "\033\[?1049l"
expect "SSH + TMUX*connecting*"
expect -exact "\033\[?1049h"
expect "SSH auth check*"
expect "work*"
send "q"
expect -exact "\033\[?1049l"
expect eof
EXPECT

# The `SSH Direct` row below the session list must be selectable with the arrow
# keys and connect over plain SSH.
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=sessions EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "Fetched tmux sessions*"
expect -re {› alpha}
send "\033\[B\033\[B\033\[B"
expect -re {› SSH Direct}
send "\r"
expect eof
EXPECT

# With no sessions at all, the trailing `＋ New Session` row still opens the name prompt.
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=empty EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "Fetched tmux sessions*"
expect "no active tmux sessions*"
expect "q quit*"
send "\r"
expect "NEW SESSION*"
expect -re {NAME +▸}
send "\r"
expect "no active tmux sessions*"
send "q"
expect eof
EXPECT

# On a wide window (>=88 columns) the session table adds the AGE column, and DIR
# shows the whole path with home shortened to `~` instead of just the last name.
# Narrower windows draw without AGE.
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=sessions EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
stty columns 100 rows 40 < $spawn_out(slave,name)
expect "Fetched tmux sessions*"
expect {
  -re {IDLE +AGE +CMD +DIR} {}
  timeout { exit 81 }
}
expect {
  -re {~/work/app} {}
  timeout { exit 82 }
}
send "q"
expect eof
EXPECT

# `←` must return to the host screen from the search row as well as from the list.
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=sessions EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "SSH auth check*"
expect "Fetched tmux sessions*"
expect -re {› work}
send "\033\[A"
expect -re {› Search}
send "\033\[D"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

# Even with no matches, the arrow keys must not trap focus on the search row.
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=sessions EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "Fetched tmux sessions*"
expect -re {› alpha}
send "\033\[A"
expect -re {› Search}
send "no-match"
expect -re {Search  no-match}
send "\033\[B"
expect -re {› alpha}
send "q"
expect eof
EXPECT

# `e` on a searched session must rename the selected session.
printf '' > "$fake_ssh_log"
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=multi EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "Fetched tmux sessions*"
expect -re {› alpha}
send "\033\[A"
expect -re {› Search}
send "bravo"
expect -re {› Search  bravo}
send "\033\[B"
expect -re {› bravo}
send "e"
expect "RENAME SESSION  bravo*"
expect {
  -re {CURRENT +bravo} { }
  timeout { exit 25 }
}
expect -re {NEW NAME +▸}
send "charlie\r"
expect "Renamed: bravo -> charlie*"
expect "Fetched the session list*"
send "q"
expect eof
EXPECT

grep -F "rename-session -t 'bravo' 'charlie'" "$fake_ssh_log" >/dev/null

# Session fields sent by the remote are never trusted.
#   - Arithmetic injection in a name (now[$(cmd)]) must not run a local command
#     (guards against an RCE regression).
#   - A '|' inside a name must not shift the other fields.
#   - ANSI escapes must not reach the terminal as-is.
export EZET_PWN_MARK="$tmp/PWNED"
rm -f "$EZET_PWN_MARK"
hostile_out=$(printf '\n' | HOME="$tmp" PATH="$EZET_FAKE_PATH" NO_COLOR=1 EZET_NO_ANIMATION=1 \
  EZET_FAKE_SSH_MODE=hostile EZET_FAKE_SSH_LOG="$tmp/fake-ssh.hostile.log" \
  EZET_PWN_MARK="$EZET_PWN_MARK" "$EZET_BIN" host-b 2>&1 || true)
if [ -e "$EZET_PWN_MARK" ]; then
  printf 'remote session name executed a local command (arithmetic injection)\n' >&2
  exit 95
fi
case "$hostile_out" in
  *'we|ird'*) ;;
  *) printf 'session name containing | must not shift fields\n' >&2; exit 96 ;;
esac
case "$hostile_out" in
  *$'\033'*) printf 'ANSI escape from remote session name must be stripped\n' >&2; exit 97 ;;
esac

# Each failure reason is reported distinctly, together with what to do about it.
#   non-POSIX shell (Windows) vs no tmux on the remote
for mode_case in "windows:non-POSIX shell (e.g. Windows)" "notmux:no tmux on the remote" "timeout:connection failed · no response"; do
  mode=${mode_case%%:*}; want=${mode_case#*:}
  # Only the classification matters here, so start each mode with an empty log to
  # avoid the retry delay.
  case_log="$tmp/fake-ssh.$mode.log"; : > "$case_log"
  out=$(printf '\n' | HOME="$tmp" PATH="$EZET_FAKE_PATH" NO_COLOR=1 EZET_NO_ANIMATION=1 \
    EZET_FAKE_SSH_MODE="$mode" EZET_FAKE_SSH_LOG="$case_log" "$EZET_BIN" host-b 2>&1)
  case "$out" in
    *"$want"*) ;;
    *) printf 'expected fetch failure label %s for mode %s\n' "$want" "$mode" >&2; exit 90 ;;
  esac
  case "$mode" in
    timeout) hint_want="Check that the host is up" ;;
    windows) hint_want="tmux sessions are unavailable" ;;
    notmux)  hint_want="Install tmux on the remote" ;;
  esac
  case "$out" in
    *"$hint_want"*) ;;
    *) printf 'expected actionable hint for mode %s\n' "$mode" >&2; exit 91 ;;
  esac
  case "$out" in
    *"tmux unavailable"*) ;;
    *) printf 'expected korean unavailable label for mode %s\n' "$mode" >&2; exit 92 ;;
  esac
done

# Hosts without a usable tmux (Windows) connect to the SSH shell with Enter, and
# need no separate `s` shortcut.
printf '' > "$fake_ssh_log"
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=windows EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "Cannot fetch tmux sessions*"
expect {
  "SSH Direct*" {}
  timeout { exit 110 }
}
send "\r"
expect {
  "SSH SHELL*connecting*" {}
  timeout { exit 111 }
  eof { exit 112 }
}
expect {
  eof {}
  timeout { exit 113 }
}
EXPECT

# `←` must still go back when the tmux query failed and there is no session row.
printf '' > "$fake_ssh_log"
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=windows EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "SSH auth check*"
expect "Cannot fetch tmux sessions*"
expect "tmux unavailable*"
expect "← back*"
send "\033\[D"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

# Without a TTY and with animation off, start/finish status still prints as one
# plain text line.
no_animation_output=$(printf '\n' | HOME="$tmp" PATH="$EZET_FAKE_PATH" NO_COLOR=1 EZET_NO_ANIMATION=1 \
  EZET_FAKE_SSH_MODE=windows EZET_FAKE_SSH_LOG="$fake_ssh_log" "$EZET_BIN" host-b 2>&1)
case "$no_animation_output" in
  *"…  Fetching tmux sessions"*"Cannot fetch tmux sessions"*"Press Enter to quit"*) ;;
  *) printf 'expected non-TTY activity status and dashboard, got: %s\n' "$no_animation_output" >&2; exit 72 ;;
esac
case "$no_animation_output" in
  *"⠋"*) printf 'spinner must be disabled for non-TTY/EZET_NO_ANIMATION\n' >&2; exit 73 ;;
esac

# The dedicated config, the Include line, file modes and the doctor must all be sane.
[ -f "$tmp/.ssh/config.d/ezet" ]
awk -v target="$tmp/.ssh/config.d/ezet" '
  tolower($1)=="include" {
    line=$0
    sub(/^[^[:space:]]+[[:space:]]+/, "", line)
    gsub(/^"|"$/, "", line)
    if (line==target) found=1
  }
  END {exit !found}
' "$tmp/.ssh/config"
HOME="$tmp" "$EZET_BIN" --doctor >/dev/null

# An existing SSH config is preserved and backed up, and an ezet Host may not
# duplicate an alias that already exists.
legacy_config='Host legacy
    HostName 192.0.2.50
    User legacy-user'
printf '%s\n' "$legacy_config" > "$legacy_tmp/.ssh/config"
HOME="$legacy_tmp" EZET_DRYRUN=1 "$EZET_BIN" legacy probe >/dev/null
[ "$(sed -n '1,$p' "$legacy_tmp/.ssh/config.ezet-backup")" = "$legacy_config" ]
awk 'tolower($1)=="include" {found=1} END {exit !found}' "$legacy_tmp/.ssh/config"
awk 'tolower($1)=="host" && $2=="legacy" {found=1} END {exit !found}' "$legacy_tmp/.ssh/config"

export EZET_LEGACY_TEST_HOME="$legacy_tmp"
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_LEGACY_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "\033\[B\r"
expect "ADDRESS*"
send "user@192.0.2.51\r"
expect -re {ALIAS +▸}
send "legacy\r"
expect {
  "Alias already exists*" { send "fresh\r" }
  timeout { exit 50 }
}
expect "Added*"
send "q"
expect eof
EXPECT

# Hosts from the main ~/.ssh/config cannot be edited or deleted in ezet, so they
# carry an `ro` badge after the VIA column (hosts in the ezet config do not).
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_LEGACY_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect {
  -re {HOST +USER +ADDRESS +VIA} {}
  timeout { exit 83 }
}
expect {
  -re {legacy .*192\.0\.2\.50 .*ro} {}
  timeout { exit 84 }
}
send "q"
expect eof
EXPECT

# In the forms `<` steps back one field and `q` cancels from any field.
# In particular a `q` in the ALIAS field must not be stored as the alias (that
# field used to have no cancel key at all).
form_tmp=$(mktemp -d)
mkdir -p "$form_tmp/.ssh/config.d"
printf 'Include %s/.ssh/config.d/ezet\n' "$form_tmp" > "$form_tmp/.ssh/config"
printf 'Host only\n    HostName 192.0.2.60\n    User u\n' > "$form_tmp/.ssh/config.d/ezet"
export EZET_FORM_TEST_HOME="$form_tmp"
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_FORM_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "\033\[B\r"
expect -re {ADDRESS +▸}
send "30001 ops@203.0.113.9\r"
expect {
  -re {ET PORT +▸} { send "30002\r" }
  timeout { exit 130 }
}
expect -re {ALIAS +▸}
send "<\r"
expect {
  -re {ET PORT +▸} { }
  timeout { exit 131 }
}
send "<\r"
expect {
  -re {ADDRESS +▸} { }
  timeout { exit 132 }
}
send "q\r"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

if grep -q '^Host q$' "$form_tmp/.ssh/config.d/ezet"; then
  printf 'q at the ALIAS step must cancel, not create a host named q\n' >&2
  exit 133
fi
if [ "$(grep -c '^Host ' "$form_tmp/.ssh/config.d/ezet")" != 1 ]; then
  printf 'cancelling the add form must not write a host\n' >&2
  exit 134
fi

# `q` in the ALIAS field of the edit form must change nothing and return to the list.
before=$(sed -n '1,$p' "$form_tmp/.ssh/config.d/ezet")
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_FORM_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "e"
expect -re {ADDRESS +▸}
send "\r"
expect -re {ALIAS +▸}
send "q\r"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT
if [ "$(sed -n '1,$p' "$form_tmp/.ssh/config.d/ezet")" != "$before" ]; then
  printf 'q at the ALIAS step of the edit form must not change the config\n' >&2
  exit 135
fi
rm -rf "$form_tmp"

# Stepping back with `<` and retyping a plain address must drop the ET port entered
# earlier. Otherwise a plain host gets an `# ezet: et-port` line and ezet connects
# with `et -p <port>` to a host that has no such forwarding.
back_tmp=$(mktemp -d)
mkdir -p "$back_tmp/.ssh/config.d"
printf 'Include %s/.ssh/config.d/ezet\n' "$back_tmp" > "$back_tmp/.ssh/config"
printf 'Host only\n    HostName 192.0.2.60\n    User u\n' > "$back_tmp/.ssh/config.d/ezet"
export EZET_BACK_TEST_HOME="$back_tmp"
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_BACK_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "\033\[B\r"
expect -re {ADDRESS +▸}
send "30001 ops@203.0.113.8\r"
expect -re {ET PORT +▸}
send "30002\r"
expect -re {ALIAS +▸}
send "<\r"
expect -re {ET PORT +▸}
send "<\r"
expect -re {ADDRESS +▸}
send "dev@192.0.2.10\r"
expect -re {ALIAS +▸}
send "plainhost\r"
expect "SSH HOSTS*"
send "q"
expect eof
EXPECT

if awk '
  tolower($1)=="host" || tolower($1)=="match" {
    if (active) exit
    active=(tolower($1)=="host" && $2=="plainhost")
  }
  active && $1=="#" && tolower($2)=="ezet:" && tolower($3)=="et-port" {found=1}
  END {exit !found}
' "$back_tmp/.ssh/config.d/ezet"; then
  printf 'a plain address entered after stepping back must not keep the earlier ET port\n' >&2
  exit 143
fi
back_out=$(HOME="$back_tmp" PATH="$fake_et_bin:/usr/bin:/bin" EZET_DRYRUN=1 "$EZET_BIN" plainhost probe 2>&1)
case "$back_out" in
  *"via et (port"*) printf 'plain host must not connect through an ET port: %s\n' "$back_out" >&2; exit 144 ;;
esac
rm -rf "$back_tmp"

# The doctor accepts macOS/Linux (WSL reports Linux) and rejects anything else.
# Git Bash/MSYS2 gets a distinct message: the Include line ezet writes uses an MSYS
# path that Windows OpenSSH cannot resolve, so WSL is the supported route.
os_tmp=$(mktemp -d)
mkdir -p "$os_tmp/bin"
cat > "$os_tmp/bin/uname" <<'FAKE_UNAME'
#!/usr/bin/env bash
case "${1:-}" in
  -s) printf '%s\n' "${FAKE_OS:-Linux}" ;;
  *)  printf '%s\n' "${FAKE_OS:-Linux}" ;;
esac
FAKE_UNAME
chmod +x "$os_tmp/bin/uname"

os_out=$(FAKE_OS='MINGW64_NT-10.0' PATH="$os_tmp/bin:$PATH" HOME="$tmp" "$EZET_BIN" --doctor 2>&1 || true)
case "$os_out" in
  *"Git Bash/MSYS2 is not supported"*) ;;
  *) printf 'doctor must reject Git Bash/MSYS2 with its own hint, got: %s\n' "$os_out" >&2; exit 140 ;;
esac
os_out=$(FAKE_OS='SunOS' PATH="$os_tmp/bin:$PATH" HOME="$tmp" "$EZET_BIN" --doctor 2>&1 || true)
case "$os_out" in
  *"supported: macOS, Linux, WSL"*) ;;
  *) printf 'doctor must reject an unknown OS, got: %s\n' "$os_out" >&2; exit 141 ;;
esac
os_out=$(FAKE_OS='Linux' PATH="$os_tmp/bin:$PATH" HOME="$tmp" "$EZET_BIN" --doctor 2>&1 || true)
case "$os_out" in
  *"[ok]   OS: Linux"*) ;;
  *) printf 'doctor must accept Linux (this is what WSL reports), got: %s\n' "$os_out" >&2; exit 142 ;;
esac
rm -rf "$os_tmp"

# --uninstall reverts only the Include line ezet added; the user's own settings,
# host list and backup are never touched.
un_tmp=$(mktemp -d)
mkdir -p "$un_tmp/.ssh/config.d"
cat > "$un_tmp/.ssh/config" <<'UCFG'
Host *
    ServerAliveInterval 60

Host work-vpn
    HostName 10.1.2.3
    User alice
    ProxyJump bastion
UCFG
cp "$un_tmp/.ssh/config" "$un_tmp/original"
printf 'Include %s/.ssh/config.d/other-tool\n' "$un_tmp" >> "$un_tmp/.ssh/config"
cp "$un_tmp/.ssh/config" "$un_tmp/original"
: > "$un_tmp/.ssh/config.d/other-tool"
printf '\n' | HOME="$un_tmp" EZET_NO_MULTIPLEX=1 EZET_SSH_CONNECT_TIMEOUT=2 "$EZET_BIN" >/dev/null 2>&1 || true
printf 'Host kept-host\n    HostName 192.0.2.77\n' >> "$un_tmp/.ssh/config.d/ezet"

# Declining must change nothing.
cp "$un_tmp/.ssh/config" "$un_tmp/installed"
printf 'n\n' | HOME="$un_tmp" "$EZET_BIN" --uninstall >/dev/null 2>&1 || true
if ! cmp -s "$un_tmp/installed" "$un_tmp/.ssh/config"; then
  printf 'uninstall must not change anything when declined\n' >&2; exit 100
fi

printf 'y\n' | HOME="$un_tmp" "$EZET_BIN" --uninstall >/dev/null 2>&1 || true
if ! cmp -s "$un_tmp/original" "$un_tmp/.ssh/config"; then
  printf 'uninstall must restore the original ssh config byte-for-byte\n' >&2
  diff "$un_tmp/original" "$un_tmp/.ssh/config" >&2 || true
  exit 101
fi
grep -q 'kept-host' "$un_tmp/.ssh/config.d/ezet" || { printf 'uninstall must keep the host list\n' >&2; exit 102; }
[ -f "$un_tmp/.ssh/config.ezet-backup" ] || { printf 'uninstall must keep the backup\n' >&2; exit 103; }
# Idempotent: a second run reports that there is nothing to undo.
again=$(printf 'y\n' | HOME="$un_tmp" "$EZET_BIN" --uninstall 2>&1 || true)
case "$again" in *"Nothing to undo"*) ;; *) printf 'uninstall must be idempotent\n' >&2; exit 104 ;; esac
rm -rf "$un_tmp"

printf 'ezet regression tests: PASS\n'
