"""Release-tag restriction, unbound :testing guard and :testing identity check."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIB = ROOT / "build/lib-release.sh"
SHA = "770b6ecb521af13d44a4a26ef965df75c77cd99b"
OTHER = "d59e77d6b9affddd59d3c0b6a2fda92bbca5e2a3"
IMAGE = "docker.io/example/mailstrix:testing"


def sh(script, *args, env=None, path_prefix=None):
    e = dict(os.environ, **(env or {}))
    if path_prefix:
        e["PATH"] = f"{path_prefix}:{e['PATH']}"
    return subprocess.run(
        ["bash", "-c", f'. "{LIB}"; {script}', "_", *args],
        env=e,
        capture_output=True,
        text=True,
        check=False,
    )


def git(cwd, *args):
    subprocess.run(
        [
            "git",
            "-C",
            str(cwd),
            "-c",
            "user.name=t",
            "-c",
            "user.email=t@example.org",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "tag.gpgsign=false",
            *args,
        ],
        check=True,
        capture_output=True,
    )


def make_repo(tmp, tags_after_release=("nightly", "rules-current"), release=True):
    repo = Path(tmp) / "repo"
    repo.mkdir()
    git(repo, "init", "-q")
    git(repo, "commit", "-q", "--allow-empty", "-m", "one")
    if release:
        git(repo, "tag", "v1.2.0")
    git(repo, "commit", "-q", "--allow-empty", "-m", "two")
    for tag in tags_after_release:
        git(repo, "tag", tag)
    return repo


def fake_gh(tmp):
    """A gh that always fails, forcing the git fallback."""
    d = Path(tmp) / "bin"
    d.mkdir(exist_ok=True)
    (d / "gh").write_text("#!/bin/sh\nexit 1\n")
    (d / "gh").chmod(0o755)
    return str(d)


class ReleaseTagTest(unittest.TestCase):
    def test_moving_prerelease_tags_never_win(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            gh = fake_gh(tmp)
            self.assertEqual(
                sh('resolve_mailstrix_release "$1"', str(repo), path_prefix=gh).stdout,
                "1.2.0",
            )
            src = sh('mailstrix_source_version "$1"', str(repo)).stdout.strip()
            self.assertRegex(src, r"^v1\.2\.0-1-g[0-9a-f]{7,}$")

    def test_no_release_tag_yields_empty_release_and_sha_version(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(tmp, release=False)
            gh = fake_gh(tmp)
            self.assertEqual(
                sh('resolve_mailstrix_release "$1"', str(repo), path_prefix=gh).stdout,
                "",
            )
            self.assertRegex(
                sh('mailstrix_source_version "$1"', str(repo)).stdout.strip(),
                r"^[0-9a-f]{7,}$",
            )

    def test_negative_control_unrestricted_describe_returns_nightly(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(tmp)
            gh = fake_gh(tmp)
            mutated = Path(tmp) / "lib-mutated.sh"
            mutated.write_text(LIB.read_text().replace(" --match 'v[0-9]*'", ""))
            self.assertNotIn("--match", mutated.read_text())
            out = subprocess.run(
                [
                    "bash",
                    "-c",
                    (
                        f'. "{mutated}"; resolve_mailstrix_release "$1"; '
                        'printf " "; mailstrix_source_version "$1"'
                    ),
                    "_",
                    str(repo),
                ],
                env=dict(os.environ, PATH=f"{gh}:{os.environ['PATH']}"),
                capture_output=True,
                text=True,
                check=False,
            ).stdout.strip()
            self.assertTrue(out.startswith("nightly "), out)
            self.assertEqual(out, "nightly nightly")


class MainRefTest(unittest.TestCase):
    def resolve(self, git_body):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "git").write_text(f"#!/bin/sh\n{git_body}\n")
            (d / "git").chmod(0o755)
            return sh("resolve_mailstrix_main_ref", path_prefix=tmp).stdout.strip()

    def test_present(self):
        self.assertEqual(self.resolve(f'printf "{SHA}\\trefs/heads/main\\n"'), SHA)

    def test_absent_empty(self):
        self.assertEqual(self.resolve("exit 0"), "")

    def test_command_failure(self):
        self.assertEqual(self.resolve("exit 128"), "")

    def test_malformed(self):
        for bad in ("zzzz" + "0" * 36, SHA[:7], SHA.upper(), SHA + "00"):
            with self.subTest(bad=bad):
                self.assertEqual(
                    self.resolve(f'printf "{bad}\\trefs/heads/main\\n"'), ""
                )

    def decide(self, push, force, ref):
        return sh('testing_prebuild_decision "$@"', push, force, ref).stdout.strip()

    def test_decision_matrix(self):
        self.assertEqual(self.decide("--push", "0", SHA), "check")
        self.assertEqual(self.decide("--push", "1", SHA), "build")
        for ref in ("", "main", SHA[:7], "z" * 40):
            for force in ("0", "1"):
                with self.subTest(ref=ref, force=force):
                    self.assertEqual(self.decide("--push", force, ref), "unbound")
        # ad-hoc (non-push) builds keep the bake default
        self.assertEqual(self.decide("", "0", "main"), "build")
        self.assertEqual(self.decide("--load", "0", ""), "build")

    def test_absent_ref_end_to_end_is_skipped(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "git").write_text("#!/bin/sh\nexit 0\n")
            (d / "git").chmod(0o755)
            out = sh(
                'ref="$(resolve_mailstrix_main_ref)"; ref="${ref:-main}"; '
                'testing_prebuild_decision --push 1 "$ref"',
                path_prefix=tmp,
            ).stdout.strip()
            self.assertEqual(out, "unbound")

    def test_negative_control_without_guard_absent_case_builds(self):
        text = LIB.read_text()
        guarded = 'elif ! is_full_sha "$ref"; then\n        echo unbound'
        self.assertIn(guarded, text)
        with tempfile.TemporaryDirectory() as tmp:
            mutated = Path(tmp) / "lib.sh"
            mutated.write_text(
                text.replace(guarded, "elif false; then\n        echo unbound")
            )
            out = subprocess.run(
                [
                    "bash",
                    "-c",
                    f'. "{mutated}"; testing_prebuild_decision --push 1 main',
                ],
                capture_output=True,
                text=True,
                check=False,
            ).stdout.strip()
            self.assertEqual(out, "build")  # unguarded: would publish unbound


class WiringTest(unittest.TestCase):
    def test_sequential_uses_guard_identity_and_bake_version(self):
        seq = (ROOT / "build/buildx-sequential.sh").read_text()
        self.assertIn("testing_prebuild_decision", seq)
        self.assertIn("verify_testing_identity", seq)
        self.assertIn("UNBOUND_SKIPPED", seq)
        daily = (ROOT / "build/daily.sh").read_text()
        self.assertIn("resolve_mailstrix_main_ref", daily)
        bake = (ROOT / "docker-bake.hcl").read_text()
        self.assertIn('VERSION = "testing-${substr(MAILSTRIX_MAIN_REF, 0, 12)}"', bake)

    def test_testing_version_format(self):
        self.assertEqual(sh('testing_version "$1"', SHA).stdout, "testing-770b6ecb521a")


class IdentityTest(unittest.TestCase):
    def verify(self, labels_sha, run_out, run_rc=0, inspect_rc=0, ref=SHA):
        """docker stub: `buildx imagetools inspect` -> labelled image; `run` -> run_out."""
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            payload = d / "image.json"
            payload.write_text(
                json.dumps(
                    {
                        "linux/amd64": {
                            "os": "linux",
                            "architecture": "amd64",
                            "config": {
                                "Labels": {
                                    "org.opencontainers.image.revision": labels_sha
                                }
                            },
                        }
                    }
                )
            )
            (d / "docker").write_text(
                "#!/bin/sh\n"
                'case "$1" in\n'
                f'buildx) cat "{payload}"; exit {inspect_rc};;\n'
                f'run) printf "%s" "{run_out}"; exit {run_rc};;\n'
                "esac\n"
            )
            (d / "docker").chmod(0o755)
            return sh(
                'verify_testing_identity "$@"',
                ref,
                IMAGE,
                "linux/amd64",
                path_prefix=tmp,
            ).returncode

    def test_match(self):
        self.assertEqual(self.verify(SHA, "strixd testing-770b6ecb521a"), 0)

    def test_label_mismatch_fails(self):
        self.assertNotEqual(self.verify(OTHER, "strixd testing-770b6ecb521a"), 0)

    def test_version_mismatch_fails(self):
        self.assertNotEqual(self.verify(SHA, "strixd testing"), 0)
        self.assertNotEqual(self.verify(SHA, "strixd testing-d59e77d6b9af"), 0)

    def test_run_failure_fails(self):
        self.assertNotEqual(
            self.verify(SHA, "strixd testing-770b6ecb521a", run_rc=1), 0
        )

    def test_registry_unreachable_fails(self):
        self.assertNotEqual(
            self.verify(SHA, "strixd testing-770b6ecb521a", inspect_rc=1), 0
        )

    def test_unbound_ref_fails(self):
        self.assertNotEqual(self.verify("main", "strixd testing-main", ref="main"), 0)


if __name__ == "__main__":
    unittest.main()
