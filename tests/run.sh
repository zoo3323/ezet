#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

bash -n "$ROOT/bin/ezet"
bash -n "$ROOT/tests/test_ezet.sh"
bash -n "$ROOT/tests/test_password_prompt.sh"

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck "$ROOT/bin/ezet" "$ROOT/tests/test_ezet.sh" "$ROOT/tests/test_password_prompt.sh" "$ROOT/tests/run.sh"
else
  printf 'warning: shellcheck not installed; static analysis skipped\n' >&2
fi

"$ROOT/tests/test_ezet.sh"
bash "$ROOT/tests/test_password_prompt.sh"
