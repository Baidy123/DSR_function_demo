"""Verify that runtime errors/timeouts cannot be reported as passing regressions."""
import contextlib
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from regression_runner import run_tests
from run_regressions import check_catalog


class RunnerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name)
        self.directory = self.project / "tests"
        self.directory.mkdir()
        (self.directory / "sample.gd").write_text("extends SceneTree\n", encoding="utf-8")
        self.logs = self.project / "logs"

    def run_sample(self, output=b"", code=0, error=None):
        response = subprocess.CompletedProcess([], code, stdout=output, stderr=b"")
        with patch("regression_runner.subprocess.run", return_value=response, side_effect=error) as execute:
            with contextlib.redirect_stdout(io.StringIO()):
                status = run_tests("godot", self.project, self.directory, ["sample"], self.logs,
                                   "fixture", {"sample": 12})
        result = json.loads((self.logs / "results.json").read_text(encoding="utf-8"))[0]
        self.assertEqual(execute.call_args.kwargs["timeout"], 12)
        self.assertIn("res://tests/sample.gd", execute.call_args.args[0])
        return status, result

    def test_zero_exit_with_script_error_fails(self):
        status, result = self.run_sample(b"SCRIPT ERROR: Invalid call\n")
        self.assertEqual(status, 1)
        self.assertFalse(result["passed"])
        self.assertTrue((self.logs / "sample_stdout.log").read_text().startswith("SCRIPT ERROR:"))

    def test_both_assertion_prefixes_fail(self):
        for text in [b"FAIL assertion\n", b"FAIL: assertion\n"]:
            with self.subTest(text=text):
                self.assertEqual(self.run_sample(text)[0], 1)

    def test_existing_certificate_exception_remains_narrow(self):
        output = b"ERROR: Cannot open root certificate store\nPASS fixture\n"
        self.assertEqual(self.run_sample(output)[0], 0)
        self.assertEqual(self.run_sample(output + b"ERROR: Missing resource\n")[0], 1)

    def test_nonzero_exit_fails_without_error_text(self):
        self.assertEqual(self.run_sample(b"partial output", 2)[0], 1)

    def test_timeout_preserves_partial_output(self):
        status, result = self.run_sample(error=subprocess.TimeoutExpired("godot", 12, output=b"before timeout"))
        self.assertEqual(status, 1)
        self.assertEqual(result["exit"], "timeout")
        self.assertEqual((self.logs / "sample_stdout.log").read_bytes(), b"before timeout")

    def test_launch_failure_is_recorded(self):
        status, result = self.run_sample(error=FileNotFoundError("missing Godot"))
        self.assertEqual(status, 1)
        self.assertEqual(result["exit"], "launch_error")

    def test_invalid_selection_fails_before_any_process_starts(self):
        for names in [[], ["sample", "missing"], ["sample", "sample"], ["../sample"]]:
            with self.subTest(names=names), patch("regression_runner.subprocess.run") as execute:
                with self.assertRaises(ValueError):
                    run_tests("godot", self.project, self.directory, names, self.logs, "fixture")
                execute.assert_not_called()

    def test_catalog_covers_every_gd_script(self):
        check_catalog()


if __name__ == "__main__":
    unittest.main()
