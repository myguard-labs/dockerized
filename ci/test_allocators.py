"""Exercise bootstrap allocator selection without starting any services."""

import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
START = "# Resolve allocator SONAMEs using this image's native loader cache.\n"
END = "# End allocator selection.\n"
SCRIPTS = {
    "src/nginx/bootstrap.sh": "jemalloc",
    "src/angie/bootstrap.sh": "jemalloc",
    "src/nginx/s6-scripts/init-bootstrap.sh": "jemalloc",
    "src/angie/s6-scripts/init-bootstrap.sh": "jemalloc",
    "src/postfix/bootstrap.sh": "mimalloc",
    "src/apache-phpfpm/bootstrap.sh": "none",
    "src/rspamd-git/bootstrap.sh": "none",
}
LIBRARIES = {
    "jemalloc": "libjemalloc.so.2",
    "mimalloc": "libmimalloc-secure.so.3",
}
ARCHITECTURES = {
    "amd64": "x86_64-linux-gnu",
    "arm64": "aarch64-linux-gnu",
}


class AllocatorsTest(unittest.TestCase):
    def run_selection(self, relative, malloc, cache, cache_status=0):
        """Run the real selection block with an isolated loader-cache fixture."""
        source = (ROOT / relative).read_text()
        self.assertEqual(source.count(START), 1)
        self.assertEqual(source.count(END), 1)
        block = source.split(START, 1)[1].split(END, 1)[0]
        with tempfile.TemporaryDirectory(prefix="dockerized-allocator-") as tmp:
            fixture = Path(tmp)
            loader = fixture / "ldconfig"
            loader.write_text(
                "#!/bin/sh\n"
                '[ "$#" = 1 ] && [ "$1" = -p ] || exit 2\n'
                'printf called > "$TEST_CACHE_CALL"\n'
                'printf "%s" "$TEST_LDCACHE"\n'
                'exit "$TEST_CACHE_STATUS"\n'
            )
            loader.chmod(0o755)
            env = os.environ.copy()
            env.pop("LD_PRELOAD", None)
            env.pop("MALLOC", None)
            env.update(
                {
                    "PATH": f"{fixture}:{env['PATH']}",
                    "TEST_LDCACHE": cache,
                    "TEST_CACHE_STATUS": str(cache_status),
                    "TEST_CACHE_CALL": str(fixture / "cache-called"),
                }
            )
            if malloc is not None:
                env["MALLOC"] = malloc
            if "/s6-scripts/" in relative:
                service = Path(relative).parts[1]
                output = fixture / "ld_preload"
                output.write_text("stale-preload")
                block = block.replace(
                    f"/run/{service}/ld_preload", '"$TEST_PRELOAD_FILE"'
                )
                env["TEST_PRELOAD_FILE"] = str(output)
                command = block
            else:
                # Bootstrap must clear a stale inherited preload for none/missing.
                command = (
                    "LD_PRELOAD=stale-preload\nexport LD_PRELOAD\n"
                    + block
                    + 'printf "%s" "${LD_PRELOAD:-}"\n'
                )
            result = subprocess.run(
                ["sh", "-eu", "-c", command],
                env=env,
                check=True,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.stderr, "")
            called = (fixture / "cache-called").exists()
            selected = (
                output.read_text() if "/s6-scripts/" in relative else result.stdout
            )
            return selected, called

    @staticmethod
    def cache_for(triplet):
        return (
            "\n".join(
                f"{lib} (libc6) => /usr/lib/{triplet}/{lib}"
                for lib in LIBRARIES.values()
            )
            + "\n"
        )

    def test_native_allocator_on_amd64_and_arm64(self):
        for relative in SCRIPTS:
            for arch, triplet in ARCHITECTURES.items():
                for malloc, lib in LIBRARIES.items():
                    with self.subTest(script=relative, arch=arch, malloc=malloc):
                        selected, called = self.run_selection(
                            relative, malloc, self.cache_for(triplet)
                        )
                        self.assertEqual(selected, f"/usr/lib/{triplet}/{lib}")
                        self.assertTrue(called)

    def test_none_disables_preload_and_skips_lookup(self):
        for relative in SCRIPTS:
            with self.subTest(script=relative):
                self.assertEqual(
                    self.run_selection(
                        relative, "none", self.cache_for("aarch64-linux-gnu")
                    ),
                    ("", False),
                )

    def test_unset_empty_and_unknown_keep_each_images_default(self):
        for relative, default in SCRIPTS.items():
            for malloc in (None, "", "unknown"):
                with self.subTest(script=relative, malloc=malloc):
                    expected = (
                        ""
                        if default == "none"
                        else f"/usr/lib/aarch64-linux-gnu/{LIBRARIES[default]}"
                    )
                    self.assertEqual(
                        self.run_selection(
                            relative, malloc, self.cache_for("aarch64-linux-gnu")
                        ),
                        (expected, default != "none"),
                    )

    def test_missing_library_and_failed_cache_disable_preload(self):
        for relative in SCRIPTS:
            for malloc in LIBRARIES:
                for status in (0, 1, 127):
                    with self.subTest(script=relative, malloc=malloc, status=status):
                        self.assertEqual(
                            self.run_selection(relative, malloc, "", status),
                            ("", True),
                        )

    def test_different_soname_is_not_selected(self):
        cache = (
            "libmimalloc.so.3 (libc6) => /usr/lib/aarch64-linux-gnu/libmimalloc.so.3\n"
            "libmimalloc-secure.so.2 (libc6) => /usr/lib/aarch64-linux-gnu/libmimalloc-secure.so.2\n"
            "libjemalloc.so.20 (libc6) => /usr/lib/aarch64-linux-gnu/libjemalloc.so.20\n"
        )
        for relative in SCRIPTS:
            for malloc in LIBRARIES:
                with self.subTest(script=relative, malloc=malloc):
                    self.assertEqual(
                        self.run_selection(relative, malloc, cache), ("", True)
                    )

    def test_dockerfile_preloads_use_secure_soname(self):
        for service in ("openssh", "rspamd-git"):
            for distro in ("deb", "ubu"):
                relative = f"src/{service}/Dockerfile-{distro}"
                with self.subTest(dockerfile=relative):
                    source = (ROOT / relative).read_text()
                    self.assertEqual(
                        re.findall(r"\bLD_PRELOAD=(\S+)", source),
                        ["libmimalloc-secure.so.3"],
                    )

    def test_rspamd_repository_uses_native_architecture(self):
        for name in ("Dockerfile-deb", "Dockerfile-deb-official"):
            source = (ROOT / "src/rspamd-git" / name).read_text()
            statements = re.findall(r'echo "deb \[[^\n"]+"', source)
            self.assertEqual(len(statements), 1)
            suites = re.findall(r"^ENV\s+DIST=(\S+)$", source, re.MULTILINE)
            self.assertEqual(len(suites), 1)
            with tempfile.TemporaryDirectory(prefix="dockerized-apt-") as tmp:
                dpkg = Path(tmp) / "dpkg"
                dpkg.write_text(
                    "#!/bin/sh\n"
                    '[ "$#" = 1 ] && [ "$1" = --print-architecture ] || exit 2\n'
                    'printf "%s\\n" "$TEST_ARCH"\n'
                )
                dpkg.chmod(0o755)
                for arch in ARCHITECTURES:
                    with self.subTest(dockerfile=name, arch=arch):
                        env = os.environ.copy()
                        env.update(
                            {
                                "PATH": f"{tmp}:{env['PATH']}",
                                "TEST_ARCH": arch,
                                "DIST": suites[0],
                            }
                        )
                        result = subprocess.run(
                            ["sh", "-eu", "-c", statements[0]],
                            env=env,
                            check=True,
                            capture_output=True,
                            text=True,
                        )
                        self.assertEqual(
                            result.stdout,
                            f"deb [arch={arch} trusted=yes] http://rspamd.com/apt-stable/ trixie main\n",
                        )

    def test_official_rspamd_suite_matches_base(self):
        source = (ROOT / "src/rspamd-git/Dockerfile-deb-official").read_text()
        bases = re.findall(r"^FROM debian:([^\s-]+)-slim$", source, re.MULTILINE)
        suites = re.findall(r"^ENV\s+DIST=(\S+)$", source, re.MULTILINE)
        self.assertEqual(bases, ["trixie"])
        self.assertEqual(suites, bases)

    def test_official_rspamd_run_stops_on_failed_install(self):
        source = (ROOT / "src/rspamd-git/Dockerfile-deb-official").read_text()
        runs = re.findall(r"^RUN (.*?)(?=\n\n)", source, re.MULTILINE | re.DOTALL)
        self.assertEqual(len(runs), 1)
        command = runs[0].replace("\\\n", "")
        # Keep the production RUN order/control flow; isolate all commands and
        # redirect its three generated config files into the private fixture.
        self.assertEqual(command.count("> /etc/rspamd/override.d/"), 3)
        command = command.replace("> /etc/rspamd/override.d/", '> "$TEST_CONFIG_DIR"/')
        stub = """#!/bin/sh
set -eu
name=${0##*/}
printf '%s %s\\n' "$name" "$*" >> "$TEST_EVENTS"
case "$name" in
    debconf-set-selections)
        while IFS= read -r line; do :; done
        ;;
    dpkg)
        if [ "$1" = --print-architecture ]; then
            printf '%s\\n' "$TEST_ARCH"
        fi
        ;;
    apt-get)
        for arg; do
            if [ "$arg" = rspamd ]; then
                exit "$TEST_INSTALL_STATUS"
            fi
        done
        ;;
    tee)
        while IFS= read -r line; do
            printf '%s\\n' "$line" >> "$TEST_APT_SOURCE"
        done
        ;;
esac
"""
        for arch in ARCHITECTURES:
            for install_status in (0, 100):
                with (
                    self.subTest(arch=arch, install_status=install_status),
                    tempfile.TemporaryDirectory(prefix="dockerized-rspamd-run-") as tmp,
                ):
                    fixture = Path(tmp)
                    bin_dir = fixture / "bin"
                    config_dir = fixture / "config"
                    bin_dir.mkdir()
                    config_dir.mkdir()
                    for name in (
                        "debconf-set-selections",
                        "dpkg",
                        "apt-get",
                        "tee",
                        "mkdir",
                        "mv",
                        "rm",
                        "chmod",
                    ):
                        executable = bin_dir / name
                        executable.write_text(stub)
                        executable.chmod(0o755)
                    env = {
                        "PATH": str(bin_dir),
                        "DIST": "trixie",
                        "TEST_ARCH": arch,
                        "TEST_INSTALL_STATUS": str(install_status),
                        "TEST_CONFIG_DIR": str(config_dir),
                        "TEST_EVENTS": str(fixture / "events"),
                        "TEST_APT_SOURCE": str(fixture / "apt-source"),
                    }
                    result = subprocess.run(
                        ["/bin/sh", "-c", command],
                        env=env,
                        check=False,
                        capture_output=True,
                        text=True,
                    )
                    events = (fixture / "events").read_text()
                    self.assertEqual(result.stderr, "")
                    self.assertEqual(result.returncode, install_status)
                    self.assertEqual(
                        (fixture / "apt-source").read_text(),
                        f"deb [arch={arch} trusted=yes] http://rspamd.com/apt-stable/ trixie main\n",
                    )
                    self.assertIn("install rspamd syslog-ng-core", events)
                    if install_status == 0:
                        self.assertIn("chmod +x /bootstrap.sh", events)
                        self.assertEqual(
                            (config_dir / "logging.inc").read_text(),
                            'type = "console";\n',
                        )
                    else:
                        self.assertNotIn("mkdir", events)
                        self.assertNotIn("chmod", events)
                        self.assertEqual(list(config_dir.iterdir()), [])


if __name__ == "__main__":
    unittest.main()
