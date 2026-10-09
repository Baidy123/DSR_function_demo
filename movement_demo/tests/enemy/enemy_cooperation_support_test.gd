extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0
var scene
var player
var shooter
var partner
var context
var partner_context
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
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.velocity = Vector3.ZERO
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	partner = load("res://scenes/enemy/enemy.tscn").instantiate()
	partner.position = Vector3(5, 0, 3)
	partner.weapon = WeaponData.new()
	arena.add_child(partner)
	for actor in [shooter, partner]:
		Fixture.configure_timing(actor)
		var ai = actor.get_node("AI")
		ai.training.profile.selected_tactics.assign([&"cooperate"])
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 1.5)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		actor.weapon.shot_interval = 0.2
		actor.weapon.magazine_capacity = 20
		actor.weapon.reload_seconds = 3.5
		actor.ammo.magazine_rounds = 20
		actor.aim_turn_speed_degrees = 3600.0
		actor.debug_shooting = false
		actor.look_at(player.global_position)
	context = shooter.get_node("AI").context
	partner_context = partner.get_node("AI").context
	# This is a fire/publication execution contract, not an autonomous selection test.
	context.utility_current = {"id": &"cooperate", "cooperation": {"kind": &"advance", "lane_id": &"position:31:0"}}
	for frame in 12: await physics_frame
	var saw_ready := false
	var saw_cycle := false
	var cycle_shots := 0
	for frame in 180:
		await _tick()
		var status: Dictionary = _status()
		if status.get("ready", false) and not saw_ready:
			saw_ready = true
			check(status.lane_id == &"target" and status.position_lane_id == &"position:31:0", "Actual hold fire uses the target lane while preserving the position slot")
		if status.get("support_cycle_valid", false):
			saw_cycle = true
			cycle_shots = shooter.shot_count
			check(not status.ready and is_zero_approx(status.support_seconds) and not _has_support(), "A normal burst pause publishes zero current fire support")
			check(status.support_resume_seconds > 0.0 and is_equal_approx(status.support_resume_seconds, context.fire.fire_pause_remaining), "Cycle recovery is the actual remaining burst pause")
			break
	check(saw_ready and saw_cycle and cycle_shots == 3, "Real 0.2-second shots finish one three-shot burst before entering its cycle")
	var no_pause_shots := true
	var resumed := false
	for frame in 180:
		var was_paused: bool = context.fire.fire_pause_remaining > STEP + 0.001
		var before: int = shooter.shot_count
		await _tick()
		if was_paused: no_pause_shots = no_pause_shots and shooter.shot_count == before
		if shooter.shot_count > cycle_shots:
			resumed = _status().get("ready", false)
			break
	check(no_pause_shots and resumed, "The real fire controller respects the pause and resumes actual support without bypassing timing")
	await _invalid_cycles(region)
	_hold_predictions()
	await _current_gun_lane(region)
	print("COOPERATION SUPPORT FACTS: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _tick() -> void:
	await physics_frame
	context.update_evidence(STEP, context.perception.can_see_player())
	partner_context.update_evidence(STEP, partner_context.perception.can_see_player())
	partner_context.cooperation_publish_execution({})
	context.fire.update(STEP, context.sees_player, false, intent)
	context.cooperation_publish_execution({"fire": intent})

func _status() -> Dictionary:
	for member: Dictionary in partner_context.cooperation_snapshot().members:
		if member.id == shooter.get_instance_id(): return member
	return {}

func _has_support() -> bool:
	return partner_context.cooperation_snapshot().supports.any(func(support): return support.owner_id == shooter.get_instance_id())

func _publish(selected_intent: Dictionary = {}) -> Dictionary:
	context.cooperation_publish_execution({"fire": intent if selected_intent.is_empty() else selected_intent})
	return _status()

func _no_cycle(label: String) -> void:
	var status := _publish()
	check(not status.get("support_cycle_valid", true) and status.get("support_resume_seconds", 0.0) < 0.0 and not status.get("ready", true) and is_zero_approx(status.get("support_seconds", -1.0)), label)

func _invalid_cycles(region: NavigationRegion3D) -> void:
	var fire = context.fire
	fire.fire_pause_remaining = 1.0
	fire.fire_reaction_elapsed = fire.fire_reaction_seconds
	fire.fire_decision.reset()
	shooter.shot_cooldown = 0.0
	shooter.weapon_stability = 1.0
	check(_publish().get("support_cycle_valid", false), "Boundary checks begin with an otherwise legal visible cycle")
	var before := [fire.fire_pause_remaining, fire.fire_reaction_elapsed, fire.fire_burst_shots, fire.fire_decision.wait_seconds, shooter.ammo.magazine_rounds, shooter.shot_count]
	_publish()
	check(before == [fire.fire_pause_remaining, fire.fire_reaction_elapsed, fire.fire_burst_shots, fire.fire_decision.wait_seconds, shooter.ammo.magazine_rounds, shooter.shot_count], "Publishing a cycle does not advance timers, change aim decisions or fire shots")
	shooter.velocity = Vector3.RIGHT
	_no_cycle("A moving provider is not a stationary support cycle")
	shooter.velocity = Vector3.ZERO
	var aim: Vector3 = shooter.aim_direction
	shooter.aim_direction = -aim
	_no_cycle("A provider turning away has lost support rather than entered a cycle")
	shooter.aim_direction = aim
	fire.fire_reaction_elapsed = 0.0
	_no_cycle("Unfinished reaction cannot masquerade as a burst cycle")
	fire.fire_reaction_elapsed = fire.fire_reaction_seconds
	fire.fire_decision.selected_action = fire.fire_decision.Action.STEADY
	_no_cycle("An actual steady decision is not a normal burst cycle")
	fire.fire_decision.reset()
	shooter.weapon_stability = 0.1
	_no_cycle("A reset steady decision still requires a truthful stability comparison")
	shooter.weapon_stability = 1.0
	shooter.shot_cooldown = 2.0
	_no_cycle("A longer mechanical cooldown cannot be advertised as the shorter burst pause")
	shooter.shot_cooldown = 0.0
	var rounds: int = shooter.ammo.magazine_rounds
	shooter.ammo.magazine_rounds = 0
	_no_cycle("An empty magazine invalidates cycle recovery")
	shooter.ammo.magazine_rounds = rounds
	shooter.request_reload()
	_no_cycle("Actual reloading invalidates cycle recovery")
	shooter.cancel_reload()
	shooter.weapon_stability = 1.0
	check(_publish().get("support_cycle_valid", false), "Cancelling the reload and restoring stability gives later negative cases a legal baseline")
	var memory_status := _publish({"owner": &"cooperate", "mode": &"memory", "point": context.last_seen_aim_position})
	check(not memory_status.get("support_cycle_valid", true) and not memory_status.get("ready", true), "A remembered point cannot authorize a visible support cycle")
	check(_publish().get("support_cycle_valid", false), "The visible cycle is legal again before adding the hard occluder")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.3, 4.0, 3.0)
	wall.add_child(shape)
	region.add_child(wall)
	wall.global_position = shooter.global_position.lerp(player.global_position, 0.5) + Vector3.UP
	for frame in 3: await physics_frame
	_no_cycle("A new hard occluder invalidates a cycle even before old visual state is refreshed")
	wall.queue_free()
	for frame in 3: await physics_frame
	check(_publish().get("support_cycle_valid", false), "Removing the hard occluder restores the same otherwise legal cycle")
	context.update_evidence(STEP, false)
	_no_cycle("Personal visual loss immediately invalidates cycle recovery")
	context.update_evidence(STEP, context.perception.can_see_player())
	shooter.update_weapon(0.01, context.last_seen_aim_position)
	shooter.weapon_stability = 1.0
	check(_publish().get("support_cycle_valid", false), "Real personal sight restores the legal baseline before the friendly-line case")
	var partner_position: Vector3 = partner.global_position
	partner.global_position = shooter.global_position.lerp(player.global_position, 0.5)
	partner_context.cooperation_publish_execution({})
	_no_cycle("A friendly body in the firing line invalidates cycle recovery")
	partner.global_position = partner_position
	partner_context.cooperation_publish_execution({})
	check(_publish().get("support_cycle_valid", false), "Moving the friendly body away restores the legal firing cycle")
	partner.ammo.magazine_rounds = 5
	partner.request_reload()
	partner_context.cooperation_publish_execution({})
	shooter.weapon_stability = 0.35
	fire.fire_decision.reset()
	var ordinary := _publish({"owner": &"cooperate", "mode": &"visible"})
	var covering := _publish()
	check(partner.ammo.is_reloading and not ordinary.get("support_cycle_valid", true) and covering.get("support_cycle_valid", false), "Only a real unmet team request gives support intent its existing steady-pressure benefit")
	check(not covering.ready and is_zero_approx(covering.support_seconds) and not _has_support(), "Support intent still grants no fire during the real burst pause")
	partner.cancel_reload()
	partner_context.cooperation_publish_execution({})
	_no_cycle("Removing the real request removes its pressure rather than preserving a promise")

func _zero_hold(action, label: String) -> void:
	var candidates: Array[Dictionary] = action.collect_candidates(true)
	check(candidates.size() == 1 and is_zero_approx(candidates[0].cooperation.support_seconds) and is_zero_approx(context.cooperation_candidate_seconds(candidates[0])), label)

func _hold_predictions() -> void:
	# Start a legal public candidate to inspect its execution contract. This does
	# not stand in for the separate autonomous flank ON/OFF runtime test.
	var fire = context.fire
	shooter.weapon_stability = 1.0
	shooter.shot_cooldown = 0.0
	fire.fire_interval_remaining = 0.0
	fire.fire_pause_remaining = 0.0
	fire.fire_reaction_elapsed = fire.fire_reaction_seconds
	fire.fire_decision.reset()
	partner.ammo.magazine_rounds = 5
	partner.request_reload()
	partner_context.cooperation_publish_execution({})
	var action = shooter.get_node("AI").actions[&"cooperate"]
	var selected: Dictionary = action._overwatch_candidate()
	check(not selected.is_empty() and selected.cooperation.support_seconds > 0.0 and selected.cooperation.support_seconds <= float(selected.hold_seconds), "A legal overwatch candidate predicts fire only within its actual initial hold")
	if selected.is_empty(): return
	context.utility_current = selected
	var began: bool = action.begin(selected, true)
	check(began and action.phase == action.Phase.HOLD, "The legal overwatch candidate starts through its normal validation and claim contract")
	if not began: return
	var saved_hold: float = action._hold_remaining
	fire.fire_pause_remaining = saved_hold + 0.3
	check(action._overwatch_candidate().is_empty(), "A burst pause outliving the initial hold cannot sell a later action's shots")
	_zero_hold(action, "A committed HOLD whose remaining life is shorter than its burst pause has zero support credit")
	fire.fire_pause_remaining = 0.0
	shooter.shot_cooldown = saved_hold + 0.3
	_zero_hold(action, "A committed HOLD cannot credit shots beyond its real mechanical cooldown")
	shooter.shot_cooldown = 0.0
	action._hold_remaining = minf(0.1, fire.fire_reaction_seconds * 0.5)
	fire.fire_reaction_elapsed = 0.0
	_zero_hold(action, "A short committed HOLD cannot credit shots before reaction completes")
	fire.fire_reaction_elapsed = fire.fire_reaction_seconds
	shooter.weapon_stability = 0.0
	_zero_hold(action, "A short committed HOLD cannot credit shots before its true support steady wait")
	shooter.weapon_stability = 1.0
	var aim: Vector3 = shooter.aim_direction
	shooter.aim_direction = -aim
	_zero_hold(action, "An unaligned HOLD has no guessed immediate support credit")
	shooter.aim_direction = aim
	var partner_position: Vector3 = partner.global_position
	partner.global_position = shooter.global_position.lerp(player.global_position, 0.5)
	partner_context.cooperation_publish_execution({})
	_zero_hold(action, "A friendly blocker removes both the initial and committed HOLD's support credit")
	check(action._overwatch_candidate().is_empty(), "An initial overwatch candidate also respects the real friendly firing line")
	partner.global_position = partner_position
	partner_context.cooperation_publish_execution({})
	var before := [action._hold_remaining, action._remaining, action.plan.duplicate(true), fire.fire_pause_remaining, fire.fire_reaction_elapsed, fire.fire_burst_shots, fire.fire_interval_remaining, fire.fire_decision.wait_seconds, shooter.shot_count]
	var candidates: Array[Dictionary] = action.collect_candidates(true)
	check(candidates.size() == 1 and candidates[0].cooperation.support_seconds > 0.0 and candidates[0].cooperation.support_seconds <= action._hold_remaining and context.cooperation_candidate_seconds(candidates[0]) > 0.0, "Restoring a legal gun restores credit bounded by the actual remaining hold")
	check(before == [action._hold_remaining, action._remaining, action.plan, fire.fire_pause_remaining, fire.fire_reaction_elapsed, fire.fire_burst_shots, fire.fire_interval_remaining, fire.fire_decision.wait_seconds, shooter.shot_count], "HOLD prediction leaves claims, timers, aim pressure and actual shots unchanged")
	action.cancel(&"test_complete")
	context.utility_current = {}
	partner.cancel_reload()
	partner_context.cooperation_publish_execution({})

func _current_gun_lane(region: NavigationRegion3D) -> void:
	var fire = context.fire
	# This geometry fixture starts a fresh, fully ready gun, including AI cadence.
	fire.fire_interval_remaining = 0.0
	fire.fire_burst_shots = 0
	fire.fire_pause_remaining = 0.0
	fire.fire_reaction_elapsed = fire.fire_reaction_seconds
	fire.fire_decision.reset()
	shooter.shot_cooldown = 0.0
	shooter.weapon_stability = 1.0
	context.update_evidence(STEP, context.perception.can_see_player())
	var origin: Vector3 = shooter.get_shot_origin()
	var desired: Vector3 = context.last_seen_aim_position - origin
	var aim: Vector3 = shooter.aim_direction
	var turn_speed: float = shooter.aim_turn_speed_degrees
	shooter.aim_direction = desired.normalized().rotated(Vector3.UP, deg_to_rad(2.5))
	shooter.aim_turn_speed_degrees = 0.0
	var action = shooter.get_node("AI").actions[&"cooperate"]
	check(_publish().get("ready", false) and action._hold_support_prediction(1.2).support_seconds > 0.0, "The current gun is inside the allowed aim angle and genuinely ready before the narrow blocker")
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.04, 3.0, 0.04)
	collision.shape = shape
	wall.add_child(collision)
	region.add_child(wall)
	wall.global_position = origin + shooter.aim_direction * 3.0
	for frame in 3: await physics_frame
	check(fire.has_clear_firing_lane(origin, desired, desired.length()) and not fire.has_clear_firing_lane(origin, shooter.aim_direction, desired.length()), "The narrow blocker obstructs the actual current gun ray while the desired target ray remains clear")
	check(is_zero_approx(action._hold_support_prediction(1.2).support_seconds), "HOLD prediction rejects the blocked current gun ray even when its desired ray is clear")
	var shots: int = shooter.shot_count
	fire.update(STEP, true, false, intent)
	var blocked := _publish()
	check(shooter.shot_count == shots and not blocked.ready and is_zero_approx(blocked.support_seconds) and not _has_support(), "Real fire execution and published readiness both reject that blocked current gun ray")
	wall.queue_free()
	for frame in 3: await physics_frame
	fire.update(STEP, true, false, intent)
	var restored := _publish()
	check(shooter.shot_count > shots and restored.ready and restored.support_seconds > 0.0 and _has_support(), "Removing the narrow blocker restores real shots and current support with the same gun direction")
	shooter.aim_direction = aim
	shooter.aim_turn_speed_degrees = turn_speed
