"""Shared process/log handling for the existing Godot regression entry points."""
import argparse
import json
from pathlib import Path
import re
import subprocess


def output_errors(output):
    return [line for line in output.splitlines()
            if "SCRIPT ERROR:" in line
            or re.match(r"^\s*FAIL(?:\s|:|$)", line)
            or (line.lstrip().startswith("ERROR:") and "root certificate store" not in line)]


def validate_names(directory, names):
    if not names:
        raise ValueError("No tests selected")
    if len(set(names)) != len(names):
        raise ValueError("Duplicate test names")
    for name in names:
        if not re.fullmatch(r"[A-Za-z0-9_]+", name) or not (directory / (name + ".gd")).is_file():
            raise ValueError("Unknown test: " + name)


def run_tests(godot, project, directory, names, logs, label, timeouts=None, editor=False):
    validate_names(directory, names)
    logs = Path(logs).resolve()
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for name in names:
        script = "res://" + (directory / (name + ".gd")).relative_to(project).as_posix()
        command = [str(godot), "--headless", "--path", str(project),
                   "--log-file", str(logs / (name + ".log"))]
        if editor:
            command.append("--editor")
        command += ["--script", script]
        try:
            run = subprocess.run(command, capture_output=True,
                                 timeout=(timeouts or {}).get(name, 75))
            output = (run.stdout + run.stderr).decode("utf-8", errors="replace")
            code = run.returncode
        except subprocess.TimeoutExpired as error:
            output = ((error.stdout or b"") + (error.stderr or b"")).decode("utf-8", errors="replace")
            code = "timeout"
        except OSError as error:
            output = "ERROR: Unable to start Godot: " + str(error)
            code = "launch_error"
        (logs / (name + "_stdout.log")).write_text(output, encoding="utf-8")
        errors = output_errors(output)
        result = {"test": name, "passed": code == 0 and not errors,
                  "exit": code, "errors": errors[:20]}
        results.append(result)
        print(("PASS " if result["passed"] else "FAIL ") + name, flush=True)
        for line in errors[:3]:
            print("  " + line, flush=True)
        (logs / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"{label}: {sum(r['passed'] for r in results)}/{len(results)} suites passed")
    return 0 if all(r["passed"] for r in results) else 1


def suite_main(directory, project, defaults, log_name, label, timeouts=None):
    parser = argparse.ArgumentParser(description=label)
    parser.add_argument("--godot", required=True, help="Godot console executable")
    parser.add_argument("tests", nargs="*", help="Optional test names, without .gd")
    args = parser.parse_args()
    names = args.tests or defaults
    try:
        validate_names(directory, names)
    except ValueError as error:
        parser.error(str(error))
    return run_tests(args.godot, project, directory, names, project / "logs" / log_name,
                     label, timeouts)
