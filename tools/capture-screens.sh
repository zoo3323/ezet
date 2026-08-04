#!/usr/bin/env bash
# Rebuild the README screenshots (docs/img/*.svg) from real ezet screens.
#
#   make docs        (= tools/capture-screens.sh)
#
# These are not hand-placed mockups: a throwaway HOME holds fixed hosts and a
# fake ssh, expect drives the real TUI, and the captured output is converted to
# SVG. Change the UI and the docs follow after one run of this script.
#
# Needs: expect, python3 (without them it only reports and changes nothing)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EZET_BIN="$ROOT/bin/ezet"
IMG_DIR="$ROOT/docs/img"
COLS=${EZET_DOC_COLS:-88}

for cmd in expect python3; do
  command -v "$cmd" >/dev/null 2>&1 || { printf '%s is required.\n' "$cmd" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
home="$work/home"
mkdir -p "$home/.ssh/config.d" "$work/bin" "$IMG_DIR"

# ── Fixed fixture for the docs ───────────────────────────────────
printf 'Include %s/.ssh/config.d/ezet\n' "$home" > "$home/.ssh/config"
cat > "$home/.ssh/config.d/ezet" <<'CFG'
Host dev
    HostName 192.0.2.10
    User dev
    # ezet: et-port 32022
Host gpu-box
    HostName 192.0.2.42
    User ml
Host gpu-farm
    HostName 192.0.2.43
    User ml
Host web-1
    HostName 203.0.113.8
    User deploy
    Port 30001
CFG
chmod 600 "$home/.ssh/config" "$home/.ssh/config.d/ezet"

# et only needs to look installed (so the VIA column reads ET); it never runs.
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/et"
# A fake ssh answers the tmux session query with fixed values. -G (config
# lookup) is handed to the real ssh.
cat > "$work/bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
for a in "$@"; do case "$a" in -G) exec /usr/bin/ssh "$@" ;; esac; done
printf '%s\n' '__DT_CONNECTED__' '__DT_TMUX__=/usr/bin/tmux' '__DT_NOW__=1700000000'
printf '%s\n' \
  '__DT_SESSION__|editor|3|attached|1699999950|1699300000|nvim|/home/dev/projects/ezet' \
  '__DT_SESSION__|server|1||1699996400|1699900000|node|/home/dev/api' \
  '__DT_SESSION__|logs|1||1699960000|1699800000|tail|/var/log/nginx'
FAKE_SSH
chmod +x "$work/bin/et" "$work/bin/ssh"

export CAP_HOME="$home" CAP_PATH="$work/bin:/usr/bin:/bin" CAP_BIN="$EZET_BIN" CAP_COLS="$COLS"

# ── Capture the screens ──────────────────────────────────────────
# One run walks the host list -> search -> session list.
expect > "$work/main.ansi" <<'EXPECT'
set timeout 8
spawn env HOME=$env(CAP_HOME) PATH=$env(CAP_PATH) TERM=xterm-256color $env(CAP_BIN)
stty columns $env(CAP_COLS) rows 40 < $spawn_out(slave,name)
expect "SSH HOSTS*"
sleep 0.4
send "\033\[A"
expect -re {› Search}
send "gpu"
sleep 0.6
send "\033\[B"
expect -re {› gpu-box}
send "\010\010\010"
expect -re {Search  host name}
send "\033\[B"
expect -re {› dev}
sleep 0.5
send "\r"
expect "TMUX*"
sleep 1.0
send "q"
expect eof
EXPECT

# For the add-host form, use the last step (two fields already filled in).
expect > "$work/addhost.ansi" <<'EXPECT'
set timeout 8
spawn env HOME=$env(CAP_HOME) PATH=$env(CAP_PATH) TERM=xterm-256color $env(CAP_BIN)
stty columns $env(CAP_COLS) rows 40 < $spawn_out(slave,name)
expect "SSH HOSTS*"
send "\033\[B\033\[B\033\[B\033\[B\r"
expect "ADDRESS*"
send "30001 ops@203.0.113.8\r"
expect -re {ET PORT +▸}
send "30002\r"
expect -re {ALIAS +▸}
sleep 0.8
send "\003"
expect eof
EXPECT

# ── Frame -> SVG ─────────────────────────────────────────────────
# Frame indexes follow the key sequence above; change one and match the other.
frame() { python3 "$ROOT/tools/ansi2svg.py" "$1" "$2" "$3" "$4"; }

hosts_frame=$(python3 - "$work/main.ansi" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding='utf-8', errors='replace', newline='').read()
frames = re.split(r'\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J', raw)
# Use the host list after the query was cleared (the last SSH HOSTS screen).
best = 0
for i, f in enumerate(frames):
    plain = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', f)
    if 'SSH HOSTS (4)' in plain and '\u203a dev' in plain:
        best = i
print(best)
PY
)
search_frame=$(python3 - "$work/main.ansi" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding='utf-8', errors='replace', newline='').read()
frames = re.split(r'\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J', raw)
best = 0
for i, f in enumerate(frames):
    plain = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', f)
    if 'Search  gpu' in plain and 'SSH HOSTS (2/4)' in plain:
        best = i
print(best)
PY
)
sessions_frame=$(python3 - "$work/main.ansi" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding='utf-8', errors='replace', newline='').read()
frames = re.split(r'\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J', raw)
best = 0
for i, f in enumerate(frames):
    plain = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', f)
    if 'TMUX (3)' in plain and 'SSH Direct' in plain:
        best = i
print(best)
PY
)
addhost_frame=$(python3 - "$work/addhost.ansi" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding='utf-8', errors='replace', newline='').read()
frames = re.split(r'\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J', raw)
best = 0
for i, f in enumerate(frames):
    plain = re.sub(r'\x1b\[[0-9;?]*[a-zA-Z]', '', f)
    if 'step 3 of 3' in plain:
        best = i
print(best)
PY
)

frame "$work/main.ansi"    "$hosts_frame"    'ezet — host picker'      "$IMG_DIR/hosts.svg"
frame "$work/main.ansi"    "$search_frame"   'ezet — search'           "$IMG_DIR/search.svg"
frame "$work/main.ansi"    "$sessions_frame" 'ezet dev — session picker' "$IMG_DIR/sessions.svg"
frame "$work/addhost.ansi" "$addhost_frame"  'ezet — add host'         "$IMG_DIR/add-host.svg"

if command -v xmllint >/dev/null 2>&1; then
  xmllint --noout "$IMG_DIR"/hosts.svg "$IMG_DIR"/search.svg \
    "$IMG_DIR"/sessions.svg "$IMG_DIR"/add-host.svg
fi
printf '\nRebuilt 4 screenshots in %s\n' "$IMG_DIR"
