# ezet

[English](README.md) · 한국어

SSH·[Eternal Terminal](https://eternalterminal.dev/)·tmux 호스트와 세션을 고르는 대화형 CLI입니다. 순수 Bash로 동작하며, ET를 사용할 수 없으면 SSH로 자동 전환합니다.

- **tmux 세션 관리** — 원격 세션을 조회·생성·수정하고 바로 attach합니다.
- **자동 재연결** — Eternal Terminal(ET)을 우선 사용해 노트북을 닫거나 네트워크가 바뀌어도 세션을 유지·재연결합니다.
- **선택적 세션 종료** — ezet은 명시적으로 활성화한 Host에서 지원되는 ET 클라이언트에만 `--close-on-hangup`을 전달합니다. 연결 상태에 따라 종료 요청이 전달되지 않을 수 있고, ET 구성요소 버전도 맞아야 합니다.
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

## 지원 플랫폼

ezet은 **macOS와 Linux**에서 동작합니다(WSL 포함 — WSL은 스스로를 Linux로 보고합니다).
두 환경 모두 푸시마다 CI 매트릭스로 검증됩니다.

**윈도우에서 직접 실행하는 것은 지원하지 않습니다.** `--doctor`가 Git Bash·MSYS2를
거부합니다. ezet이 기록하는 `Include` 줄이 MSYS 경로(`/c/Users/...`)여서 Windows
OpenSSH가 해석할 수 없기 때문입니다. 윈도우에서는 WSL을 쓰세요.

**원격 호스트가 윈도우인 경우는 지원합니다.** 셸이 POSIX가 아니라 tmux 조회를 실행할
수 없는데, ezet이 이를 감지해 `non-POSIX shell (e.g. Windows)`로 표시하고 tmux 없이
접속하는 `SSH Direct` 행을 제공합니다. 이 경로는 실제 cmd.exe 동작(여러 줄 명령의 첫
줄만 실행하고 종료코드 0)을 재현하는 대역으로 테스트에서 검증합니다.

## SSH 설정

ezet 호스트는 `~/.ssh/config.d/ezet`에 저장됩니다. 기존 설정에는 `Include` 한 줄만 추가하며, 변경 전 백업을 만듭니다. ET 포트는 다음처럼 주석으로 저장됩니다.

```sshconfig
Host host-ext
    HostName 203.0.113.10
    User user
    Port 30001
    # ezet: et-port 30002
```

원격 ET 구성요소가 모두 [PR #837](https://github.com/MisterTea/EternalTerminal/pull/837)을 포함하는지 확인한 뒤, ezet이 관리하는 와일드카드가 없는 개별 `Host` 블록에 다음 marker를 추가해 활성화하세요.

```sshconfig
# ezet: close-on-hangup yes
```

이 marker는 ezet이 관리하는 `Host` 블록 안에서 위 형식의 주석으로만 인식합니다. wildcard나 `Match` 블록, 전역 설정으로는 사용할 수 없습니다. `ezet --doctor`는 로컬 클라이언트 지원 여부를 별도로 보고하며, Host별 활성화나 원격 서버 상태는 확인할 수 없습니다. `7.0.0` 같은 버전 문자열만으로는 지원 여부를 확인할 수 없습니다.

`--close-on-hangup`은 [PR #837](https://github.com/MisterTea/EternalTerminal/pull/837)을 통한 연결 상태의 세션 종료를 최선의 노력으로 요청합니다. 원격 `etserver`와 `etterminal` 모두 해당 변경을 포함해야 하며 ezet은 이를 확인할 수 없습니다. 구형 서버는 종료 패킷을 치명적 오류로 처리할 수 있고, 네트워크 단절·전원 장애·강제 종료 뒤에는 처리할 수 없으므로 복구가 필요하면 원격 셸을 tmux 안에서 실행하세요.

ezet에서 연결 설정을 편집하면 opt-in marker가 지워지고, alias만 바꾸는 작업에서는 보존됩니다. 서버를 바꾼 뒤 다시 확인하고, ezet을 업그레이드한 뒤에는 실행 중인 ezet을 종료하고 다시 시작하세요.

ezet과 별개로 ET에 적용하는 사용자 패치로 복구 버퍼 상한을 8MiB로 낮출 수 있으며, 이전 upstream 제안은 철회됐습니다. 이는 메모리와 복구 범위 사이의 절충이며, 오래된 세션 문제를 해결하거나 고정된 메모리 상한을 보장하지 않습니다. backpressure로 읽기가 멈출 수 있고 tmux도 ET scrollback을 무제한 보존하지 않습니다. 자세한 배경은 [PR #846 논의](https://github.com/MisterTea/EternalTerminal/pull/846#issuecomment-5753440337)를 참고하세요.

`ezet --uninstall`은 ezet이 추가한 `Include`만 제거합니다.

## 개발

```bash
make test    # 회귀 테스트 (bash -n, shellcheck, expect)
make docs    # README 스크린샷을 실제 TUI 에서 다시 생성
```

`make docs`는 고정 픽스처로 실제 TUI를 expect로 몰아 터미널 출력을 그대로 SVG로 바꿉니다. 그래서 스크린샷이 UI와 어긋날 수 없습니다.

## 라이선스

[MIT](LICENSE)
