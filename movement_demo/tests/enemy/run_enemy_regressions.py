"""Run the modular enemy regression suite; script errors fail even if Godot exits 0."""
import argparse
import json
from pathlib import Path
import subprocess

TESTS = [
    "enemy_route_evaluation_batch_test",
    "enemy_ally_spacing_test",
    "enemy_ally_spacing_runtime_test",
    "enemy_firing_cadence_test",
    "enemy_cover_inspection_test",
    "enemy_ally_navigation_test",
    "enemy_ally_navigation_integration_test",
    "enemy_ally_route_recovery_test",
    "enemy_ally_route_autonomous_test",
    "enemy_navigation_corner_recovery_test",
    "enemy_geometry_batch_test",
    "enemy_candidate_reuse_test",
    "suppression_purpose_test",
    "enemy_cooperation_service_test",
    "enemy_team_planner_test",
    "enemy_cooperation_flank_service_test",
    "enemy_flank_route_test",
    "enemy_cooperation_support_test",
    "enemy_shared_contact_test",
    "enemy_spatial_revision_test",
    "enemy_cooperation_flank_runtime_test",
    "enemy_cooperation_line_safety_test",
    "enemy_cooperation_search_test",
    "enemy_cooperation_reload_test",
    "enemy_cooperation_solo_test",
    "cooperation_tactics_test",
    "enemy_half_cover_test",
    "low_cover_band_test",
    "enemy_low_cover_loss_test",
    "enemy_low_cover_behavior_test",
    "enemy_vault_utility_test",
    "enemy_vault_navigation_test",
    "enemy_posture_lifecycle_test",
    "enemy_modular_contract_test",
    "enemy_configuration_cleanup_test",
    "enemy_scene_test",
    "search_components_test",
    "search_area_coverage_test",
    "search_reacquisition_test",
    "search_pursuit_test",
    "search_persistence_test",
    "enemy_firing_lane_test",
    "enemy_basic_capabilities_test",
    "enemy_execution_contract_test",
    "enemy_shared_geometry_settings_test",
    "enemy_melee_execution_test",
    "enemy_melee_utility_test",
    "enemy_melee_approach_test",
    "enemy_melee_timing_test",
    "enemy_melee_weapon_test",
    "enemy_reload_observation_test",
    "enemy_melee_tactics_test",
    "enemy_melee_cover_test",
    "enemy_melee_low_cover_test",
    "enemy_melee_cover_vault_path_test",
    "enemy_melee_shelter_test",
    "enemy_melee_cover_exit_test",
    "enemy_melee_cover_continuity_test",
    "enemy_melee_navigation_test",
    "enemy_melee_tactics_lifecycle_test",
    "enemy_reload_test",
    "enemy_reload_cover_test",
    "attack_hold_regression_test",
    "attack_points_test",
    "enemy_weapon_test",
    "enemy_ranged_equipment_test",
    "enemy_probability_test",
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
    "exit_suppression_ownership_test",
    "utility_suppression_trigger_test",
    "enemy_fire_timing_test",
    "enemy_fire_decision_test",
    "utility_runtime_test",
    "cooperation_runtime_test",
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
            timeout = 300 if name == "enemy_cooperation_flank_runtime_test" else 180 if name == "cooperation_runtime_test" else 75
            run = subprocess.run(command, capture_output=True, timeout=timeout)
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
