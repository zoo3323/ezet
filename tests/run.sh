#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/bin/ezet"
bash -n "$ROOT/tests/test_ezet.sh"
bash -n "$ROOT/tests/test_password_prompt.sh"
bash -n "$ROOT/tests/test_et_options.sh"
bash -n "$ROOT/tools/build-et-memory-fix.sh"
bash -n "$ROOT/tools/install-et-memory-fix.sh"
bash -n "$ROOT/install.sh"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/ezet" "$ROOT/tests/test_ezet.sh" "$ROOT/tests/test_password_prompt.sh" "$ROOT/tests/test_et_options.sh" "$ROOT/tests/run.sh" "$ROOT/tools/build-et-memory-fix.sh" "$ROOT/tools/install-et-memory-fix.sh" "$ROOT/install.sh"
else
  printf 'warning: shellcheck not installed; static analysis skipped\n' >&2
fi

"$ROOT/tests/test_ezet.sh"
bash "$ROOT/tests/test_password_prompt.sh"
bash "$ROOT/tests/test_et_options.sh"

python3 "$ROOT/tests/test_tmux_discovery.py"
python3 "$ROOT/tests/test_et_install.py"
