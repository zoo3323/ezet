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

# CI에도 Eternal Terminal이 설치돼 있다고 가정하지 않고, 실제 호출 인자를 기록하는 대역을 쓴다.
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

# 외부 SSH 형식 "포트 user@ip"가 SSH 포트와 선택적 ET 포트를 함께 저장해야 한다.
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

# 일반 형식 "user@ip"는 포트를 추가로 묻거나 Port 항목을 만들지 않아야 한다.
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

# 별도 ET 포트를 지정한 외부 SSH 호스트는 Eternal Terminal을 선택해야 한다.
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

# 기존 버전에서 만든 외부 SSH 호스트에는 ET 메타데이터가 없다. 이 설정은 그대로 SSH를 써야 한다.
printf '\nHost legacy-ext\n    HostName 203.0.113.11\n    User user\n    Port 30003\n' \
  >> "$tmp/.ssh/config.d/ezet"
dryrun=$(HOME="$tmp" PATH="$fake_et_bin:/usr/bin:/bin" EZET_DRYRUN=1 "$EZET_BIN" legacy-ext probe 2>&1)
case "$dryrun" in
  *"via ssh"*) ;;
  *) printf 'expected external host without ET port to keep using ssh, got: %s\n' "$dryrun" >&2; exit 21 ;;
esac

# 선택한 Host만 확인 후 삭제해야 한다.
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

# 선택한 Host의 주소, 외부 포트와 별칭을 함께 수정해야 한다.
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

# 편집에서 "-"를 입력하면 ET 포트만 해제하고 외부 SSH 설정은 유지해야 한다.
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

# Windows 호스트도 별도 접속 모드 없이 일반 Host로 추가해야 한다.
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

# 첫 호스트에서 ↑를 누르면 상단 검색 행으로 이동하고, 입력한 검색어로 즉시
# 필터링한 뒤 ↓로 결과 목록에 다시 내려갈 수 있어야 한다.
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

# `o`로 순서 편집에 들어가 선택한 호스트를 아래로 옮기면 전체 순서를 별도
# 파일에 저장하고, 다음 실행의 호스트 목록에도 같은 순서를 적용해야 한다.
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

# 원격 tmux 조회·접속·수정 동작을 검증하기 위한 SSH 대역.
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
    # 악의적 원격: 세션명에 '|' 와 산술 주입(now[$(...)]) , ANSI 이스케이프를 섞는다.
    printf '%s\n' '__DT_CONNECTED__' '__DT_TMUX__=/usr/bin/tmux' '__DT_NOW__=1700000000'
    printf '__DT_SESSION__|we|ird|2|attached|now[$(touch %s)]|age[$(touch %s)]|bash|/srv/app\n' "$EZET_PWN_MARK" "$EZET_PWN_MARK"
    printf '__DT_SESSION__|\033[31mred\033[0m|1||1699999900|1699993000|bash|/srv/x\n'
    ;;
  notmux)
    printf "%s\n" "__DT_CONNECTED__" "__DT_NO_TMUX__"
    ;;
  windows)
    # 실제 Windows cmd 동작: 여러 줄 중 첫 줄만 실행하고 오류를 내지만 종료코드는 0.
    # (오류 문구는 OS 언어로 현지화되므로 문자열이 아니라 "마커 없음"으로 판별해야 한다.)
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

# 대화형 실행은 별도 터미널 화면에서 시작해 호스트 목록과 tmux 대시보드를
# 같은 화면에서 교체한다. 종료할 때는 반드시 원래 터미널 화면으로 복귀해야 한다.
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

# 세션 목록 아래의 `SSH 직접 연결` 행은 방향키로 선택해 일반 SSH로 접속할 수 있어야 한다.
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

# 세션이 하나도 없어도 목록 마지막의 `＋ New Session` 행으로 새 세션 입력을 열 수 있어야 한다.
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

# 넓은 창(≥88칸)에서는 세션 표에 AGE 컬럼이 펼쳐지고, DIR 은 마지막 이름이 아니라
# 홈을 `~` 로 줄인 전체 경로를 보여야 한다. 좁은 창에서는 AGE 없이 그린다.
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

# `←`는 목록뿐 아니라 검색 행에 포커스가 있어도 즉시 호스트 화면으로 돌아가야 한다.
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

# 검색 결과가 없어도 방향키로 검색 행에 갇히지 않고 세션 목록으로 돌아와야 한다.
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

# 검색한 세션에서 `e`를 누르면 선택한 세션 이름을 수정해야 한다.
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

# 원격이 보낸 세션 필드는 절대 신뢰하지 않는다.
#   - 세션명의 산술 주입(now[$(cmd)])으로 로컬 명령이 실행되면 안 된다(RCE 회귀 방지).
#   - 세션명에 '|' 가 있어도 필드가 밀리지 않아야 한다.
#   - ANSI 이스케이프가 그대로 터미널로 나가면 안 된다.
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

# 실패 사유는 케이스별로 구분해 표기하고 조치 안내를 함께 보여줘야 한다.
#   비POSIX 셸(Windows) vs 원격에 tmux 없음
for mode_case in "windows:non-POSIX shell (e.g. Windows)" "notmux:no tmux on the remote" "timeout:connection failed · no response"; do
  mode=${mode_case%%:*}; want=${mode_case#*:}
  # 사유 분류만 확인하므로 모드별로 빈 로그를 써서 재시도 지연을 피한다.
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

# Windows처럼 tmux를 쓸 수 없는 호스트는 별도 `s` 단축키 없이 Enter로 SSH 셸에 접속해야 한다.
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

# tmux 조회가 불가능하고 세션 행이 하나도 없어도 `←` 뒤로 가기는 동작해야 한다.
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

# 비TTY이면서 애니메이션을 끈 경우에도 작업 시작·완료 상태는 일반 텍스트 한 줄로 남아야 한다.
no_animation_output=$(printf '\n' | HOME="$tmp" PATH="$EZET_FAKE_PATH" NO_COLOR=1 EZET_NO_ANIMATION=1 \
  EZET_FAKE_SSH_MODE=windows EZET_FAKE_SSH_LOG="$fake_ssh_log" "$EZET_BIN" host-b 2>&1)
case "$no_animation_output" in
  *"…  Fetching tmux sessions"*"Cannot fetch tmux sessions"*"Press Enter to quit"*) ;;
  *) printf 'expected non-TTY activity status and dashboard, got: %s\n' "$no_animation_output" >&2; exit 72 ;;
esac
case "$no_animation_output" in
  *"⠋"*) printf 'spinner must be disabled for non-TTY/EZET_NO_ANIMATION\n' >&2; exit 73 ;;
esac

# 전용 config, Include, 권한과 호환성 진단이 정상이어야 한다.
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

# 기존 SSH config는 보존·백업하고, 기존 별칭과 중복되는 ezet Host 생성을 막아야 한다.
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

# 메인 ~/.ssh/config 의 호스트는 ezet 에서 수정·삭제할 수 없으므로 VIA 칸 뒤에
# `ro` 배지를 붙여 구분해야 한다(ezet 전용 config 호스트에는 붙지 않는다).
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

# 폼에서 `<` 는 앞 칸으로 되돌아가고, `q` 는 어느 칸에서든 취소해야 한다.
# 특히 ALIAS 칸의 q 가 별칭으로 저장되면 안 된다(예전에는 취소 키가 없었다).
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

# 수정 폼의 ALIAS 칸에서 q 를 누르면 아무것도 바꾸지 않고 목록으로 돌아가야 한다.
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

# --uninstall 은 ezet 이 넣은 Include 한 줄만 되돌리고, 사용자의 기존 설정과
# 호스트 목록·백업은 절대 건드리지 않아야 한다.
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

# 취소하면 아무것도 바뀌지 않아야 한다.
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
# 멱등: 두 번째 실행은 되돌릴 것이 없다고 알려야 한다.
again=$(printf 'y\n' | HOME="$un_tmp" "$EZET_BIN" --uninstall 2>&1 || true)
case "$again" in *"Nothing to undo"*) ;; *) printf 'uninstall must be idempotent\n' >&2; exit 104 ;; esac
rm -rf "$un_tmp"

printf 'ezet regression tests: PASS\n'
