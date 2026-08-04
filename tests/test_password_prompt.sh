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

# Like the real OpenSSH password prompt, write to the controlling terminal
# rather than to redirected stderr.
printf 'Administrator@192.0.2.10 password: ' > /dev/tty
IFS= read -rs password < /dev/tty
printf '\n' > /dev/tty
[ "$password" = test-password ] || exit 255

# Reproduce a Windows cmd that cannot run the POSIX query script after auth.
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

# While an SSH call may still ask for a password, the fixed "type it or wait"
# notice must come first instead of a spinner.
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

# Once the prompt is open, the spinner must not paint over it again.
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
