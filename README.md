# ezet

English · [한국어](README.ko.md)

An interactive CLI for picking SSH · [Eternal Terminal](https://eternalterminal.dev/) · tmux hosts and sessions. Pure Bash, and it falls back to plain SSH whenever ET is unavailable.

- **tmux session management** — list, create and rename remote sessions, then attach right away.
- **Auto-reconnect** — prefers Eternal Terminal (ET), so sessions survive a closed laptop lid or a network change.
- **SSH fallback** — hosts without ET, or without a usable tmux, are reached over plain SSH.

[![test](https://github.com/zoo3323/ezet/actions/workflows/test.yml/badge.svg)](https://github.com/zoo3323/ezet/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Screens

Hosts and tmux sessions are picked from the same dashboard.

Host picker:

<img src="docs/img/hosts.svg" alt="host picker screen" width="780">

Narrowing the list with search:

<img src="docs/img/search.svg" alt="host search screen" width="780">

Session picker:

<img src="docs/img/sessions.svg" alt="tmux session picker screen" width="780">

Adding a host:

<img src="docs/img/add-host.svg" alt="add host screen" width="780">

## Install

```bash
brew install zoo3323/tap/ezet
```

or:

```bash
curl -fsSL https://raw.githubusercontent.com/zoo3323/ezet/main/install.sh | bash
```

For ET auto-reconnect, install `et` locally and `etserver` on the remote host. Without them ezet still connects over SSH.

## Usage

```bash
ezet                 # pick a host
ezet <host>          # pick a session
ezet <host> <name>   # connect to a session directly
ezet --doctor        # check the setup
ezet --version
```

Move with the arrow keys and pick with `Enter`. The host screen adds, edits, deletes and reorders hosts; the session screen attaches or creates tmux sessions, or connects without tmux through the `SSH Direct` row. `q` quits and `←` goes back to the previous screen.

In the add and edit forms, `Enter` accepts the shown default, `<` steps back to the previous field and `q` cancels.

## Requirements

- Bash 3.2+
- OpenSSH (`ssh`)
- Eternal Terminal (`et`, optional)
- Remote `tmux` (optional; without it ezet connects through `SSH Direct`)

A local tmux is not needed.

## SSH config

ezet hosts live in `~/.ssh/config.d/ezet`. Your existing config only gains a single `Include` line, and it is backed up before the change. ET ports are stored as a comment:

```sshconfig
Host host-ext
    HostName 203.0.113.10
    User user
    Port 30001
    # ezet: et-port 30002
```

`ezet --uninstall` removes only the `Include` line ezet added.

## Development

```bash
make test    # regression tests (bash -n, shellcheck, expect)
make docs    # regenerate the README screenshots from the real TUI
```

`make docs` drives the actual TUI with expect against a fixed fixture and converts the captured terminal output to SVG, so the screenshots cannot drift from the UI.

## License

[MIT](LICENSE)
