#!/usr/bin/env bash
# ezet installer
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash
#
# What it does:
#   1) downloads bin/ezet into ~/.local/bin and makes it executable
#   2) explains how to add that directory when it is not on PATH
#   3) prints the OS-specific command for the optional dependency (Eternal Terminal)
#   4) checks the result with ezet --doctor
#
# Environment:
#   EZET_INSTALL_DIR   install directory (default ~/.local/bin)
#   EZET_REF           git ref to download (default main)
set -euo pipefail

REPO="zoo3323/ezet"
REF="${EZET_REF:-main}"
BINDIR="${EZET_INSTALL_DIR:-$HOME/.local/bin}"
RAW="https://raw.githubusercontent.com/$REPO/$REF/bin/ezet"

c_g=''; c_y=''; c_b=''; c_d=''; c_r=''
if [ -t 1 ]; then c_g=$'\e[32m'; c_y=$'\e[33m'; c_b=$'\e[1m'; c_d=$'\e[2m'; c_r=$'\e[0m'; fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '  %s✓%s %s\n' "$c_g" "$c_r" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_y" "$c_r" "$*"; }
step() { printf '\n%s==>%s %s\n' "$c_b" "$c_r" "$*"; }

os="$(uname -s 2>/dev/null || echo unknown)"

# ── 1) Download ──────────────────────────────────────────────
step "Downloading ezet  ($REF -> $BINDIR/ezet)"
mkdir -p "$BINDIR"
tmp="$BINDIR/.ezet.download.$$"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$RAW" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp" "$RAW"
else
  say "curl or wget is required." >&2
  rm -f "$tmp" 2>/dev/null || true
  exit 1
fi
# Minimal sanity check that what we downloaded is the script
if ! head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash'; then
  say "The downloaded file does not look right. Please try again in a moment." >&2
  rm -f "$tmp" 2>/dev/null || true
  exit 1
fi
chmod +x "$tmp"
mv "$tmp" "$BINDIR/ezet"
ok "Installed: $BINDIR/ezet"

# ── 2) Check PATH ────────────────────────────────────────────
step "Checking PATH"
case ":$PATH:" in
  *":$BINDIR:"*) ok "$BINDIR is already on PATH" ;;
  *)
    warn "$BINDIR is not on PATH. Add this line to your shell config:"
    rc="$HOME/.bashrc"
    case "${SHELL:-}" in *zsh) rc="$HOME/.zshrc" ;; esac
    # $PATH stays literal here: this is a command for the user to copy (the single
    # quotes are intentional).
    # shellcheck disable=SC2016
    printf '\n    echo '\''export PATH="%s:$PATH"'\'' >> %s && source %s\n' "$BINDIR" "$rc" "$rc"
    ;;
esac

# ── 3) Optional dependency: Eternal Terminal ─────────────────
step "Checking the optional dependency (Eternal Terminal)"
if command -v et >/dev/null 2>&1; then
  ok "Eternal Terminal is installed - sessions reconnect across network changes"
else
  warn "Eternal Terminal (et) is missing. ezet works over ssh without it, but installing it turns on auto-reconnect:"
  case "$os" in
    Darwin)
      printf '\n    brew install eternal-terminal\n' ;;
    Linux)
      if command -v apt-get >/dev/null 2>&1; then
        printf '\n    sudo add-apt-repository ppa:jgmath2000/et -y\n'
        printf '    sudo apt-get update && sudo apt-get install -y et\n'
      elif command -v dnf >/dev/null 2>&1; then
        printf '\n    sudo dnf copr enable jgmath2000/et -y && sudo dnf install -y et\n'
      elif command -v pacman >/dev/null 2>&1; then
        printf '\n    # AUR: yay -S eternalterminal\n'
      else
        printf '\n    # Install guide: https://eternalterminal.dev/\n'
      fi ;;
    *)
      printf '\n    # Install guide: https://eternalterminal.dev/\n' ;;
  esac
  say "  ${c_d}Note: auto-reconnect also needs etserver on the remote host.${c_r}"
fi

# ── 4) Verify ────────────────────────────────────────────────
step "Verifying the install"
if "$BINDIR/ezet" --doctor; then
  printf '\n%sDone.%s  Run %sezet%s to start.\n' "$c_b" "$c_r" "$c_b" "$c_r"
else
  printf '\nInstalled, but the check reported warnings or errors. See the --doctor output above.\n' >&2
fi
