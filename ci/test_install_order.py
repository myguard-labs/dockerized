#!/usr/bin/env python3
"""Check that the web-server package precedes lua-resty in every apt install.

lua-resty-core depends on
`nginx-http-lua-abi-* | nginx-stream-lua-abi-* | angie-http-lua-abi-* | ...`.
apt only resolves an or-group to a later alternative when that provider is
already installed or marked for install, otherwise it takes the first one.
With `lua-resty` listed before `angie-full`, every Angie image pulled in
libnginx-mod-http-lua -> nginx-common, which collides with angie-common on
the apport hook and fails the build (2026-10-21, 8 of 59 targets).
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INSTALL = "apt-get -y --no-install-recommends install \\"
PACKAGE = re.compile(r"^\s+(\S+) (?:\\|;\\?)$")
SERVER = {"nginx": "nginx-full", "angie": "angie-full"}


def install_lists(text):
    """Return the package lists of every multi-line apt-get install block."""
    lists, current = [], None
    for line in text.splitlines():
        if line.strip() == INSTALL:
            current = []
            continue
        if current is None:
            continue
        match = PACKAGE.match(line)
        if match:
            current.append(match.group(1))
            if match.group(0).rstrip("\\").endswith(";"):
                lists.append(current)
                current = None
        else:
            lists.append(current)
            current = None
    return lists


def server_before_lua_resty(packages, server):
    if "lua-resty" not in packages:
        return True
    return server in packages and packages.index(server) < packages.index("lua-resty")


class ServerBeforeLuaResty(unittest.TestCase):
    def test_every_server_dockerfile_orders_server_first(self):
        checked = 0
        for component, server in SERVER.items():
            for path in sorted((ROOT / "src" / component).glob("Dockerfile*")):
                lists = [p for p in install_lists(path.read_text()) if "lua-resty" in p]
                self.assertTrue(lists, f"{path}: no apt install block with lua-resty found")
                for packages in lists:
                    with self.subTest(file=str(path.relative_to(ROOT))):
                        self.assertTrue(server_before_lua_resty(packages, server),
                                        f"{server} must precede lua-resty: {packages}")
                    checked += 1
        self.assertGreaterEqual(checked, 34)

    def test_negative_control_lua_resty_first_is_rejected(self):
        self.assertFalse(server_before_lua_resty(["lua-resty", "angie-full"], "angie-full"))
        self.assertFalse(server_before_lua_resty(["lua-resty"], "angie-full"))

    def test_positive_and_boundary(self):
        self.assertTrue(server_before_lua_resty(["angie-full", "lua-resty"], "angie-full"))
        self.assertTrue(server_before_lua_resty(["curl"], "angie-full"))

    def test_parser_reads_template_block(self):
        text = (ROOT / "src/nginx/Dockerfile.template").read_text()
        lists = [p for p in install_lists(text) if "lua-resty" in p]
        self.assertEqual(len(lists), 1)
        self.assertIn("nginx-full", lists[0])


if __name__ == "__main__":
    unittest.main()
