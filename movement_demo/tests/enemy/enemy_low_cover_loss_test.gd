extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func settle() -> void:
	for frame in 8: await physics_frame

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	# 本项验证远程压制证据；实例明确具备火器资格，不依赖关卡当前选中的兵种。
	enemy.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	var firearm: WeaponData = enemy.weapon.duplicate(true)
	firearm.fire_mode = WeaponData.FireMode.AUTOMATIC
	enemy.equip_weapon(firearm)
	Fixture.set_training_action(ai, &"exit_suppression", true)
	ai.training.profile.set_setting(&"perception", &"close_cover_intelligence_enabled", false)
	var cover = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var center: Vector3 = cover.global_position
	center.y = 0.0
	enemy.global_position = center + Vector3.BACK * 0.85
	player.global_position = center + Vector3.FORWARD * 1.4
	enemy.look_at(player.global_position)
	await settle()
	var remembered: Vector3 = player.global_position
	var query: PhysicsRayQueryParameters3D = ai.context.cover_selection._ray_query(enemy.get_eye_position(), enemy.get_posture_eye_position(true, remembered))
	check(enemy.get_world_3d().direct_space_state.intersect_ray(query).is_empty(), "eye-level classification ray passes above the nearby low wall")
	check(ai.perception.can_see_player() and not player.is_crouching(), "standing player is genuinely visible before contact is lost")
	ai.context.reset_memory()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	enemy.rotate_y(PI)
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	var evidence: Dictionary = ai.context.suppression_basis()
	check(not ai.context.sees_player and not player.is_crouching() and evidence.get("source") == &"visual_loss", "ordinary field-of-view loss creates visual-loss evidence without a crouch or close clue")
	check(evidence.get("low_cover_context", false) and evidence.get("position", Vector3.INF) == remembered, "low wall association is captured from the last observed point")
	var suppression = ai.actions[&"suppression"]
	var candidates: Array = suppression.collect_candidates(false)
	check(not candidates.is_empty() and candidates[0].outcome.get("preference_credit", 0.0) > 0.0, "non-crouch disappearance receives the same Utility point-suppression preference")
	var serial: int = evidence.get("id", -1)
	player.global_position += Vector3.RIGHT * 3.0
	player.request_crouch(true)
	player._update_posture(0.3)
	ai.context.update_evidence(0.1, false)
	var frozen: Dictionary = ai.context.suppression_basis()
	check(frozen.get("id", -2) == serial and frozen.get("position", Vector3.INF) == remembered and frozen.get("low_cover_context", false), "hidden movement and posture changes never move or reclassify the frozen event")
	check(ai.perception.last_observed_cover(center + Vector3.FORWARD * 4.0) == null, "a distant point does not inherit an unrelated foreground low wall")
	enemy.global_position = center + Vector3.BACK * 4.0
	await settle()
	var distant: Vector3 = center + Vector3.FORWARD * 2.2
	query = ai.context.cover_selection._ray_query(enemy.get_eye_position(), enemy.get_posture_eye_position(true, distant))
	check(enemy.get_world_3d().direct_space_state.intersect_ray(query).get("collider") == cover, "distant classification fixture also hits the low wall at eye level")
	check(ai.perception.last_observed_cover(distant) == null, "eye-level and lower rays enforce the same cover-association distance")
	print("LOW COVER LOSS: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
