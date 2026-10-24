extends "res://tests/enemy/enemy_vault_link_runtime_test.gd"

const Motion = preload("res://scripts/enemy/actions/enemy_route_motion.gd")
var _two_walls := false

func _run() -> void:
	_vault_connection_only = true
	_build_fixture()
	var arena = scene.get_node("Arena")
	arena.set_physics_process(true)
	wall.vault_enabled = true
	player.health.debug_invincible = true
	var peer = load("res://scenes/enemy/enemy.tscn").instantiate()
	peer.position = Vector3(4, 0, 4)
	peer.get_node("UnitType").profile = enemy.get_node("UnitType").profile.duplicate(true)
	peer.get_node("Training").profile = enemy.get_node("Training").profile.duplicate(true)
	peer.weapon = enemy.weapon.duplicate(true)
	arena.add_child(peer)
	peer.set_physics_process(false)
	peer.get_node("AI").set_physics_process(false)
	var other = peer.get_node("AI").context
	for frame in 100:
		await physics_frame
		ai.context.refresh_environment()
		other.refresh_environment()
		if arena.vault_navigation.ready and not arena.vault_navigation.connections().is_empty(): break
	await physics_frame
	await physics_frame
	# Graph construction and the server's asynchronous map iteration are
	# separate. Synchronize the native map before testing validation slices.
	NavigationServer3D.map_force_update(ai.agent.get_navigation_map())
	ai.context.routes.native_queries.clear()
	ai.context.routes.native_last_units = 0
	var description := NativeRoute.query(ai.context, TARGET)
	check(description.is_empty() and NativeRoute.pending(ai.context, TARGET) and ai.context.routes.native_last_units <= 4, "Native geometry is pending after at most four validation units")
	var units: int = ai.context.routes.native_last_units
	NativeRoute.query(ai.context, TARGET)
	check(ai.context.routes.native_last_units == units, "Repeated same-frame query cannot spend another validation slice")
	ai.context.routes.native_queries[TARGET].created -= 2000
	await physics_frame
	description = NativeRoute.query(ai.context, TARGET)
	check(not description.is_empty(), "Pending validation older than a cache TTL resumes instead of restarting")
	for frame in 20:
		await physics_frame
		description = NativeRoute.query(ai.context, TARGET)
		if not description.is_empty(): break
	check(not description.is_empty() and NativeRoute.current(ai.context, description), "Incremental validation finishes a current owned route")
	if description.is_empty(): await _finish_contract(); return
	var vault: Dictionary = description.segments[1]
	var endpoint: Vector3 = enemy.global_position
	var nav_target: Vector3 = ai.agent.target_position
	NativeRoute.query(ai.context, TARGET)
	check(enemy.global_position == endpoint and ai.agent.target_position == nav_target and _pure(description), "Geometry query cannot move or retarget a body and returns pure values")
	var original_unit = ai.context.unit
	ai.context.unit = original_unit.duplicate(true)
	ai.context.unit.capabilities.erase(&"locomotion")
	check(NativeRoute.query(ai.context, TARGET).is_empty(), "Removing locomotion capability rejects even a cached route")
	ai.context.unit = original_unit
	ai.context.routes.native_queries.clear()
	ai.context.routes.native_deadline_usec = Time.get_ticks_usec() - 1
	check(NativeRoute.query(ai.context, TARGET).is_empty() and NativeRoute.pending(ai.context, TARGET), "Exhausted preparation deadline retains pending work")
	ai.context.routes.native_deadline_usec = 0
	# Actual preflight failure is finite and actor-local; the static graph remains.
	enemy.global_position = vault.entry
	player.global_position = vault.exit
	await physics_frame
	var motion = Motion.new()
	motion.begin(description)
	# Isolate the selected vault boundary after the completed approach leg.
	motion.segment_index = 1
	var output: Dictionary = motion.apply(ai.context, {"running": true}, STEP)
	check(output.has("vault") and not enemy.begin_vault(output.vault), "Selected typed request still obeys the body's occupied-landing check")
	await physics_frame
	output = motion.apply(ai.context, {"running": true}, STEP)
	check(motion.failed and not output.running and not output.has("vault") and ai.context.routes.failed_links().has(vault.link_key), "Rejected start exits once and remembers a finite failed channel")
	check(not arena.vault_navigation.resolve_link(vault.owner_id).is_empty(), "One actor's failed start never disables a shared native link")
	enemy.global_position = START
	player.global_position = TARGET
	var alternate := {}
	for frame in 24:
		await physics_frame
		alternate = NativeRoute.query(ai.context, TARGET, Vector3.INF, ai.context.routes.failed_links())
		if not alternate.is_empty(): break
	check(not alternate.is_empty() and alternate.segments[1].link_key != vault.link_key, "Failed channel can prepare a bounded neighboring crossing")
	# Airborne cancellation/death cannot release physical transit ownership.
	enemy.global_position = vault.entry
	await physics_frame
	check(arena.cooperation.acquire_vault_transit(ai.context, vault) and enemy.begin_vault(NativeRoute.execution_vault(ai.context, vault)), "Lifecycle control starts a real physical vault with transit ownership")
	for frame in 8:
		await physics_frame
		enemy._physics_process(STEP)
	motion.reset()
	arena.cooperation.release_vault_transit(ai.context)
	check(enemy.is_vaulting() and not arena.cooperation.acquire_vault_transit(other, vault), "Withdrawing route intent retains airborne physical occupancy")
	enemy.receive_hit(enemy.max_health + 1)
	arena.cooperation.release_member(enemy.get_instance_id())
	check(enemy.is_vaulting() and not arena.cooperation.acquire_vault_transit(other, vault), "Death and team release keep the airborne body's corridor occupied")
	for frame in 180:
		await physics_frame
		enemy._physics_process(STEP)
		if not enemy.is_vaulting(): break
	check(not enemy.is_vaulting() and arena.cooperation.acquire_vault_transit(other, vault) and motion.route.is_empty(), "Safe landing releases physical occupancy without resurrecting cancelled route intent")
	arena.cooperation.release_vault_transit(other)
	# Invalid geometry is rejected immediately, before the bounded rebuild.
	wall.vault_enabled = false
	check(not NativeRoute.current(ai.context, description), "Changed cover rejects stale route before background rebuilding")
	await _multiple_links_case()
	await _finish_contract()

func _multiple_links_case() -> void:
	scene.queue_free()
	await process_frame
	_two_walls = true
	_build_fixture()
	wall.vault_enabled = true
	var region: NavigationRegion3D = ai.context.navigation_region
	var second = load("res://scenes/world/low_cover.tscn").instantiate()
	second.position = Vector3(0, 0.55, -3)
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 1.1, 0.6)
	second.get_node("CollisionShape3D").shape = shape
	second.get_node("CollisionShape3D").transform = Transform3D.IDENTITY
	region.get_node("Environment").add_child(second)
	scene.get_node("Arena").set_physics_process(true)
	var destination := Vector3(0, 0, -6)
	player.global_position = destination
	player.health.debug_invincible = true
	for frame in 100:
		await physics_frame
		if ai.context.vault_navigation.ready and ai.context.vault_navigation.connections().size() >= 4: break
	await physics_frame
	await physics_frame
	var description := {}
	for frame in 32:
		await physics_frame
		description = NativeRoute.query(ai.context, destination)
		if not description.is_empty(): break
	check(not description.is_empty() and description.segments.filter(func(segment): return segment.kind == &"vault").size() == 2, "One native route represents two sequential walls across three islands")
	if description.is_empty(): return
	# This executor control ends at a free standing post, independently of melee
	# stopping distance around the real player tested by the runtime suite.
	player.global_position = Vector3(5, 0, -6)
	var motion = Motion.new()
	motion.begin(description)
	var jumps := 0
	var previously_airborne := false
	for frame in 500:
		await physics_frame
		enemy._physics_process(STEP)
		var output: Dictionary = motion.apply(ai.context, {"running": true, "multiplier": 1.0}, STEP)
		if output.has("vault"): enemy.begin_vault(output.vault)
		if enemy.is_vaulting() and not previously_airborne: jumps += 1
		previously_airborne = enemy.is_vaulting()
		enemy.move_character(output.get("direction", Vector3.ZERO), STEP, output.get("multiplier", 1.0), output.get("stop_position", Vector3.INF))
		if motion.failed or motion.completed: break
	check(motion.completed and jumps == 2 and enemy.global_position.distance_to(destination) < 0.2, "Shared executor physically completes walk/vault/walk/vault/walk")
	print("MULTI EXEC completed=", motion.completed, " failed=", motion.failed, " jumps=", jumps, " position=", enemy.global_position)
	enemy.global_position = destination
	var reverse := {}
	for frame in 32:
		await physics_frame
		reverse = NativeRoute.query(ai.context, START)
		if not reverse.is_empty(): break
	check(not reverse.is_empty() and reverse.segments.filter(func(segment): return segment.kind == &"vault").all(func(segment): return segment.direction.z > 0), "Bidirectional metadata reverses both vault directions correctly")
	region.rotation.y = PI * 0.5
	enemy.global_position = region.to_global(START)
	var rotated_destination := region.to_global(destination)
	player.global_position = rotated_destination
	for frame in 100:
		await physics_frame
		if ai.context.vault_navigation.ready and not NativeRoute.current(ai.context, description): break
	await physics_frame
	await physics_frame
	var rotated := {}
	for frame in 64:
		await physics_frame
		rotated = NativeRoute.query(ai.context, rotated_destination)
		if not rotated.is_empty(): break
	check(not rotated.is_empty() and rotated.segments.filter(func(segment): return segment.kind == &"vault").size() == 2, "Rotated owning region rebuilds the same legal multi-link route")

func _navigation_mesh() -> NavigationMesh:
	if not _two_walls: return super._navigation_mesh()
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	var vertices := PackedVector3Array()
	for z in [-8.0, -4.0, -2.0, -1.0, 1.0, 8.0]:
		for x in [-8.0, -2.5, 2.5, 8.0]: vertices.append(Vector3(x, 0, z))
	mesh.vertices = vertices
	for z in [0, 2, 4]:
		for x in 3:
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	return mesh

func _finish_contract() -> void:
	print("NATIVE VAULT CONTRACT: ", checks - failures, "/", checks)
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)
