extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

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
	player.health.debug_invincible = true
	ai.unit_type.profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	ai.actions[&"search"].tracking_cheat_enabled = false
	ai.refresh_configuration()
	var weapon := WeaponData.new()
	weapon.fire_mode = WeaponData.FireMode.MELEE
	weapon.melee_enabled = true
	enemy.equip_weapon(weapon)
	var cover = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var center: Vector3 = cover.global_position
	center.y = 0.0
	enemy.global_position = center + Vector3.BACK * 2.0
	player.global_position = center + Vector3.FORWARD * 3.0
	enemy.look_at(player.global_position)
	for frame in 8: await physics_frame
	ai.context.reset_memory()
	ai.context.update_evidence(0.1, ai.perception.can_see_player())
	var action = ai.actions[&"melee_engage"]
	var options: Array = []
	for frame in 12:
		await physics_frame
		options = ai.action_selector.assess_options(ai, true)
	var walk: Array = options.filter(func(candidate): return candidate.id == &"melee_engage" and candidate.get("route", {}).is_empty())
	var vaults: Array = options.filter(func(candidate): return candidate.id == &"melee_engage" and not candidate.get("route", {}).is_empty())
	check(not walk.is_empty() and not vaults.is_empty(), "shared budget prepares both walk and one-vault melee alternatives")
	var best: Dictionary = ai.action_selector.choose_option(options)
	check(not best.get("route", {}).is_empty(), "ordinary Utility autonomously prefers the shorter low-wall route")
	if not vaults.is_empty():
		var exposure: float = vaults[0].outcome.exposed_seconds
		check(exposure > 0.0 and vaults[0].outcome.unavailable_seconds >= vaults[0].route.vault.duration, "airborne exposure and no-attack duration contribute to the original outcome")
	# Execution must also discover the route while moving, without warmed caches
	# from the separate candidate-inspection assertions above.
	ai.context.spatial.reset_evaluation()
	var saw_vault := false
	var crossed := false
	for frame in 240:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		saw_vault = saw_vault or enemy.is_vaulting()
		if enemy.global_position.z < center.z - 0.8 and not enemy.is_vaulting():
			crossed = true
			break
	check(saw_vault and crossed, "selected action executes approach-vault-landing through normal AI and body entry points")
	ai._cancel_utility_execution()
	enemy.global_position = center + Vector3.BACK * 2.0
	enemy.velocity = Vector3.ZERO
	ai.context.spatial.reset_evaluation()
	enemy.request_crouch(false)
	enemy._physics_process(0.3)
	for frame in 16:
		await physics_frame
		ai.action_selector.assess_options(ai, true)
	var cancelled := false
	var landed := false
	for frame in 300:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		enemy._physics_process(1.0 / 60.0)
		if enemy.is_vaulting() and enemy.body_motion.progress > 0.55 and not cancelled:
			ai._cancel_utility_execution(&"configuration")
			# Withdraw combat permission as well as the current request: otherwise a
			# fresh legal melee choice after landing is expected, not resurrection.
			ai.unit_type.profile.default_behaviors.clear()
			ai.refresh_configuration(true)
			cancelled = true
			check(action.route_motion.route.is_empty() and ai.current_action == null and enemy.is_vaulting(), "cancelling the selected action clears route ownership while the body safely finishes")
		if cancelled and not enemy.is_vaulting():
			landed = enemy.global_position.y < 0.2
			break
	# A revoked request must never return after the body finishes its safe landing.
	check(cancelled and landed and action.route_motion.route.is_empty() and ai.current_action == null, "cancelled movement and attack requests do not resurrect on safe landing")
	print("ENEMY VAULT UTILITY: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
