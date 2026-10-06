"""Check that the sequential builder distinguishes timeouts from killed clients."""

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class BuildFailuresTest(unittest.TestCase):
    def test_timeout_kill_and_ordinary_failure(self):
        source = (ROOT / "build/buildx-sequential.sh").read_text()
        start = source.index('            if [ "$EXIT_CODE" -eq 124 ]')
        end = source.index("            # Show full log path", start)
        block = source[start:end]
        functions = (
            'log_error() { printf "%s\\n" "$1"; }\n'
            'format_time() { printf "%s" "$1"; }\n'
        )
        for status in (124, 137, 1):
            with (
                self.subTest(status=status),
                tempfile.TemporaryDirectory(prefix="dockerized-failure-") as tmp,
            ):
                log = Path(tmp) / "build.log"
                log.write_text("build output\n")
                env = dict(
                    os.environ,
                    EXIT_CODE=str(status),
                    TARGET_ELAPSED="2",
                    BUILD_TIMEOUT="4h",
                    TARGET_LOG=str(log),
                )
                result = subprocess.run(
                    ["sh", "-eu", "-c", functions + block],
                    env=env,
                    check=True,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.stderr, "")
                if status == 124:
                    self.assertIn("TIMEOUT (limit 4h", result.stdout)
                    self.assertIn("TIMEOUT: build exceeded 4h", log.read_text())
                else:
                    self.assertIn(f"FAILED (2 exit code: {status})", result.stdout)
                    self.assertEqual(log.read_text(), "build output\n")


if __name__ == "__main__":
    unittest.main()
