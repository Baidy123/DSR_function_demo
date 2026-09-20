extends RefCounted

# 在真实竞技场找一个可用短边端面，实走到射界通畅的 Peek。
func run_short_walk(scene: Node) -> Dictionary:
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var cover = enemy.get_node("AI/Tactics/CoverAction")
	var arena = scene.get_node("Arena")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = arena.to_global(Vector3(7, 0, 2))
	for frame in range(5):
		await scene.get_tree().physics_frame
	var chosen := false
	for region in scene.get_tree().get_nodes_in_group("cover_region"):
		if chosen:
			break
		var collision = region.get_node("CollisionShape3D")
		var size: Vector3 = collision.shape.size
		var axis := Vector3.RIGHT if size.x >= size.z else Vector3.BACK
		for side in [-1.0, 1.0]:
			if chosen:
				break
			cover.reset()
			cover.look_position = collision.to_global(axis * side * (maxf(size.x, size.z) * 0.5 + 2.5)) - Vector3.UP * size.y * 0.5
			cover.threat_origin = cover.look_position + Vector3.UP * 0.8
			for candidate in region.get_candidates(cover.threat_origin, enemy.global_position):
				if not ai.is_position_free(candidate.hide) or cover.selection._path_to(candidate.hide, candidate.hide).is_empty():
					continue
				if not cover.selection._center_hidden_by_cover(candidate.hide, cover.threat_origin, region):
					continue
				var peek: Vector3 = cover.selection._choose_peek(candidate.hide, candidate.peeks, cover.look_position)
				if not peek.is_finite():
					continue
				enemy.global_position = candidate.hide
				enemy.velocity = Vector3.ZERO
				cover.hide_position = candidate.hide
				cover.peek_position = peek
				cover.active_cover_body = region
				chosen = true
				break
	var checks := {"short_face_pair_available": chosen}
	if chosen:
		checks["short_face_blocks_view"] = not cover._peek_has_los(enemy.global_position)
		for frame in range(4):
			await scene.get_tree().physics_frame
		cover._start_move(cover.Phase.PEEK_OUT, cover.peek_position)
		var watched := false
		for frame in range(1200):
			await scene.get_tree().physics_frame
			var direction: Vector3 = cover.step(1.0 / 60.0, false)
			enemy.move_character(direction, 1.0 / 60.0, cover.movement_multiplier())
			if cover.phase == cover.Phase.WATCH:
				watched = true
				break
			if not cover.is_active():
				break
		checks["short_face_reaches_watch"] = watched
		checks["short_face_actual_view_clear"] = watched and cover._peek_has_los(enemy.global_position)
		checks["short_face_actual_peek_reached"] = watched and ai._horizontal_distance(cover.peek_position) <= 0.12
	scene.set_meta("short_face_walk_checks", checks)
	return checks

# 在 Main 中调用；先检查实际掩体四个方向，再检查真实导航边界和临时堵墙。
func run(scene: Node) -> Dictionary:
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var cover = enemy.get_node("AI/Tactics/CoverAction")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.global_position = arena.to_global(Vector3(7, 0, 2))
	for frame in range(5):
		await scene.get_tree().physics_frame
	var checks := {}
	var directions := [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]
	for region in scene.get_tree().get_nodes_in_group("cover_region"):
		var collision = region.get_node("CollisionShape3D")
		var size: Vector3 = collision.shape.size
		for index in range(4):
			var direction: Vector3 = directions[index]
			var threat: Vector3 = collision.to_global(direction * 10.0)
			var candidates = region.get_candidates(threat, enemy.global_position)
			var valid: bool = not candidates.is_empty()
			for candidate in candidates:
				var local: Vector3 = collision.to_local(candidate.hide)
				valid = valid and local.dot(direction) < 0.0
				valid = valid and region.is_hiding_position(candidate.hide, threat)
				for peek in candidate.peeks:
					var local_peek: Vector3 = collision.to_local(peek)
					var tangent := Vector3(-direction.z, 0, direction.x)
					var extent: float = size.x * 0.5 if absf(tangent.x) > 0.5 else size.z * 0.5
					valid = valid and absf(local_peek.dot(tangent)) > extent
			checks[str(region.name) + "_face_" + str(index)] = valid
		# 玩家处于斜角时允许两面参与，再交给遮挡检查筛选。
		var diagonal: Vector3 = collision.to_global(Vector3(10, 0, 10))
		var found_x := false
		var found_z := false
		for candidate in region.get_candidates(diagonal, enemy.global_position):
			var local: Vector3 = collision.to_local(candidate.hide)
			found_x = found_x or local.x < -size.x * 0.5
			found_z = found_z or local.z < -size.z * 0.5
		checks[str(region.name) + "_diagonal_two_faces"] = found_x and found_z
	var inside: Vector3 = arena.to_global(Vector3(12, 0, 8))
	var outside: Vector3 = arena.to_global(Vector3(13.2, 0, 8))
	checks["inside_navigation_reachable"] = not cover.selection._path_to(inside, inside).is_empty()
	checks["outside_navigation_rejected"] = cover.selection._path_to(inside, outside).is_empty()
	checks["wrong_floor_rejected"] = cover.selection._path_to(inside, inside + Vector3.UP * 3).is_empty()
	cover.look_position = arena.to_global(Vector3(11, 0, 8))
	checks["outside_peek_rejected"] = not cover.selection._choose_peek(inside, [outside], cover.look_position).is_finite()
	# 临时墙只加入运行中的场景，不改竞技场布局。
	var blocker := StaticBody3D.new()
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1, 2, 1)
	shape_node.shape = shape
	blocker.add_child(shape_node)
	arena.add_child(blocker)
	blocker.global_position = inside + Vector3.UP
	for frame in range(3):
		await scene.get_tree().physics_frame
	checks["wall_blocks_standing"] = not ai.is_position_free(inside)
	checks["wall_blocks_peek"] = not cover.selection._choose_peek(inside + Vector3.LEFT * 2, [inside], cover.look_position).is_finite()
	blocker.queue_free()
	return checks
