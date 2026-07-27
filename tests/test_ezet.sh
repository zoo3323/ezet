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

# 외부 SSH 형식 "포트 user@ip"가 한 번의 입력으로 Host를 생성해야 한다.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "접속 주소*"
send "30001 user@203.0.113.10\r"
expect {
  "별칭*" { send "host-ext\r" }
  "잘못된 접속 주소*" { exit 10 }
  "SSH 외부 포트*" { exit 11 }
  timeout { exit 12 }
}
expect "추가됨*"
send "q"
expect eof
EXPECT

resolved=$(ssh -F "$tmp/.ssh/config" -G host-ext 2>/dev/null)
awk '$1=="hostname" && $2=="203.0.113.10" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="user" && $2=="user" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="port" && $2=="30001" {ok=1} END {exit !ok}' <<< "$resolved"

# 일반 형식 "user@ip"는 포트를 추가로 묻거나 Port 항목을 만들지 않아야 한다.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "n"
expect "접속 주소*"
send "user@192.0.2.20\r"
expect {
  "별칭*" { send "host-a\r" }
  "SSH 외부 포트*" { exit 30 }
  timeout { exit 31 }
}
expect "추가됨*"
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

# 외부 SSH 호스트는 et가 설치돼 있어도 SSH transport를 선택해야 한다.
dryrun=$(HOME="$tmp" EZET_DRYRUN=1 "$EZET_BIN" host-ext probe 2>&1)
case "$dryrun" in
  *"via ssh"*) ;;
  *) printf 'expected external host to use ssh, got: %s\n' "$dryrun" >&2; exit 20 ;;
esac

# 선택한 Host만 확인 후 삭제해야 한다.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "d"
expect {
  "정말 삭제할까요*" { send "y\r" }
  timeout { exit 40 }
}
expect "삭제됨*"
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
expect "입력 (Enter=현재값, q=취소):*"
send "30002 user@198.51.100.20\r"
expect "별칭*"
send "host-edit\r"
expect "변경됨*"
send "q"
expect eof
EXPECT

resolved=$(ssh -F "$tmp/.ssh/config" -G host-edit 2>/dev/null)
awk '$1=="hostname" && $2=="198.51.100.20" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="user" && $2=="user" {ok=1} END {exit !ok}' <<< "$resolved"
awk '$1=="port" && $2=="30002" {ok=1} END {exit !ok}' <<< "$resolved"

# Windows 호스트도 별도 접속 모드 없이 일반 Host로 추가해야 한다.
expect <<'EXPECT'
set timeout 3
spawn env HOME=$env(EZET_TEST_HOME) NO_COLOR=1 $env(EZET_TEST_BIN)
expect "SSH HOSTS*"
send "n"
expect "접속 주소*"
send "user@198.51.100.7\r"
expect "별칭*"
send "host-b\r"
expect "추가됨*"
send "q"
expect eof
EXPECT

if grep -Eiq '^[[:space:]]*#[[:space:]]*ezet:[[:space:]]*mode[[:space:]]*=' "$tmp/.ssh/config.d/ezet"; then
  printf 'per-host connection mode metadata must not be written\n' >&2
  exit 60
fi

# 모든 세션 선택기의 마지막 항목에 SSH SHELL이 있어야 한다. 한 번 아래로 이동해
# 선택하면 원격 tmux 명령 없이 정확히 `ssh -t HOST`를 실행해야 한다.
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

has_tty=0
has_short_timeout=0
has_one_attempt=0
expect_ssh_option=0
positionals=0
plain_host=
for arg in "$@"; do
  if [ "$expect_ssh_option" -eq 1 ]; then
    case "$arg" in
      ConnectTimeout=*)
        timeout_value=${arg#ConnectTimeout=}
        case "$timeout_value" in
          ''|*[!0-9]*) ;;
          *)
            if [ "$timeout_value" -ge 1 ] && [ "$timeout_value" -le 10 ]; then
              has_short_timeout=1
            fi
            ;;
        esac
        ;;
      ConnectionAttempts=1) has_one_attempt=1 ;;
    esac
    expect_ssh_option=0
    continue
  fi
  case "$arg" in
    -t) has_tty=1 ;;
    -o) expect_ssh_option=1 ;;
    -*) ;;
    *)
      positionals=$((positionals + 1))
      [ "$positionals" -eq 1 ] && plain_host=$arg
      ;;
  esac
done

if [ "$has_tty" -eq 1 ]; then
  if [ "${EZET_FAKE_SSH_MODE:-sessions}" = timeout ]; then
    printf 'TIMEOUT_PLAIN\t%s\tpositionals=%s\ttimeout=%s\tattempts=%s\n' \
      "$plain_host" "$positionals" "$has_short_timeout" "$has_one_attempt" >> "$EZET_FAKE_SSH_LOG"
    if [ "$positionals" -eq 1 ] && [ "$has_short_timeout" -eq 1 ] && [ "$has_one_attempt" -eq 1 ]; then
      exit 255
    fi
    sleep 3
    exit 124
  fi
  if [ "$positionals" -eq 1 ]; then
    printf 'PLAIN\t%s\n' "$plain_host" >> "$EZET_FAKE_SSH_LOG"
    exit 0
  fi
fi

printf 'REMOTE' >> "$EZET_FAKE_SSH_LOG"
for arg in "$@"; do printf '\t%s' "$arg" >> "$EZET_FAKE_SSH_LOG"; done
printf '\n' >> "$EZET_FAKE_SSH_LOG"

case "${EZET_FAKE_SSH_MODE:-sessions}" in
  sessions)
    printf '%s\n' \
      '__DT_CONNECTED__' \
      '__DT_TMUX__=/usr/bin/tmux' \
      '__DT_NOW__=1700000000' \
      '__DT_SESSION__|work|1||1699999900|bash|/home/user'
    ;;
  multi)
    case "$*" in
      *capture-pane*) printf 'PANE_OF_SECOND\n'; exit 0 ;;
    esac
    printf '%s\n' \
      '__DT_CONNECTED__' \
      '__DT_TMUX__=/usr/bin/tmux' \
      '__DT_NOW__=1700000000' \
      '__DT_SESSION__|alpha|1||1699999900|bash|/home/user' \
      '__DT_SESSION__|bravo|1||1699999900|bash|/home/user'
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
    # 실패한 일반 SSH 직후 ezet이 자동 재조회하면 동일한 네트워크 지연이 한 번 더 생긴다.
    # 그 중복 시도까지 회귀 테스트가 잡도록 두 번째 probe를 느리게 만든다.
    if grep -q '^TIMEOUT_PLAIN' "$EZET_FAKE_SSH_LOG"; then sleep 3; fi
    printf '%s\n' 'ssh: connect to host 198.51.100.7 port 22: Operation timed out' >&2
    exit 255
    ;;
esac
FAKE_SSH
chmod +x "$fake_bin/ssh"

expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=sessions EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "tmux 세션 조회 중*"
expect "tmux 세션 조회 완료*"
expect "work*"
expect "SSH shell*"
send "\033\[B"
expect "SSH shell*"
send "\r"
expect "SSH SHELL*연결 중*"
expect {
  eof {}
  "세션 목록 새로고침*" { exit 74 }
  timeout { exit 75 }
}
EXPECT

awk -F '\t' '$1=="PLAIN" && $2=="host-b" && NF==2 {found=1} END {exit !found}' "$fake_ssh_log"

# 미리보기(p) 후 목록으로 돌아와도 커서가 그대로여야 한다.
# 커서가 첫 항목으로 튀면 이어지는 r/d 가 엉뚱한 세션에 적용된다(실서버에서 발생했던 버그).
printf '' > "$fake_ssh_log"
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=multi EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "tmux 세션 조회 완료*"
expect -re {› alpha}
send "\033\[B"
expect -re {› bravo}
send "p"
expect {
  "PANE_OF_SECOND" {}
  timeout { exit 80 }
}
send " "
expect {
  -re {› bravo} {}
  -re {› alpha} { exit 81 }
  timeout { exit 82 }
}
send "q"
expect eof
EXPECT

# 실패 사유는 케이스별로 구분해 표기하고 조치 안내를 함께 보여줘야 한다.
#   비POSIX 셸(Windows) vs 원격에 tmux 없음
for mode_case in "windows:Windows 등 비POSIX 셸" "notmux:원격에 tmux 없음" "timeout:연결 실패 · 응답 없음"; do
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
    timeout) hint_want="확인하세요" ;;
    *)       hint_want="SSH 셸로 접속" ;;
  esac
  case "$out" in
    *"$hint_want"*) ;;
    *) printf 'expected actionable hint for mode %s\n' "$mode" >&2; exit 91 ;;
  esac
  case "$out" in
    *"tmux 사용 불가"*) ;;
    *) printf 'expected korean unavailable label for mode %s\n' "$mode" >&2; exit 92 ;;
  esac
done

# Windows cmd 응답처럼 tmux 조회 자체가 실패해도 종료하지 않고 SSH SHELL을 선택할 수 있어야 한다.
printf '' > "$fake_ssh_log"
expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=windows EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "tmux 세션 조회 중*"
expect "tmux 세션 조회 불가*"
expect "tmux unavailable*"
expect "SSH shell*"
send "\r"
expect "SSH SHELL*연결 중*"
expect {
  eof {}
  "세션 목록 새로고침*" { exit 76 }
  timeout { exit 77 }
}
EXPECT

awk -F '\t' '$1=="PLAIN" && $2=="host-b" && NF==2 {found=1} END {exit !found}' "$fake_ssh_log"

# 접속 불가 호스트에서 SSH SHELL을 골라도 짧은 SSH 타임아웃을 적용해 UI가 오래 멈추지 않아야 한다.
# fake ssh는 ConnectTimeout과 ConnectionAttempts가 모두 없으면 3초간 멈추므로, 2초 안에
# 선택 화면이 다시 나타나야 한다. positionals=1 검사는 호스트 뒤에 원격 명령이 없다는 뜻이다.
printf '' > "$fake_ssh_log"
expect <<'EXPECT'
set timeout 2
spawn env HOME=$env(EZET_TEST_HOME) PATH=$env(EZET_FAKE_PATH) NO_COLOR=1 EZET_FAKE_SSH_MODE=timeout EZET_FAKE_SSH_LOG=$env(EZET_FAKE_SSH_LOG) $env(EZET_TEST_BIN) host-b
expect "tmux 세션 조회 중*"
expect "tmux 세션 조회 불가*"
expect "tmux unavailable*"
expect "SSH shell*"
send "\r"
expect {
  "SSH SHELL*연결 중*" {}
  timeout { exit 70 }
  eof { exit 71 }
}
expect "연결 실패 (status 255)*"
expect "tmux unavailable*"
expect "SSH shell*"
send "q"
expect eof
EXPECT

awk -F '\t' '
  $1=="TIMEOUT_PLAIN" && $2=="host-b" && $3=="positionals=1" && $4=="timeout=1" && $5=="attempts=1" {found=1}
  END {exit !found}
' "$fake_ssh_log"

# 비TTY이면서 애니메이션을 끈 경우에도 작업 시작·완료 상태는 일반 텍스트 한 줄로 남아야 한다.
no_animation_output=$(printf '\n' | HOME="$tmp" PATH="$EZET_FAKE_PATH" NO_COLOR=1 EZET_NO_ANIMATION=1 \
  EZET_FAKE_SSH_MODE=windows EZET_FAKE_SSH_LOG="$fake_ssh_log" "$EZET_BIN" host-b 2>&1)
case "$no_animation_output" in
  *"…  tmux 세션 조회 중"*"tmux 세션 조회 불가"*"SSH shell"*) ;;
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
send "n"
expect "접속 주소*"
send "user@192.0.2.51\r"
expect "별칭*"
send "legacy\r"
expect {
  "이미 존재하는 별칭입니다*" { send "fresh\r" }
  timeout { exit 50 }
}
expect "추가됨*"
send "q"
expect eof
EXPECT

printf 'ezet regression tests: PASS\n'
