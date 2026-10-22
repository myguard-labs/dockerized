#!/usr/bin/env python3
"""Check that php images get a Snuffleupagus secret_key per container.

The php*-snuffleupagus postinst writes a random secret_key at install time,
which is image build time: every container of a published image would share
it. The php-fpm build puts the package placeholder back before /etc/php moves
to /etc/php.orig, and every bootstrap that populates /etc/php runs
snuffleupagus-secret, which fills the placeholder with one key per container
and keeps a key that is already set.
"""

import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar

ROOT = Path(__file__).resolve().parents[1]
PHPFPM = ROOT / "src" / "php-fpm"
HELPER = PHPFPM / "snuffleupagus-secret.sh"
INSTALLED = "/usr/local/sbin/snuffleupagus-secret"
PLACEHOLDER = "YOU _DO_ NEED TO CHANGE THIS WITH SOME RANDOM CHARACTERS."
KEY_LINE = re.compile(r'^sp\.global\.secret_key\("([^"]*)"\);', re.M)
RESET_SED = re.compile(r"sed -i -E '(s/\^\(sp\\\.global\\\.secret_key[^']*)'")

RULES = """# secret_key must match across rulebooks
sp.global.secret_key("{key}");
sp.disable_function.function("exec").drop();
"""


def rules(key=PLACEHOLDER):
    return RULES.format(key=key)


def keys(path):
    return KEY_LINE.findall(path.read_text())


class Helper(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory()))

    def put(self, ver, name, text):
        d = self.root / ver / "php-snuffleupagus"
        d.mkdir(parents=True, exist_ok=True)
        (d / name).write_text(text)
        return d / name

    def run_helper(self, helper=HELPER):
        return subprocess.run(["sh", str(helper), str(self.root)],
                              capture_output=True, text=True, check=False)

    def test_fills_placeholder_with_one_key_for_all_versions(self):
        files = [self.put(v, n, rules()) for v in ("7.4", "8.5")
                 for n in ("php-relax.rules", "mcp-agent.rules")]
        r = self.run_helper()
        self.assertEqual(r.returncode, 0, r.stderr)
        found = {k for f in files for k in keys(f)}
        self.assertEqual(len(found), 1)
        key = found.pop()
        self.assertRegex(key, r"^[A-Za-z0-9]{64}$")
        self.assertIn("exec", files[0].read_text())

    def test_new_key_each_container(self):
        a = self.put("8.5", "php-relax.rules", rules())
        self.run_helper()
        first = keys(a)[0]
        a.write_text(rules())
        self.run_helper()
        self.assertNotEqual(first, keys(a)[0])

    def test_second_start_keeps_key(self):
        f = self.put("8.5", "php-relax.rules", rules())
        self.run_helper()
        before = f.read_text()
        r = self.run_helper()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(before, f.read_text())
        self.assertNotIn("generated", r.stdout)

    def test_reuses_existing_key_for_later_version(self):
        existing = "A" * 40
        self.put("8.4", "php-relax.rules", rules(existing))
        late = self.put("8.5", "php-relax.rules", rules())
        self.assertEqual(self.run_helper().returncode, 0)
        self.assertEqual(keys(late), [existing])

    def test_ignores_short_existing_key(self):
        self.put("8.4", "php-relax.rules", rules("short"))
        late = self.put("8.5", "php-relax.rules", rules())
        self.run_helper()
        self.assertRegex(keys(late)[0], r"^[A-Za-z0-9]{64}$")

    def test_no_rules_is_a_noop(self):
        (self.root / "8.5" / "fpm").mkdir(parents=True)
        r = self.run_helper()
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout, "")

    def test_file_without_key_line_untouched(self):
        readme = self.put("8.5", "README.rules", "# secret_key notes only\n")
        self.put("8.5", "php-relax.rules", rules())
        self.run_helper()
        self.assertEqual(readme.read_text(), "# secret_key notes only\n")

    def test_negative_control_broken_helper_fails_check(self):
        broken = self.root / "broken.sh"
        broken.write_text(HELPER.read_text().replace('sed -i "s/YOU', 'true "s/YOU'))
        f = self.put("8.5", "php-relax.rules", rules())
        self.run_helper(broken)
        self.assertEqual(keys(f), [PLACEHOLDER])


class BuildReset(unittest.TestCase):
    def setUp(self):
        self.footer = (PHPFPM / "Dockerfile-template.footer").read_text()

    def test_reset_runs_before_move_to_orig(self):
        reset = self.footer.index("sp\\.global\\.secret_key")
        move = self.footer.index("mv /etc/php /etc/php.orig")
        self.assertLess(reset, move)

    def test_reset_expression_restores_placeholder(self):
        expr = RESET_SED.search(self.footer).group(1)
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "x.rules"
            path.write_text(rules("Xy9" * 21) + '# sp.global.secret_key("comment");\n',
                            encoding="utf-8")
            subprocess.run(["sed", "-i", "-E", expr, str(path)], check=True)
            text = path.read_text(encoding="utf-8")
        self.assertEqual(KEY_LINE.findall(text), [PLACEHOLDER])
        self.assertNotIn("Xy9", text)
        self.assertIn('# sp.global.secret_key("comment");', text)

    def test_generated_dockerfiles_install_helper_and_reset(self):
        dockerfiles = sorted(PHPFPM.glob("Dockerfile-*-*"))
        dockerfiles = [p for p in dockerfiles if "template" not in p.name]
        self.assertGreaterEqual(len(dockerfiles), 2)
        for p in dockerfiles:
            text = p.read_text()
            with self.subTest(dockerfile=p.name):
                self.assertIn(f"COPY --chmod=0755 snuffleupagus-secret.sh {INSTALLED}", text)
                self.assertLess(text.index("sp\\.global\\.secret_key"),
                                text.index("mv /etc/php /etc/php.orig"))


class BootstrapWiring(unittest.TestCase):
    CASES: ClassVar[dict[str, tuple[str, str]]] = {
        "src/php-fpm/bootstrap.sh":
            ("cp -r /etc/php.orig/* /etc/php/", "php-fpm${PHPVERSION} -t"),
        "src/apache-phpfpm/bootstrap.sh":
            ("cp -r /etc/php.orig/${PHPVERSION}/*", "php-fpm${PHPVERSION} -t"),
        "src/nginx/s6-scripts/init-bootstrap.sh":
            ('cp -r "/etc/php.orig/${_v}/"*', "php-fpm${_v} -t"),
        "src/angie/s6-scripts/init-bootstrap.sh":
            ('cp -r "/etc/php.orig/${_v}/"*', "php-fpm${_v} -t"),
    }

    def test_helper_runs_after_copy_before_fpm_check(self):
        for rel, (copy, check) in self.CASES.items():
            text = (ROOT / rel).read_text()
            with self.subTest(script=rel):
                call = text.index(INSTALLED)
                self.assertLess(text.index(copy), call)
                self.assertLess(call, text.index(check))
                self.assertRegex(text[call:call + 200], r"\|\|\s*(exit 1|\{)")


if __name__ == "__main__":
    unittest.main()
