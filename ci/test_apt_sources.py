#!/usr/bin/env python3
"""Check that our own APT mirrors are verified with the deb.myguard.nl key.

The ondrej-php mirror is re-signed by the deb.myguard.nl key. A
`[trusted=yes]` entry without `signed-by=` made apt warn "OpenPGP signature
verification failed ... Missing key" on every PHP image build and accept
unverified packages.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
URL = "http://edge.deb.myguard.nl:8888/mirror/ondrej-php"
MIRROR = re.compile(r"deb \[([^\]]*)\] http://edge\.deb\.myguard\.nl:8888/mirror/")
KEYRING = "signed-by=/usr/share/keyrings/deb.myguard.nl.gpg"


def mirror_lines(text):
    return [m.group(1) for m in MIRROR.finditer(text)]


def unsigned_mirror_options(text):
    return [opts for opts in mirror_lines(text) if KEYRING not in opts or "trusted=yes" in opts]


class OwnMirrorSigning(unittest.TestCase):
    def test_every_dockerfile_mirror_entry_uses_keyring(self):
        files = sorted((ROOT / "src").rglob("Dockerfile*"))
        seen = 0
        bad = []
        for path in files:
            text = path.read_text(errors="replace")
            seen += len(mirror_lines(text))
            rel = path.relative_to(ROOT)
            bad += [f"{rel}: [{o}]" for o in unsigned_mirror_options(text)]
        self.assertGreater(seen, 0, "no edge.deb.myguard.nl mirror entries found")
        self.assertEqual(bad, [])

    def test_signed_entry_accepted(self):
        self.assertEqual(unsigned_mirror_options(
            f'echo "deb [{KEYRING}] {URL} trixie main"'), [])

    def test_trusted_entry_rejected(self):
        self.assertEqual(unsigned_mirror_options(
            f'echo "deb [trusted=yes] {URL} trixie main"'),
            ["trusted=yes"])

    def test_trusted_with_keyring_rejected(self):
        line = f"deb [{KEYRING} trusted=yes] {URL} x main"
        self.assertEqual(len(unsigned_mirror_options(line)), 1)

    def test_other_hosts_ignored(self):
        line = "deb [trusted=yes] http://rspamd.com/apt-stable/ trixie main"
        self.assertEqual(mirror_lines(line), [])


if __name__ == "__main__":
    unittest.main()
