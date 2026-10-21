"""Check that every target keeps its own ref in the shared local build cache."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def bake_block():
    source = (ROOT / "build/buildx-sequential.sh").read_text()
    start = source.index('        if timeout --kill-after=60s "$BUILD_TIMEOUT" docker buildx bake')
    end = source.index("; then", start)
    return source[start:end] + "; then :; fi\n"


def run_bake(block, target, tmp):
    """Run the bake invocation against a stub docker; return its argv."""
    stub = Path(tmp) / "bin"
    stub.mkdir(exist_ok=True)
    argv = Path(tmp) / f"argv-{target}"
    (stub / "docker").write_text(
        f'#!/bin/sh\nprintf "%s\\n" "$@" > "{argv}"\n'
    )
    (stub / "docker").chmod(0o755)
    env = dict(
        os.environ,
        PATH=f"{stub}:{os.environ['PATH']}",
        BUILD_TIMEOUT="10s",
        PROJECT_ROOT=str(ROOT),
        BUILDER_NAME="probe",
        CACHE_DIR=str(Path(tmp) / "cache"),
        PUSH_ARG="--load",
        TARGET=target,
        TARGET_LOG=str(Path(tmp) / f"{target}.log"),
    )
    subprocess.run(["sh", "-eu", "-c", block], env=env, check=True)
    return argv.read_text().splitlines()


def cache_sets(args):
    return [args[i + 1] for i, a in enumerate(args) if a == "--set" and "cache-" in args[i + 1]]


class CacheTagsTest(unittest.TestCase):
    def test_import_and_export_use_the_target_tag(self):
        with tempfile.TemporaryDirectory(prefix="dockerized-cachetag-") as tmp:
            args = run_bake(bake_block(), "debian-base", tmp)
        cache = str(Path(tmp) / "cache")
        self.assertEqual(
            cache_sets(args),
            [
                f"*.cache-from=type=local,src={cache},tag=debian-base",
                f"*.cache-to=type=local,dest={cache},mode=max,tag=debian-base",
            ],
        )
        self.assertEqual(args[-1], "debian-base")

    def test_distinct_targets_get_distinct_refs(self):
        with tempfile.TemporaryDirectory(prefix="dockerized-cachetag-") as tmp:
            a = cache_sets(run_bake(bake_block(), "ubuntu-multiphp", tmp))
            b = cache_sets(run_bake(bake_block(), "debian-multiphp", tmp))
        self.assertTrue(all(s.endswith(",tag=ubuntu-multiphp") for s in a))
        self.assertTrue(all(s.endswith(",tag=debian-multiphp") for s in b))
        self.assertFalse(set(a) & set(b))

    def test_untagged_invocation_is_rejected(self):
        # Negative control: the pre-fix invocation shares one "latest" ref.
        block = bake_block().replace(",tag=$TARGET", "")
        with tempfile.TemporaryDirectory(prefix="dockerized-cachetag-") as tmp:
            sets = cache_sets(run_bake(block, "debian-base", tmp))
        self.assertEqual(len(sets), 2)
        self.assertFalse(any("tag=" in s for s in sets))

    def test_every_cache_option_is_tagged(self):
        source = (ROOT / "build/buildx-sequential.sh").read_text()
        lines = [
            line for line in source.splitlines() if "cache-from=" in line or "cache-to=" in line
        ]
        self.assertEqual(len(lines), 2)
        for line in lines:
            self.assertIn(",tag=$TARGET", line)


if __name__ == "__main__":
    unittest.main()
