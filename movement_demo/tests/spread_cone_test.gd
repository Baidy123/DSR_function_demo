extends RefCounted

func run(scene: Node) -> Dictionary:
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	var reticle = combat.get_node("HUD/Reticle")
	var weapon = combat.weapon.duplicate()
	var checks := {}
	var fields: Array[String] = []
	for property in weapon.get_property_list():
		fields.append(property.name)
	checks["weapon_exports_min_and_max_spread"] = fields.has("min_spread_angle_degrees") and fields.has("max_spread_angle_degrees")
	checks["combat_provides_current_angle"] = combat.has_method("get_spread_half_angle_degrees")
	if not checks.weapon_exports_min_and_max_spread or not checks.combat_provides_current_angle:
		return checks
	player.set_physics_process(false)
	player.position = Vector3(0, 0, -1)
	player.rotation = Vector3.ZERO
	var target = scene.get_node("CombatTest/TargetA")
	var other = scene.get_node("CombatTest/TargetB")
	var wall = scene.get_node("CombatTest/Cover")
	target.position = Vector3(0, 0, -4.5)
	other.position = Vector3(6, 0, -4.5)
	wall.position = Vector3(7, 1, -2)
	weapon.min_spread_angle_degrees = 1.0
	weapon.max_spread_angle_degrees = 11.0
	combat.equip_weapon(weapon)
	for frame in range(5):
		await scene.get_tree().physics_frame
	combat.begin_frame(0.0, true)
	checks["locks_existing_target"] = combat.locked_target == target
	combat.accuracy = 0.0
	checks["unstable_uses_max_angle"] = is_equal_approx(combat.get_spread_half_angle_degrees(), 11.0)
	combat.accuracy = 0.5
	checks["stability_shrinks_angle"] = is_equal_approx(combat.get_spread_half_angle_degrees(), 6.0)
	combat.accuracy = 1.0
	checks["stable_uses_weapon_minimum"] = is_equal_approx(combat.get_spread_half_angle_degrees(), 1.0)
	weapon.min_spread_angle_degrees = 20.0
	weapon.max_spread_angle_degrees = 5.0
	checks["reversed_limits_remain_safe"] = combat.get_spread_half_angle_degrees() >= 20.0
	weapon.min_spread_angle_degrees = 0.0
	weapon.max_spread_angle_degrees = 12.0
	checks["zero_angle_is_exact"] = combat._random_direction_in_spread_cone(Vector3.FORWARD, 0.0).is_equal_approx(Vector3.FORWARD)
	seed(1042)
	var contained := true
	var normalized := true
	var mean_cap_fraction := 0.0
	var sideways := false
	var vertical := false
	var centered := 0
	var cap: float = 1.0 - cos(deg_to_rad(12.0))
	for index in range(4096):
		var direction: Vector3 = combat._random_direction_in_spread_cone(Vector3.FORWARD, 12.0)
		var cosine: float = clampf(direction.dot(Vector3.FORWARD), -1.0, 1.0)
		contained = contained and rad_to_deg(acos(cosine)) <= 12.001
		normalized = normalized and is_equal_approx(direction.length(), 1.0)
		mean_cap_fraction += (1.0 - cosine) / cap
		sideways = sideways or absf(direction.x) > 0.05
		vertical = vertical or absf(direction.y) > 0.05
		if direction.is_equal_approx(Vector3.FORWARD):
			centered += 1
	checks["all_samples_inside_cone"] = contained
	checks["sample_directions_normalized"] = normalized
	checks["spread_includes_horizontal_and_vertical"] = sideways and vertical
	checks["uniform_solid_angle_distribution"] = absf(mean_cap_fraction / 4096.0 - 0.5) < 0.025
	checks["no_forced_center_hits"] = centered == 0
	var upward: Vector3 = combat._random_direction_in_spread_cone(Vector3.UP, 12.0)
	checks["vertical_aim_is_valid"] = upward.is_finite() and upward.dot(Vector3.UP) >= cos(deg_to_rad(12.0))
	# 真实开枪：即使稳定度100%，武器仍保留10度最小散布，不能再保证中心命中。
	weapon.min_spread_angle_degrees = 10.0
	weapon.max_spread_angle_degrees = 10.0
	var before: int = target.hit_count
	seed(77)
	for index in range(64):
		combat.accuracy = 1.0
		combat.shot_cooldown = 0.0
		combat.shoot()
	var hits: int = target.hit_count - before
	checks["full_stability_nonzero_cone_can_miss"] = hits > 0 and hits < 64
	# 武器允许0度时则恢复精准直射；损伤仍按实际射线处理。
	weapon.min_spread_angle_degrees = 0.0
	combat.accuracy = 1.0
	combat.shot_cooldown = 0.0
	before = target.hit_count
	combat.shoot()
	checks["zero_minimum_hits_at_full_stability"] = target.hit_count == before + 1
	checks["shots_reduce_stability"] = combat.accuracy < 1.0
	var penalized: float = combat.accuracy
	combat.cancel_aim()
	checks["reaim_does_not_clear_penalty"] = combat.accuracy <= penalized
	combat.begin_frame(0.0, true)
	combat.accuracy = 1.0
	combat.end_frame(0.1, true)
	checks["movement_still_limits_stability"] = combat.accuracy <= weapon.moving_accuracy_cap
	var angle_before: float = combat.get_spread_half_angle_degrees()
	combat.end_frame(weapon.accuracy_recovery_delay + weapon.stabilize_seconds * 4.0, false)
	checks["rest_recovers_and_shrinks_cone"] = combat.get_spread_half_angle_degrees() < angle_before
	combat._update_status()
	checks["hud_reports_stability"] = combat.get_node("HUD/Panel/Status").text.contains("稳定度")
	checks["hud_no_longer_claims_hit_probability"] = not combat.get_node("HUD/Panel/Status").text.contains("命中率")
	combat.accuracy = 1.0
	weapon.min_spread_angle_degrees = 0.0
	reticle._process(0.0)
	checks["stable_reticle_keeps_original_minimum"] = is_equal_approx(reticle.radius, reticle.minimum_radius)
	weapon.min_spread_angle_degrees = 3.0
	reticle._process(0.0)
	var small_radius: float = reticle.radius
	weapon.min_spread_angle_degrees = 6.0
	reticle._process(0.0)
	checks["reticle_keeps_original_style_across_weapons"] = is_equal_approx(reticle.radius, small_radius)
	combat.accuracy = 0.0
	reticle._process(0.0)
	checks["unstable_reticle_expands"] = is_equal_approx(reticle.radius, reticle.maximum_radius)
	checks["reticle_is_visible_on_target"] = reticle.visible
	# 移动目标的原稳定度惩罚仍然生效。
	weapon.min_spread_angle_degrees = 0.0
	combat.accuracy = 1.0
	combat._start_target_movement_tracking(target)
	target.position.x += 0.2
	combat._apply_target_movement_accuracy_penalty(0.1)
	checks["moving_target_still_penalizes_stability"] = combat.accuracy < 1.0
	randomize()
	return checks
