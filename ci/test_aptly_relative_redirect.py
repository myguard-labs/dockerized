#!/usr/bin/env python3
"""Check that the aptly repo server emits relative redirects.

The container listens on 80 but is published on another host port (:8888).
nginx's default absolute directory redirect drops that port, sending clients
to the public :80/:443 vhost instead. `absolute_redirect off;` must stay in
the repo server block.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONF = ROOT / "src" / "aptly" / "nginx.conf"
DIRECTIVE = re.compile(r"^\s*absolute_redirect\s+off\s*;", re.MULTILINE)


def strip_comments(text):
    return "\n".join(line.split("#", 1)[0] for line in text.splitlines())


def relative_redirects(text):
    return bool(DIRECTIVE.search(strip_comments(text)))


class AptlyRelativeRedirectTest(unittest.TestCase):
    def test_shipped_conf_disables_absolute_redirect(self):
        self.assertTrue(relative_redirects(CONF.read_text()))

    def test_missing_directive_is_detected(self):
        self.assertFalse(relative_redirects("server {\n    root /x;\n}\n"))

    def test_commented_directive_is_not_enough(self):
        self.assertFalse(relative_redirects("    # absolute_redirect off;\n"))

    def test_absolute_redirect_on_is_rejected(self):
        self.assertFalse(relative_redirects("    absolute_redirect on;\n"))


if __name__ == "__main__":
    unittest.main()
