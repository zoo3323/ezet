#!/usr/bin/env python3
"""Exercise client selection and install transactions in disposable directories."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ezet install ")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "path"
        self.bin.mkdir()
        self.home = self.root / "home"
        (self.home / ".ssh/config.d").mkdir(parents=True)
        (self.home / ".ssh/config").write_text(
            f'Include "{self.home}/.ssh/config.d/ezet"\n')
        (self.home / ".ssh/config.d/ezet").write_text(
            "Host probe\n  HostName 192.0.2.1\n  # ezet: et-port 2022\n")
        self.log = self.root / "calls"
        self.data = self.root / "managed data"
        self.env = dict(os.environ, HOME=str(self.home), EZET_DATA_DIR=str(self.data),
                        PATH=f"{self.bin}:{os.environ['PATH']}", NO_COLOR="1",
                        EZET_NO_MULTIPLEX="1", ET_CALLS=str(self.log))
        self.env.pop("EZET_ET_BIN", None)
        self.executable(self.bin / "ssh", '''#!/usr/bin/env bash
if [ "${1:-}" = -V ]; then echo OpenSSH_9.9; exit; fi
if [ "${*: -2}" = "sh -s" ]; then
  cat >/dev/null
  printf '%s\\n' '__DT_CONNECTED__' '__DT_TMUX__=/usr/bin/tmux' '__DT_TMUX_SOCKET__=ezet-3.7c' '__DT_NOW__=1700000000'
fi
''')
        self.et(self.bin / "et", "system")

    def executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)
        return path

    def et(self, path, label, broken=False):
        return self.executable(path, '#!/bin/sh\n'
                               + f'printf "%s:%s\\n" "{label}" "$*" >> "$ET_CALLS"\n'
                               + ('exit 9\n' if broken else
                                  'case "$1" in\n'
                                  f'  --version) echo "et {label}" ;;\n'
                                  '  --help) echo "--close-on-hangup" ;;\n'
                                  'esac\n'))

    def build(self, label, broken=False):
        build = self.root / f"build {label}"
        for name in ("et", "etserver", "etterminal"):
            self.et(build / name, label, broken)
        return build

    def ezet(self, *args, env=None, check=True):
        return subprocess.run([str(ROOT / "bin/ezet"), *map(str, args)],
                              env=env or self.env, text=True, capture_output=True,
                              check=check)

    def connect(self, label, env=None):
        self.log.write_text("")
        self.ezet("probe", "work", env=env)
        self.assertIn(f"{label}:", self.log.read_text())
        self.assertIn("new-session -A -s 'work'", self.log.read_text())

    def install_server(self, build, prefix, service=None, check=True):
        args = [str(ROOT / "tools/install-et-memory-fix.sh"), str(build),
                "--prefix", str(prefix)]
        if service:
            args += ["--service", service]
        return subprocess.run(args, env=self.env, text=True, capture_output=True,
                              check=check)

    def systemctl(self, fail_restart=False):
        marker = self.root / "fail restart"
        if fail_restart:
            marker.touch()
        self.env["FAIL_RESTART"] = str(marker)
        self.executable(self.bin / "systemctl", '''#!/bin/sh
printf 'systemctl:%s\\n' "$*" >> "$ET_CALLS"
if [ "$1" = restart ] && [ -f "$FAIL_RESTART" ]; then
  rm -f "$FAIL_RESTART"
  exit 42
fi
''')

    def test_managed_client_updates_and_rolls_back_without_changing_path_et(self):
        original = (self.bin / "et").read_bytes()
        self.connect("system")
        self.ezet("--install-et", self.build("first"))
        self.connect("first")
        self.ezet("--install-et", self.build("second"))
        self.connect("second")
        self.ezet("--rollback-et")
        self.connect("first")
        self.ezet("--rollback-et")
        self.connect("second")
        self.assertEqual(original, (self.bin / "et").read_bytes())
        self.assertIn(str(self.data / "et/current"), self.ezet("--doctor").stdout)

    def test_failed_update_keeps_both_current_and_previous_clients(self):
        self.ezet("--install-et", self.build("first"))
        self.ezet("--install-et", self.build("second"))
        result = self.ezet("--install-et", self.build("broken", True), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.connect("second")
        self.ezet("--rollback-et")
        self.connect("first")
        self.assertFalse((self.data / "et/.install-lock").exists())
        self.assertEqual(len(list((self.data / "et/releases").iterdir())), 2)

    def test_interrupted_install_does_not_delete_the_activated_binary(self):
        self.executable(self.bin / "mv", '''#!/usr/bin/env bash
/bin/mv "$@" || exit
case "${*: -1}" in */et/current) kill -TERM "$PPID" ;; esac
''')
        result = self.ezet("--install-et", self.build("activated"), check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.data / "et/current").is_file())
        self.connect("activated")

    def test_explicit_client_override_takes_priority(self):
        self.ezet("--install-et", self.build("managed"))
        env = dict(self.env, EZET_ET_BIN="et")
        self.connect("system", env)
        custom = self.et(self.root / "custom path/et", "custom")
        self.connect("custom", dict(self.env, EZET_ET_BIN=str(custom)))
        self.assertNotEqual(self.ezet("--doctor", env=dict(self.env,
                            EZET_ET_BIN=str(self.root / "missing")), check=False).returncode, 0)

    def test_xdg_data_directory_is_used_when_no_override_is_set(self):
        env = dict(self.env, XDG_DATA_HOME=str(self.root / "xdg data"))
        env.pop("EZET_DATA_DIR")
        self.ezet("--install-et", self.build("xdg"), env=env)
        self.assertTrue((self.root / "xdg data/ezet/et/current").is_file())
        self.connect("xdg", env)

    def test_missing_previous_client_and_install_lock_do_not_replace_current(self):
        self.ezet("--install-et", self.build("first"))
        self.assertNotEqual(self.ezet("--rollback-et", check=False).returncode, 0)
        lock = self.data / "et/.install-lock"
        lock.mkdir()
        self.assertNotEqual(self.ezet("--install-et", self.build("second"), check=False).returncode, 0)
        self.assertTrue(lock.exists())
        self.connect("first")

    def test_directory_selector_is_rejected_without_writing_through_the_link(self):
        folder = self.root / "unrelated folder"
        folder.mkdir()
        (self.data / "et").mkdir(parents=True)
        (self.data / "et/current").symlink_to(folder)
        self.assertNotEqual(self.ezet("--install-et", self.build("new"), check=False).returncode, 0)
        self.assertTrue((self.data / "et/current").is_symlink())
        self.assertEqual(list(folder.iterdir()), [])

    def test_host_menu_shows_managed_et_when_no_system_client_is_available(self):
        expect = shutil.which("expect")
        if not expect:
            self.skipTest("expect is required for the interactive menu test")
        env = dict(self.env, PATH=f"{self.bin}:/usr/bin:/bin", TERM="xterm-256color",
                   TEST_EZET=str(ROOT / "bin/ezet"))
        (self.bin / "et").unlink()
        if shutil.which("et", path=env["PATH"]):
            self.skipTest("this fixture needs a PATH without a system ET client")
        self.ezet("--install-et", self.build("managed"), env=env)
        result = subprocess.run([expect], input='''set timeout 3
spawn -noecho $env(TEST_EZET)
expect {
  "ET 2022" {}
  timeout {exit 71}
  eof {exit 72}
}
send -- "q"
expect eof
set result [wait]
exit [lindex $result 3]
''', env=env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_custom_prefix_fresh_install_requires_no_service_or_root(self):
        prefix = self.root / "custom prefix"
        build = self.build("new")
        self.install_server(build, prefix)
        for name in ("et", "etserver", "etterminal"):
            self.assertEqual((build / name).read_bytes(), (prefix / "bin" / name).read_bytes())
        self.assertNotIn("systemctl:", self.log.read_text())

    def test_custom_service_is_restarted_only_when_requested(self):
        self.systemctl()
        self.install_server(self.build("new"), self.root / "prefix", "custom-et.service")
        self.assertIn("systemctl:restart custom-et.service", self.log.read_text())
        self.assertIn("systemctl:is-active --quiet custom-et.service", self.log.read_text())

    def test_failed_restart_restores_old_files_and_symlinks(self):
        self.systemctl(fail_restart=True)
        prefix = self.root / "prefix"
        old = self.build("old")
        (prefix / "bin").mkdir(parents=True)
        for name in ("et", "etserver", "etterminal"):
            (prefix / "bin" / name).symlink_to(old / name)
        result = self.install_server(self.build("new"), prefix, "custom-et.service", check=False)
        self.assertEqual(result.returncode, 42)
        for name in ("et", "etserver", "etterminal"):
            self.assertTrue((prefix / "bin" / name).is_symlink())
            self.assertEqual((prefix / "bin" / name).resolve(), (old / name).resolve())
        self.assertEqual(self.log.read_text().count("systemctl:restart custom-et.service"), 2)
        self.assertFalse((prefix / "lib/ezet/.install-lock").exists())

    def test_failed_fresh_install_removes_only_new_binaries(self):
        self.systemctl(fail_restart=True)
        prefix = self.root / "prefix"
        result = self.install_server(self.build("new"), prefix, "custom-et.service", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(list((prefix / "bin").iterdir()), [])

    def build_tools(self):
        # Keep the real scripts and transactions; replace compilation/network
        # boundaries so fetch failure, retry and defaults are deterministic.
        self.executable(self.bin / "uname", '#!/bin/sh\necho Linux\n')
        self.executable(self.bin / "git", '''#!/usr/bin/env bash
printf 'git:%s\\n' "$*" >> "$ET_CALLS"
dir=""
if [ "${1:-}" = -C ]; then dir=$2; shift 2; fi
case "$1" in
  init) mkdir -p "$2/.git" ;;
  rev-parse) [ -f "$dir/checked-out" ] || exit 1 ;;
  fetch)
    if [ -f "${FAIL_FETCH:-/nonexistent}" ]; then
      rm -f "$FAIL_FETCH"; exit 8
    fi ;;
  checkout) touch "$dir/checked-out" ;;
  config) printf '%s\\n' 'submodule.external/ThreadPool.path external/ThreadPool' 'submodule.external/vcpkg.path external/vcpkg' ;;
  submodule) mkdir -p "$dir/${*: -1}"; touch "$dir/${*: -1}/ready" ;;
esac
''')
        self.executable(self.bin / "cmake", '''#!/usr/bin/env bash
printf 'cmake:%s\\n' "$*" >> "$ET_CALLS"
case "$1" in
  -S)
    build=""; mib=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        -B) build=$2; shift ;;
        -DET_RECOVERY_BUFFER_MIB=*) mib=${1#*=} ;;
      esac
      shift
    done
    mkdir -p "$build"
    printf 'ET_RECOVERY_BUFFER_MIB:STRING=%s\\n' "$mib" > "$build/CMakeCache.txt"
    printf '#!/bin/sh\\nexit 0\\n' > "$build/et-test"
    printf '#!/bin/sh\\necho "et built"\\n' > "$build/et"
    chmod +x "$build/et-test" "$build/et" ;;
  -E) printf '%s\\n' 'fixture-patch-sha256' ;;
esac
''')

    def fetch_build(self, work, *options, check=True):
        return subprocess.run([str(ROOT / "tools/build-et-memory-fix.sh"),
                               "--fetch", str(work), *options],
                              env=self.env, text=True, capture_output=True, check=check)

    def test_fetch_build_pins_source_and_defaults_to_upstream_buffer(self):
        self.build_tools()
        work = self.root / "work dir"
        self.fetch_build(work)
        calls = self.log.read_text()
        self.assertIn("fetch --depth 1 origin a8367415783a64405c62c70b755b4c09b410532b", calls)
        self.assertIn("https://github.com/MisterTea/EternalTerminal.git", calls)
        self.assertIn("submodule update --init --recursive -- external/ThreadPool", calls)
        self.assertNotIn("submodule update --init --recursive -- external/vcpkg", calls)
        info = work / "build/ezet-et-build.info"
        self.assertIn("recovery_buffer_mib=64", info.read_text())
        self.fetch_build(work, "-DET_RECOVERY_BUFFER_MIB=8")
        self.assertIn("recovery_buffer_mib=8", info.read_text())
        self.assertFalse((work / "build/.ezet-build-lock").exists())

    def test_failed_fetch_can_be_retried_without_deleting_the_workspace(self):
        self.build_tools()
        marker = self.root / "fail fetch"
        marker.touch()
        self.env["FAIL_FETCH"] = str(marker)
        work = self.root / "work"
        self.assertNotEqual(self.fetch_build(work, check=False).returncode, 0)
        self.assertTrue((work / "source/.git").exists())
        self.fetch_build(work)
        self.assertTrue((work / "build/ezet-et-build.info").exists())

    def downloader(self):
        self.env["FIXTURE_ROOT"] = str(ROOT)
        self.executable(self.bin / "curl", '''#!/usr/bin/env bash
url=""; dest=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) dest=$2; shift ;;
    https://*) url=$1 ;;
  esac
  shift
done
case "$url" in
  */bin/ezet) source="$FIXTURE_ROOT/bin/ezet" ;;
  */tools/*) source="$FIXTURE_ROOT/tools/${url##*/}" ;;
  *) exit 3 ;;
esac
cp "$source" "$dest"
''')

    def test_one_command_install_and_update_selects_managed_client(self):
        self.build_tools()
        self.downloader()
        dest = self.root / "installed bin"
        self.env.update(EZET_WITH_PATCHED_ET="1", EZET_INSTALL_DIR=str(dest),
                        EZET_ET_RECOVERY_BUFFER_MIB="64", EZET_REF="fixture")
        for _ in range(2):
            result = subprocess.run([str(ROOT / "install.sh")], env=self.env,
                                    text=True, capture_output=True, check=True)
            self.assertIn("ET client path:", result.stdout)
        current = self.data / "et/current"
        previous = self.data / "et/previous"
        self.assertTrue(current.is_file())
        self.assertTrue(previous.is_file())
        self.assertNotEqual(current.resolve(), previous.resolve())
        self.assertEqual(len(list((self.data / "et-build").iterdir())), 1)
        self.assertIn("recovery_buffer_mib=64", (current.resolve().parent.parent / "build.info").read_text())
        self.assertTrue((dest / "ezet").is_file())

    def test_default_install_does_not_fetch_or_replace_et(self):
        self.downloader()
        original = (self.bin / "et").read_bytes()
        self.env["EZET_INSTALL_DIR"] = str(self.root / "installed")
        subprocess.run([str(ROOT / "install.sh")], env=self.env,
                       text=True, capture_output=True, check=True)
        self.assertFalse((self.data / "et/current").exists())
        self.assertFalse((self.data / "tools").exists())
        self.assertEqual((self.bin / "et").read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
