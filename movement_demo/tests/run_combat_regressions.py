"""Run player combat and aim regressions; script errors fail even if Godot exits 0."""
from pathlib import Path
from regression_runner import suite_main

TESTS = ["aim_disruption_test", "combat_compatibility_test", "player_reload_test", "player_reload_checkpoint_test",
         "weapon_ammo_test", "weapon_slots_test", "player_health_test", "player_medkit_test", "player_medkit_lifecycle_test",
         "player_automatic_fire_test", "player_melee_test", "player_melee_presentation_test",
         "player_melee_physics_test", "player_melee_zone_test", "player_melee_stamina_test", "player_enemy_melee_hit_test",
         "player_half_cover_test", "player_vault_hit_reset_test", "low_cover_geometry_test", "half_cover_presentation_test",
         "posture_animation_profile_test", "posture_animation_adapter_test", "weapon_presentation_test",
         "player_camera_test", "camera_occlusion_test", "melee_hit_effects_test"]


def main():
    directory = Path(__file__).resolve().parent
    return suite_main(directory, directory.parent, TESTS, "combat_regressions", "Combat regressions")

if __name__ == "__main__":
    raise SystemExit(main())
