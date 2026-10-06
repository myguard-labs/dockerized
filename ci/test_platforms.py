#!/usr/bin/env python3
"""Check the expanded Bake plan without building or publishing images."""

import json
import os
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def bake_plan(platforms=None):
    """Expand every concrete target, including targets outside the daily groups."""
    env = os.environ.copy()
    env.pop("PLATFORMS", None)
    if platforms is not None:
        env["PLATFORMS"] = platforms

    def bake(*args):
        result = subprocess.run(
            ["docker", "buildx", "bake", *args],
            cwd=ROOT,
            env=env,
            check=True,
            capture_output=True,
            text=True,
        )
        return json.loads(result.stdout)

    targets = [
        entry["name"]
        for entry in bake("--list=type=targets,format=json")
        if not entry.get("group") and not entry["name"].startswith("_")
    ]
    if not targets:
        raise AssertionError("Bake has no concrete targets")
    return bake("--print", *targets)["target"]


class PlatformsTest(unittest.TestCase):
    def assert_platforms(self, plan, expected):
        self.assertTrue(plan)
        for name, target in plan.items():
            with self.subTest(target=name):
                self.assertEqual(set(target.get("platforms", [])), expected)

    def test_every_target_defaults_to_amd64_and_arm64(self):
        self.assert_platforms(bake_plan(), {"linux/amd64", "linux/arm64"})

    def test_local_build_can_select_either_architecture(self):
        for platform in ("linux/amd64", "linux/arm64"):
            with self.subTest(platform=platform):
                self.assert_platforms(bake_plan(platform), {platform})

    def test_local_dependencies_use_buildkit_image_names(self):
        # The Dockerfile frontend looks up Docker Hub contexts by their familiar
        # name, without docker.io/. Qualified keys otherwise pull the published
        # image, which may still lack the architecture being bootstrapped here.
        dependencies = 0
        for name, target in bake_plan().items():
            for image, source in target.get("contexts", {}).items():
                if source.startswith("target:"):
                    dependencies += 1
                    with self.subTest(target=name, image=image):
                        self.assertFalse(image.startswith("docker.io/"))
        self.assertGreater(dependencies, 0)


if __name__ == "__main__":
    unittest.main()
