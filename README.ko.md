# ezet

[English](README.md) · 한국어

SSH·[Eternal Terminal](https://eternalterminal.dev/)·tmux 호스트와 세션을 고르는 대화형 CLI입니다. 순수 Bash로 동작하며, ET를 사용할 수 없으면 SSH로 자동 전환합니다.

- **tmux 세션 관리** — 원격 세션을 조회·생성·수정하고 바로 attach합니다.
- **자동 재연결** — Eternal Terminal(ET)을 우선 사용해 노트북을 닫거나 네트워크가 바뀌어도 세션을 유지·재연결합니다.
- **SSH 폴백** — ET를 설치하지 않았거나 tmux를 사용할 수 없는 호스트는 일반 SSH로 접속합니다.

[![test](https://github.com/zoo3323/ezet/actions/workflows/test.yml/badge.svg)](https://github.com/zoo3323/ezet/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## 사용 화면

호스트와 tmux 세션을 한 화면에서 선택합니다.

호스트 선택:

<img src="docs/img/hosts.svg" alt="호스트 선택 화면" width="780">

검색으로 목록 좁히기:

<img src="docs/img/search.svg" alt="호스트 검색 화면" width="780">

tmux 세션 선택:

<img src="docs/img/sessions.svg" alt="tmux 세션 선택 화면" width="780">

새 호스트 추가:

<img src="docs/img/add-host.svg" alt="새 호스트 추가 화면" width="780">

## 설치

```bash
brew install zoo3323/tap/ezet
```

또는:

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash
```

ET 자동 재연결을 사용하려면 로컬에 `et`, 원격 호스트에 `etserver`를 설치하세요. 설치하지 않아도 SSH로 접속할 수 있습니다.

## 사용

```bash
ezet                 # 호스트 선택
ezet <host>          # 세션 선택
ezet <host> <name>   # 세션 바로 연결
ezet --doctor        # 설정 점검
ezet --version
```

화면에서는 방향키로 이동하고 `Enter`로 선택합니다. 호스트 화면에서 호스트를 추가·수정·삭제하고 순서를 변경할 수 있으며, 세션 화면에서 tmux 세션을 attach·생성하거나 `SSH Direct` 행으로 tmux 없이 접속할 수 있습니다. `q`는 종료, `←`는 이전 화면입니다.

추가·수정 폼에서는 `Enter`가 표시된 기본값을 그대로 받고, `<`는 앞 칸으로, `q`는 취소입니다.

## 요구 사항

- Bash 3.2+
- OpenSSH (`ssh`)
- Eternal Terminal (`et`, 선택)
- 원격 `tmux` (선택; 없으면 `SSH Direct` 로 접속)

로컬 tmux는 필요하지 않습니다.

## SSH 설정

ezet 호스트는 `~/.ssh/config.d/ezet`에 저장됩니다. 기존 설정에는 `Include` 한 줄만 추가하며, 변경 전 백업을 만듭니다. ET 포트는 다음처럼 주석으로 저장됩니다.

```sshconfig
Host host-ext
    HostName 203.0.113.10
    User user
    Port 30001
    # ezet: et-port 30002
```

`ezet --uninstall`은 ezet이 추가한 `Include`만 제거합니다.

## 개발

```bash
make test    # 회귀 테스트 (bash -n, shellcheck, expect)
make docs    # README 스크린샷을 실제 TUI 에서 다시 생성
```

`make docs`는 고정 픽스처로 실제 TUI를 expect로 몰아 터미널 출력을 그대로 SVG로 바꿉니다. 그래서 스크린샷이 UI와 어긋날 수 없습니다.

## 라이선스

[MIT](LICENSE)
