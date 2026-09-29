"""Run the modular enemy regression suite; script errors fail even if Godot exits 0."""
import argparse
import json
from pathlib import Path
import subprocess

TESTS = [
    "enemy_modular_contract_test",
    "enemy_optional_removal_test",
    "enemy_configuration_lifecycle_test",
    "reload_approach_timing_test",
    "utility_score_test",
    "utility_budget_test",
    "utility_search_cover_test",
    "utility_collision_recovery_test",
    "cover_tactical_safety_test",
    "stationary_cover_search_test",
    "attack_point_validation_test",
    "attack_region_quality_test",
    "close_range_spacing_test",
    "search_evidence_test",
    "search_navigation_recovery_test",
    "retreat_fire_credit_test",
    "lost_contact_initiative_test",
    "suppression_lane_test",
    "utility_suppression_blocked_test",
    "exit_suppression_geometry_test",
    "utility_suppression_trigger_test",
    "enemy_fire_timing_test",
    "enemy_fire_decision_test",
    "utility_runtime_test",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True, help="Godot console executable")
    parser.add_argument("tests", nargs="*", help="Optional test names, without .gd")
    args = parser.parse_args()
    test_directory = Path(__file__).resolve().parent
    project = test_directory.parents[1]
    logs = project / "logs" / "enemy_regressions"
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for name in args.tests or TESTS:
        if not (test_directory / (name + ".gd")).is_file():
            parser.error("Unknown test: " + name)
        command = [args.godot, "--headless", "--path", str(project),
                   "--log-file", str(logs / (name + ".log")),
                   "--script", "res://tests/enemy/" + name + ".gd"]
        try:
            run = subprocess.run(command, capture_output=True, timeout=75)
            output = (run.stdout + run.stderr).decode("utf-8", errors="replace")
            code = run.returncode
        except subprocess.TimeoutExpired as error:
            output = ((error.stdout or b"") + (error.stderr or b"")).decode("utf-8", errors="replace")
            code = "timeout"
        (logs / (name + "_stdout.log")).write_text(output, encoding="utf-8")
        errors = [line for line in output.splitlines()
                  if "SCRIPT ERROR:" in line or line.startswith("FAIL ")
                  or (line.startswith("ERROR:") and "root certificate store" not in line)]
        result = {"test": name, "passed": code == 0 and not errors,
                  "exit": code, "errors": errors[:20]}
        results.append(result)
        print(("PASS " if result["passed"] else "FAIL ") + name, flush=True)
        for line in errors[:3]:
            print("  " + line, flush=True)
        (logs / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Enemy regressions: {sum(r['passed'] for r in results)}/{len(results)} suites passed")
    return 0 if all(r["passed"] for r in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
