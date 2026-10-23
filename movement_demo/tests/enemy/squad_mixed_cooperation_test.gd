extends "res://tests/enemy/squad_command_runtime_test.gd"

## Real saved-map bodies. Only instance equipment and physical inputs change.
const Geometry = preload("res://scripts/systems/character_geometry.gd")
var melee_members: Array = []
var shooters: Array = []
var hits := {}
var costs: Array[int] = []
var clearance := INF
var ownership := true

func _run() -> void:
	if OS.get_cmdline_user_args().has("--saved-runtime"):
		# Run the unchanged original scenario at its saved starts. Configure
		# equipment before children enter the tree and freeze their profiles.
		root.child_entered_tree.connect(_saved_equipment)
		await super._run()
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="): level = int(arg.trim_prefix("--level="))
	seed(20261024)
	if await _setup_mixed():
		if OS.get_cmdline_user_args().has("--ranged"):
			await _crossfire()
			if OS.get_cmdline_user_args().has("--legacy-search"): await _search_case()
		else:
			if OS.get_cmdline_user_args().has("--search"):
				await _search_support()
			else:
				await _contact_cooperation()
				await _small_retreat()
		check(ownership, "Members keep installed roles and squad authority")
		check(clearance >= 0.64, "Bodies preserve physical collision clearance")
		costs.sort()
		check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Full-frame P99 <16ms / maximum <50ms")
		print("MIXED METRICS clearance=", clearance, " p99_usec=", costs[int(costs.size() * 0.99)], " peak_usec=", costs[-1])
	scene.queue_free()
	await physics_frame
	print("SQUAD MIXED COOPERATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _saved_equipment(node: Node) -> void:
	if not node.has_node("Arena/Squad"): return
	for actor in node.get_node("Arena").find_children("*", "CharacterBody3D", true, false):
		if not actor.has_node("AI"): continue
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres")
		actor.weapon = load("res://resources/weapons/enemy_test_pistol.tres").duplicate(true)
		actor.weapon.fire_mode = 0

func _setup_mixed() -> bool:
	scene = load("res://scenes/main.tscn").instantiate()
	var squad = scene.get_node("Arena/Squad")
	squad.profile = squad.profile.duplicate(true)
	squad.profile.level = level
	actors = scene.get_node("Arena").find_children("*", "CharacterBody3D", true, false).filter(func(actor): return actor.has_node("AI"))
	melee_members.clear()
	shooters.clear()
	hits.clear()
	for index in actors.size():
		var actor = actors[index]
		var close := index > 0 and not OS.get_cmdline_user_args().has("--ranged")
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/%s.tres" % ("melee" if close else "ranged"))
		actor.weapon = load("res://resources/weapons/enemy_test_%s.tres" % ("melee" if close else "pistol")).duplicate(true)
		actor.weapon.fire_mode = 2 if close else 0
		var training = load("res://resources/enemy/training/arena.tres").duplicate(true)
		training.selected_tactics.clear()
		training.selected_tactics.append(&"cooperate" if close else &"suppression")
		training.search.tracking_cheat_enabled = false
		actor.get_node("Training").profile = training
		if close: melee_members.append(actor)
		else: shooters.append(actor)
		hits[actor.get_instance_id()] = 0
		actor.melee_struck.connect(func(target, _settings, _direction):
			if target == player: hits[actor.get_instance_id()] += 1)
	root.add_child(scene)
	current_scene = scene
	arena = scene.get_node("Arena")
	player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get("combat").set_physics_process(false)
	player.get("health").debug_invincible = true
	if OS.get_cmdline_user_args().has("--capture"):
		root.get_node("DebugSettings").enabled = true
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 27.0
		arena.add_child(camera)
		camera.global_position = arena.to_global(Vector3(2, 25, 12))
		camera.look_at(arena.to_global(Vector3(2, 0, 2)))
		camera.make_current()
	player.global_position = arena.to_global(Vector3(1, 0, 0))
	var starts := [Vector3(-2, 0, -3), Vector3(1, 0, -3), Vector3(4, 0, -3)]
	if OS.get_cmdline_user_args().has("--ranged"):
		player.global_position = arena.to_global(Vector3(1, 0, 2))
		starts = [Vector3(-0.3, 0, -3), Vector3(1, 0, -3), Vector3(2.3, 0, -3)]
	for index in actors.size():
		actors[index].global_position = arena.to_global(starts[index])
		actors[index].look_at(player.global_position)
	for frame in 30: await physics_frame
	var valid := actors.all(func(actor):
		var ctx = actor.get_node("AI").context
		var projected := NavigationServer3D.region_get_closest_point(ctx.navigation_region.get_rid(), actor.global_position)
		return actor.is_on_floor() and absf(actor.global_position.y - player.global_position.y) < 0.1 and Vector2(projected.x - actor.global_position.x, projected.z - actor.global_position.z).length() < 0.4 and ctx.member_capability_snapshot().get("ready", false) and ctx.sees_player and ctx.coordination_assignment().get("accepted", false))
	check(valid, "Fixture: grounded, navigable, assembled members obtain real sight and accepted tasks")
	valid = valid and shooters.all(func(actor): return actor.can_use_firearms() and actor.get_node("AI").context.member_capability_snapshot().firearms) and melee_members.all(func(actor): return not actor.can_use_firearms() and actor.get_node("AI").context.command_melee_enabled())
	check(valid, "Fixture: runtime weapons and frozen capabilities match intended attack methods")
	print("MIXED FIXTURE ", JSON.stringify(actors.map(_trace)))
	return valid

func _sample() -> void:
	var total: int = arena.cooperation.last_advance_usec
	for index in actors.size():
		var actor = actors[index]
		if actor.is_dead: continue
		var ai = actor.get_node("AI")
		var task: Dictionary = ai.context.coordination_assignment()
		ownership = ownership and not task.is_empty() and ai.utility_decision_count == 0 and ai.actions.has(task.get("action", &""))
		if not actor.can_use_firearms(): ownership = ownership and not task.get("role") in [&"support", &"reload"]
		for cost in ai.frame_costs.values(): total += int(cost)
		for other in actors.slice(index + 1):
			if not other.is_dead: clearance = minf(clearance, actor.global_position.distance_to(other.global_position))
	costs.append(total)

func _contact_cooperation() -> void:
	var concurrent := 0
	var rear_shots := 0
	var previous: int = shooters[0].shot_count
	for frame in 600:
		await physics_frame
		_sample()
		var approaching: bool = melee_members.any(func(actor): return actor.velocity.length() > 0.2 and actor.global_position.distance_to(player.global_position) > actor.weapon.melee_range)
		if shooters[0].shot_count > previous and approaching:
			concurrent += shooters[0].shot_count - previous
			if melee_members.any(func(actor): return actor.velocity.length() > 0.2 and shooters[0].global_position.distance_to(player.global_position) > actor.global_position.distance_to(player.global_position) + 0.5): rear_shots += 1
		previous = shooters[0].shot_count
		if frame % 120 == 0: print("MIXED CONTACT ", frame, " ", JSON.stringify(actors.map(_trace)), " hits=", hits)
	check(melee_members.all(func(actor): return hits[actor.get_instance_id()] > 0), "Each melee member actually reaches and hits the player")
	check(concurrent > 0, "Ranged fire occurs during a teammate's real melee approach")
	check(rear_shots > 0, "Concurrent support shots originate behind the advancing melee front")
	print("MIXED FIRE concurrent=", concurrent, " hits=", hits)

func _small_retreat() -> void:
	var actor = melee_members[0]
	var start_hits: int = hits[actor.get_instance_id()]
	var valid: bool = start_hits > 0 and actor.is_on_floor() and actor.global_position.distance_to(player.global_position) <= actor.weapon.melee_range
	check(valid, "Retreat precondition: same melee member has hit and holds a valid attack position")
	if not valid: return
	var away: Vector3 = player.global_position - actor.global_position
	away.y = 0.0
	var destination: Vector3 = player.global_position + away.normalized() * 0.7
	valid = Geometry.can_occupy(player, destination, player.get_body_height(), 0.35, true)
	check(valid, "Sub-metre retreat destination has real body clearance")
	if not valid: return
	player.global_position = destination
	var recovered := -1
	var initial_distance: float = actor.global_position.distance_to(player.global_position)
	for frame in 240:
		await physics_frame
		_sample()
		if hits[actor.get_instance_id()] > start_hits and recovered < 0: recovered = frame
	check(initial_distance > actor.weapon.melee_range, "A real 0.7m retreat invalidates the former attack range")
	check(recovered >= 0 and recovered <= 180, "The same melee member adjusts and hits again within three seconds")
	print("MIXED RETREAT distance=", initial_distance, " recovered=", recovered, " ", JSON.stringify(actors.map(_trace)))

func _crossfire() -> void:
	var shots := {}
	var directions := {}
	var widest := 0.0
	var moving_fire := 0
	for actor in shooters: shots[actor.get_instance_id()] = actor.shot_count
	for frame in 600:
		await physics_frame
		_sample()
		for actor in shooters:
			var id: int = actor.get_instance_id()
			if actor.shot_count <= shots[id]: continue
			shots[id] = actor.shot_count
			var direction: Vector3 = (actor.global_position - player.global_position).normalized()
			for other in directions:
				if other != id: widest = maxf(widest, direction.angle_to(directions[other]))
			directions[id] = direction
			if shooters.any(func(peer): return peer != actor and peer.velocity.length() > 0.2): moving_fire += 1
		if frame % 180 == 0: print("CROSSFIRE ", frame, " ", JSON.stringify(actors.map(_trace)))
	check(directions.size() == shooters.size(), "Every ranged member actually fires with personal sight")
	check(widest >= deg_to_rad(45.0), "Available lateral posts produce actual shots at least 45 degrees apart")
	check(moving_fire > 0, "A shooter retains fire while another member manoeuvres")
	print("CROSSFIRE METRICS angle=", rad_to_deg(widest), " moving_fire=", moving_fire)

func _search_support() -> void:
	# Establish the last sight near the saved left wall, then a second real
	# screen permits sustained inspection without inventing observation facts.
	for point in [Vector3(-4.84, 0, -1.9), Vector3(-4.84, 0, 0.68)]:
		while player.global_position.distance_to(arena.to_global(point)) > 0.01:
			player.global_position = player.global_position.move_toward(arena.to_global(point), 0.12)
			await physics_frame
	var screen := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.3, 3.0, 8.0)
	collision.shape = shape
	screen.add_child(collision)
	arena.add_child(screen)
	screen.global_position = arena.to_global(Vector3(-7, 1.5, 1.5))
	player.global_position = arena.to_global(Vector3(-7.6, 0, 1.5))
	for frame in 12: await physics_frame
	var hidden: bool = actors.all(func(actor): return not actor.get_node("AI").context.sees_player)
	check(hidden, "Search fixture loses personal sight behind real saved-wall and screen geometry")
	if not hidden: return
	var shooter = shooters[0]
	var previous: int = shooter.shot_count
	var paired := 0
	var watching := 0
	var waited := 0
	var inspected := 0
	var blind_shots := 0
	var reload_requested := false
	var pressured := OS.get_cmdline_user_args().has("--pressure")
	var invalidated := false
	var independent_steps := 0
	var hidden_stable := true
	var frozen: Vector3 = arena.get_node("Squad").coordinator._objective.position
	var honest_ready := true
	var max_wait := 0
	var wait_frames := {}
	var captured := false
	var squad = arena.get_node("Squad").coordinator
	for frame in 900:
		if frame == 60: player.global_position += Vector3(0, 0, 0.4)
		await physics_frame
		_sample()
		if actors.all(func(actor): return not actor.get_node("AI").context.sees_player): hidden_stable = hidden_stable and squad._objective.position == frozen
		var ctx = shooter.get_node("AI").context
		if not ctx.sees_player and shooter.shot_count > previous: blind_shots += shooter.shot_count - previous
		previous = shooter.shot_count
		for actor in melee_members:
			var peer = actor.get_node("AI").context
			var task: Dictionary = peer.coordination_assignment()
			var link: Dictionary = squad._support.snapshot(actor.get_instance_id())
			if task.get("role") == &"search" and task.get("progress", 0.0) > 0.0: inspected += 1
			if task.get("support_mode") == &"independent" and actor.velocity.length() > 0.2: independent_steps += 1
			if not link.is_empty():
				paired += 1
				if not link.get("ready", []).is_empty():
					watching += 1
					honest_ready = honest_ready and not shooter.ammo.is_reloading and shooter.ammo.magazine_rounds > 0 and preload("res://scripts/enemy/services/enemy_visual_observation.gd").visible(ctx, link.region)
			if task.get("reason") == &"support_preparing":
				waited += 1
				wait_frames[actor.get_instance_id()] = int(wait_frames.get(actor.get_instance_id(), 0)) + 1
				max_wait = maxi(max_wait, wait_frames[actor.get_instance_id()])
			else: wait_frames[actor.get_instance_id()] = 0
			if task.get("reason") == &"support_unavailable" or not squad._support.independent_until.is_empty(): invalidated = true
		if not reload_requested and watching > 10 and shooter.ammo.magazine_rounds < shooter.weapon.magazine_capacity:
			if pressured:
				shooter.receive_hit(35.0)
				reload_requested = shooter.health < shooter.max_health
			else: reload_requested = shooter.request_reload()
		if not captured and watching > 5 and OS.get_cmdline_user_args().has("--capture"):
			captured = true
			_capture_support.call_deferred()
		if frame % 180 == 0 or frame < 180 and frame % 30 == 0: print("MIXED SEARCH ", frame, " ", JSON.stringify(actors.map(_trace)), " support=", squad._support.links.values().map(func(link): return {"phase": link.phase, "ready": link.ready, "deadline": link.deadline}))
	check(paired > 0 and watching > 0 and inspected > 0, "Melee inspections receive an associated ranged member who actually arrives and observes their area")
	check(honest_ready and blind_shots == 0, "Readiness uses actual observation/ammunition and hidden support never fires")
	check(waited > 0 and max_wait <= 150, "Entry support waits are real and bounded, with a new executable plan")
	check(reload_requested and invalidated, "A real supporter injury invalidates support and triggers finite recovery" if pressured else "A real supporter reload invalidates support and triggers finite recovery")
	check(hidden_stable, "Hidden player displacement never updates the frozen legal attack clue")
	check(independent_steps > 0, "Unavailable support produces actual short independent inspection movement")
	print("MIXED SEARCH METRICS paired=", paired, " watching=", watching, " inspected=", inspected, " waits=", waited, " max_wait=", max_wait, " independent=", independent_steps)
	shooter.receive_hit(shooter.health + 1.0)
	var before_hits := hits.duplicate()
	player.global_position = arena.to_global(Vector3(-1, 0, -3))
	var stale := false
	for frame in 600:
		await physics_frame
		_sample()
		if frame > 120:
			for actor in melee_members:
				var task: Dictionary = actor.get_node("AI").context.coordination_assignment()
				stale = stale or task.get("waiting_for", []).has(shooter.get_instance_id())
	check(not stale and melee_members.all(func(actor): return hits[actor.get_instance_id()] > before_hits[actor.get_instance_id()]), "Supporter death clears dependencies and surviving melee members actually hit after reacquisition")

func _capture_support() -> void:
	await RenderingServer.frame_post_draw
	var destination := "res://logs/ranged_melee_support_20261024.png"
	var result := root.get_texture().get_image().save_png(destination)
	check(result == OK, "Independent graphical instance captures actual support and inspection")
