"""Check per-run log hygiene and the build-proxy pre-flight in lib-runlogs.sh."""

import json
import os
import socket
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "build/lib-runlogs.sh"


def run(script, *args, env=None):
    return subprocess.run(
        ["bash", "-c", f'source "{LIB}"; {script}', "_", *args],
        env=env,
        capture_output=True,
        text=True,
    )


class LogHygieneTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="dockerized-runlogs-")
        self.dir = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def touch(self, *names):
        for name in names:
            (self.dir / name).write_text("log\n")

    def names(self):
        return sorted(p.name for p in self.dir.iterdir())

    def test_clear_removes_only_target_logs(self):
        self.touch(
            "buildx-target-ubuntu-reprepro.log",
            "buildx-target-debian-base.log",
            "buildx-summary-1.txt",
            "dockerized-daily-run.abc.log",
            "buildx-target-notalog.txt",
        )
        result = run('clear_target_logs "$1"', str(self.dir))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.names(),
            ["buildx-summary-1.txt", "buildx-target-notalog.txt",
             "dockerized-daily-run.abc.log"],
        )

    def test_clear_on_empty_dir_succeeds(self):
        result = run('clear_target_logs "$1"', str(self.dir))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.names(), [])

    def test_prune_keeps_failed_logs(self):
        self.touch(
            "buildx-target-debian-base.log",
            "buildx-target-ubuntu-base.log",
            "buildx-target-ubuntu-reprepro.log",
        )
        result = run(
            'd="$1"; shift; prune_success_logs "$d" "$@"',
            str(self.dir), "debian-base", "ubuntu-base", "never-logged",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.names(), ["buildx-target-ubuntu-reprepro.log"])

    def test_prune_without_successes_keeps_everything(self):
        self.touch("buildx-target-ubuntu-reprepro.log")
        result = run('prune_success_logs "$1"', str(self.dir))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.names(), ["buildx-target-ubuntu-reprepro.log"])


class ProxyCheckTest(unittest.TestCase):
    def setUp(self):
        self.server = socket.socket()
        self.server.bind(("127.0.0.1", 0))
        self.server.listen(4)
        self.port = self.server.getsockname()[1]
        closed = socket.socket()
        closed.bind(("127.0.0.1", 0))
        self.closed_port = closed.getsockname()[1]
        closed.close()

    def tearDown(self):
        self.server.close()

    def check(self, url):
        return run('check_build_proxy "$1"', url)

    def test_reachable_proxy_passes(self):
        for url in (
            f"http://127.0.0.1:{self.port}",
            f"http://127.0.0.1:{self.port}/",
            f"http://user:pw@127.0.0.1:{self.port}",
        ):
            with self.subTest(url=url):
                result = self.check(url)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_no_proxy_passes(self):
        self.assertEqual(self.check("").returncode, 0)

    def test_unreachable_proxy_fails(self):
        result = self.check(f"http://127.0.0.1:{self.closed_port}")
        self.assertEqual(result.returncode, 1)
        self.assertIn(f"127.0.0.1:{self.closed_port} is not reachable", result.stderr)

    def test_malformed_proxy_fails(self):
        for url in ("http://:3128", "http://host:notaport"):
            with self.subTest(url=url):
                result = self.check(url)
                self.assertEqual(result.returncode, 1)
                self.assertIn("malformed build proxy URL", result.stderr)


class DockerProxyConfigTest(unittest.TestCase):
    def read(self, config):
        with tempfile.TemporaryDirectory(prefix="dockerized-dockercfg-") as tmp:
            if config is not None:
                Path(tmp, "config.json").write_text(config)
            env = dict(os.environ, DOCKER_CONFIG=tmp)
            result = run("docker_build_proxy", env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()

    def test_reads_default_http_proxy(self):
        cfg = {"proxies": {"default": {"httpProxy": "http://192.168.178.3:3128"}}}
        self.assertEqual(self.read(json.dumps(cfg)), "http://192.168.178.3:3128")

    def test_missing_or_unset_proxy_is_empty(self):
        self.assertEqual(self.read(None), "")
        self.assertEqual(self.read(json.dumps({"auths": {}})), "")

    def test_malformed_config_is_empty(self):
        self.assertEqual(self.read("{not json"), "")


class WiringTest(unittest.TestCase):
    def test_sequential_builder_uses_helpers(self):
        source = (ROOT / "build/buildx-sequential.sh").read_text()
        check = source.index('check_build_proxy "$BUILD_PROXY"')
        clear = source.index("clear_target_logs /tmp")
        loop = source.index("for LAYER in")
        prune = source.index('prune_success_logs /tmp "${SUCCEEDED_TARGETS[@]}"')
        summary = source.index("# Final Summary")
        self.assertLess(check, loop)
        self.assertLess(clear, loop)
        self.assertLess(prune, summary)
        self.assertIn('SUCCEEDED_TARGETS+=("$TARGET")', source)


if __name__ == "__main__":
    unittest.main()
