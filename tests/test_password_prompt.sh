#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
EZET_BIN="$ROOT/bin/ezet"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/.ssh/config.d" "$tmp/fake-bin"
printf 'Include %s\n' "$tmp/.ssh/config.d/ezet" > "$tmp/.ssh/config"
printf '%s\n' \
  'Host prompt-host' \
  '    HostName 192.0.2.10' \
  '    User Administrator' > "$tmp/.ssh/config.d/ezet"
chmod 600 "$tmp/.ssh/config" "$tmp/.ssh/config.d/ezet"

real_ssh=$(command -v ssh)
export EZET_PROMPT_REAL_SSH="$real_ssh"

cat > "$tmp/fake-bin/ssh" <<'FAKE_SSH'
#!/usr/bin/env bash
set -eu

for arg in "$@"; do
  case "$arg" in
    -V|-G) exec "$EZET_PROMPT_REAL_SSH" "$@" ;;
  esac
done

# 실제 OpenSSH 비밀번호 프롬프트처럼 리디렉션된 stderr가 아니라 제어 터미널에 쓴다.
printf 'Administrator@192.0.2.10 password: ' > /dev/tty
IFS= read -rs password < /dev/tty
printf '\n' > /dev/tty
[ "$password" = test-password ] || exit 255

# 인증 뒤 Windows cmd가 POSIX 조회 스크립트를 실행하지 못하는 상황을 재현한다.
printf '%s\n' "'valid_tmux_path' is not recognized as an internal or external command" >&2
FAKE_SSH
chmod +x "$tmp/fake-bin/ssh"

export EZET_PROMPT_HOME="$tmp"
export EZET_PROMPT_PATH="$tmp/fake-bin:/usr/bin:/bin"
export EZET_PROMPT_BIN="$EZET_BIN"

expect <<'EXPECT'
set timeout 5
spawn env HOME=$env(EZET_PROMPT_HOME) PATH=$env(EZET_PROMPT_PATH) TERM=xterm-256color \
  NO_COLOR=1 EZET_NO_MULTIPLEX=1 $env(EZET_PROMPT_BIN) prompt-host

# 인증 가능한 SSH 호출 중에는 스피너가 아니라 입력/대기 상태를 구분하는 고정 안내가 먼저 보여야 한다.
expect {
  -re {SSH auth check[^\r\n]*} {}
  -re {Fetching tmux sessions[^\r\n]*} { exit 120 }
  timeout { exit 121 }
}
expect {
  -re {Type your password if prompted[^\r\n]*} {}
  timeout { exit 122 }
}
expect {
  -re {password:[^\r\n]*} {}
  timeout { exit 123 }
}

# 프롬프트가 열린 뒤에도 스피너가 다시 덮어쓰면 안 된다.
set timeout 1
expect {
  -re {Fetching tmux sessions[^\r\n]*} { exit 124 }
  timeout {}
}
set timeout 5
send "test-password\r"
expect "Cannot fetch tmux sessions*"
expect "SSH Direct*"
send "q"
expect eof
EXPECT

printf 'ezet password prompt regression test: PASS\n'
