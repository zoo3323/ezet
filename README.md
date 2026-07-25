# ezet

SSH · [Eternal Terminal](https://eternalterminal.dev/) · tmux 원격 세션을 골라 접속하는 대화형 CLI.
순수 Bash, 외부 의존성 없음.

[![test](https://github.com/zoo3323/ezet/actions/workflows/test.yml/badge.svg)](https://github.com/zoo3323/ezet/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)
![shell](https://img.shields.io/badge/shell-bash%203.2%2B-4EAA25?logo=gnubash&logoColor=white)

- 호스트를 골라 접속 — SSH config 편집 없이 추가·수정·삭제
- 원격 tmux 세션 attach·생성·이름변경·미리보기
- Eternal Terminal 우선 접속으로 네트워크가 바뀌어도 자동 재연결 (없으면 `ssh` 폴백)
- `/` 로 호스트·세션 즉시 검색

---

## 사용 화면

**호스트 선택** — `ezet`

<img src="docs/img/hosts.svg" alt="호스트 선택 화면" width="620">

**세션 선택** — `ezet dev`

<img src="docs/img/sessions.svg" alt="세션 선택 화면" width="760">

**검색** — `/` 입력

<img src="docs/img/search.svg" alt="검색 화면" width="620">

---

## 설치

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash
```

내려받기·실행 권한·PATH 안내·의존성 점검까지 처리합니다.
`wget` 사용 시: `wget -qO- https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash`

<details>
<summary>Eternal Terminal 설치 (선택)</summary>

없어도 `ssh` 로 동작합니다. 설치하면 자동 재연결이 켜집니다.

```bash
# macOS
brew install eternal-terminal

# Ubuntu / Debian
sudo add-apt-repository ppa:jgmath2000/et -y
sudo apt-get update && sudo apt-get install -y et

# Fedora
sudo dnf copr enable jgmath2000/et -y && sudo dnf install -y et
```

원격 서버에도 `etserver` 가 있어야 ET 모드로 접속합니다.
</details>

<details>
<summary>수동 설치</summary>

```bash
mkdir -p ~/.local/bin
curl -fsSL -o ~/.local/bin/ezet https://raw.githubusercontent.com/zoo3323/ezet/main/bin/ezet
chmod +x ~/.local/bin/ezet
```
</details>

---

## 요구 사항

| 항목 | 필수 | 비고 |
|---|---|---|
| Bash 3.2+ | ✅ | macOS 기본 Bash |
| `ssh` (OpenSSH) | ✅ | |
| `et` ([Eternal Terminal](https://eternalterminal.dev/)) | 선택 | 자동 재연결 |
| 원격 `tmux` | 선택 | 없으면 SSH 셸로 접속 |

로컬 tmux는 필요 없습니다.

---

## 사용법

```bash
ezet                 # 호스트 목록에서 선택
ezet <host>          # 해당 호스트의 세션 목록
ezet <host> <name>   # 세션에 바로 attach (없으면 생성)
ezet --doctor        # 설정 점검
ezet --version
ezet --help
```

**호스트 목록**

| 키 | 동작 |
|---|---|
| `↑` `↓` | 이동 |
| `Enter` | 접속 |
| `/` | 검색 (`Esc` 취소) |
| `n` `e` `d` | 추가 · 수정 · 삭제 |
| `q` | 종료 |

**세션 목록**

| 키 | 동작 |
|---|---|
| `↑` `↓` | 이동 |
| `Enter` | attach (없으면 생성) |
| `s` | SSH 셸 접속 |
| `p` | 세션 미리보기 |
| `n` `r` | 새 세션 · 이름 변경 |
| `/` | 검색 |
| `b` `←` | 호스트 목록 |
| `q` | 종료 |

---

## SSH 설정

호스트는 `~/.ssh/config.d/ezet` 에 저장되고, 기본 설정에는 Include 한 줄만 추가됩니다.

```sshconfig
# ~/.ssh/config
Include "~/.ssh/config.d/ezet"
```

- 최초 실행 시 파일(`600`)과 디렉터리(`700`)를 생성하고, 기존 config가 있으면 `~/.ssh/config.ezet-backup` 을 한 번 만듭니다.
- `~/.ssh/config` 에 직접 정의한 Host도 목록에 흐리게 표시되며, 접속만 가능하고 수정·삭제하지 않습니다. 매칭 패턴(`*` `?` `!` `[ ]`)은 제외됩니다.

---

## 환경 변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `EZET_SSH_CONNECT_TIMEOUT` | `5` | SSH 연결 대기(초), 1~60 |
| `EZET_NO_MULTIPLEX` | | `1` 이면 SSH 연결 재사용 끔 |
| `EZET_NO_ANIMATION` | | `1` 이면 스피너 끔 |
| `EZET_CONTROL_DIR` | `~/.ssh/ezet-cm` | 멀티플렉싱 소켓 위치 |
| `EZET_DRYRUN` | | `1` 이면 접속 대신 대상만 출력 |

세션 조회·새로고침·이름변경은 SSH 마스터 연결을 재사용합니다(OpenSSH 6.7+ 자동, `et` 접속에는 영향 없음).

---

## 개발

```bash
make test
```

`expect` 로 대화형 UI를 구동하고 `shellcheck` 로 정적 분석합니다. 테스트는 임시 `HOME` 을 사용합니다.

---

## 라이선스

[MIT](LICENSE)
