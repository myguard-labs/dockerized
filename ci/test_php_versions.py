#!/usr/bin/env python3
"""Check that every PHP version in build/config.sh is wired through the images.

The generator and bake matrix read PHP_VERSIONS, but the runtime scripts, the
php-fpm footer cleanup and the apache handler confs spell each version by
hand. A version missing from one of them builds fine and then fails at
runtime: a MULTI image never starts that FPM, or a single-version image keeps
a stale /etc/php tree from the base layer.
"""

import re
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVERS = ("nginx", "angie")


def php_versions():
    out = subprocess.run(
        ["bash", "-c", 'source build/config.sh >/dev/null && echo "${PHP_VERSIONS[@]}"'],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout.split()
    return out


def missing_exts():
    out = subprocess.run(
        ["bash", "-c", 'source build/config.sh >/dev/null && '
                       'for v in "${!PHP_VERSION_MISSING_EXTS[@]}"; do '
                       'echo "$v ${PHP_VERSION_MISSING_EXTS[$v]}"; done'],
        cwd=ROOT, check=True, capture_output=True, text=True,
    ).stdout
    return {line.split()[0]: line.split()[1:] for line in out.splitlines() if line.strip()}


def env_pairs(text):
    """Return the version:PHPnn pairs a runtime script loops over."""
    return set(re.findall(r"\b(\d\.\d):PHP(\d\d)\b", text))


def nn(version):
    return version.replace(".", "")


class PhpVersionWiring(unittest.TestCase):
    def setUp(self):
        self.versions = php_versions()

    def test_config_lists_versions(self):
        self.assertIn("8.6", self.versions)
        self.assertEqual(self.versions, sorted(self.versions, key=lambda v: tuple(map(int, v.split(".")))))

    def test_runtime_scripts_know_every_version(self):
        for server in SERVERS:
            for rel in ("s6-rc.d/php-fpm/run", "s6-scripts/init-bootstrap.sh"):
                path = ROOT / "src" / server / rel
                pairs = env_pairs(path.read_text())
                for v in self.versions:
                    with self.subTest(file=f"{server}/{rel}", version=v):
                        self.assertIn((v, nn(v)), pairs)

    def test_legacy_bootstrap_starts_every_version(self):
        for server in SERVERS:
            text = (ROOT / "src" / server / "bootstrap.sh").read_text()
            for v in self.versions:
                with self.subTest(server=server, version=v):
                    self.assertIn(f'"${{PHP{nn(v)}}}" = "YES"', text)
                    self.assertIn(f'startphp "{v}"', text)

    def test_footer_removes_every_version_tree(self):
        text = (ROOT / "src/php-fpm/Dockerfile-template.footer").read_text()
        for v in self.versions:
            with self.subTest(version=v):
                self.assertRegex(text, rf"rm -rf /etc/php/{re.escape(v)} /usr/lib/php/\d{{8}} ;")

    def test_apache_conf_per_version(self):
        for v in self.versions:
            path = ROOT / f"src/apache-phpfpm/conf-available/php{v}-fpm.conf"
            with self.subTest(version=v):
                self.assertTrue(path.is_file(), path)
                self.assertIn(f"/run/php/php{v}-fpm.sock", path.read_text())

    def test_generated_dockerfiles_skip_missing_exts(self):
        for v, exts in missing_exts().items():
            for distro in ("deb", "ubu"):
                path = ROOT / f"src/php-fpm/Dockerfile-{nn(v)}-{distro}"
                text = path.read_text()
                with self.subTest(file=path.name):
                    self.assertIn(f"php{v}-fpm", text)
                    for ext in exts:
                        self.assertNotRegex(text, rf"php{re.escape(v)}-{ext}\b")

    def test_negative_control_detects_missing_pair(self):
        text = (ROOT / "src/nginx/s6-rc.d/php-fpm/run").read_text()
        stripped = text.replace(" 8.6:PHP86", "")
        self.assertNotEqual(text, stripped)
        self.assertNotIn(("8.6", "86"), env_pairs(stripped))

    def test_malformed_pair_is_ignored(self):
        self.assertEqual(env_pairs("8.6:PHP8 86:PHP86 8.6-PHP86"), set())


if __name__ == "__main__":
    unittest.main()
