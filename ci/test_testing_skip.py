"""Check the mailstrix:testing unchanged-commit skip in build/lib-release.sh."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SHA = "81d3771e16a491ff9c95232b29bb1a391fd896bb"
OLD = "78b7976ec8ef415c80ca87bb9470e030ff74e259"


PLATFORMS = ("linux/amd64", "linux/arm64")


def image(rev, platform="linux/amd64"):
    os_name, arch = platform.split("/")
    return {
        "os": os_name,
        "architecture": arch,
        "config": {"Labels": {"org.opencontainers.image.revision": rev}},
    }


def multi(*revs, platforms=PLATFORMS):
    return {p: image(r, p) for p, r in zip(platforms, revs, strict=True)}


class TestingSkipTest(unittest.TestCase):
    def run_check(self, ref, image_json, docker_rc=0, platforms=PLATFORMS):
        with tempfile.TemporaryDirectory(prefix="dockerized-skip-") as tmp:
            stub = Path(tmp) / "docker"
            payload = Path(tmp) / "image.json"
            payload.write_text("" if image_json is None else json.dumps(image_json))
            stub.write_text(f'#!/bin/sh\ncat "{payload}"\nexit {docker_rc}\n')
            stub.chmod(0o755)
            env = dict(os.environ, PATH=f"{tmp}:{os.environ['PATH']}")
            script = (
                f'. "{ROOT}/build/lib-release.sh"; '
                'image_built_from "$1" docker.io/example/mailstrix:testing "${@:2}"'
            )
            return subprocess.run(
                ["bash", "-c", script, "_", ref, *platforms],
                env=env,
                capture_output=True,
                text=True,
                check=False,
            ).returncode

    def test_same_commit_all_platforms_skips(self):
        self.assertEqual(self.run_check(SHA, multi(SHA, SHA)), 0)

    def test_single_platform_image_builds_when_two_required(self):
        self.assertNotEqual(self.run_check(SHA, image(SHA)), 0)

    def test_single_platform_image_skips_when_it_is_the_only_required(self):
        self.assertEqual(self.run_check(SHA, image(SHA), platforms=("linux/amd64",)), 0)

    def test_single_platform_image_wrong_arch_builds(self):
        self.assertNotEqual(
            self.run_check(SHA, image(SHA, "linux/arm64"), platforms=("linux/amd64",)),
            0,
        )

    def test_inspect_failure_with_matching_output_builds(self):
        self.assertNotEqual(self.run_check(SHA, multi(SHA, SHA), docker_rc=1), 0)

    def test_missing_arm64_builds(self):
        self.assertNotEqual(
            self.run_check(SHA, multi(SHA, platforms=("linux/amd64",))), 0
        )

    def test_extra_published_platform_skips(self):
        published = multi(SHA, SHA, SHA, platforms=(*PLATFORMS, "linux/riscv64"))
        self.assertEqual(self.run_check(SHA, published), 0)

    def test_no_required_platforms_builds(self):
        self.assertNotEqual(self.run_check(SHA, multi(SHA, SHA), platforms=()), 0)

    def test_new_commit_builds(self):
        self.assertNotEqual(self.run_check(SHA, multi(OLD, OLD)), 0)

    def test_mixed_platform_revisions_build(self):
        self.assertNotEqual(self.run_check(SHA, multi(SHA, OLD)), 0)

    def test_missing_label_builds(self):
        self.assertNotEqual(
            self.run_check(SHA, {"linux/amd64": {"config": {"Labels": {}}}}), 0
        )

    def test_symbolic_ref_builds(self):
        self.assertNotEqual(self.run_check("main", multi("main", "main")), 0)

    def test_short_sha_builds(self):
        self.assertNotEqual(self.run_check(SHA[:7], multi(SHA[:7], SHA[:7])), 0)

    def test_registry_unreachable_builds(self):
        self.assertNotEqual(self.run_check(SHA, None, docker_rc=1), 0)

    def test_malformed_inspect_output_builds(self):
        self.assertNotEqual(self.run_check(SHA, "not json"), 0)


if __name__ == "__main__":
    unittest.main()
