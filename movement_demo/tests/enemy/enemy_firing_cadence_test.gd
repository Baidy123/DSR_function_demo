extends SceneTree

## Execution contract. Autonomous coordination is covered by the runtime suites;
## this fixture drives real weapons, reloads, vision and friendly-line checks.
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var scene
var player
var shooter
var partner
var context
var partner_context
var checks := 0
var failures := 0
var clock := 0.0
var intent := {"owner": &"cooperate", "mode": &"visible", "support_intent": true}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	shooter = arena.get_node("Enemy")
	for child in arena.get_children():
		if child != shooter and child.has_node("AI"): child.free()
	shooter.position = Vector3(5, 0, 0)
	shooter.weapon = WeaponData.new()
	shooter.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	player = scene.get_node("Player")
	player.position = Vector3(20, 0, 0)
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	mesh.vertices = PackedVector3Array([Vector3(-8, 0.5, -8), Vector3(8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	for body in region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	partner = load("res://scenes/enemy/enemy.tscn").instantiate()
	partner.position = Vector3(5, 0, 3)
	partner.weapon = WeaponData.new()
	arena.add_child(partner)
	for actor in [shooter, partner]:
		Fixture.configure_timing(actor)
		var ai = actor.get_node("AI")
		ai.training.profile.selected_tactics.assign([&"cooperate"])
		ai.training.profile.set_setting(&"tactics", &"shot_interval_multiplier", 1.5)
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 1.8)
		ai.training.profile.set_setting(&"tactics", &"support_burst_shot_count", 6)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		actor.weapon.shot_interval = 0.2
		actor.weapon.magazine_capacity = 40
		actor.weapon.reload_seconds = 3.5
		actor.ammo.magazine_rounds = 40
		actor.aim_turn_speed_degrees = 3600.0
		actor.debug_shooting = false
		actor.look_at(player.global_position)
	context = shooter.get_node("AI").context
	partner_context = partner.get_node("AI").context
	for frame in 12: await physics_frame
	var defaults = preload("res://scripts/enemy/config/tactics_settings.gd").new()
	check(defaults.burst_shot_count == 3 and defaults.support_burst_shot_count == 6 and is_equal_approx(defaults.burst_pause_seconds, 1.8) and is_equal_approx(defaults.shot_interval_multiplier, 1.5), "Production defaults specify three shots, six covering shots, 1.8-second observation and 1.5 AI interval")
	check(is_equal_approx(shooter.weapon.shot_interval, 0.2) and is_equal_approx(context.fire.shot_interval_seconds(), 0.3), "AI cadence slows to 0.3 seconds without modifying the weapon interval")
	await _ordinary_burst()
	await _covering_burst()
	await _cancel_request()
	await _isolation_and_safety(region)
	await _autonomous_support()
	await _solo_cadence()
	print("FIRING CADENCE: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _reset() -> void:
	if is_instance_valid(partner):
		partner.cancel_reload()
		partner_context.cooperation_publish_execution({})
	context.fire.reset_fire_timing()
	shooter.shot_cooldown = 0.0
	shooter.ammo.magazine_rounds = 40
	shooter.weapon_stability = 1.0
	shooter.look_at(player.global_position)
	context.utility_current = {"id": &"cooperate"}
	clock = 0.0

func _tick(selected: Dictionary = {}) -> void:
	await physics_frame
	clock += STEP
	if is_instance_valid(partner):
		partner_context.update_evidence(STEP, partner_context.perception.can_see_player())
		partner_context.fire.update(STEP, partner_context.sees_player, false, {})
		partner_context.cooperation_publish_execution({})
	context.update_evidence(STEP, context.perception.can_see_player())
	var fire_intent: Dictionary = intent if selected.is_empty() else selected
	context.fire.update(STEP, context.sees_player, false, fire_intent)
	context.cooperation_publish_execution({"fire": fire_intent})

func _first_wave(selected: Dictionary = {}) -> Array[float]:
	var times: Array[float] = []
	var before: int = shooter.shot_count
	for frame in 360:
		await _tick(selected)
		if shooter.shot_count > before:
			times.append(clock)
			before = shooter.shot_count
		if context.fire.fire_pause_remaining > 0.0: break
	return times

func _legal_gaps(times: Array[float]) -> bool:
	if times.size() < 2: return false
	for index in range(1, times.size()):
		var gap := times[index] - times[index - 1]
		if gap < 0.3 - 0.001 or gap > 0.3 + STEP * 1.5: return false
	return true

func _status() -> Dictionary:
	for member: Dictionary in partner_context.cooperation_snapshot().members:
		if member.id == shooter.get_instance_id(): return member
	return {}

func _ordinary_burst() -> void:
	_reset()
	var wave := await _first_wave()
	check(wave.size() == 3 and _legal_gaps(wave), "A support label without real teammate demand fires only three slower shots")
	check(is_equal_approx(context.fire.fire_pause_remaining, 1.8), "The third ordinary shot starts the complete observation pause")
	var status := _status()
	check(not status.get("ready", true) and is_zero_approx(float(status.get("support_seconds", -1.0))), "The observation pause publishes no current covering fire")
	var count: int = shooter.shot_count
	var last: float = clock
	var no_early := true
	for frame in 120:
		await _tick()
		if shooter.shot_count > count:
			no_early = clock - last >= 1.8 - 0.001
			break
	check(no_early and shooter.shot_count == count + 1, "Actual shots resume only after the 1.8-second observation pause")
	var saved: float = context.fire.fire_interval_remaining
	await _tick({"owner": &"engage", "mode": &"visible"})
	check(shooter.shot_count == count + 1 and context.fire.fire_interval_remaining < saved and context.fire.fire_interval_remaining > 0.0, "Changing the authorized action preserves the outstanding AI shot interval")

func _covering_burst() -> void:
	_reset()
	partner.ammo.magazine_rounds = 5
	partner.request_reload()
	partner_context.cooperation_publish_execution({})
	check(partner.ammo.is_reloading and context.fire.burst_limit(true) == 6 and context.fire.burst_limit(false) == 3, "Only the real teammate reload extends an explicit covering intent")
	var wave := await _first_wave()
	check(wave.size() == 6 and _legal_gaps(wave), "A real reload receives six actual covering shots at the slower AI cadence")
	check(partner.ammo.is_reloading and wave.size() == 6 and wave.back() - wave.front() >= 1.5 - STEP, "The long burst overlaps the teammate's actual vulnerable reload")
	check(context.fire.fire_pause_remaining > 1.79 and not _status().get("ready", true), "Even a long covering burst ends in a real observation pause")
	partner.cancel_reload()
	partner_context.cooperation_publish_execution({})
	check(context.fire.burst_limit(true) == 3, "Finishing the real request removes the permission for another long burst")

func _cancel_request() -> void:
	_reset()
	partner.ammo.magazine_rounds = 5
	partner.request_reload()
	partner_context.cooperation_publish_execution({})
	var start: int = shooter.shot_count
	for frame in 180:
		await _tick()
		if shooter.shot_count >= start + 4: break
	check(shooter.shot_count == start + 4 and context.fire.fire_pause_remaining == 0.0, "Cancellation fixture reaches the fourth real covering shot")
	partner.cancel_reload()
	await _tick()
	check(shooter.shot_count == start + 4 and context.fire.fire_pause_remaining > 1.79 and context.fire.fire_burst_shots == 0, "Removing demand after the short quota is spent starts rest without a free fifth shot")
	var before := [context.fire.fire_interval_remaining, context.fire.fire_pause_remaining, context.fire.fire_burst_shots, shooter.shot_count]
	context.fire.shot_wait_seconds()
	context.fire.burst_window_seconds(true)
	context.fire.support_burst_duration()
	check(before == [context.fire.fire_interval_remaining, context.fire.fire_pause_remaining, context.fire.fire_burst_shots, shooter.shot_count], "Cadence estimates are read-only and cannot renew a pause or fire")

func _isolation_and_safety(region: NavigationRegion3D) -> void:
	_reset()
	partner.ammo.magazine_rounds = 5
	partner.request_reload()
	partner_context.cooperation_publish_execution({})
	var group: StringName = partner.communication_group
	partner.communication_group = &"cadence_other_group"
	partner_context.update_evidence(STEP, partner_context.perception.can_see_player())
	partner_context.cooperation_publish_execution({})
	check(context.fire.burst_limit(true) == 3, "A different communication group cannot authorize covering bursts")
	partner.communication_group = group
	partner_context.update_evidence(STEP, partner_context.perception.can_see_player())
	partner_context.cooperation_publish_execution({})
	check(context.fire.burst_limit(true) == 6, "Restoring a live same-group reload restores only its real covering opportunity")
	var saved: Vector3 = partner.global_position
	partner.global_position = shooter.global_position.lerp(player.global_position, 0.5)
	partner_context.cooperation_publish_execution({})
	var count: int = shooter.shot_count
	for frame in 50: await _tick()
	check(shooter.shot_count == count and not _status().get("ready", true), "Covering demand never permits firing through a friendly body")
	partner.global_position = saved
	partner.cancel_reload()
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(0.4, 4, 3)
	wall.add_child(collision)
	region.add_child(wall)
	wall.global_position = shooter.global_position.lerp(player.global_position, 0.5) + Vector3.UP
	for frame in 30: await _tick()
	check(shooter.shot_count == count and not context.sees_player, "A hard wall still stops visible fire despite the support intent")
	context.fire.reset_fire_timing()
	check(is_zero_approx(context.fire.fire_interval_remaining) and is_zero_approx(context.fire.fire_pause_remaining) and context.fire.fire_burst_shots == 0, "Lifecycle reset clears the added cadence timer together with the existing burst state")
	wall.queue_free()
	for frame in 3: await physics_frame

func _solo_cadence() -> void:
	partner.queue_free()
	await physics_frame
	partner = null
	partner_context = null
	var ai = shooter.get_node("AI")
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	_reset()
	var normal := {"owner": &"engage", "mode": &"visible", "support_intent": true}
	var disabled := await _first_wave(normal)
	check(not context.cooperation_enabled() and disabled.size() == 3 and _legal_gaps(disabled), "An actual single enemy with collaboration disabled still fires the new ordinary short cadence")
	ai.training.profile.selected_tactics.assign([&"cooperate"])
	ai.refresh_configuration(true)
	_reset()
	var enabled := await _first_wave(normal)
	check(context.cooperation_enabled() and enabled.size() == 3 and _legal_gaps(enabled), "Enabling collaboration for the same single enemy grants no invented long covering burst")
	check(not disabled.is_empty() and disabled.size() == enabled.size() and absf((disabled.back() - disabled.front()) - (enabled.back() - enabled.front())) < STEP, "Solo collaboration ON/OFF preserves the same measured short-burst spacing")
	check(context.fire.fire_interval_remaining > 0.0 and context.fire.fire_pause_remaining > 0.0, "Death lifecycle case starts with both cadence timers genuinely running")
	shooter.receive_hit(shooter.max_health)
	check(shooter.is_dead and is_zero_approx(context.fire.fire_interval_remaining) and is_zero_approx(context.fire.fire_pause_remaining), "Actual death clears the AI interval and burst pause")
	shooter.reset_target()
	check(not shooter.is_dead and is_zero_approx(context.fire.fire_interval_remaining) and is_zero_approx(context.fire.fire_pause_remaining), "Actual respawn starts without a leftover cadence delay")

func _autonomous_support() -> void:
	_reset()
	var first_ai = shooter.get_node("AI")
	var second_ai = partner.get_node("AI")
	for ai in [first_ai, second_ai]:
		ai.reset_actions()
		ai.context.reset_memory()
		ai.actor.velocity = Vector3.ZERO
		ai.actor.look_at(player.global_position)
	partner.ammo.magazine_rounds = 0
	var maximum_wave := 0
	var wave := 0
	var last_shot_frame := -1000
	var covered_shots := 0
	var covered_move_seconds := 0.0
	var reload_frames := 0
	var chosen: Dictionary = {}
	for frame in 360:
		var partner_position: Vector3 = partner.global_position
		await physics_frame
		var before: int = shooter.shot_count
		var exposed: bool = partner.ammo.is_reloading
		first_ai._physics_process(STEP)
		second_ai._physics_process(STEP)
		if partner.ammo.is_reloading: reload_frames += 1
		var moved: Vector3 = partner.global_position - partner_position
		if exposed and Vector2(moved.x, moved.z).length() > 0.001 and _status().get("ready", false): covered_move_seconds += STEP
		var action: String = "%s/%s" % [first_ai.utility_current.get("id", &""), first_ai.utility_current.get("plan", &"")]
		chosen[action] = int(chosen.get(action, 0)) + 1
		if shooter.shot_count > before:
			wave = wave + 1 if frame - last_shot_frame <= 20 else 1
			last_shot_frame = frame
			maximum_wave = maxi(maximum_wave, wave)
			if exposed and context.fire.request.get("support_intent", false): covered_shots += 1
	print("AUTONOMOUS CADENCE wave=%d covering_shots=%d reload_frames=%d covered_move=%.3f actions=%s" % [maximum_wave, covered_shots, reload_frames, covered_move_seconds, chosen])
	check(reload_frames > 0 and partner.ammo.magazine_rounds > 0, "The ordinary Utility loop independently starts and completes the empty teammate's real reload")
	check(covered_shots >= 4 and maximum_wave == 6, "The ordinary Utility loop chooses a real six-shot covering wave overlapping the teammate reload")
	check(covered_move_seconds >= 0.3, "The teammate actually moves for at least 0.3 seconds while reloading under the measured covering fire")
	check(context.fire.burst_shot_count == 3 and is_equal_approx(context.fire.shot_interval_seconds(), 0.3), "Autonomous covering uses the new ordinary three-shot and 0.3-second cadence settings")
	first_ai.reset_actions()
	second_ai.reset_actions()
