#!/usr/bin/env python3
"""Check the lua strip in the nginx/angie boot scripts.

Without NGX_MODULES every module is enabled, and the boot scripts drop the
lua modules that need extra configuration. The package reorder script links
http-lua at 20 (not 50), and lua-upstream resolves symbols from http-lua, so
the strip must match any priority and drop lua-upstream with it. The .quiet
opt-out lives in modules-enabled.
"""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = [
    (ROOT / "src" / server / name, server)
    for server in ("nginx", "angie")
    for name in ("bootstrap.sh", "s6-scripts/init-bootstrap.sh")
]
ENABLED = [
    "10-mod-http-ndk.conf",
    "15-mod-stream.conf",
    "20-mod-http-lua.conf",
    "50-mod-http-echo.conf",
    "50-mod-http-lua-upstream.conf",
    "50-mod-stream-lua.conf",
]
KEPT = ["10-mod-http-ndk.conf", "15-mod-stream.conf", "50-mod-http-echo.conf"]


def strip_block(text):
    """Return the shell lines of the quiet-guarded strip block."""
    match = re.search(
        r'^    if \[ ! -e "(?P<quiet>[^"]+)" \]; then\n(?P<body>.*?)^    fi$',
        text,
        re.MULTILINE | re.DOTALL,
    )
    if not match:
        raise AssertionError("strip block not found")
    return match.group("quiet"), match.group("body")


def run_strip(body, server, enabled):
    body = body.replace(f"/etc/{server}/modules-enabled", str(enabled))
    subprocess.run(["sh", "-ec", body], check=True, capture_output=True)
    return sorted(p.name for p in enabled.iterdir())


class ModuleStripTest(unittest.TestCase):
    def setUp(self):
        self.enabled = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def populate(self):
        for p in self.enabled.iterdir():
            p.unlink()
        for name in ENABLED:
            (self.enabled / name).touch()

    def test_strip_removes_lua_at_any_priority(self):
        for script, server in SCRIPTS:
            with self.subTest(script=str(script.relative_to(ROOT))):
                self.populate()
                _, body = strip_block(script.read_text())
                self.assertEqual(run_strip(body, server, self.enabled), KEPT)

    def test_quiet_marker_in_modules_enabled(self):
        for script, server in SCRIPTS:
            with self.subTest(script=str(script.relative_to(ROOT))):
                quiet, _ = strip_block(script.read_text())
                self.assertEqual(quiet, f"/etc/{server}/modules-enabled/.quiet")

    def test_old_fixed_priority_strip_misses_lua(self):
        # Negative control: the former 50- names leave 20-mod-http-lua.conf
        # and its consumer lua-upstream enabled.
        self.populate()
        old = (
            "        rm -f /etc/nginx/modules-enabled/50-mod-http-lua.conf\n"
            "        rm -f /etc/nginx/modules-enabled/50-mod-stream-lua.conf\n"
        )
        left = run_strip(old, "nginx", self.enabled)
        self.assertIn("20-mod-http-lua.conf", left)
        self.assertIn("50-mod-http-lua-upstream.conf", left)


if __name__ == "__main__":
    unittest.main()
