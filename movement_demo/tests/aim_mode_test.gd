extends RefCounted

func run(scene: Node) -> Dictionary:
	var p = scene.get_node("Player")
	var c = p.get_node("Combat")
	var r = c.get_node("HUD/Reticle")
	var checks := {}
	var exported := false
	for property in c.get_property_list():
		if property.name == "aim_mode":
			exported = bool(property.usage & PROPERTY_USAGE_EDITOR) and property.hint == PROPERTY_HINT_ENUM
	checks["combat_exports_mode_dropdown"] = exported
	if not exported:
		return checks
	checks["player_no_longer_has_mode"] = not "aim_mode" in p
	c.aim_mode = c.AimMode.SPREAD_CONE
	checks["selects_spread_cone"] = c.is_using_spread_cone()
	p.set_physics_process(false)
	p.position = Vector3(0, 0, -1)
	p.rotation = Vector3.ZERO
	var target = scene.get_node("CombatTest/TargetA")
	target.position = Vector3(0, 0, -4.5)
	scene.get_node("CombatTest/TargetB").position = Vector3(6, 0, -4.5)
	scene.get_node("CombatTest/Cover").position = Vector3(7, 1, -2)
	var weapon = c.weapon.duplicate()
	weapon.min_spread_angle_degrees = 20.0
	weapon.max_spread_angle_degrees = 20.0
	c.equip_weapon(weapon)
	for i in range(5): await scene.get_tree().physics_frame
	c.begin_frame(0.0, true)
	c.aim_mode = c.AimMode.PROBABILITY
	checks["selects_probability_mode"] = not c.is_using_spread_cone()
	var before: int = target.hit_count
	for i in range(12):
		c.accuracy = 1.0
		c.shot_cooldown = 0.0
		c.shoot()
	checks["probability_full_accuracy_ignores_spread_limits"] = target.hit_count == before + 12
	c.accuracy = 0.5
	c._update_status()
	r._process(0.0)
	checks["probability_uses_legacy_reticle"] = is_equal_approx(r.radius, lerpf(r.maximum_radius, r.minimum_radius, 0.5))
	checks["probability_hud_names_center_chance"] = c.status.text.contains("中心概率")
	var misses_in_band := true
	for i in range(128):
		var direction: Vector3 = c._random_direction_in_miss_cone(Vector3.FORWARD, 8.0, 20.0)
		var angle: float = rad_to_deg(acos(clampf(direction.dot(Vector3.FORWARD), -1.0, 1.0)))
		misses_in_band = misses_in_band and angle >= 7.999 and angle <= 20.001
	checks["legacy_miss_band_preserved"] = misses_in_band
	var stability_before: float = c.accuracy
	c.aim_mode = c.AimMode.SPREAD_CONE
	checks["switch_keeps_stability_and_lock"] = is_equal_approx(c.accuracy, stability_before) and c.locked_target == target
	c._update_status()
	r._process(0.0)
	checks["switch_keeps_circle_and_updates_hud"] = is_equal_approx(r.radius, lerpf(r.maximum_radius, r.minimum_radius, 0.5)) and c.status.text.contains("稳定度")
	before = target.hit_count
	seed(77)
	for i in range(64):
		c.accuracy = 1.0
		c.shot_cooldown = 0.0
		c.shoot()
	checks["switch_restores_actual_cone_shooting"] = target.hit_count - before < 64
	randomize()
	return checks
