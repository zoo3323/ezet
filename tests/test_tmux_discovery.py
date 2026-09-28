#!/usr/bin/env python3
"""Exercise the actual remote POSIX script with isolated tmux installations."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = (Path(__file__).resolve().parents[1] / "bin/ezet").read_text()
SCRIPT = SOURCE.split("fetch_script <<'FETCH_SCRIPT' || true\n", 1)[1].split("\nFETCH_SCRIPT", 1)[0]


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / "calls"
        self.script = SCRIPT
        # Map absolute candidate locations to a fixture filesystem. Leave sh,
        # awk and sed real, and run the exact discovery/query implementation.
        for prefix in ("/usr/", "/opt/", "/home/linuxbrew/", "/run/", "/snap/"):
            self.script = self.script.replace(prefix, str(self.root) + prefix)
        self.home = self.root / "home/user"
        self.home.mkdir(parents=True)
        self.path_bin = self.root / "path"
        self.path_bin.mkdir()
        self.shell = self.root / "shell"
        self.shell.write_text('#!/bin/sh\nprintf "%s\\n" "$LOGIN_TMUX"\n')
        self.shell.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), SHELL=str(self.shell),
                        PATH=f"{self.path_bin}:/usr/bin:/bin", LOGIN_TMUX="",
                        TMUX_TEST_LOG=str(self.log))

    def install(self, relative, version, broken=False):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('#!/bin/sh\n'
                        + ('exit 1\n' if broken else
                           f'if [ "$1" = -V ]; then printf "tmux {version}\\n"; exit; fi\n'
                           'printf "%s\\n" "$*" >> "$TMUX_TEST_LOG"\n'
                           'printf "%s\\n" "__DT_SESSION__|work|1||1|1|bash|/work"\n'))
        path.chmod(0o755)
        return path

    def run_query(self):
        result = subprocess.run(["/bin/sh"], input=self.script, text=True,
                                env=self.env, capture_output=True, check=True)
        return result.stdout

    def test_user_install_beats_old_ssh_path_and_queries_versioned_server(self):
        self.install("path/tmux", "3.2a")
        newest = self.install("home/user/.local/bin/tmux", "3.7c")
        output = self.run_query()
        self.assertIn(f"__DT_TMUX__={newest}\n", output)
        self.assertIn("__DT_TMUX_SOCKET__=ezet-3.7c\n", output)
        self.assertIn("-L ezet-3.7c list-sessions", self.log.read_text())
        self.assertIn("__DT_SESSION__|work|", output)

    def test_numeric_minor_versions_and_homebrew(self):
        self.install("path/tmux", "3.9")
        self.install("home/user/.local/bin/tmux", "3.7c")
        newest = self.install("opt/homebrew/bin/tmux", "3.10")
        self.assertIn(f"__DT_TMUX__={newest}\n", self.run_query())

    def test_patch_suffix_and_login_shell_candidate(self):
        self.install("path/tmux", "3.7a")
        self.install("home/user/.local/bin/tmux", "3.7b")
        newest = self.install("custom/tmux", "3.7c")
        self.env["LOGIN_TMUX"] = str(newest)
        self.assertIn(f"__DT_TMUX__={newest}\n", self.run_query())

    def test_broken_install_does_not_hide_working_version(self):
        self.install("path/tmux", "3.2a", broken=True)
        newest = self.install("home/user/.local/bin/tmux", "3.7c")
        self.assertIn(f"__DT_TMUX__={newest}\n", self.run_query())

    def test_unknown_or_unsafe_versions_are_not_used_as_socket_names(self):
        self.install("path/tmux", "next-unknown")
        self.install("home/user/.local/bin/tmux", "3.7c;bad")
        self.assertIn("__DT_NO_TMUX__", self.run_query())
        self.assertFalse(self.log.exists())

    def test_upgrade_changes_socket_without_touching_old_server(self):
        self.install("path/tmux", "3.4")
        self.assertIn("__DT_TMUX_SOCKET__=ezet-3.4", self.run_query())
        self.install("path/tmux", "3.7c")
        self.assertIn("__DT_TMUX_SOCKET__=ezet-3.7c", self.run_query())
        calls = self.log.read_text().splitlines()
        self.assertEqual(len(calls), 2)
        self.assertTrue(all("list-sessions" in call for call in calls))


if __name__ == "__main__":
    unittest.main()
