"""Run player combat and aim regressions; script errors fail even if Godot exits 0."""
import argparse
import json
from pathlib import Path
import subprocess

TESTS = ["aim_disruption_test", "combat_compatibility_test", "player_reload_test", "player_reload_checkpoint_test",
         "weapon_ammo_test", "weapon_slots_test", "player_health_test",
         "player_automatic_fire_test", "player_melee_test", "player_melee_presentation_test",
         "player_melee_physics_test", "player_melee_zone_test", "player_melee_stamina_test", "player_enemy_melee_hit_test",
         "player_half_cover_test", "player_vault_hit_reset_test", "low_cover_geometry_test", "half_cover_presentation_test"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", required=True)
    parser.add_argument("tests", nargs="*")
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent
    project = directory.parent
    logs = project / "logs" / "combat_regressions"
    logs.mkdir(parents=True, exist_ok=True)
    results = []
    for name in args.tests or TESTS:
        if not (directory / (name + ".gd")).is_file():
            parser.error("Unknown test: " + name)
        command = [args.godot, "--headless", "--path", str(project), "--log-file",
                   str(logs / (name + ".log")), "--script", "res://tests/" + name + ".gd"]
        try:
            run = subprocess.run(command, capture_output=True, timeout=75)
            output = (run.stdout + run.stderr).decode("utf-8", errors="replace")
            code = run.returncode
        except subprocess.TimeoutExpired as error:
            output = ((error.stdout or b"") + (error.stderr or b"")).decode("utf-8", errors="replace")
            code = "timeout"
        (logs / (name + "_stdout.log")).write_text(output, encoding="utf-8")
        errors = [line for line in output.splitlines() if "SCRIPT ERROR:" in line
                  or line.startswith("FAIL ")
                  or (line.startswith("ERROR:") and "root certificate store" not in line)]
        passed = code == 0 and not errors
        results.append({"test": name, "passed": passed, "exit": code, "errors": errors[:20]})
        print(("PASS " if passed else "FAIL ") + name, flush=True)
        for line in errors[:3]:
            print("  " + line, flush=True)
        (logs / "results.json").write_text(json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Combat regressions: {sum(item['passed'] for item in results)}/{len(results)} suites passed")
    return 0 if all(item["passed"] for item in results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
