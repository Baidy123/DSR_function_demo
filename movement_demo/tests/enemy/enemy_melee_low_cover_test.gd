extends SceneTree

const STEP := 1.0 / 60.0
const START := Vector3(0.0, 0.0, 3.0)
const TARGET := Vector3(0.0, 0.0, -4.0)
const Training = preload("res://scripts/enemy/config/enemy_training_profile.gd")
const MeleeSettings = preload("res://scripts/enemy/config/melee_tactics_settings.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")

var checks := 0
var failures := 0
var scene: Node3D
var enemy
var player
var ai
var wall
var budget_ok := true
var peak_query_usec := 0
var peak_execution_usec := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print("PASS " if value else "FAIL ", label)

func _run() -> void:
	_build_fixture()
	await _prepare()
	if not ai.context.environment_ready() or not ai.context.is_arena_active():
		var context = ai.context
		var zone_shape: CollisionShape3D = context.arena_zone.get_node("CollisionShape3D")
		print("FIXTURE environment spawn=", context._spawn_position, " actor=", enemy.global_position,
			" player=", player.global_position, " free=", context.is_position_free(context._spawn_position),
			" nav=", NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), context._spawn_position),
			" iteration=", NavigationServer3D.region_get_iteration_id(context.navigation_region.get_rid()),
			" zone_local=", zone_shape.to_local(context._spawn_position + Vector3.UP * 0.875),
			" zone_size=", zone_shape.shape.size, " overlaps=", context.arena_zone.get_overlapping_bodies())
	check(ai.context.environment_ready() and ai.context.is_arena_active(), "independent low-wall fixture has synchronized navigation and real combat overlap")
	check(ai.perception.can_see_player() and ai.context.observed_reload_window() > 0.0, "real visible reload establishes an opportunity before the cold decision loop")
	check(ai.actions.has(&"cover") and ai.actions.has(&"melee_cover") and ai.actions[&"cover"].transfer != ai.actions[&"melee_cover"].transfer, "base shelter and trained melee advance keep separate action and movement instances")
	var samples: Array = wall.get_candidates(player.get_eye_position(), enemy.global_position)
	check(not samples.is_empty() and samples.all(func(point): return point.crouch and point.peeks.is_empty() and point.hide.is_equal_approx(point.stand)), "real low-wall candidates provide crouch/stand at one point and no corner peeks")
	var action = ai.actions[&"melee_cover"]
	var point: Dictionary = {}
	for candidate in action.evaluation_points():
		if candidate.body == wall and ai.context.spatial.cover_valid(candidate):
			point = candidate
			break
	check(not point.is_empty(), "a real crouch-protected low-wall destination is reachable in the fixture")
	var assessment: Dictionary = action.evaluate_point(point) if not point.is_empty() else {}
	# This is the old implementation's direct regression: peeks=[] must not remove
	# a valid melee destination. It does not force the Utility winner or execution.
	check(not assessment.is_empty(), "melee advance evaluates a low wall without inventing side peek points")
	if not assessment.is_empty():
		check(assessment.destination.exit.is_equal_approx(assessment.destination.hide), "low-wall observation uses the same standing point rather than a corner exit")
		await _blocked_destination_checks(action, assessment.destination)
	await _wall_blocks_melee()
	await _prepare()
	check(ai.context.spatial.total_evaluated_count == 0 and ai.context.spatial.destinations(ai.actions[&"melee_cover"]).is_empty(), "full approach starts with empty shared spatial and route caches")
	var health_before: float = player.health.health
	var selected := false
	var crouched := false
	var stood_after_crouch := false
	var released := false
	var crouch_at := -1
	var release_at := -1
	var hit_at := -1
	var selected_plan: Dictionary = {}
	for frame in 600:
		await _tick()
		if ai.utility_current.get("id") == &"melee_cover" and ai.utility_current.get("destination", {}).get("body") == wall:
			selected = true
			if selected_plan.is_empty(): selected_plan = ai.utility_current.duplicate(true)
			if enemy.is_crouching():
				crouched = true
				if crouch_at < 0: crouch_at = frame
		if crouched and not enemy.is_vaulting() and enemy.body_motion.amount <= 0.0001:
			stood_after_crouch = true
		if crouched and ai.utility_current.get("id") != &"melee_cover":
			released = true
			if release_at < 0: release_at = frame
		if player.health.health < health_before:
			hit_at = frame
			break
	check(selected, "cold-cache ordinary Utility autonomously selects low-wall melee advance")
	check(crouched and crouch_at >= 0, "selected advance physically reaches a completed crouching posture behind the wall")
	check(stood_after_crouch and released, "finite low-wall concealment stands to observe and releases the advancing action")
	check(enemy.melee_count > 0 and player.health.health < health_before and hit_at >= 0, "ordinary melee execution actually damages the player after leaving the low wall")
	check(enemy.shot_count == 0 and not enemy.can_use_firearms(), "low-wall use never grants a melee unit firearm execution")
	print("LOW WALL CYCLE selected=", selected, " crouch=", crouch_at, " release=", release_at, " hit=", hit_at, " plan=", selected_plan.get("destination", {}))
	await _hidden_target_and_timeout()
	await _blocked_stand_and_revocation()
	check(budget_ok and ai.context.spatial.EVALUATION_POINTS_PER_FRAME == 24 and ai.context.spatial.EVALUATION_BUDGET_USEC == 2000, "new low-wall evaluation retains the original shared 24-point/2-ms budget")
	check(peak_query_usec < 20000 and peak_execution_usec < 20000, "low-wall candidate and execution calls retain the original 20-ms maximum")
	print("MELEE LOW COVER: %d/%d passed; query %d us; execution %d us" % [checks - failures, checks, peak_query_usec, peak_execution_usec])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _blocked_destination_checks(action, destination: Dictionary) -> void:
	var candidate: Dictionary = action._advance_candidate(destination, false)
	check(not candidate.is_empty() and action.validate(candidate, true), "unblocked low-wall advance passes the normal commit validation")
	if candidate.is_empty(): return
	var blocker := _box(Vector3(0.8, 2.0, 0.8), destination.hide + Vector3.UP)
	scene.add_child(blocker)
	await physics_frame
	check(not action.validate(candidate, true), "a dynamically occupied crouch destination rejects the previous low-wall plan")
	blocker.queue_free()
	await physics_frame
	var ceiling := _box(Vector3(1.4, 0.2, 1.4), destination.hide + Vector3.UP * 1.3)
	scene.add_child(ceiling)
	await physics_frame
	check(Geometry.can_occupy(enemy, destination.hide, enemy.get_posture_body_height(true), 0.35) and not Geometry.can_occupy(enemy, destination.hide, enemy.get_posture_body_height(false), 0.35), "low ceiling really permits crouching but blocks the standing observation capsule")
	check(not action.validate(candidate, true), "a dynamically blocked standing exit rejects the old low-wall observation plan")
	ceiling.queue_free()
	await physics_frame

func _wall_blocks_melee() -> void:
	enemy.global_position = Vector3(0.0, 0.0, 0.85)
	player.global_position = Vector3(0.0, 0.0, -0.7)
	enemy.look_at(player.global_position)
	await physics_frame
	var visible: bool = ai.perception.can_see_player()
	ai.context.update_evidence(0.0, visible)
	check(visible and enemy.global_position.distance_to(player.global_position) < enemy.weapon.melee_range, "standing heads are visible and within melee distance on opposite sides of the low wall")
	check(not ai.context.melee.can_request(visible), "seeing a head above a low wall does not authorize a torso-blocked melee strike")
	var hits: int = enemy.melee_count
	var health: float = player.health.health
	for frame in 18:
		await _tick()
	check(enemy.melee_count == hits and player.health.health == health, "the original melee controller does not strike or damage through the wall")

func _hidden_target_and_timeout() -> void:
	await _prepare()
	var reached: bool = await _reach_crouch()
	check(reached, "hidden-target boundary starts from an autonomously selected completed low-wall crouch")
	if not reached: return
	var action = ai.actions[&"melee_cover"]
	var known: Vector3 = ai.context.last_known_position
	# The blocker is beyond the last seen position. The old standing observation
	# ray stays legal, but the actual hidden player cannot be reacquired through it.
	var screen := _box(Vector3(6.0, 2.5, 0.3), Vector3(0.0, 1.25, -5.0))
	scene.add_child(screen)
	player.global_position = Vector3(-0.5, 0.0, -6.0)
	await physics_frame
	check(not ai.perception.can_see_player(), "hidden-target fixture has actual physics occlusion")
	ai.context.update_evidence(0.0, false)
	var position: Vector3 = enemy.global_position
	var nav_target: Vector3 = enemy.agent.target_position
	var timer: float = action.transfer.timer
	var before: Array = action.collect_candidates(false)
	player.global_position = Vector3(0.5, 0.0, -6.5)
	player.combat.cancel_reload()
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	await physics_frame
	check(not ai.perception.can_see_player(), "second hidden position and reload also remain truly unobserved")
	ai.context.update_evidence(0.0, false)
	var after: Array = action.collect_candidates(false)
	check(not before.is_empty() and before == after and ai.context.last_known_position == known, "valid low-wall candidates and known target stay unchanged by hidden movement/reload")
	check(enemy.global_position == position and enemy.agent.target_position == nav_target and action.transfer.timer == timer, "evaluating a low-wall continuation does not move, retarget navigation or reset its timer")
	var health: float = player.health.health
	var returned_to_search := false
	var knowledge_preserved := true
	for frame in 360:
		await _tick()
		knowledge_preserved = knowledge_preserved and ai.context.last_known_position == known
		if ai.utility_current.get("id") == &"search":
			returned_to_search = true
			break
	check(returned_to_search and knowledge_preserved and player.health.health == health and enemy.melee_count == 0, "finite standing observation returns to search without tracing or striking a hidden player")
	screen.queue_free()
	await physics_frame

func _blocked_stand_and_revocation() -> void:
	await _prepare()
	var reached: bool = await _reach_crouch()
	check(reached, "dynamic standing-space boundary starts from real selected crouch")
	if reached:
		var action = ai.actions[&"melee_cover"]
		var ceiling := _box(Vector3(1.4, 0.2, 1.4), enemy.global_position + Vector3.UP * 1.3)
		scene.add_child(ceiling)
		await physics_frame
		var invalidated := false
		for frame in 180:
			await _tick()
			if ai.current_action != action:
				invalidated = true
				break
		check(invalidated and enemy.melee_count == 0, "blocked stand transition has a finite exit and cannot issue a crouching melee strike")
		ceiling.queue_free()
		await physics_frame
	await _prepare()
	reached = await _reach_crouch()
	check(reached, "permission withdrawal occurs during an actual low-wall advance")
	if not reached: return
	var old_action = ai.actions[&"melee_cover"]
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"melee_cover") and not old_action.is_enabled() and not old_action.transfer.is_active() and old_action.route_motion.route.is_empty(), "withdrawing training clears the old low-wall action, transfer and route ownership")
	for frame in 24: await _tick()
	check(ai.current_action != old_action and not enemy.is_crouching(), "revoked low-wall posture intent does not remain latched or resurrect")

func _reach_crouch() -> bool:
	for frame in 240:
		await _tick()
		if ai.utility_current.get("id") == &"melee_cover" and enemy.is_crouching(): return true
	return false

func _prepare() -> void:
	seed(20261008)
	ai._cancel_utility_execution()
	enemy.reset_target()
	enemy.global_position = START
	player.global_position = TARGET
	player.velocity = Vector3.ZERO
	player.health.health = player.health.max_health
	player.health.debug_invincible = false
	player.combat.cancel_reload()
	player.request_crouch(false)
	enemy.look_at(player.global_position)
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	ai.refresh_configuration(true)
	for frame in 12:
		await physics_frame
		if ai.context.environment_ready() and ai.context.is_arena_active(): break
	enemy.receive_hit(5.0, player.global_position)
	player.combat.ammo.magazine_rounds = 0
	player.combat.ammo.infinite_reserve = true
	player.combat.request_reload()
	# Observation advances the real weapon reload, but never primes spatial jobs.
	for frame in 12:
		await physics_frame
		player.combat.begin_frame(STEP, false)
		player.combat.end_frame(STEP, false)
		ai.context.update_evidence(STEP, ai.perception.can_see_player())
	ai.context.spatial.reset_evaluation()

func _tick() -> void:
	await physics_frame
	player.combat.begin_frame(STEP, false)
	player.combat.end_frame(STEP, false)
	enemy._physics_process(STEP)
	ai._physics_process(STEP)
	budget_ok = budget_ok and ai.context.spatial.last_evaluated_count <= 24
	peak_query_usec = maxi(peak_query_usec, ai.context.spatial.last_evaluation_usec)
	peak_execution_usec = maxi(peak_execution_usec, int(ai.frame_costs.get("execution", 0)))

func _build_fixture() -> void:
	scene = Node3D.new()
	scene.name = "LowWallMeleeFixture"
	# Reuse the actual player subtree only. No saved arena layout, navigation,
	# scene override or user weapon/training settings enter this fixture.
	var donor = load("res://scenes/main.tscn").instantiate()
	player = donor.get_node("Player")
	donor.remove_child(player)
	donor.free()
	player.position = TARGET
	scene.add_child(player)
	var arena := Node3D.new()
	arena.name = "Arena"
	arena.set_script(preload("res://scripts/world/shooting_range.gd"))
	scene.add_child(arena)
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = _navigation_mesh()
	arena.add_child(region)
	var environment := Node3D.new()
	environment.name = "Environment"
	region.add_child(environment)
	environment.add_child(_box(Vector3(18.0, 0.5, 18.0), Vector3(0.0, -0.25, 0.0)))
	wall = load("res://scenes/world/low_cover.tscn").instantiate()
	wall.name = "LowCover"
	wall.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, 0.0))
	wall.low_cover = true
	# Exercise the walking/sheltering contract on a legitimately non-vaultable
	# low wall. A faster legal vault may otherwise interrupt this advance; the
	# separate enemy_vault_utility_test covers that ordinary competing route.
	wall.vault_enabled = false
	wall.wall_gap = 0.55
	wall.hide_depth = 0.4
	var shape := BoxShape3D.new()
	shape.size = Vector3(4.0, 1.1, 0.6)
	wall.get_node("CollisionShape3D").shape = shape
	wall.get_node("CollisionShape3D").transform = Transform3D.IDENTITY
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	wall.get_node("Mesh").mesh = mesh
	wall.get_node("Mesh").transform = Transform3D.IDENTITY
	environment.add_child(wall)
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	zone.add_to_group("combat_zone")
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(17.0, 3.0, 17.0)
	zone_shape.shape = box
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	arena.add_child(zone)
	enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.position = START
	# The hand-authored floor is exactly y=0. The prefab's 0.5 offset is for
	# baked navigation above the floor and would strand this agent at path[0].
	enemy.get_node("NavigationAgent3D").path_height_offset = 0.0
	enemy.get_node("UnitType").profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	var training := Training.new()
	training.action_overrides.append(MeleeSettings.new())
	training.selected_tactics.assign([&"melee_cover"])
	training.set_setting(&"search", &"tracking_cheat_enabled", false)
	training.set_setting(&"perception", &"hearing_enabled", false)
	training.set_setting(&"perception", &"close_cover_intelligence_enabled", false)
	enemy.get_node("Training").profile = training
	var weapon := WeaponData.new()
	weapon.fire_mode = WeaponData.FireMode.MELEE
	weapon.melee_enabled = true
	enemy.weapon = weapon
	arena.add_child(enemy)
	root.add_child(scene)
	current_scene = scene
	ai = enemy.get_node("AI")
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	var gun := WeaponData.new()
	gun.reload_seconds = 4.0
	player.combat.equip_weapon(gun)

func _navigation_mesh() -> NavigationMesh:
	# Eight connected convex floor tiles around a real wall-sized hole. The gap
	# includes capsule clearance; no NavMesh polygon passes through the low wall.
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	var xs := [-8.0, -2.5, 2.5, 8.0]
	var zs := [-8.0, -0.8, 0.8, 8.0]
	var vertices := PackedVector3Array()
	for z in zs:
		for x in xs: vertices.append(Vector3(x, 0.0, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if x == 1 and z == 1: continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	return mesh

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body
