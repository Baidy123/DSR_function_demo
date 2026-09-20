extends RefCounted

func run_cycle(scene: Node) -> Dictionary:
	var arena = scene.get_node("Arena")
	var enemy = arena.get_node("Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var cover = enemy.get_node("Cover")
	var checks := {}
	var tree = scene.get_tree()
	ai.set_physics_process(false)
	player.set_physics_process(false)
	enemy.global_position = arena.to_global(Vector3(-4.75126, 0, 3.100522))
	player.global_position = arena.to_global(Vector3(7, 0, 2))
	cover.threat_origin = player.global_position + Vector3.UP * 0.8
	cover.look_position = player.global_position
	cover.debug_cover_selection = false
	cover.hide_seconds = 0.2
	for frame in range(4):
		await tree.physics_frame
	checks["cycle_selects_pair"] = cover._choose_cover()
	if not checks["cycle_selects_pair"]:
		scene.set_meta("cover_cycle_checks", checks)
		return checks
	cover._start_move(cover.Phase.RUN_TO_COVER, cover.hide_position)
	var hidden := false
	var peeking := false
	var watched := false
	for frame in range(1500):
		await tree.physics_frame
		var direction: Vector3 = cover.step(1.0 / 60.0, false)
		enemy.move_character(direction, 1.0 / 60.0, cover.movement_multiplier())
		hidden = hidden or (cover.phase == cover.Phase.HIDE and cover._selected_cover_blocks(enemy.global_position, cover.threat_origin))
		peeking = peeking or cover.phase == cover.Phase.PEEK_OUT
		if cover.phase == cover.Phase.WATCH:
			watched = cover._peek_has_los(enemy.global_position)
			break
		if not cover.is_active():
			break
	checks["cycle_hides_in_safe_region"] = hidden
	checks["cycle_starts_peek"] = peeking
	checks["cycle_reaches_clear_watch"] = watched
	scene.set_meta("cover_cycle_checks", checks)
	return checks


# 通过实际物理移动检查两侧的 Hide -> Peek，不仅核对候选点的数学位置。
func run_walk(scene: Node) -> Dictionary:
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var arena = scene.get_node("Arena")
	var cover = enemy.get_node("Cover")
	var player = scene.get_node("Player")
	var wall = arena.get_node("NavigationRegion3D/Environment/CoverA")
	var collision = wall.get_node("CollisionShape3D")
	var tree = scene.get_tree()
	var checks := {}
	ai.set_physics_process(false)
	player.set_physics_process(false)
	cover.debug_cover_selection = false
	for side in [-1.0, 1.0]:
		cover.reset()
		player.global_position = collision.to_global(Vector3(side * 3.0, -1.1, 0))
		cover.threat_origin = player.global_position + Vector3.UP * 0.8
		cover.look_position = player.global_position
		var chosen := false
		for candidate in wall.get_candidates(cover.threat_origin, enemy.global_position):
			if not ai._ranged_point_is_free(candidate.hide):
				continue
			if not cover._center_hidden_by_cover(candidate.hide, cover.threat_origin, wall):
				continue
			var peek: Vector3 = cover._choose_peek(candidate.hide, candidate.peeks)
			if not peek.is_finite():
				continue
			enemy.global_position = candidate.hide
			cover.hide_position = candidate.hide
			cover.peek_position = peek
			cover.active_cover_body = wall
			chosen = true
			break
		var suffix := "_" + str(side)
		checks["peek_pair_available" + suffix] = chosen
		if not chosen:
			continue
		enemy.velocity = Vector3.ZERO
		for frame in range(4):
			await tree.physics_frame
		checks["hide_blocks_view" + suffix] = not cover._peek_has_los(enemy.global_position)
		cover._start_move(cover.Phase.PEEK_OUT, cover.peek_position)
		var watched := false
		for frame in range(900):
			await tree.physics_frame
			var direction: Vector3 = cover.step(1.0 / 60.0, false)
			enemy.move_character(direction, 1.0 / 60.0, cover.movement_multiplier())
			if cover.phase == cover.Phase.WATCH:
				watched = true
				break
			if not cover.is_active():
				break
		checks["walk_reaches_watch" + suffix] = watched
		checks["actual_standing_view_is_clear" + suffix] = watched and cover._peek_has_los(enemy.global_position)
		checks["actual_standing_reaches_peek" + suffix] = watched and ai._horizontal_distance(cover.peek_position) <= 0.12
	cover.reset()
	scene.set_meta("cover_region_walk_checks", checks)
	return checks


func run(scene: Node) -> Dictionary:
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var arena = scene.get_node("Arena")
	var cover = enemy.get_node("Cover")
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	ai.set_physics_process(false)
	player.global_position = arena.to_global(Vector3(7, 0, 2))
	for frame in range(5):
		await scene.get_tree().physics_frame
	enemy.global_position = arena.to_global(Vector3(-4.75126, 0, 3.100522))
	cover.debug_cover_selection = false
	cover.threat_origin = player.global_position + Vector3.UP * 0.8
	cover.look_position = player.global_position
	var checks := {}
	checks["selects_cover"] = cover._choose_cover()
	if checks["selects_cover"]:
		enemy.global_position = cover.hide_position
		cover.peek_position = cover.hide_position
		cover.phase = cover.Phase.PEEK_OUT
		cover.timer = 3.0
		enemy.agent.target_position = cover.peek_position
		for frame in range(3):
			await scene.get_tree().physics_frame
		cover.step(0.0, false)
		checks["blocked_peek_never_enters_watch"] = cover.phase != cover.Phase.WATCH
	cover.reset()
	var regions = scene.get_tree().get_nodes_in_group("cover_region")
	checks["six_covers_own_regions"] = regions.size() == 6
	checks["independent_markers_removed"] = not arena.has_node("CoverPositions")
	if regions.is_empty():
		return checks
	for region in regions:
		var collision = region.get_node("CollisionShape3D")
		var shape_size: Vector3 = collision.shape.size
		var along_x: bool = shape_size.x >= shape_size.z
		var threat_local := Vector3(0, 0, 4) if along_x else Vector3(4, 0, 0)
		var positive: Vector3 = collision.to_global(threat_local)
		var negative: Vector3 = collision.to_global(-threat_local)
		var first = region.get_candidates(positive, enemy.global_position)
		var second = region.get_candidates(negative, enemy.global_position)
		var both_sides: bool = not first.is_empty() and not second.is_empty()
		var inside: bool = true
		var opposite: bool = true
		var peeks_outside: bool = true
		for pair in [[first, positive], [second, negative]]:
			for candidate in pair[0]:
				inside = inside and region.is_hiding_position(candidate.hide, pair[1])
				var local_hide: Vector3 = collision.to_local(candidate.hide)
				var local_threat: Vector3 = collision.to_local(pair[1])
				opposite = opposite and (local_hide.z * local_threat.z < 0.0 if along_x else local_hide.x * local_threat.x < 0.0)
				for peek in candidate.peeks:
					var local_peek: Vector3 = collision.to_local(peek)
					peeks_outside = peeks_outside and (absf(local_peek.x) > shape_size.x * 0.5 if along_x else absf(local_peek.z) > shape_size.z * 0.5)
		checks[str(region.name) + "_both_sides"] = both_sides
		checks[str(region.name) + "_samples_inside_region"] = inside
		checks[str(region.name) + "_opposite_threat"] = opposite
		checks[str(region.name) + "_peeks_beyond_corners"] = peeks_outside

	# 复制、移动、旋转和缩放后仍由掩体自身生成位置，不依赖原场景中的点位。
	var original = regions[0]
	var copy = original.duplicate()
	arena.add_child(copy)
	var old_frame: Transform3D = copy.global_transform
	var source_threat: Vector3 = copy.get_node("CollisionShape3D").to_global(Vector3(4, 0, 4))
	var source_from: Vector3 = copy.get_node("CollisionShape3D").to_global(Vector3(-4, 0, -4))
	var before = copy.get_candidates(source_threat, source_from)
	copy.rotate_y(0.7)
	copy.position += Vector3(40, 0, 30)
	copy.scale *= 1.2
	var change: Transform3D = copy.global_transform * old_frame.affine_inverse()
	var after = copy.get_candidates(change * source_threat, change * source_from)
	checks["copy_registers_regions"] = copy.is_in_group("cover_region")
	checks["transform_preserves_samples"] = before.size() == after.size()
	if not before.is_empty() and not after.is_empty():
		checks["hide_follows_transform"] = (change * before[0].hide).is_equal_approx(after[0].hide)
		checks["peek_follows_transform"] = (change * before[0].peeks[0]).is_equal_approx(after[0].peeks[0])
	copy.queue_free()
	return checks
