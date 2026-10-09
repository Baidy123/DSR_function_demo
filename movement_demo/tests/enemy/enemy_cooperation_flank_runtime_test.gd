extends SceneTree

const STEP := 1.0 / 60.0
const OPPOSITE_MARGIN := 0.5
const TARGET_CLEARANCE := 1.5
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	for count in [1, 2, 3, 6]:
		var off: Dictionary = await _measure(count, false)
		var on: Dictionary = await _measure(count, true)
		if count == 1:
			check(off.shots > 0 and on.shots > 0 and not off.used_cooperation and not on.used_cooperation and off.max_claims == 0 and on.max_claims == 0, "Solo ON/OFF both retain ordinary actual firing without waiting for a team")
		else:
			check(on.max_opposite > off.max_opposite and on.opposite_seconds > off.opposite_seconds, "%d enemies visibly occupy the opposite side more with cooperation ON than OFF" % count)
	await _blocked_routes()
	print("COOPERATION FLANK RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _navigation_mesh(half_width: float = 8.0) -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	mesh.vertices = PackedVector3Array([Vector3(-8, 0.5, -half_width), Vector3(8, 0.5, -half_width), Vector3(8, 0.5, half_width), Vector3(-8, 0.5, half_width)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	return mesh

func _fixture(count: int, enabled: bool, narrow: bool = false) -> Dictionary:
	seed(8423)
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var first = arena.get_node("Enemy")
	# Keep the declared population independent of unsaved/local arena duplicates.
	for child in arena.get_children():
		if child != first and child.has_node("AI"): child.free()
	first.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	first.weapon = WeaponData.new()
	first.position = Vector3(5, 0, -(count - 1) * 0.5 * 0.85)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	region.navigation_mesh = _navigation_mesh(1.0 if narrow else 8.0)
	# The test's declared navigation rectangle must have a real supporting floor.
	# The saved arena floor is offset and does not extend to the south arc.
	var floor: StaticBody3D = region.get_node("Environment/Floor")
	var floor_collision: CollisionShape3D = floor.get_node("CollisionShape3D")
	var floor_shape: BoxShape3D = floor_collision.shape.duplicate()
	var floor_center: Vector3 = floor.position + floor_collision.position
	floor_shape.size.x = maxf(floor_shape.size.x, 2.0 * (8.0 + absf(floor_center.x) + 1.0))
	floor_shape.size.z = maxf(floor_shape.size.z, 2.0 * ((1.0 if narrow else 8.0) + absf(floor_center.z) + 1.0))
	floor_collision.shape = floor_shape
	for body in region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	root.add_child(scene)
	current_scene = scene
	# Nodes with a physics callback are registered during tree entry. Freeze the
	# completed scene as the original probe does, not only its pre-tree instance.
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.velocity = Vector3.ZERO
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	player.global_position = Vector3(20, 0, 0)
	var actors: Array = [first]
	for index in range(1, count):
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.weapon = WeaponData.new()
		actor.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
		actor.position = Vector3(5, 0, (index - (count - 1) * 0.5) * 0.85)
		arena.add_child(actor)
		actors.append(actor)
	for index in count:
		var actor = actors[index]
		var ai = actor.get_node("AI")
		var weapon := WeaponData.new()
		weapon.magazine_capacity = 20
		weapon.reload_seconds = 3.5
		weapon.shot_interval = 0.2
		actor.equip_weapon(weapon)
		ai.training.profile.selected_tactics.assign([&"cover", &"covering_retreat", &"attack_position", &"suppression"])
		if enabled: ai.training.profile.selected_tactics.append(&"cooperate")
		ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 10)
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 1.5)
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		ai.cover_selection.debug_cover_selection = false
		ai.cover_selection.debug_attack_points = false
		actor.debug_shooting = false
		actor.global_position = Vector3(25, 0, (index - (count - 1) * 0.5) * 0.85)
		actor.look_at(player.global_position)
	for frame in 12: await physics_frame
	var ground_y: float = floor_collision.to_global(Vector3(0, floor_shape.size.y * 0.5, 0)).y
	var supported_navigation := true
	for vertex in region.navigation_mesh.vertices:
		var point: Vector3 = region.to_global(vertex)
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, ground_y + 1.0, point.z), Vector3(point.x, ground_y - 1.0, point.z), 1)
		var hit: Dictionary = floor.get_world_3d().direct_space_state.intersect_ray(query)
		supported_navigation = supported_navigation and hit.get("collider") == floor and absf(hit.get("position", Vector3.INF).y - ground_y) < 0.01
	check(supported_navigation, "Every declared navigation corner is supported by the real test floor collision")
	check(player.global_position.distance_to(Vector3(20, 0, 0)) < 0.001 and not player.is_physics_processing() and not player.get_node("Combat").is_physics_processing(), "A/B fixture starts with the player frozen at the declared target anchor")
	check(actors.all(func(actor): return actor.get_node("AI").context.is_arena_active()), "Every declared A/B member has a valid real spawn, navigation region and active target")
	return {"scene": scene, "arena": arena, "player": player, "actors": actors, "ground_y": ground_y}

func _flanking(ai) -> bool:
	return ai.utility_current.get("id", &"") == &"cooperate" and ai.utility_current.get("plan", &"") == &"opposite_flank"

func _measure(count: int, enabled: bool) -> Dictionary:
	var fixture: Dictionary = await _fixture(count, enabled)
	var actors: Array = fixture.actors
	var anchor: Vector3 = fixture.player.global_position
	var result := {"count": count, "enabled": enabled, "shots": 0, "used_cooperation": false, "used_flank": false,
		"max_opposite": 0, "max_claims": 0, "opposite_seconds": 0.0, "longest_opposite_seconds": 0.0,
		"front_shots_during_flank": 0, "opposite_shots": 0, "front_support_seconds": 0.0,
		"max_front_gap_seconds": 0.0, "minimum_front": count, "minimum_flank_radius": INF,
		"cycle_wait_frames": 0, "player_max_drift": 0.0, "actor_max_height_error": 0.0, "actions": {}}
	var previous_positions: Array[Vector3] = []
	var previous_shots: Array[int] = []
	var previous_flanking: Array[bool] = []
	for actor in actors:
		previous_positions.append(actor.global_position)
		previous_shots.append(actor.shot_count)
		previous_flanking.append(false)
	var opposite_run := 0.0
	var front_gap := 0.0
	var player_frozen := true
	var equipped := true
	for actor in actors:
		equipped = equipped and actor.get_node("AI").context.cooperation_enabled() == enabled and actor.can_use_firearms()
	check(equipped, "%d enemies ON=%s use the requested switch and real firearm loadout" % [count, enabled])
	# The only driver is the normal AI loop; no candidate injection or action start.
	for frame in (600 if count == 1 else 1500):
		await physics_frame
		player_frozen = player_frozen and not fixture.player.is_physics_processing() and not fixture.player.get_node("Combat").is_physics_processing()
		result.player_max_drift = maxf(result.player_max_drift, fixture.player.global_position.distance_to(anchor))
		for actor in actors:
			result.actor_max_height_error = maxf(result.actor_max_height_error, absf(actor.global_position.y - fixture.ground_y))
			actor.get_node("AI")._physics_process(STEP)
			result.actor_max_height_error = maxf(result.actor_max_height_error, absf(actor.global_position.y - fixture.ground_y))
		result.player_max_drift = maxf(result.player_max_drift, fixture.player.global_position.distance_to(anchor))
		var snapshot: Dictionary = actors[0].get_node("AI").context.cooperation_snapshot()
		var claims: Array = snapshot.claims.filter(func(claim): return claim.get("kind", &"") == &"flank")
		result.max_claims = maxi(result.max_claims, claims.size())
		var opposite := 0
		var front := 0
		var flank_active: bool = not claims.is_empty()
		for actor in actors:
			if actor.global_position.x < anchor.x - OPPOSITE_MARGIN: opposite += 1
			if actor.global_position.x > anchor.x + OPPOSITE_MARGIN: front += 1
			flank_active = flank_active or _flanking(actor.get_node("AI"))
		result.max_opposite = maxi(result.max_opposite, opposite)
		if opposite > 0:
			result.opposite_seconds += STEP
			opposite_run += STEP
			result.longest_opposite_seconds = maxf(result.longest_opposite_seconds, opposite_run)
		else: opposite_run = 0.0
		if flank_active or opposite > 0:
			result.minimum_front = mini(result.minimum_front, front)
			var supported: bool = snapshot.supports.any(func(support): return not support.get("moving", false) and support.position.x > anchor.x + OPPOSITE_MARGIN and support.get("lane_id", &"") == &"target" and support.get("support_seconds", 0.0) > 0.0)
			if supported:
				result.front_support_seconds += STEP
				front_gap = 0.0
			else:
				front_gap += STEP
				result.max_front_gap_seconds = maxf(result.max_front_gap_seconds, front_gap)
		else: front_gap = 0.0
		for index in count:
			var actor = actors[index]
			var ai = actor.get_node("AI")
			var action_id: StringName = ai.utility_current.get("id", &"idle")
			result.actions[action_id] = true
			result.used_cooperation = result.used_cooperation or action_id == &"cooperate"
			var flanking := _flanking(ai)
			result.used_flank = result.used_flank or flanking
			if flanking or previous_flanking[index]:
				var start: Vector3 = previous_positions[index]
				var end: Vector3 = actor.global_position
				start.y = anchor.y
				end.y = anchor.y
				var nearest: Vector3 = Geometry3D.get_closest_point_to_segment(anchor, start, end)
				result.minimum_flank_radius = minf(result.minimum_flank_radius, anchor.distance_to(nearest))
			if flanking and ai.current_action.phase == ai.current_action.Phase.WAIT_SUPPORT and snapshot.members.any(func(member): return member.id != actor.get_instance_id() and member.get("support_cycle_valid", false)):
				result.cycle_wait_frames += 1
			var shots: int = actor.shot_count - previous_shots[index]
			result.shots += shots
			if shots > 0 and actor.global_position.x < anchor.x - OPPOSITE_MARGIN: result.opposite_shots += shots
			if shots > 0 and (flank_active or opposite > 0) and actor.global_position.x > anchor.x + OPPOSITE_MARGIN: result.front_shots_during_flank += shots
			previous_positions[index] = actor.global_position
			previous_shots[index] = actor.shot_count
			previous_flanking[index] = flanking
	check(player_frozen and result.player_max_drift < 0.001, "%d enemies ON=%s keep the actual target feet fixed throughout every simulated frame" % [count, enabled])
	check(result.actor_max_height_error < 0.1, "%d enemies ON=%s keep every actor physically on the arena floor throughout the run" % [count, enabled])
	check(result.shots > 0, "%d enemies ON=%s actually fire under normal perception and Utility" % [count, enabled])
	if enabled and count > 1:
		var quota: int = floori(count * 0.5)
		check(result.used_flank and result.max_opposite > 0 and result.longest_opposite_seconds >= 1.0, "%d enemies autonomously complete an opposite-side flank and remain there" % count)
		check(result.max_opposite <= quota and result.max_claims <= quota and result.minimum_front >= count - quota, "%d enemies keep at most floor(N/2) opposite and preserve the front" % count)
		check(result.front_shots_during_flank >= 3 and result.opposite_shots > 0 and result.front_support_seconds >= 0.3, "%d enemies provide real front fire while the opposite side also attacks" % count)
		check(result.minimum_flank_radius >= TARGET_CLEARANCE - 0.05, "%d enemies go around the target instead of cutting through its clearance circle" % count)
	if not enabled: check(not result.used_cooperation and result.max_claims == 0, "%d enemies OFF do not acquire advanced cooperation roles" % count)
	if not is_finite(result.minimum_flank_radius): result.minimum_flank_radius = -1.0
	print("COOP_FLANK_AB ", JSON.stringify(result))
	await _dispose(fixture)
	return result

func _blocked_routes() -> void:
	# Both routes around a 1.5m target circle are outside this actual nav strip.
	var fixture: Dictionary = await _fixture(3, true, true)
	var started := false
	var claimed := false
	var opposite := false
	var shots := 0
	var anchor: Vector3 = fixture.player.global_position
	var player_frozen := true
	var actor_max_height_error := 0.0
	for frame in 480:
		await physics_frame
		player_frozen = player_frozen and fixture.player.global_position.distance_to(anchor) < 0.001 and not fixture.player.is_physics_processing() and not fixture.player.get_node("Combat").is_physics_processing()
		for actor in fixture.actors:
			var ai = actor.get_node("AI")
			actor_max_height_error = maxf(actor_max_height_error, absf(actor.global_position.y - fixture.ground_y))
			ai._physics_process(STEP)
			actor_max_height_error = maxf(actor_max_height_error, absf(actor.global_position.y - fixture.ground_y))
			started = started or _flanking(ai)
			opposite = opposite or actor.global_position.x < fixture.player.global_position.x - OPPOSITE_MARGIN
		var snapshot: Dictionary = fixture.actors[0].get_node("AI").context.cooperation_snapshot()
		claimed = claimed or snapshot.claims.any(func(claim): return claim.get("kind", &"") == &"flank")
	for actor in fixture.actors: shots += actor.shot_count
	check(player_frozen and fixture.player.global_position.distance_to(anchor) < 0.001, "The blocked-route fixture also keeps the real target fixed")
	check(actor_max_height_error < 0.1, "The blocked-route fixture keeps every actor physically on the real floor")
	check(not started and not claimed and not opposite and shots > 0, "With both safe side routes unreachable, normal Utility retains actual front fire without a false flank or indefinite role")
	await _dispose(fixture)

func _dispose(fixture: Dictionary) -> void:
	fixture.scene.queue_free()
	await process_frame
	await physics_frame
