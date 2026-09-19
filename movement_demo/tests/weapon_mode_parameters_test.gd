extends RefCounted

func run(scene: Node) -> Dictionary:
	var c = scene.get_node("Player/Combat")
	var weapon = c.weapon.duplicate()
	var checks := {"separate_mode_settings_available": weapon.has_method("get_aim_settings")}
	if not checks.separate_mode_settings_available:
		return checks
	weapon.min_spread_angle_degrees = 5.0
	weapon.max_spread_angle_degrees = 25.0
	weapon.initial_spread_angle_degrees = 15.0
	weapon.spread_recovery_degrees_per_second = 4.0
	weapon.moving_spread_angle_degrees = 17.0
	weapon.shot_spread_penalty_degrees = 2.0
	weapon.shot_max_spread_angle_degrees = 21.0
	weapon.spread_recovery_delay = 0.3
	weapon.target_move_spread_degrees_per_meter_slow = 1.0
	weapon.target_move_spread_degrees_per_meter_fast = 3.0
	weapon.target_move_max_spread_angle_degrees = 19.0
	weapon.spread_target_move_fast_speed = 5.0
	weapon.initial_accuracy = 0.8
	weapon.shot_accuracy_penalty = 0.25
	var cone: Dictionary = weapon.get_aim_settings(true)
	var probability: Dictionary = weapon.get_aim_settings(false)
	checks["cone_initial_uses_degrees"] = is_equal_approx(cone.initial, 0.5)
	checks["cone_recovery_uses_degrees_per_second"] = is_equal_approx(cone.recovery, 0.2)
	checks["cone_movement_uses_angle"] = is_equal_approx(cone.moving_cap, 0.4)
	checks["cone_shot_uses_degrees"] = is_equal_approx(cone.shot_penalty, 0.1)
	checks["cone_shot_limit_uses_angle"] = is_equal_approx(cone.shot_floor, 0.2)
	checks["cone_delay_independent"] = is_equal_approx(cone.delay, 0.3)
	checks["cone_target_motion_uses_degrees"] = is_equal_approx(cone.slow, 0.05) and is_equal_approx(cone.fast, 0.15)
	checks["cone_target_limit_uses_angle"] = is_equal_approx(cone.target_floor, 0.3)
	checks["probability_values_preserved"] = is_equal_approx(probability.initial, 0.8) and is_equal_approx(probability.shot_penalty, 0.25)
	weapon.shot_accuracy_penalty = 0.9
	checks["probability_edit_does_not_change_cone"] = is_equal_approx(weapon.get_aim_settings(true).shot_penalty, 0.1)
	weapon.shot_spread_penalty_degrees = 6.0
	checks["cone_edit_does_not_change_probability"] = is_equal_approx(weapon.get_aim_settings(false).shot_penalty, 0.9)
	weapon.shot_spread_penalty_degrees = 2.0
	c.aim_mode = c.AimMode.SPREAD_CONE
	c.equip_weapon(weapon)
	checks["equip_reads_cone_initial_angle"] = is_equal_approx(c.get_spread_half_angle_degrees(), 15.0)
	c.accuracy = 0.2
	c.cancel_aim()
	checks["cancel_does_not_clear_cone_penalty"] = is_equal_approx(c.accuracy, 0.2)
	# 最大与最小相等时保持固定角度，不发生除零或非有限状态。
	weapon.max_spread_angle_degrees = 5.0
	var fixed: Dictionary = weapon.get_aim_settings(true)
	checks["fixed_cone_has_finite_settings"] = true
	for value in fixed.values():
		checks.fixed_cone_has_finite_settings = checks.fixed_cone_has_finite_settings and is_finite(float(value))
	checks["fixed_cone_stays_at_minimum"] = is_equal_approx(c.get_spread_half_angle_degrees(), 5.0)
	return checks
