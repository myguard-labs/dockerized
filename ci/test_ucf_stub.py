#!/usr/bin/env python3
"""Check the ucf stub around the PHP installs and the merged multi install.

ucf asks debconf about every module .ini it registers, which dominated PHP
install time (multi: 7 installs of ~30 modules). The php-fpm generator now
emits one install RUN per Dockerfile, wrapped in a ucf copy with its debconf
block disabled, and puts the real ucf back in the same RUN. roundcube and
vimbadmin carry the same stub lines.
"""

import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FPM = ROOT / "src" / "php-fpm"
GEN = FPM / ".generate.sh"
FAST = "UCF_FORCE_CONFFNEW=1 apt-get install -y --no-install-recommends \\"
PKG = re.compile(r"^\s+php[0-9.]+(-[a-z0-9]+)? (\\|;\\)$")


def stub(name):
    text = GEN.read_text()
    return re.search(rf"UCF_STUB_{name} <<'EOF' \|\| true\n(.*?)\nEOF", text, re.S).group(1)


def php_versions():
    text = (ROOT / "build" / "config.sh").read_text()
    return re.search(r"PHP_VERSIONS=\(([^)]*)\)", text).group(1).split()


def check_install(text):
    """Return a list of problems with the PHP install of one Dockerfile."""
    lines = text.split("\n")
    on, off = stub("ON").split("\n"), stub("OFF").split("\n")
    problems = []
    if text.count(FAST) != 1:
        return ["want exactly one stubbed install, got %d" % text.count(FAST)]
    i = [l.strip() for l in lines].index(FAST)
    if lines[i - len(on):i] != on:
        problems.append("ucf stub not right before the install")
    j = i + 1
    while j < len(lines) and PKG.match(lines[j]) and lines[j].endswith(" \\"):
        j += 1
    if j >= len(lines) or not PKG.match(lines[j]) or not lines[j].endswith(" ;\\"):
        problems.append("package list does not end in ' ;\\' at line %d" % (j + 1))
    elif lines[j + 1:j + 1 + len(off)] != off:
        problems.append("real ucf not restored right after the install")
    plain = [l for l in lines if "apt-get install" in l and re.search(r"\bphp[0-9]", l)]
    if plain:
        problems.append("unstubbed php install: %s" % plain)
    return problems


def run_generator(tree):
    return subprocess.run(["bash", str(tree / "src/php-fpm/.generate.sh")],
                          capture_output=True, text=True)


def copy_tree(dst):
    shutil.copytree(ROOT / "build", dst / "build")
    shutil.copytree(FPM, dst / "src/php-fpm")


def apply_stub(ucf_text):
    """Run the stub's sed + fallback against a fixture ucf; return the result."""
    with tempfile.TemporaryDirectory() as d:
        real, out = Path(d, "ucf.real"), Path(d, "ucf")
        real.write_text(ucf_text)
        cmds = [l.strip().rstrip("\\").rstrip().rstrip(";") for l in stub("ON").split("\n")
                if l.strip().startswith(("sed ", "grep "))]
        script = " ;\n".join(cmds).replace("/usr/bin/ucf.real", str(real)).replace("/usr/bin/ucf", str(out))
        subprocess.run(["sh", "-ec", script], check=True)
        return out.read_text()


UCF_FIXTURE = """#!/bin/bash
set -e
if [ -e /usr/share/debconf/confmodule ]; then
  . /usr/share/debconf/confmodule
fi
db_stop
"""


class UcfStub(unittest.TestCase):
    def test_every_php_fpm_dockerfile_is_stubbed(self):
        files = sorted(FPM.glob("Dockerfile-[0-9m]*"))
        self.assertEqual(len(files), 2 * len(php_versions()) + 2)
        for path in files:
            with self.subTest(file=path.name):
                self.assertEqual(check_install(path.read_text()), [])

    def test_multi_has_one_install_with_every_version(self):
        for distro in ("deb", "ubu"):
            text = (FPM / f"Dockerfile-multi-{distro}").read_text()
            with self.subTest(distro=distro):
                self.assertEqual(text.count("apt-get install -y --no-install-recommends \\"), 1)
                for v in php_versions():
                    self.assertRegex(text, rf"\n\s+php{re.escape(v)}-fpm \\")

    def test_roundcube_and_vimbadmin_carry_same_stub(self):
        for name in ("roundcube", "vimbadmin"):
            text = (ROOT / "src" / name / "Dockerfile").read_text()
            with self.subTest(image=name):
                self.assertIn(stub("ON") + "\n" + "    " + FAST, text)
                self.assertIn("\n" + stub("OFF") + " ;\\\n", text)

    def test_generated_dockerfiles_up_to_date(self):
        with tempfile.TemporaryDirectory() as d:
            tree = Path(d)
            copy_tree(tree)
            res = run_generator(tree)
            self.assertEqual(res.returncode, 0, res.stderr)
            for path in sorted(FPM.glob("Dockerfile-[0-9m]*")):
                with self.subTest(file=path.name):
                    self.assertEqual((tree / "src/php-fpm" / path.name).read_text(), path.read_text())

    def test_stripping_last_package_keeps_list_closed(self):
        with tempfile.TemporaryDirectory() as d:
            tree = Path(d)
            copy_tree(tree)
            cfg = tree / "build/config.sh"
            cfg.write_text(cfg.read_text().replace("declare -ga PHP_UBUNTU_MISSING_EXTS=(\n",
                                                   "declare -ga PHP_UBUNTU_MISSING_EXTS=(\n    zip\n", 1))
            res = run_generator(tree)
            self.assertEqual(res.returncode, 0, res.stderr)
            text = (tree / "src/php-fpm/Dockerfile-85-ubu").read_text()
            self.assertNotIn("php8.5-zip", text)
            self.assertEqual(check_install(text), [])

    def test_generator_rejects_non_package_line(self):
        with tempfile.TemporaryDirectory() as d:
            tree = Path(d)
            copy_tree(tree)
            tpl = tree / "src/php-fpm/Dockerfile-template.php"
            tpl.write_text(tpl.read_text().replace("      php#PHPVERSION#-zip",
                                                   "      php#PHPVERSION#-zip \\\n      rm -rf /",
                                                   1))
            res = run_generator(tree)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("not a package", res.stderr)

    def test_generator_rejects_missing_install_line(self):
        with tempfile.TemporaryDirectory() as d:
            tree = Path(d)
            copy_tree(tree)
            tpl = tree / "src/php-fpm/Dockerfile-template.php"
            tpl.write_text(tpl.read_text().replace("apt-get install", "apt-get  install"))
            res = run_generator(tree)
            self.assertNotEqual(res.returncode, 0)
            self.assertIn("missing install line", res.stderr)

    def test_stub_disables_debconf_block(self):
        out = apply_stub(UCF_FIXTURE)
        self.assertIn("\nif false; then\n", out)
        self.assertNotIn("if [ -e /usr/share/debconf/confmodule ]", out)
        self.assertEqual(out.split("\n")[1], "db_stop() { :; }")

    def test_stub_falls_back_to_real_ucf_when_pattern_moves(self):
        moved = UCF_FIXTURE.replace("if [ -e", "if  [ -e")
        self.assertEqual(apply_stub(moved), moved)

    def test_missing_restore_detected(self):
        text = (FPM / "Dockerfile-85-deb").read_text().replace(stub("OFF"), "    true")
        self.assertIn("real ucf not restored right after the install", check_install(text))

    def test_unstubbed_install_detected(self):
        text = (FPM / "Dockerfile-85-deb").read_text()
        text += "RUN apt-get install -y --no-install-recommends php8.5-vips\n"
        self.assertTrue(any("unstubbed" in p for p in check_install(text)))

    def test_dangling_continuation_detected(self):
        text = (FPM / "Dockerfile-85-deb").read_text().replace("php8.5-zip ;\\", "php8.5-zip \\")
        self.assertTrue(any("does not end" in p for p in check_install(text)))


if __name__ == "__main__":
    unittest.main()
