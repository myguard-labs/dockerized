#!/usr/bin/env python3
"""Check that apt installs run under eatmydata at build time only.

The base images point apt's Dir::Bin::dpkg at a wrapper that runs dpkg under
eatmydata and syncs once afterwards. Per-file fsync made QEMU arm64 package
installs crawl. eatmydata must never reach a running container through
ENV LD_PRELOAD: mariadb, dovecot and valkey would silently lose fsync.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "src" / "base"
WRAPPER = "/usr/local/sbin/dpkg-eatmydata"
APT_CONF = f'Dir::Bin::dpkg "{WRAPPER}";'
FALLBACK = 'if [ -x /usr/bin/eatmydata ]; then'
ENV_PRELOAD = re.compile(r"^\s*ENV\b[^\n]*\bLD_PRELOAD\b[^\n]*eatmydata", re.M | re.I)


def wires_eatmydata(text):
    return ("eatmydata" in re.findall(r"apt-get install[^;]*ssl-cert[^;]*", text)[0]
            and f"> {WRAPPER}" in text
            and APT_CONF in text
            and "/usr/bin/eatmydata /usr/bin/dpkg" in text
            and FALLBACK in text
            and "sync" in text)


def env_preload_files(paths):
    return [p.name for p in paths if ENV_PRELOAD.search(p.read_text(errors="replace"))]


class EatmydataBuildOnly(unittest.TestCase):
    def test_template_and_generated_bases_wire_wrapper(self):
        for name in ("Dockerfile-template", "Dockerfile-debian-base", "Dockerfile-ubuntu-base"):
            with self.subTest(name=name):
                self.assertTrue(wires_eatmydata((BASE / name).read_text()))

    def test_wrapper_configured_before_myguard_packages(self):
        text = (BASE / "Dockerfile-template").read_text()
        self.assertLess(text.index(APT_CONF), text.index("libjemalloc2"))

    def test_no_dockerfile_preloads_eatmydata_at_runtime(self):
        self.assertEqual(env_preload_files(sorted((ROOT / "src").rglob("Dockerfile*"))), [])

    def test_missing_apt_conf_rejected(self):
        text = (BASE / "Dockerfile-template").read_text().replace(APT_CONF, "")
        self.assertFalse(wires_eatmydata(text))

    def test_missing_fallback_rejected(self):
        text = (BASE / "Dockerfile-template").read_text().replace(FALLBACK, "")
        self.assertFalse(wires_eatmydata(text))

    def test_env_preload_detected(self):
        self.assertTrue(ENV_PRELOAD.search('ENV     LD_PRELOAD="libeatmydata.so"'))
        self.assertTrue(ENV_PRELOAD.search("ENV TZ=UTC LD_PRELOAD=/usr/lib/libeatmydata.so"))

    def test_jemalloc_preload_not_flagged(self):
        self.assertIsNone(ENV_PRELOAD.search('ENV LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libjemalloc.so.2"'))


if __name__ == "__main__":
    unittest.main()
