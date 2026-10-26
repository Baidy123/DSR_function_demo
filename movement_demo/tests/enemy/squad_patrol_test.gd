extends SceneTree

## Real autonomous patrol on an independent map; no injected tasks, sight,
## acceptance or completion. The narrow-map section tests only the data service.
const Patrol = preload("res://scripts/enemy/services/squad_patrol.gd")
const Settings = preload("res://scripts/enemy/config/cooperation_settings.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	seed(20261026)
	for level in [1, 2]: await _runtime(level)
	await _memory()
	_configuration()
	print("LOCAL SQUAD PATROL: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _box(parent: Node, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	parent.add_child(body)
	return body

func _navigation(size: Vector2) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-size.x, 0, -size.y), Vector3(size.x, 0, -size.y), Vector3(size.x, 0, size.y), Vector3(-size.x, 0, size.y)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	return region

func _runtime(level: int) -> void:
	var radius := 3.0 if level == 1 else 4.5
	var scene := Node3D.new()
	scene.set_script(preload("res://scripts/world/shooting_range.gd"))
	scene.add_child(_navigation(Vector2(24, 24)))
	_box(scene, Vector3(0, -0.1, 0), Vector3(50, 0.2, 50))
	# A real wall keeps the stationary player hidden. Perception remains active.
	_box(scene, Vector3(0, 2, 12), Vector3(48, 4, 0.8))
	var obstacle := _box(scene, Vector3(-12 + radius, 1, 0), Vector3(0.8, 2, 0.8))
	var zone := Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	zone_shape.shape = BoxShape3D.new()
	zone_shape.shape.size = Vector3(48, 6, 48)
	zone_shape.position.y = 2.0
	zone.add_child(zone_shape)
	scene.add_child(zone)
	var player = load("res://scenes/player/player.tscn").instantiate()
	player.position = Vector3(0, 0, 18)
	scene.add_child(player)
	var squad = load("res://scenes/world/squad.tscn").instantiate()
	squad.profile = Settings.new()
	squad.profile.level = level
	if squad.profile.get("patrol_radius") != null: squad.profile.patrol_radius = radius
	scene.add_child(squad)
	var actors: Array = []
	for x in [-12, 0, 12]:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		# Patrol geometry should not depend on saved weapon tuning or a melee
		# test weapon being assigned to the generic ranged prefab.
		actor.weapon = WeaponData.new()
		actor.position = Vector3(x, 0, 0)
		squad.add_child(actor)
		actors.append(actor)
	root.add_child(scene)
	current_scene = scene
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	var arrivals: Array = [[], [], []]
	var tokens: Array = [{}, {}, {}]
	var early := [0.0, 0.0, 0.0]
	var later := [0.0, 0.0, 0.0]
	var last: Array = actors.map(func(actor): return actor.global_position)
	var bounded := true
	var peaceful := true
	var commanded := true
	var ordered := true
	var reversal := false
	var stable := true
	var previous := [{}, {}, {}]
	var costs: Array[int] = []
	# At 4.5m and the original 2m/s speed, a full circuit plus stops needs
	# more than 20 seconds. Observe one complete circuit at both radii.
	for frame in 1560:
		# Reopen the blocked post midway, without altering navigation or AI facts.
		if frame == 600: obstacle.queue_free()
		await physics_frame
		var total: int = scene.cooperation.last_advance_usec
		for i in actors.size():
			var actor = actors[i]
			var ai = actor.get_node("AI")
			var ctx = ai.context
			var task: Dictionary = ctx.coordination_assignment()
			for cost in ai.frame_costs.values(): total += int(cost)
			var moved: float = actor.global_position.distance_to(last[i])
			if frame < 600: early[i] += moved
			else: later[i] += moved
			last[i] = actor.global_position
			if frame < 30: continue
			peaceful = peaceful and not ctx.sees_player and squad.coordinator._objective.get("phase") == &"patrol"
			commanded = commanded and not task.is_empty() and ai.utility_decision_count == 0
			bounded = bounded and _distance(actor.global_position, ctx._spawn_position) <= radius + 0.5
			if task.get("role") != &"patrol": continue
			for vertex in task.route: bounded = bounded and _distance(vertex, ctx._spawn_position) <= radius + 0.5
			bounded = bounded and absf(_distance(task.position, ctx._spawn_position) - radius) < 0.4
			if previous[i].get("state") == &"executing" and previous[i].get("role") == &"patrol" and previous[i].get("task_id") != task.task_id:
				stable = false
			previous[i] = task.duplicate(true)
			if task.get("state") != &"complete" or tokens[i].has(task.task_id): continue
			tokens[i][task.task_id] = true
			var index := int(str(task.site_key).get_slice(":", 2))
			var sequence: Array = arrivals[i]
			if i > 0 and not sequence.is_empty(): ordered = ordered and index == (int(sequence[-1].index) + 1) % 12
			if sequence.size() >= 2: reversal = reversal or index == sequence[-2].index
			sequence.append({"index": index, "time": frame / 60.0})
		costs.append(total)
	check(peaceful and commanded, "Level %d: real unseen player, continuous squad authority, zero personal Utility" % level)
	check(bounded, "Level %d: actual bodies and all patrol route vertices stay within each own spawn radius" % level)
	check(early.all(func(value): return value > 2.0) and later.all(func(value): return value > 2.0) and arrivals.all(func(items): return items.size() >= 4), "Level %d: every member keeps moving and physically completes multiple posts" % level)
	check(ordered and not reversal, "Level %d: open circuits advance in order without immediate A-B-A reversals" % level)
	check(not arrivals[0].is_empty() and arrivals[0][0].index != 0 and arrivals[0].any(func(item): return item.time > 10.0 and item.index == 0), "Level %d: a real obstacle is skipped and its reopened post becomes usable" % level)
	check(stable, "Level %d: teammate arrivals do not replace another member's executing leg" % level)
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Level %d: original whole-frame P99 <16ms and peak <50ms" % level)
	print("LOCAL PATROL RESULT level=", level, " arrivals=", arrivals.map(func(items): return items.map(func(item): return item.index)), " later=", later, " p99=", costs[int(costs.size() * 0.99)], " peak=", costs[-1])
	# Enter genuine sight from a patrol, then hide behind the same real wall.
	# The home memory must survive both transitions without retaining patrol orders.
	player.global_position = actors[1].global_position - actors[1].global_basis.z * 1.5
	for frame in 120: await physics_frame
	check(squad.coordinator._objective.get("phase") == &"contact" and actors.all(func(actor): return actor.get_node("AI").context.coordination_assignment().get("role") != &"patrol"), "Level %d: actual player sight interrupts local patrol through the original command flow" % level)
	var memory: Dictionary = squad.coordinator._patrol.snapshot(actors[1].get_instance_id())
	player.global_position = Vector3(0, 0, 18)
	for frame in 120: await physics_frame
	check(squad.coordinator._objective.get("phase") == &"search" and squad.coordinator._patrol.snapshot(actors[1].get_instance_id()) == memory, "Level %d: losing real sight enters search without resetting or advancing patrol memory" % level)
	# Membership changes must not reset the survivors' homes or progress.
	var removed_id: int = actors[2].get_instance_id()
	actors[2].receive_hit(actors[2].max_health + 1.0)
	for frame in 90: await physics_frame
	check(squad.coordinator._patrol.snapshot(removed_id).is_empty() and not squad.coordinator._patrol.snapshot(actors[0].get_instance_id()).is_empty(), "Level %d: member death releases only its patrol state" % level)
	scene.queue_free()
	await physics_frame

func _memory() -> void:
	var navigation := _navigation(Vector2(4, 0.2))
	root.add_child(navigation)
	var actor := Node3D.new()
	root.add_child(actor)
	for frame in 120:
		await physics_frame
		if NavigationServer3D.region_get_iteration_id(navigation.get_rid()) > 0: break
	var context := {"actor": actor, "navigation_region": navigation, "_spawn_position": Vector3.ZERO}
	var patrol = Patrol.new()
	var id := actor.get_instance_id()
	var sites: Array = patrol.sites(context, 3.0, 0.0)
	check(sites.size() == 2, "Narrow real navigation leaves only the two corridor ends")
	if sites.size() == 2:
		for index in 2:
			var task: Dictionary = sites[index].duplicate(true)
			task.merge({"generation": 1, "task_id": index, "version": 1})
			patrol.complete(id, task, float(index))
			var state: Dictionary = patrol.snapshot(id)
			patrol.complete(id, task, float(index) + 0.1)
			check(patrol.snapshot(id) == state, "Duplicate completion does not advance or refresh recent memory")
		check(patrol.sites(context, 3.0, 2.0).is_empty() and patrol.sites(context, 3.0, 10.0).size() == 2, "Two-point dead end waits before revisiting; history does not cause permanent standstill")
		actor.position.x = 1.0
		patrol.sites(context, 3.0, 11.0)
		check(patrol.snapshot(id).center == Vector3.ZERO, "Movement and replanning cannot move the frozen home")
	patrol.reset()
	check(patrol.snapshot(id).is_empty() and patrol.visits().is_empty(), "Scene reset clears patrol memory and diagnostics")
	check(not Patrol.route_within(PackedVector3Array([Vector3.ZERO, Vector3(9, 0, 0), Vector3(1, 0, 0)]), Vector3.ZERO, 3.0), "Nearby endpoint with a distant detour is rejected")
	actor.queue_free()
	navigation.queue_free()
	await physics_frame

func _configuration() -> void:
	var settings = Settings.new()
	check(settings.patrol_radius == 3.0 and settings.values().patrol_radius == 3.0, "Original profiles receive the default 3m radius through the existing settings interface")
	settings.patrol_radius = 4.5
	var path := "user://squad_patrol_settings_test.tres"
	var saved := ResourceSaver.save(settings, path)
	var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(saved == OK and restored.patrol_radius == 4.5 and settings.duplicate(true).patrol_radius == 4.5, "Radius survives profile duplication and save/reload")
	DirAccess.remove_absolute(path)

func _distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
