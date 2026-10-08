extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func settle(count: int = 4) -> void:
	for index in count:
		await physics_frame
		await process_frame

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
	Fixture.configure_timing(enemy)
	Fixture.set_training_action(ai, &"exit_suppression", true)
	ai.actions[&"search"].tracking_cheat_enabled = false
	player.health.debug_invincible = true
	var cover = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var center: Vector3 = cover.global_position
	center.y = 0.0
	enemy.global_position = center + Vector3.BACK
	player.global_position = center + Vector3.FORWARD * 0.66
	enemy.look_at(player.global_position)
	await settle(8)
	check(is_equal_approx(enemy.get_body_height(), 1.75), "enemy standing height is 1.75m")
	enemy.request_crouch(true)
	enemy._physics_process(0.1)
	check(enemy.get_body_height() < 1.75 and enemy.get_body_height() > 1.0, "capsule visibly transitions through intermediate crouch height")
	enemy._physics_process(0.1)
	check(is_equal_approx(enemy.get_body_height(), 1.0) and is_equal_approx(enemy.get_node("Body").mesh.height, 1.0) and is_equal_approx(enemy.get_node("FrontMarker").position.y, 0.75), "crouch collision and capsule mesh both reach 1m")
	check(enemy.get_movement_noise_radius() == 1.5 and not enemy.can_melee(), "crouch noise multiplier and stand-before-melee entry guard")
	var ceiling := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.0, 0.2, 1.0)
	collision.shape = box
	ceiling.add_child(collision)
	scene.add_child(ceiling)
	ceiling.global_position = enemy.global_position + Vector3.UP * 1.2
	await settle()
	enemy.request_crouch(false)
	enemy._physics_process(0.3)
	check(enemy.is_crouching(), "standing cannot grow through a low ceiling")
	ceiling.queue_free()
	await settle()
	enemy._physics_process(0.3)
	check(not enemy.is_crouching(), "standing resumes when headroom is clear")
	# Independently force the actual player posture through its public controller API.
	player.request_crouch(true)
	player._update_posture(0.3)
	await settle()
	check(player.is_crouching() and not ai.perception.can_see_player(), "1.1m wall can still hide a crouching player only 1.66m away")
	ai.context.reset_memory()
	ai.training.profile.set_setting(&"perception", &"close_cover_intelligence_enabled", true)
	ai.context.update_evidence(0.1, false)
	var basis: Dictionary = ai.context.suppression_basis()
	check(not basis.is_empty() and basis.get("source") == &"close_cover_exact" and basis.position.is_equal_approx(player.global_position), "close same-wall encounter produces one exact frozen clue")
	check(not ai.context.has_visual_memory and not ai.context.sees_player and ai.context.observed_reload_window() == 0.0, "exact clue does not forge visual or reload evidence")
	var captured: Vector3 = basis.get("position", Vector3.INF)
	var event_id: int = basis.get("id", -1)
	player.global_position.x += 0.1
	for index in 5: ai.context.update_evidence(0.1, false)
	check(ai.context.suppression_basis().get("id") == event_id and ai.context.suppression_basis().position == captured, "remaining in contact neither tracks coordinates nor renews the event")
	var suppression = ai.actions[&"suppression"]
	check(basis.get("low_cover_context", false), "low-cover context is frozen with the exact clue")
	var exits = ai.actions[&"exit_suppression"]
	check(exits.utility_available(), "low-cover exit suppression remains a legal geometric alternative")
	ai.training.profile.set_setting(&"suppression", &"low_cover_point_preference", 0.0)
	var unbiased: Dictionary = ai.action_selector.score_outcome(ai.context, 1.0, 1.0, 1.0, suppression.preference_credit())
	ai.training.profile.set_setting(&"suppression", &"low_cover_point_preference", 1.0)
	var biased: Dictionary = ai.action_selector.score_outcome(ai.context, 1.0, 1.0, 1.0, suppression.preference_credit())
	check(is_equal_approx(unbiased.cost - biased.cost, 1.0) and biased.exposed_seconds == unbiased.exposed_seconds and exits.preference_credit() == 0.0, "low-cover preference transparently improves point suppression without falsifying outcomes")
	var alternatives: Array = [{"id": &"point", "cost": biased.cost}, {"id": &"better", "cost": biased.cost - 0.1}]
	check(ai.action_selector.choose_option(alternatives).id == &"better", "another lower-cost candidate can still beat the low-cover preference")
	# Move towards one end: exits no longer offer symmetric containment of the known point.
	enemy.global_position.x += 0.6
	await settle()
	var candidates: Array = suppression.collect_candidates(false)
	check(not candidates.is_empty(), "exact non-visual clue grants authorized suppression eligibility")
	if not candidates.is_empty():
		var best: Dictionary = ai.action_selector.choose_option(ai.action_selector.assess_options(ai, false))
		check(best.get("id") == &"suppression", "ordinary Utility selects authorized suppression from an exact clue")
		ai._start_utility_option(best, false)
		check(suppression.active and suppression.target_center.is_equal_approx(captured + Vector3.UP * 0.8), "suppression executes its evidence snapshot")
		var shots: int = enemy.shot_count
		var wall_hits := 0
		for frame in 100:
			await physics_frame
			ai.context.update_evidence(1.0 / 60.0, false)
			var output: Dictionary = suppression.tick(1.0 / 60.0, false)
			enemy.face_direction(output.facing, 1.0 / 60.0)
			var previous: int = enemy.shot_count
			ai.context.fire.update(1.0 / 60.0, false, false, output.fire)
			if enemy.shot_count > previous and enemy.last_shot_collider == cover: wall_hits += 1
		check(enemy.shot_count > shots and wall_hits > 0, "Utility-selected suppression fires real shots that stop at the low wall")
		check(suppression.target_center == captured + Vector3.UP * 0.8, "suppression never follows the hidden live target")
		var expiry: float = basis.valid_until
		ai._cancel_utility_execution()
		check(suppression.collect_candidates(false).is_empty(), "switching actions cannot restart a spent suppression event")
		ai.context.evidence_elapsed_seconds = expiry + 0.1
		check(ai.context.suppression_basis().is_empty(), "close clue expires on its own clock")
	ai.context.reset_memory()
	ai.context.last_known_position = player.global_position
	ai.context.is_alerted = true
	check(suppression.collect_candidates(false).is_empty(), "a position-only fuzzy hint never gains suppression eligibility")
	# Default close-wall geometry must offer a same-feet standing observation:
	# targeting an assumed crouched eye here would incorrectly reject the lane.
	player.request_crouch(false)
	player._update_posture(0.3)
	player.global_position = center + Vector3.FORWARD * 0.85
	enemy.global_position = center + Vector3.BACK * 0.85
	enemy.request_crouch(true)
	enemy._physics_process(0.3)
	await settle()
	ai.context.reset_memory()
	ai.context.has_visual_memory = true
	ai.context.is_alerted = true
	ai.context.last_seen_position = player.global_position
	ai.context.last_known_position = player.global_position
	var cover_action = ai.actions[&"cover"]
	cover_action.transfer.start_reload_transfer({"body": cover, "hide": enemy.global_position, "crouch": true}, player.global_position)
	cover_action.transfer.phase = cover_action.transfer.Phase.HIDE
	var peeks: Array = cover_action.collect_candidates(ai.perception.can_see_player()).filter(func(candidate): return candidate.get("destination", {}).get("stand_peek", false))
	check(not peeks.is_empty(), "default low wall offers same-position standing observation against a legally assumed standing target")
	if not peeks.is_empty():
		cover_action.begin(peeks[0], ai.perception.can_see_player())
		var start: Vector3 = enemy.global_position
		for frame in 18:
			await physics_frame
			var output: Dictionary = cover_action.execute_tick(1.0 / 60.0, ai.perception.can_see_player())
			enemy.request_crouch(output.get("crouch", false))
			enemy._physics_process(1.0 / 60.0)
		check(enemy.get_body_height() > 1.74 and enemy.global_position.distance_to(start) < 0.02 and ai.perception.can_see_player(), "same-position peek actually stands without shifting its feet and observes the exposed player")
		enemy.look_at(player.global_position)
		enemy.shot_cooldown = 0.0
		enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
		ai.context.fire.reset_fire_timing()
		var count: int = enemy.shot_count
		for frame in 90:
			await physics_frame
			var visible: bool = ai.perception.can_see_player()
			ai.context.update_evidence(1.0 / 60.0, visible)
			ai.context.fire.update(1.0 / 60.0, visible, false, {"owner": &"engage", "mode": &"visible"})
		check(enemy.shot_count > count and enemy.last_shot_collider == player, "standing peek fires through the actual clear muzzle lane")
		enemy.global_position = center + Vector3.BACK
		player.global_position = center + Vector3.FORWARD * 0.66
		await settle()
		ai.context.update_evidence(0.1, ai.perception.can_see_player())
		player.request_crouch(true)
		player._update_posture(0.3)
		await settle()
		ai.context.update_evidence(0.1, ai.perception.can_see_player())
		var lost: Dictionary = ai.context.suppression_basis()
		check(not ai.perception.can_see_player() and lost.get("low_cover_context", false) and not suppression.collect_candidates(false).is_empty(), "crouching out of real sight grants a frozen low-wall suppression alternative")
	cover_action.cancel()
	# Physical vault execution, attack exclusion and damage use the ordinary actor entry points.
	player.global_position = center + Vector3.FORWARD * 3.0
	enemy.global_position = center + Vector3.BACK
	enemy.velocity = Vector3.ZERO
	await settle()
	var plan := LowCover.query_vault(enemy, Vector3.FORWARD)
	check(plan.get("valid", false), "enemy standing capsule has a collision-safe low-wall vault")
	if plan.get("valid", false):
		enemy.ammo.magazine_rounds = 1
		enemy.request_reload()
		check(enemy.begin_vault(plan) and not enemy.ammo.is_reloading, "vault owns execution and cancels the active reload")
		check(not enemy.can_fire() and not enemy.can_melee() and not enemy.request_reload(), "direct shooting melee reload calls cannot bypass vault exclusion")
		var health: float = enemy.health
		enemy.receive_hit(1.0)
		check(enemy.health == health - 1.0, "vault remains damageable")
		for index in 90:
			enemy.move_character(Vector3.ZERO, 1.0 / 60.0)
			enemy._physics_process(1.0 / 60.0)
			await physics_frame
			if not enemy.is_vaulting(): break
		check(not enemy.is_vaulting() and enemy.global_position.distance_to(plan.exit) < 0.2, "swept vault reaches the checked landing and releases occupation")
		enemy._physics_process(0.3)
		check(not enemy.is_crouching() and enemy.can_reload(), "landing restores posture and execution permission")
	print("ENEMY HALF COVER: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
