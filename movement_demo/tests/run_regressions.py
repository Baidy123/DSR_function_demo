"""List, check, or run the project's runtime regression suites."""
import argparse
from datetime import datetime
import json
from pathlib import Path

from run_combat_regressions import TESTS as COMBAT_TESTS
from enemy.run_enemy_regressions import TESTS as ENEMY_TESTS
from regression_runner import run_tests, validate_names

DIRECTORY = Path(__file__).resolve().parent
PROJECT = DIRECTORY.parent
SYSTEM_TESTS = [
    "movement_test", "sprint_test", "interaction_test", "hearing_test",
    "movement_noise_modes_test", "debug_mode_test", "noise_debug_test",
    "presentation_interfaces_test", "presentation_movement_compatibility_test",
    "presentation_range_reset_test", "dialogue_cache_test",
    "quest_conditions_test", "quest_system_test", "stage_system_test",
    "quest_panel_test", "record_player_quest_test",
]
# The optional interaction prototype is absent from some local project baselines.
if (DIRECTORY / "interactable_test.gd").is_file():
    SYSTEM_TESTS.append("interactable_test")
SUITES = {
    "systems": (DIRECTORY, SYSTEM_TESTS),
    "combat": (DIRECTORY, COMBAT_TESTS),
    "enemy": (DIRECTORY / "enemy", ENEMY_TESTS),
}
TIMEOUTS = {"enemy_squad_runtime_test": 180, "enemy_cooperation_flank_runtime_test": 300, "cooperation_runtime_test": 180,
            "enemy_team_awareness_levels_runtime_test": 240, "enemy_team_support_execution_test": 240}

# These entries need their documented harness; never glob-run every .gd file.
SPECIAL = {
    "bake_arena.gd": "maintenance command: writes navigation; never a regression",
    "bake_levels.gd": "maintenance command: writes level navigation; never a regression",
    "presentation_fixture.gd": "fixture used by presentation tests",
    "enemy/enemy_fire_fixture.gd": "fixture used by enemy tests",
    "enemy/modular_probe_action.gd": "action fixture used by modular contracts",
    "aim_mode_test.gd": "run by combat_compatibility_test",
    "spread_cone_test.gd": "run by combat_compatibility_test",
    "player_move_spread_test.gd": "run by combat_compatibility_test",
    "weapon_mode_parameters_test.gd": "run by combat_compatibility_test",
    "shot_collision_test.gd": "run by combat_compatibility_test",
    "range_reset_test.gd": "run by presentation_range_reset_test",
    "presentation_editor_test.gd": "standalone --headless --editor --script",
    "weapon_fire_mode_inspector_test.gd": "standalone --headless --editor --script",
    "enemy/enemy_training_inspector_test.gd": "standalone --headless --editor --script",
    "test_cover_instance_save.gd": "Godot AI editor harness with saved arena fixture",
    "test_weapon_mode_inspector.gd": "Godot AI editor harness with Main open",
    "enemy/test_enemy_probability_inspector.gd": "Godot AI editor harness with enemy scene open",
    "player_health_ui_test.gd": "rendered Main: await new().run(scene)",
    "range_door_test.gd": "Main run(scene), fixed spawn/input fixture; migration pending",
    "target_health_test.gd": "Main run(scene), fixed weapon/ammo fixture; migration pending",
    "combat_test.gd": "legacy Main run/run_input; old movement accuracy expectations; migration pending",
    "combat_refinement_test.gd": "legacy Main run(scene); old movement accuracy expectations; migration pending",
}


def check_catalog():
    registered = set()
    for directory, names in SUITES.values():
        validate_names(directory, names)
        for name in names:
            path = (directory / (name + ".gd")).relative_to(DIRECTORY).as_posix()
            if path in registered:
                raise ValueError("Duplicate suite entry: " + path)
            registered.add(path)
    overlap = registered & SPECIAL.keys()
    if overlap:
        raise ValueError("Runtime/special overlap: " + ", ".join(sorted(overlap)))
    present = {p.relative_to(DIRECTORY).as_posix() for p in DIRECTORY.rglob("*.gd")}
    expected = registered | SPECIAL.keys()
    if present != expected:
        raise ValueError(f"Unclassified: {sorted(present - expected)}; missing: {sorted(expected - present)}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", help="Godot console executable; required when running")
    parser.add_argument("--suite", action="append", choices=SUITES, help="Repeat to select suites; default: all runtime suites")
    parser.add_argument("--list", action="store_true", help="Show the live catalog without starting Godot")
    parser.add_argument("--check", action="store_true", help="Check file coverage and duplicate registrations")
    parser.add_argument("--output", type=Path, help="A new directory for this run's logs and report")
    args = parser.parse_args()
    try:
        check_catalog()
    except ValueError as error:
        parser.error(str(error))
    selected = list(dict.fromkeys(args.suite or SUITES))
    if args.list:
        for key in selected:
            print(f"{key}: {len(SUITES[key][1])} suites")
            for name in SUITES[key][1]:
                print("  " + name)
        print("Special entries (excluded from runtime totals):")
        for name, mode in SPECIAL.items():
            print(f"  {name}: {mode}")
    if args.list or args.check:
        print("Catalog OK")
        return 0
    if not args.godot:
        parser.error("--godot is required when running tests")
    output = (args.output or PROJECT / "logs" / "regressions" / datetime.now().strftime("%Y%m%d_%H%M%S_%f")).resolve()
    if output.exists():
        parser.error("Output directory already exists; use a new directory to preserve previous results")
    output.mkdir(parents=True)
    report = []
    for key in selected:
        directory, names = SUITES[key]
        code = run_tests(args.godot, PROJECT, directory, names, output / key, key, TIMEOUTS)
        report.append({"suite": key, "count": len(names), "passed": code == 0,
                       "results": str(output / key / "results.json")})
        (output / "report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("Report: " + str(output / "report.json"))
    return 0 if all(item["passed"] for item in report) else 1


if __name__ == "__main__":
    raise SystemExit(main())
