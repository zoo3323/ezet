# ezet

SSH · [Eternal Terminal](https://eternalterminal.dev/) · tmux 원격 세션을 골라 접속하는 대화형 CLI.
순수 Bash, 외부 의존성 없음.

[![test](https://github.com/zoo3323/ezet/actions/workflows/test.yml/badge.svg)](https://github.com/zoo3323/ezet/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey)
![shell](https://img.shields.io/badge/shell-bash%203.2%2B-4EAA25?logo=gnubash&logoColor=white)

- 호스트를 골라 접속 — SSH config 편집 없이 추가·수정·삭제
- 호스트 목록 순서를 직접 바꾸고 다음 실행에도 유지
- 별도 터미널 화면에서 실행되는 TUI — 종료하면 원래 셸 화면으로 복귀
- 원격 tmux 세션 attach·생성·수정
- Windows 등 tmux를 쓸 수 없는 호스트는 SSH 셸로 직접 접속
- Eternal Terminal 우선 접속으로 네트워크가 바뀌어도 자동 재연결 (없으면 `ssh` 폴백)
- 외부망 포트포워딩 환경에서 SSH 포트와 ET 포트를 각각 설정
- 호스트·세션 목록 맨 위의 검색 행에서 즉시 필터링

---

## 사용 화면

**호스트 선택** — `ezet`

<img src="docs/img/hosts.svg" alt="호스트 선택 화면" width="620">

**세션 선택** — `ezet dev`

<img src="docs/img/sessions.svg" alt="세션 선택 화면" width="760">

---

## 설치

**Homebrew** (macOS · Linux)

```bash
brew install zoo3323/tap/ezet
```

**설치 스크립트** — 내려받기·실행 권한·PATH 안내·의존성 점검까지 처리합니다.

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash
```

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

외부망에서 공유기 포트포워딩으로 접속한다면 SSH와 ET 포트를 각각 열어야 합니다. 예:

```text
공인IP:30001/TCP  →  원격 호스트:22/TCP    (SSH)
공인IP:32022/TCP  →  원격 호스트:2022/TCP  (Eternal Terminal)
```

호스트 추가·수정 화면에서 접속 주소는 `30001 user@공인IP`, 이어지는 `ET 외부 포트`에는 `32022`를 입력합니다. ET 포트를 열지 않았다면 Enter를 눌러 SSH만 사용할 수 있지만, 이 경우 잠자기·네트워크 전환 후 자동 재연결은 되지 않습니다.
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
| 원격 `tmux` | 선택 | 없으면 SSH 셸로 직접 접속 |

로컬 tmux는 필요 없습니다.

---

## 사용법

```bash
ezet                 # 호스트 목록에서 선택
ezet <host>          # 해당 호스트의 세션 목록
ezet <host> <name>   # 세션에 바로 attach (없으면 생성)
ezet --doctor        # 설정 점검
ezet --uninstall     # 추가한 Include 한 줄만 제거
ezet --version
ezet --help
```

**호스트 목록**

첫 번째 호스트에서 `↑`를 누르면 제목 아래의 검색 행으로 이동합니다. 검색어를 입력한 뒤 `↓`로 결과 목록을 탐색합니다.
목록 아래의 `＋ 새 호스트` 행을 선택하고 `Enter`를 눌러도 호스트를 추가할 수 있습니다.

| 키 | 동작 |
|---|---|
| `↑` `↓` | 이동 |
| `Enter` | 접속 |
| `o` | 순서 편집 (`↑` `↓` 이동, `Enter` 완료) |
| `e` `d` | 수정 · 삭제 |
| `q` | 종료 |

**세션 목록**

호스트 목록과 마찬가지로 첫 번째 항목에서 `↑`를 누르면 검색 행으로 이동합니다. 표 우측 위의 `← 뒤로` 안내처럼 왼쪽 화살표를 누르면 호스트 목록으로 돌아갑니다.
검색 결과가 없을 때도 `↑`·`↓`로 검색 행을 빠져나올 수 있습니다.

| 키 | 동작 |
|---|---|
| `↑` `↓` | 이동 |
| `Enter` | attach (없으면 생성) |
| `e` | 수정 |
| `←` | 호스트 목록 |
| `q` | 종료 |

tmux를 사용할 수 있는 호스트에서는 세션 목록 아래에 `＋ 새 세션`과 `SSH 셸` 행이 표시됩니다. 각 행을 방향키로 선택하고 `Enter`를 누르면 새 세션을 만들거나 일반 SSH 셸로 접속합니다. Windows·비POSIX 셸 또는 tmux가 없는 호스트에서는 `SSH 셸` 행 하나만 표시됩니다.

세션을 조회할 때 SSH 인증이 필요할 수 있는 동안에는 로딩 애니메이션 대신 고정된 `SSH 인증 확인` 안내가 표시됩니다. 비밀번호 프롬프트가 나타나면 입력하면 되고(입력 문자는 보이지 않음), 프롬프트가 없으면 연결 중이므로 잠시 기다리면 됩니다.

---

## SSH 설정

ezet 이 추가하는 호스트는 `~/.ssh/config.d/ezet` 에만 저장되고, 기존 `~/.ssh/config` 에는 `Include` 한 줄만 덧붙습니다(수정 전 `~/.ssh/config.ezet-backup` 백업 생성). 직접 정의해 둔 Host 도 목록에 흐리게 표시되며 접속만 가능하고 건드리지 않습니다.

호스트 목록에서 `o`를 누르면 순서 편집 화면으로 전환됩니다. `↑`·`↓`로 선택한 항목을 옮기고 `Enter`로 완료합니다. 순서는 `~/.ssh/config.d/ezet.order`에 저장되므로 ezet을 다시 실행해도 유지되며, 직접 작성한 SSH Host의 순서도 바꿀 수 있습니다. 새로 추가되거나 직접 작성한 Host는 기존 목록 뒤에 자동으로 나타납니다.

외부망 호스트에 ET 포트를 지정하면 아래처럼 OpenSSH가 무시하는 주석으로 함께 저장합니다. ezet은 이 값을 읽어 `et -p 32022 host-ext`로 접속합니다.

```sshconfig
Host host-ext
    HostName 203.0.113.10
    User user
    Port 30001
    # ezet: et-port 32022
```

기존 외부망 호스트는 `e`로 수정한 뒤 접속 주소는 Enter로 유지하고 ET 외부 포트만 입력하면 됩니다. ET를 다시 끄려면 같은 화면에서 `-`를 입력합니다.

되돌리려면 `ezet --uninstall` — 추가했던 `Include` 한 줄만 제거하고, 호스트 목록과 백업 파일은 그대로 둡니다.

<details>
<summary>환경 변수</summary>

| 변수 | 기본값 | 설명 |
|---|---|---|
| `EZET_SSH_CONNECT_TIMEOUT` | `5` | SSH 연결 대기(초), 1~60 |
| `EZET_NO_MULTIPLEX` | | `1` 이면 SSH 연결 재사용 끔 |
| `EZET_NO_ANIMATION` | | `1` 이면 스피너 끔 |
| `EZET_NO_ALT_SCREEN` | | `1` 이면 터미널 대체 화면을 사용하지 않음 |
| `EZET_CONTROL_DIR` | `~/.ssh/ezet-cm` | 멀티플렉싱 소켓 위치 |
| `EZET_HOST_ORDER_FILE` | `~/.ssh/config.d/ezet.order` | 호스트 목록 순서 저장 위치 |
| `EZET_DRYRUN` | | `1` 이면 접속 대신 대상만 출력 |

세션 조회·새로고침·수정은 SSH 마스터 연결을 재사용합니다(OpenSSH 6.7+ 자동, `et` 접속에는 영향 없음).
</details>

---

## 라이선스

[MIT](LICENSE)
