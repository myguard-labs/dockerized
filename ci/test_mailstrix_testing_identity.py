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

    def test_prerelease_tags_never_win(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(tmp, tags_after_release=())
            git(repo, "commit", "-q", "--allow-empty", "-m", "three")
            git(repo, "tag", "v1.3.0-rc.1")
            for tag in ("nightly", "rules-current"):
                git(repo, "tag", tag)
            gh = fake_gh(tmp)
            self.assertEqual(
                sh('resolve_mailstrix_release "$1"', str(repo), path_prefix=gh).stdout,
                "1.2.0",
            )
            src = sh('mailstrix_source_version "$1"', str(repo)).stdout.strip()
            self.assertRegex(src, r"^v1\.2\.0-2-g[0-9a-f]{7,}$")

    def test_negative_control_without_exclude_prerelease_wins(self):
        with tempfile.TemporaryDirectory() as tmp:
            repo = make_repo(tmp, tags_after_release=())
            git(repo, "commit", "-q", "--allow-empty", "-m", "three")
            git(repo, "tag", "v1.3.0-rc.1")
            gh = fake_gh(tmp)
            mutated = Path(tmp) / "lib-mutated.sh"
            mutated.write_text(LIB.read_text().replace(" --exclude 'v*-*'", ""))
            self.assertNotIn("--exclude", mutated.read_text())
            out = subprocess.run(
                [
                    "bash",
                    "-c",
                    f'. "{mutated}"; resolve_mailstrix_release "$1"',
                    "_",
                    str(repo),
                ],
                env=dict(os.environ, PATH=f"{gh}:{os.environ['PATH']}"),
                capture_output=True,
                text=True,
                check=False,
            ).stdout
            self.assertEqual(out, "1.3.0-rc.1")  # unguarded: prerelease wins

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


class NightlyRefTest(unittest.TestCase):
    def resolve(self, git_body):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "git").write_text(f"#!/bin/sh\n{git_body}\n")
            (d / "git").chmod(0o755)
            return sh("resolve_mailstrix_nightly_ref", path_prefix=tmp).stdout.strip()

    def test_present(self):
        self.assertEqual(self.resolve(f'printf "{SHA}\\trefs/tags/nightly\\n"'), SHA)

    def test_annotated_tag_uses_peeled_commit(self):
        # ls-remote lists the tag object first, then the peeled ^{} commit
        self.assertEqual(
            self.resolve(
                f'printf "{OTHER}\\trefs/tags/nightly\\n'
                f'{SHA}\\trefs/tags/nightly^{{}}\\n"'
            ),
            SHA,
        )

    def test_peeled_commit_wins_regardless_of_order(self):
        self.assertEqual(
            self.resolve(
                f'printf "{SHA}\\trefs/tags/nightly^{{}}\\n'
                f'{OTHER}\\trefs/tags/nightly\\n"'
            ),
            SHA,
        )

    def test_queries_the_nightly_tag_not_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "git").write_text(f'#!/bin/sh\nprintf "%s\\n" "$@" > "{d}/args"\n')
            (d / "git").chmod(0o755)
            sh("resolve_mailstrix_nightly_ref", path_prefix=tmp)
            args = (d / "args").read_text().splitlines()
        self.assertEqual(args[0], "ls-remote")
        self.assertIn("refs/tags/nightly", args)
        self.assertIn("refs/tags/nightly^{}", args)
        self.assertNotIn("refs/heads/main", args)

    def test_other_refs_are_ignored(self):
        # a similarly named ref (or main) must never be taken for the tag
        for ref in ("refs/heads/main", "refs/tags/nightly-old", "refs/heads/nightly"):
            with self.subTest(ref=ref):
                self.assertEqual(self.resolve(f'printf "{SHA}\\t{ref}\\n"'), "")

    def test_absent_empty(self):
        self.assertEqual(self.resolve("exit 0"), "")

    def test_command_failure(self):
        self.assertEqual(self.resolve("exit 128"), "")

    def test_valid_line_but_failing_git_is_empty(self):
        self.assertEqual(
            self.resolve(f'printf "{SHA}\\trefs/tags/nightly\\n"; exit 1'), ""
        )

    def test_malformed(self):
        for bad in ("zzzz" + "0" * 36, SHA[:7], SHA.upper(), SHA + "00"):
            with self.subTest(bad=bad):
                self.assertEqual(
                    self.resolve(f'printf "{bad}\\trefs/tags/nightly\\n"'), ""
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
                'ref="$(resolve_mailstrix_nightly_ref)"; ref="${ref:-main}"; '
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
        self.assertIn("resolve_mailstrix_nightly_ref", daily)
        bake = (ROOT / "docker-bake.hcl").read_text()
        self.assertIn(
            'BUILD_VERSION = "nightly-${substr(MAILSTRIX_NIGHTLY_REF, 0, 12)}"', bake
        )

    def test_testing_target_downloads_the_nightly_release(self):
        out = subprocess.run(
            [
                "docker",
                "buildx",
                "bake",
                "-f",
                str(ROOT / "docker-bake.hcl"),
                "--print",
                "debian-mailstrix-testing",
            ],
            env=dict(os.environ, MAILSTRIX_NIGHTLY_REF=SHA),
            capture_output=True,
            text=True,
            check=False,
        )
        if out.returncode != 0:
            self.skipTest(f"docker buildx bake unavailable: {out.stderr.strip()[:200]}")
        tgt = json.loads(out.stdout)["target"]["debian-mailstrix-testing"]
        self.assertEqual(tgt["dockerfile"], "docker/Dockerfile.release")
        self.assertEqual(tgt["target"], "final")
        self.assertEqual(
            tgt["context"], f"https://github.com/myguard-labs/mailstrix.git#{SHA}"
        )
        self.assertEqual(tgt["args"]["RELEASE_TAG"], "nightly")
        self.assertEqual(tgt["args"]["RELEASE_CACHEBUST"], SHA)
        self.assertNotIn("VERSION", tgt["args"])  # VERSION would pick a release
        self.assertEqual(tgt["args"]["BUILD_VERSION"], "nightly-770b6ecb521a")
        self.assertEqual(tgt["labels"]["org.opencontainers.image.revision"], SHA)
        # the bake label and the identity check agree on the version string
        self.assertEqual(
            tgt["args"]["BUILD_VERSION"], sh('testing_version "$1"', SHA).stdout
        )
        self.assertEqual(sorted(tgt["platforms"]), ["linux/amd64", "linux/arm64"])

    def test_release_target_stays_on_release_binaries(self):
        out = subprocess.run(
            [
                "docker",
                "buildx",
                "bake",
                "-f",
                str(ROOT / "docker-bake.hcl"),
                "--print",
                "debian-mailstrix",
            ],
            env=dict(os.environ, MAILSTRIX_RELEASE="1.2.0"),
            capture_output=True,
            text=True,
            check=False,
        )
        if out.returncode != 0:
            self.skipTest(f"docker buildx bake unavailable: {out.stderr.strip()[:200]}")
        tgt = json.loads(out.stdout)["target"]["debian-mailstrix"]
        self.assertEqual(tgt["dockerfile"], "docker/Dockerfile.release")
        self.assertEqual(tgt["args"]["VERSION"], "1.2.0")
        self.assertNotIn("RELEASE_TAG", tgt["args"])
        self.assertEqual(sorted(tgt["platforms"]), ["linux/amd64", "linux/arm64"])

    def test_summary_counts_unbound_skip_once(self):
        seq = (ROOT / "build/buildx-sequential.sh").read_text()
        self.assertNotIn("Skipped (unchanged)", seq)
        self.assertNotIn("Skipped (unbound mailstrix:testing ref)", seq)
        self.assertIn("Skipped: $SKIPPED/$TOTAL_TARGETS", seq)
        self.assertIn("of which unbound mailstrix:testing ref", seq)
        # the unbound branch still feeds the overall skip total
        self.assertIn("UNBOUND_SKIPPED=$((UNBOUND_SKIPPED+1))", seq)
        self.assertIn("SKIPPED=$((SKIPPED+1))", seq)

    def test_testing_version_format(self):
        self.assertEqual(sh('testing_version "$1"', SHA).stdout, "nightly-770b6ecb521a")


def write_docker_stub(d, labels_sha, run_out):
    payload = d / "image.json"
    payload.write_text(
        json.dumps(
            {
                "linux/amd64": {
                    "os": "linux",
                    "architecture": "amd64",
                    "config": {
                        "Labels": {"org.opencontainers.image.revision": labels_sha}
                    },
                }
            }
        )
    )
    (d / "docker").write_text(
        "#!/bin/sh\n"
        'case "$1" in\n'
        f'buildx) cat "{payload}";;\n'
        f'run) printf "%s" "{run_out}";;\n'
        "esac\n"
    )
    (d / "docker").chmod(0o755)


def skip_block():
    """The skip-unchanged `if` from buildx-sequential.sh, verbatim."""
    text = (ROOT / "build/buildx-sequential.sh").read_text()
    start = text.index('            if [[ "$PUSH_ARG" == "--push" && "${MAILSTRIX_TESTING_FORCE')
    end = text.index("\n            fi\n", start) + len("\n            fi\n")
    return text[start:end]


def run_skip_block(block, labels_sha, run_out):
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        write_docker_stub(d, labels_sha, run_out)
        script = (
            f'. "{LIB}"; log_info() {{ :; }}; SKIPPED=0; PUSH_ARG=--push; '
            f"MAILSTRIX_NIGHTLY_REF={SHA}; TESTING_IMAGE={IMAGE}; "
            "TESTING_PLATFORMS=(linux/amd64)\n"
            f"for _ in 1; do\n{block}\necho BUILD\ndone"
        )
        return sh(script, path_prefix=tmp).stdout.strip()


class SkipPathTest(unittest.TestCase):
    def test_label_and_version_match_is_skipped(self):
        out = run_skip_block(skip_block(), SHA, "strixd nightly-770b6ecb521a")
        self.assertEqual(out, "")  # `continue` before echo BUILD

    def test_label_match_but_old_version_is_built(self):
        out = run_skip_block(skip_block(), SHA, "strixd testing")
        self.assertEqual(out, "BUILD")

    def test_label_mismatch_is_built(self):
        out = run_skip_block(skip_block(), OTHER, "strixd nightly-770b6ecb521a")
        self.assertEqual(out, "BUILD")

    def test_negative_control_label_only_skips_old_version(self):
        block = skip_block()
        self.assertIn("verify_testing_identity", block)
        mutated = block.replace("verify_testing_identity", "image_built_from")
        # revision label alone would skip an image whose version is stale
        self.assertEqual(run_skip_block(mutated, SHA, "strixd testing"), "")


class DailyWiringTest(unittest.TestCase):
    def test_unbound_warning_accepts_same_push_values_as_sequential(self):
        seq = (ROOT / "build/buildx-sequential.sh").read_text()
        daily = (ROOT / "build/daily.sh").read_text()
        self.assertIn('"$PUSH" == "1" || "$PUSH" == "true"', seq)
        self.assertIn(
            'if [[ "$PUSH" == 1 || "$PUSH" == true ]] && ! is_full_sha', daily
        )


class IdentityTest(unittest.TestCase):
    def verify(self, labels_sha, run_out, run_rc=0, inspect_rc=0, ref=SHA):
        return self.verify_calls(labels_sha, run_out, run_rc, inspect_rc, ref)[0]

    def verify_calls(self, labels_sha, run_out, run_rc=0, inspect_rc=0, ref=SHA):
        """Return (exit code, docker argv lines recorded by the stub)."""
        rc, calls, _ = self.verify_full(labels_sha, run_out, run_rc, inspect_rc, ref)
        return rc, calls

    def verify_full(
        self,
        labels_sha,
        run_out,
        run_rc=0,
        inspect_rc=0,
        ref=SHA,
        script='verify_testing_identity "$@"',
    ):
        """Return (exit code, docker argv lines, stderr text) from the stub run."""
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            calls = d / "calls.log"
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
                f'echo "$*" >> "{calls}"\n'
                'case "$1" in\n'
                f'buildx) cat "{payload}"; exit {inspect_rc};;\n'
                f'run) printf "%s" "{run_out}"; exit {run_rc};;\n'
                "rm) exit 0;;\n"
                "esac\n"
            )
            (d / "docker").chmod(0o755)
            done = sh(
                script,
                ref,
                IMAGE,
                "linux/amd64",
                path_prefix=tmp,
            )
            recorded = calls.read_text() if calls.exists() else ""
            return done.returncode, recorded.splitlines(), done.stderr

    def test_match(self):
        self.assertEqual(self.verify(SHA, "strixd nightly-770b6ecb521a"), 0)

    def test_label_mismatch_fails(self):
        self.assertNotEqual(self.verify(OTHER, "strixd nightly-770b6ecb521a"), 0)

    def test_version_mismatch_fails(self):
        self.assertNotEqual(self.verify(SHA, "strixd testing"), 0)
        self.assertNotEqual(self.verify(SHA, "strixd nightly-d59e77d6b9af"), 0)

    def test_run_failure_fails(self):
        self.assertNotEqual(
            self.verify(SHA, "strixd nightly-770b6ecb521a", run_rc=1), 0
        )

    def test_registry_unreachable_fails(self):
        self.assertNotEqual(
            self.verify(SHA, "strixd nightly-770b6ecb521a", inspect_rc=1), 0
        )

    def test_unbound_ref_fails(self):
        self.assertNotEqual(self.verify("main", "strixd nightly-main", ref="main"), 0)

    @staticmethod
    def run_name(calls):
        """The --name value of the recorded `run` call (exactly one expected)."""
        runs = [line.split() for line in calls if line.startswith("run ")]
        assert len(runs) == 1, calls
        argv = runs[0]
        return argv[argv.index("--name") + 1]

    def test_timeout_force_removes_named_container(self):
        rc, calls = self.verify_calls(SHA, "", run_rc=124)
        self.assertNotEqual(rc, 0)
        name = self.run_name(calls)
        self.assertRegex(name, r"^dockerized-testing-identity-\d+-\d+$")
        self.assertIn(f"rm -f {name}", calls)

    def test_run_failure_force_removes_named_container(self):
        rc, calls = self.verify_calls(SHA, "strixd nightly-770b6ecb521a", run_rc=1)
        self.assertNotEqual(rc, 0)
        self.assertIn(f"rm -f {self.run_name(calls)}", calls)

    def test_success_does_not_remove_container(self):
        rc, calls = self.verify_calls(SHA, "strixd nightly-770b6ecb521a")
        self.assertEqual(rc, 0)
        self.assertFalse(any(line.startswith("rm ") for line in calls), calls)

    def test_two_calls_in_one_shell_get_distinct_names(self):
        # prebuild skip check and post-push check share $$; the nonce must differ
        rc, calls, _ = self.verify_full(
            SHA,
            "",
            run_rc=124,
            script='verify_testing_identity "$@"; verify_testing_identity "$@"',
        )
        self.assertNotEqual(rc, 0)
        runs = [line.split() for line in calls if line.startswith("run ")]
        self.assertEqual(len(runs), 2, calls)
        names = [argv[argv.index("--name") + 1] for argv in runs]
        self.assertNotEqual(names[0], names[1])
        for name in names:
            self.assertRegex(name, r"^dockerized-testing-identity-\d+-\d+$")
            self.assertIn(f"rm -f {name}", calls)

    def test_failure_branches_print_one_reason_line(self):
        rc, _, err = self.verify_full(OTHER, "strixd nightly-770b6ecb521a")
        self.assertNotEqual(rc, 0)
        self.assertEqual(
            err,
            f"identity: revision label check failed for {IMAGE} (want {SHA})\n",
        )
        rc, _, err = self.verify_full(SHA, "", inspect_rc=1)
        self.assertEqual(
            err,
            f"identity: revision label check failed for {IMAGE} (want {SHA})\n",
        )
        rc, _, err = self.verify_full(SHA, "", run_rc=124)
        self.assertEqual(err, "identity: docker run failed rc=124\n")
        rc, _, err = self.verify_full(SHA, "strixd nightly-770b6ecb521a", run_rc=1)
        self.assertEqual(err, "identity: docker run failed rc=1\n")
        rc, _, err = self.verify_full(SHA, "strixd testing")
        self.assertNotEqual(rc, 0)
        self.assertEqual(
            err,
            "identity: version mismatch: got 'strixd testing' "
            "want 'strixd nightly-770b6ecb521a'\n",
        )

    def test_success_prints_nothing_on_stderr(self):
        rc, _, err = self.verify_full(SHA, "strixd nightly-770b6ecb521a")
        self.assertEqual(rc, 0)
        self.assertEqual(err, "")


if __name__ == "__main__":
    unittest.main()
