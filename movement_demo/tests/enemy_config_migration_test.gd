extends SceneTree

# 迁移前2026-09-22快照：原脚本默认值叠加用户场景覆盖，防止迁移重置调参。
const Training = preload("res://enemy_training.gd")
const EXPECTED := {
	"ai_patrol_pause_seconds": 1.5,
	"ai_attack_position_uncertainty": 1.0,
	"tactics_can_covering_retreat": true,
	"tactics_can_use_attack_positions": true,
	"tactics_can_suppress_fire": true,
	"tactics_can_suppress_exits": true,
	"tactics_attack_position_chance": 0.5,
	"tactics_fire_while_moving": true,
	"tactics_fire_reaction_seconds": 0.3,
	"tactics_fire_stability_target": 0.9,
	"tactics_burst_shot_count": 10,
	"tactics_burst_pause_seconds": 1.5,
	"tactics_ranged_min_distance": 4.0,
	"tactics_ranged_max_distance": 6.0,
	"tactics_ranged_repath_seconds": 0.75,
	"tactics_ranged_flank_weight": 5.0,
	"tactics_ranged_wall_support_weight": 4.0,
	"tactics_ranged_wall_probe_distance": 1.5,
	"tactics_stopping_distance": 1.3,
	"search_tracking_cheat_enabled": true,
	"search_lost_target_hint_chance": 1.0,
	"search_search_hint_chance": 0.35,
	"search_search_hint_interval_seconds": 1.5,
	"search_search_hint_decay_mode": 3,
	"search_search_hint_min_multiplier": 0.1,
	"search_search_hint_linear_decay_seconds": 8.0,
	"search_search_hint_half_life_seconds": 4.0,
	"search_search_hint_distance_falloff": 10.0,
	"search_tracking_hint_error_radius": 1.25,
	"search_tracking_hint_position_attempts": 4,
	"search_tracking_cheat_max_distance": 12.0,
	"search_debug_tracking_cheat": true,
	"search_track_distance": 4.0,
	"search_track_seconds": 10.0,
	"search_track_move_speed_multiplier": 0.55,
	"search_track_attention_weight": 0.75,
	"search_track_sight_angle_degrees": 220.0,
	"search_track_nav_edge_margin": 0.35,
	"search_track_nav_probe_tolerance": 0.12,
	"search_track_arrival_distance": 0.45,
	"search_search_coverage_radius": 2.0,
	"search_search_coverage_goal": 0.95,
	"search_search_seconds": 0.0,
	"search_search_radius": 5.0,
	"search_search_pause_seconds": 0.6,
	"search_search_arrival_distance": 0.5,
	"search_search_nav_snap_tolerance": 0.65,
	"search_search_move_speed_multiplier": 0.45,
	"search_search_stuck_repath_seconds": 0.8,
	"search_search_stuck_min_progress_distance": 0.08,
	"search_debug_systematic_search": false,
	"cover_shot_radius": 1.5,
	"cover_take_cover_chance": 0.4,
	"cover_hide_seconds": 2.0,
	"cover_watch_seconds": 1.0,
	"cover_run_speed_multiplier": 2.0,
	"cover_peek_speed_multiplier": 0.5,
	"cover_covering_retreat_chance": 0.4,
	"cover_covering_retreat_speed_multiplier": 0.8,
	"cover_damage_force_sprint_chance": 0.7,
	"cover_cover_stuck_repath_seconds": 0.8,
	"cover_cover_stuck_min_progress_distance": 0.08,
	"cover_cover_max_detour_retries": 4,
	"cover_cover_detour_distance": 1.5,
	"cover_cover_detour_angle_degrees": 65.0,
	"cover_cover_detour_arrival_distance": 0.45,
	"suppression_duration_min": 3.0,
	"suppression_duration_max": 5.0,
	"suppression_target_radius": 0.75,
	"exit_suppression_duration_min": 3.0,
	"exit_suppression_duration_max": 5.0,
	"exit_suppression_target_radius": 0.75,
	"exit_suppression_cover_inference_distance": 1.75,
	"exit_suppression_shots_per_exit_min": 2,
	"exit_suppression_shots_per_exit_max": 5,
	"fire_decision_recovery_gain_weight": 0.35,
	"fire_decision_close_range_weight": 0.35,
	"fire_decision_wait_pressure_per_second": 0.45,
	"perception_sight_distance": 8.0,
	"perception_sight_angle_degrees": 120.0,
	"perception_close_awareness_radius": 2.0,
	"selection_away_from_threat_weight": 4.0,
	"selection_closer_to_threat_weight": 5.0,
	"selection_require_assigned_cover": true,
	"selection_cover_lateral_test_distance": 0.3,
	"selection_minimum_cover_quality": 0.1,
	"selection_cover_quality_weight": 3.0,
	"selection_debug_cover_selection": true,
	"selection_debug_attack_points": true,
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	actor.get_node("AI").set_physics_process(false)
	var training = actor.get_node("Training")
	var failed := 0
	for key in EXPECTED:
		if training.get(key) != EXPECTED[key]:
			failed += 1
			print("FAIL ", key, " expected=", EXPECTED[key], " actual=", training.get(key))
	if actor.get_node("UnitType").combat_type != 1:
		failed += 1
		print("FAIL combat_type")
	print("CONFIG MIGRATION: ", EXPECTED.size() + 1 - failed, "/", EXPECTED.size() + 1)
	scene.free()
	quit(0 if failed == 0 else 1)
