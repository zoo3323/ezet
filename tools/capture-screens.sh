#!/usr/bin/env bash
# README 스크린샷(docs/img/*.svg)을 실제 ezet 화면에서 다시 만든다.
#
#   make docs        (= tools/capture-screens.sh)
#
# 손으로 좌표를 찍은 목업이 아니라, 임시 HOME 에 가짜 호스트·가짜 ssh 를 두고
# 실제 TUI 를 expect 로 몰아 출력을 그대로 캡처한 뒤 SVG 로 변환한다. UI 를
# 바꾸면 이 스크립트만 다시 돌리면 문서가 따라온다.
#
# 필요한 것: expect, python3 (둘 다 없으면 안내만 하고 아무것도 바꾸지 않는다)
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EZET_BIN="$ROOT/bin/ezet"
IMG_DIR="$ROOT/docs/img"
COLS=${EZET_DOC_COLS:-88}

for cmd in expect python3; do
  command -v "$cmd" >/dev/null 2>&1 || { printf '%s 가 필요합니다.\n' "$cmd" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
home="$work/home"
mkdir -p "$home/.ssh/config.d" "$work/bin" "$IMG_DIR"

# ── 문서용 고정 픽스처 ───────────────────────────────────────────
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

# et 는 있다고 보이게만 한다(VIA 칸이 ET 로 나오도록). 실제로 실행되지는 않는다.
printf '#!/usr/bin/env bash\nexit 0\n' > "$work/bin/et"
# tmux 세션 목록은 고정 값으로 답하는 가짜 ssh 가 낸다. -G(설정 조회)는 진짜 ssh 로 넘긴다.
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

# ── 화면 캡처 ────────────────────────────────────────────────────
# 한 번 실행에서 호스트 목록 → 검색 → 세션 목록을 지나간다.
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

# 새 호스트 추가 폼은 마지막 단계(값이 두 칸 채워진 상태)를 쓴다.
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

# ── 프레임 → SVG ─────────────────────────────────────────────────
# 프레임 번호는 위 조작 순서에 따라 정해진다. 조작을 바꾸면 여기도 맞춰야 한다.
frame() { python3 "$ROOT/tools/ansi2svg.py" "$1" "$2" "$3" "$4"; }

hosts_frame=$(python3 - "$work/main.ansi" <<'PY'
import re, sys
raw = open(sys.argv[1], encoding='utf-8', errors='replace', newline='').read()
frames = re.split(r'\x1b\[2J\x1b\[H|\x1b\[\d+A\r?\x1b\[J', raw)
# 검색어가 지워진 뒤의 호스트 목록(가장 마지막 SSH HOSTS 화면)을 쓴다.
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
printf '\n%s 의 스크린샷 4장을 다시 만들었습니다.\n' "$IMG_DIR"
