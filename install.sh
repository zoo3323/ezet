#!/usr/bin/env bash
# ezet 설치 스크립트
#   curl -fsSL https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash
#
# 하는 일:
#   1) bin/ezet 를 ~/.local/bin 에 내려받아 실행 권한 부여
#   2) PATH 에 없으면 추가 방법 안내
#   3) 선택 의존성(Eternal Terminal)이 없으면 OS에 맞는 설치 명령을 안내
#   4) ezet --doctor 로 상태 점검
#
# 환경변수:
#   EZET_INSTALL_DIR   설치 경로(기본 ~/.local/bin)
#   EZET_REF           내려받을 git 참조(기본 main)
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

# ── 1) 다운로드 ───────────────────────────────────────────────
step "ezet 내려받는 중  ($REF → $BINDIR/ezet)"
mkdir -p "$BINDIR"
tmp="$BINDIR/.ezet.download.$$"
if command -v curl >/dev/null 2>&1; then
  curl -fsSL "$RAW" -o "$tmp"
elif command -v wget >/dev/null 2>&1; then
  wget -qO "$tmp" "$RAW"
else
  say "curl 또는 wget 이 필요합니다." >&2
  rm -f "$tmp" 2>/dev/null || true
  exit 1
fi
# 받은 파일이 정상 스크립트인지 최소 검증
if ! head -n1 "$tmp" | grep -q '^#!/usr/bin/env bash'; then
  say "다운로드 내용이 올바르지 않습니다. 잠시 후 다시 시도해주세요." >&2
  rm -f "$tmp" 2>/dev/null || true
  exit 1
fi
chmod +x "$tmp"
mv "$tmp" "$BINDIR/ezet"
ok "설치됨: $BINDIR/ezet"

# ── 2) PATH 확인 ─────────────────────────────────────────────
step "PATH 확인"
case ":$PATH:" in
  *":$BINDIR:"*) ok "$BINDIR 가 이미 PATH 에 있습니다" ;;
  *)
    warn "$BINDIR 가 PATH 에 없습니다. 아래 한 줄을 셸 설정에 추가하세요:"
    rc="$HOME/.bashrc"
    case "${SHELL:-}" in *zsh) rc="$HOME/.zshrc" ;; esac
    # $PATH 는 사용자에게 보여줄 리터럴 명령이므로 확장하지 않는다(single quote 의도적).
    # shellcheck disable=SC2016
    printf '\n    echo '\''export PATH="%s:$PATH"'\'' >> %s && source %s\n' "$BINDIR" "$rc" "$rc"
    ;;
esac

# ── 3) 선택 의존성: Eternal Terminal ──────────────────────────
step "선택 의존성 확인 (Eternal Terminal)"
if command -v et >/dev/null 2>&1; then
  ok "Eternal Terminal 설치됨 — 네트워크가 바뀌어도 자동 재연결됩니다"
else
  warn "Eternal Terminal(et)이 없습니다. 없어도 ssh 로 동작하지만, 설치하면 자동 재연결이 켜집니다:"
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
        printf '\n    # 설치 안내: https://eternalterminal.dev/\n'
      fi ;;
    *)
      printf '\n    # 설치 안내: https://eternalterminal.dev/\n' ;;
  esac
  say "  ${c_d}참고: Eternal Terminal 자동 재연결은 원격 서버에도 etserver 가 있어야 동작합니다.${c_r}"
fi

# ── 4) 상태 점검 ─────────────────────────────────────────────
step "설치 점검"
if "$BINDIR/ezet" --doctor; then
  printf '\n%s설치 완료.%s  이제 %sezet%s 를 실행하세요.\n' "$c_b" "$c_r" "$c_b" "$c_r"
else
  printf '\n설치는 됐지만 점검에서 경고/오류가 있습니다. 위 --doctor 결과를 확인하세요.\n' >&2
fi
