extends "res://tests/enemy/squad_contact_recovery_test.gd"

## Saved Lvl5 wave two. Exercise nearby melee contact after a small visible
## player move, with real capsule checks for the entire player trajectory.
var observed_frame := 0

func _run() -> void:
	seed(1)
	scene = load("res://scenes/world/levels/lvl_5.tscn").instantiate()
	scene.get_node("LevelFlow").free()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	if not await _wave(1): return
	for actor in scene.enemies.duplicate(): actor.receive_hit(100000.0)
	if not await _wave(2): return
	var squad = scene.get_node("EnemyWaves/Wave2/Squad")
	var actors: Array = squad.get_children().filter(func(node): return node.has_node("AI"))
	check(actors.size() == 6, "Saved Lvl5 wave supplies all six squad members")
	if actors.size() != 6:
		_finish()
		return
	var positions := [Vector3(11.383, 0, -2.834), Vector3(11.252, 0, -8.641), Vector3(10.223, 0, -4.934), Vector3(12.436, 0, -7.602), Vector3(12.2, 0, -11.847), Vector3(10.1, 0, -8.5)]
	player.global_position = Vector3(9.5, 0, -11.5)
	for index in actors.size(): actors[index].global_position = positions[index]
	var melee: Array = actors.filter(func(actor): return not actor.can_use_firearms())
	check(melee.size() == 2, "Both saved melee members retain their own equipment and training")
	var hits := {}
	var first_after_move := {}
	var idle := {}
	var longest_idle := {}
	var anchors := {}
	for actor in melee:
		var id: int = actor.get_instance_id()
		hits[id] = 0
		idle[id] = 0.0
		longest_idle[id] = 0.0
		anchors[id] = actor.global_position
		actor.melee_struck.connect(func(target, _settings, _direction):
			if target == player:
				hits[id] += 1
				if observed_frame >= 90 and not first_after_move.has(id): first_after_move[id] = observed_frame)
	var clear_approach := true
	var Geometry = load("res://scripts/systems/character_geometry.gd")
	var player_shape = player.get_node("CollisionShape3D").shape
	check(Geometry.can_sweep(player, player.global_position, player.global_position + Vector3(-0.6, 0, 0), player_shape.height, player_shape.radius, true), "The player's entire small movement stays outside static walls")
	for actor in melee:
		var destination: Vector3 = player.global_position + (actor.global_position - player.global_position).normalized() * 2.2
		clear_approach = clear_approach and Geometry.can_sweep(actor, actor.global_position, destination, actor.get_body_height(), actor.get_node("CollisionShape3D").shape.radius, true)
	check(clear_approach, "Both initial contact approaches have no static body obstruction")
	var owned := true
	var labels := true
	var visible := {}
	var clearance := INF
	var clear_contact := true
	var costs: Array[int] = []
	for frame in 1440:
		observed_frame = frame
		await physics_frame
		if frame >= 60 and frame < 90: player.global_position.x -= 0.02
		var total: int = scene.cooperation.last_advance_usec
		for actor in actors:
			var ai = actor.get_node("AI")
			owned = owned and ai.utility_decision_count == 0 and (frame < 30 or not ai.context.coordination_assignment().is_empty())
			for cost in ai.frame_costs.values(): total += int(cost)
		for actor in melee:
			var id: int = actor.get_instance_id()
			var ctx = actor.get_node("AI").context
			clear_contact = clear_contact and ctx.cover_selection.has_clear_line(actor.get_torso_position(), player.get_torso_position())
			if ctx.sees_player: visible[id] = true
			labels = labels and not actor._status_text.contains("调整射界")
			# Count visible physical inactivity outside strike reach regardless
			# of whether the task happens to say guard, engage or blocked.
			if not ctx.sees_player or actor.melee_active or not actor.can_move() or actor.global_position.distance_to(player.global_position) <= actor.weapon.melee_range or actor.global_position.distance_to(anchors[id]) > 0.1:
				idle[id] = 0.0
				anchors[id] = actor.global_position
			else:
				idle[id] += 1.0 / 60.0
				longest_idle[id] = maxf(longest_idle[id], idle[id])
		for index in actors.size():
			for other in actors.slice(index + 1):
				var offset: Vector3 = actors[index].global_position - other.global_position
				clearance = minf(clearance, Vector2(offset.x, offset.z).length())
		if frame > 60: costs.append(total)
		if frame == 120: _retained_post(melee[0].get_node("AI").context, player.global_position)
		if frame % 180 == 0:
			print("MELEE CONTACT TRACE ", frame, " ", melee.map(func(actor):
				var ctx = actor.get_node("AI").context
				var task: Dictionary = ctx.coordination_assignment()
				return {"name": actor.name, "position": actor.global_position, "role": task.get("role"), "hits": hits[actor.get_instance_id()], "recovery": ctx.coordination_debug_snapshot().get("contact_recovery", {})}))
	check(visible.size() == 2, "Both melee members obtain real personal sight")
	check(clear_contact, "Both melee members retain an unobstructed static contact line throughout the movement")
	check(first_after_move.size() == 2 and first_after_move.values().all(func(frame): return frame < 720), "Both melee members actually hit the moved player within twelve seconds")
	check(hits.values().all(func(count): return count >= 2), "Both melee members sustain real hits rather than only receiving attack labels")
	check(longest_idle.values().all(func(seconds): return seconds < 10.0), "No visible melee member remains motionless outside strike range for ten seconds")
	check(labels, "Melee status never claims to adjust its own firing lane")
	check(owned, "Melee recovery retains squad ownership and installed action execution")
	check(clearance >= 0.64, "Melee recovery preserves real body clearance")
	costs.sort()
	check(costs[int(costs.size() * 0.99)] < 16000 and costs[-1] < 50000, "Whole-frame P99 <16ms and peak <50ms remain unchanged")
	print("MELEE CONTACT METRICS ", {"hits": hits, "first_after_move": first_after_move, "longest_idle": longest_idle, "clearance": clearance, "p99": costs[int(costs.size() * 0.99)], "peak": costs[-1]})
	_finish()

func _retained_post(ctx, target: Vector3) -> void:
	# A detached proposal exercises the geometry boundary without injecting a
	# task, perception, acceptance or progress into the live squad.
	var Combat = load("res://scripts/enemy/services/squad_combat_tactics.gd")
	var point: Vector3 = target + Vector3(1.9, 0, 0.3)
	var path := PackedVector3Array([ctx.actor.global_position, point])
	var task := {"contact_post": true, "position": point, "look_position": target, "route": path}
	var next_target: Vector3 = target + Vector3(0.04, 0, 0)
	var profile: Dictionary = ctx.member_capability_snapshot()
	var valid: bool = Combat.melee_post_valid(ctx, profile, point, next_target, 0.08)
	var refreshed: bool = Combat.refresh_contact_post(ctx, profile, ctx.member_runtime_snapshot(), task, next_target)
	check(valid and refreshed and task.position == point and task.route == path and task.look_position == next_target, "A still-reachable melee post survives small target motion without a new route")
