extends RefCounted

func run(scene: Node) -> Dictionary:
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	p.set_physics_process(false)
	p.position = Vector3(0, 0, -1)
	var w = c.weapon.duplicate()
	w.min_spread_angle_degrees = 0.0
	w.max_spread_angle_degrees = 20.0
	w.moving_spread_angle_degrees = 10.0
	w.spread_recovery_delay = 0.4
	# 用 set 让缺少新导出参数的旧实现也能运行到行为断言。
	w.set("player_move_spread_degrees_per_meter", 4.0)
	c.aim_mode = c.AimMode.SPREAD_CONE
	c.equip_weapon(w)
	for frame in range(5):
		await scene.get_tree().physics_frame
	c.accuracy = 1.0
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	var checks := {"small_step_adds_only_distance_penalty": is_equal_approx(c.get_spread_half_angle_degrees(), 0.4)}
	c.accuracy = 1.0
	_step(c, p, Vector3(1, 0, 0), 0.2)
	var one_step: float = c.get_spread_half_angle_degrees()
	checks["one_meter_adds_exported_degrees"] = is_equal_approx(one_step, 4.0)
	c.accuracy = 1.0
	for i in range(10):
		_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["same_distance_independent_of_speed_and_frames"] = is_equal_approx(c.get_spread_half_angle_degrees(), one_step)
	c.accuracy = 0.55
	_step(c, p, Vector3(1, 0, 0), 0.1)
	checks["movement_stops_at_its_limit"] = is_equal_approx(c.get_spread_half_angle_degrees(), 10.0)
	c.accuracy = 0.25
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["movement_does_not_shrink_wider_spread"] = is_equal_approx(c.get_spread_half_angle_degrees(), 15.0)
	c.accuracy = 1.0
	_step(c, p, Vector3.ZERO, 0.1)
	checks["no_displacement_does_not_expand"] = is_equal_approx(c.get_spread_half_angle_degrees(), 0.0)
	_step(c, p, Vector3(0, 0.1, 0), 0.1)
	checks["vertical_motion_does_not_expand"] = is_equal_approx(c.get_spread_half_angle_degrees(), 0.0)
	w.set("player_move_spread_degrees_per_meter", 0.0)
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["zero_rate_disables_expansion"] = is_equal_approx(c.get_spread_half_angle_degrees(), 0.0)
	w.set("player_move_spread_degrees_per_meter", 8.0)
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["rate_can_be_tuned"] = is_equal_approx(c.get_spread_half_angle_degrees(), 0.8)
	_step(c, p, Vector3.ZERO, 0.1, false)
	checks["stopping_keeps_recovery_delay"] = is_equal_approx(c.get_spread_half_angle_degrees(), 0.8)
	_step(c, p, Vector3.ZERO, 1.0, false)
	checks["rest_still_recovers"] = is_equal_approx(c.get_spread_half_angle_degrees(), 0.0)
	w.set("player_move_accuracy_loss_per_meter", 0.2)
	c.aim_mode = c.AimMode.PROBABILITY
	c.accuracy = 1.0
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["probability_also_changes_gradually"] = is_equal_approx(c.accuracy, 0.98)
	c.accuracy = w.moving_accuracy_cap + 0.01
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["probability_stops_at_movement_limit"] = is_equal_approx(c.accuracy, w.moving_accuracy_cap)
	c.accuracy = 0.1
	_step(c, p, Vector3(0.1, 0, 0), 0.1)
	checks["movement_does_not_raise_lower_probability"] = is_equal_approx(c.accuracy, 0.1)
	return checks

func _step(c: Node, p: Node3D, offset: Vector3, delta: float, moving: bool = true) -> void:
	c.begin_frame(delta, true)
	c.locked_target = null
	p.position += offset
	c.end_frame(delta, moving)
