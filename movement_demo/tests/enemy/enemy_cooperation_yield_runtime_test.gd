extends "res://tests/enemy/enemy_cooperation_flank_runtime_test.gd"

func _yield_case() -> void:
	var fixture: Dictionary = await _fixture(2, true)
	for actor in fixture.actors:
		var weapon: WeaponData = actor.weapon.duplicate(true)
		weapon.magazine_capacity = 60
		actor.equip_weapon(weapon)
	var original: Dictionary = {}
	var mover
	var origin := Vector3.INF
	var correction_seconds := 0.0
	var displaced := 0.0
	var canceled := false
	var fixed_deadline := true
	var completed := false
	for frame in 1080:
		await physics_frame
		for actor in fixture.actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var action = ai.actions[&"cooperate"]
			if original.is_empty() and task.get("accepted", false) and task.role == &"flank" and action.phase == action.Phase.MOVE:
				var partner = fixture.actors[1] if actor == fixture.actors[0] else fixture.actors[0]
				# Start the same finite, capsule/path-validated body correction that
				# a passing ally requests. The AI still owns its original assignment,
				# route, support, timeout and all subsequent actual motion.
				if actor.local_motion._start_side(partner, actor.global_position - partner.global_position, &"yield"):
					original = task.duplicate(true)
					mover = actor
					origin = actor.global_position
			elif actor == mover:
				var correcting: bool = actor.local_motion._point.is_finite() or actor.local_motion._hold_remaining > 0.0
				if correcting: correction_seconds += STEP
				displaced = maxf(displaced, actor.global_position.distance_to(origin))
				if task.get("plan_id", 0) != original.plan_id and not completed: canceled = true
				if task.get("plan_id", 0) == original.plan_id:
					fixed_deadline = fixed_deadline and task.expires_at == original.expires_at
					completed = completed or (task.get("complete", false) and ai.context._coordination_execution_completed and actor.global_position.distance_to(task.selected_position) <= 0.35)
		if completed or canceled: break
	check(not original.is_empty() and correction_seconds > 1.5 and displaced > 0.5, "A real released flank performs a finite side-step, yield and return longer than the ordinary stuck window")
	check(not canceled and fixed_deadline and completed, "The original flank survives local yielding and physically completes without replacing its plan or extending its deadline")
	print("YIELD_SAMPLE ", JSON.stringify({"seconds": correction_seconds, "displacement": displaced, "canceled": canceled, "completed": completed}))
	await _dispose(fixture)

func _run() -> void:
	await _yield_case()
	for kind: String in ["passing", "moving", "permanent", "wall"]: await _blocked_checkpoint(kind)
	await _damage_during_flank()
	print("COOPERATION YIELD: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _blocked_checkpoint(kind: String) -> void:
	var f: Dictionary = await _fixture(2, true)
	for actor in f.actors:
		var weapon: WeaponData = actor.weapon.duplicate(true)
		weapon.magazine_capacity = 60
		actor.equip_weapon(weapon)
	var original: Dictionary = {}
	var mover
	var provider
	var blocker
	if kind == "moving":
		# A different communication group shares physical space, not this plan.
		# Keep the real provider running while this third body crosses the point.
		blocker = load("res://scenes/enemy/enemy.tscn").instantiate()
		blocker.communication_group = &"checkpoint_fixture"
		blocker.position = Vector3(7, 0, 7)
		f.arena.add_child(blocker)
		blocker.get_node("AI").set_physics_process(false)
		blocker.set_physics_process(false)
	var provider_position := Vector3.INF
	var blocked_at := 0.0
	var dropped_at := -1.0
	var cleared := false
	var completed := false
	var actual_block := false
	var premature := false
	var fixed := true
	var block_point := Vector3.INF
	for frame in 1500:
		await physics_frame
		if kind == "moving" and not original.is_empty() and not cleared:
			var moving_seconds: float = mover.get_node("AI").context.coordination_now() - blocked_at
			blocker.global_position = block_point + Vector3(0.0, 0.0, minf(0.5, moving_seconds * 0.24))
		if not original.is_empty() and not cleared:
			actual_block = actual_block or not mover.get_node("AI").context.is_position_free(block_point)
		for actor in f.actors:
			if actor == provider and not cleared and kind in ["passing", "permanent"]: continue
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var action = ai.actions[&"cooperate"]
			if original.is_empty() and task.get("accepted", false) and task.role == &"flank" and action.phase == action.Phase.MOVE:
				original = task.duplicate(true)
				mover = actor
				provider = f.actors[1] if actor == f.actors[0] else f.actors[0]
				provider_position = provider.global_position
				blocked_at = ai.context.coordination_now()
				block_point = action._move_target()
				if kind == "wall":
					var wall := StaticBody3D.new()
					var shape := CollisionShape3D.new()
					var box := BoxShape3D.new()
					box.size = Vector3(0.8, 2.0, 0.8)
					shape.shape = box
					wall.add_child(shape)
					f.scene.add_child(wall)
					wall.global_position = action._move_target() + Vector3.UP
				elif kind == "moving":
					blocker.global_position = block_point
				else:
					provider.global_position = action._move_target()
					provider.velocity = Vector3.ZERO
			elif actor == mover:
				var now: float = ai.context.coordination_now()
				if not cleared:
					premature = premature or task.get("complete", false)
				if task.get("assignment_id", 0) != original.assignment_id and dropped_at < 0.0: dropped_at = now
				if task.get("assignment_id", 0) == original.assignment_id:
					fixed = fixed and task.expires_at == original.expires_at
					completed = completed or (task.get("complete", false) and ai.context._coordination_execution_completed and actor.global_position.distance_to(task.selected_position) <= 0.35)
				if kind in ["passing", "moving"] and not cleared and now - blocked_at >= (2.1 if kind == "moving" else 0.6):
					premature = premature or dropped_at >= 0.0
					if kind == "moving": blocker.global_position = f.arena.to_global(Vector3(7, 0, 7))
					else:
						provider.global_position = provider_position
						provider.velocity = Vector3.ZERO
					cleared = true
		if completed or dropped_at >= 0.0: break
	check(not original.is_empty() and actual_block, "%s: an actual capsule or wall occupies a released flank checkpoint" % kind)
	check(fixed and not premature, "%s: obstruction cannot renew the deadline or invent completion" % kind)
	if kind in ["passing", "moving"]:
		check(cleared and dropped_at < 0.0 and completed, "%s: the ally clears and the same accepted flank reaches its actual destination" % kind)
	else:
		check(dropped_at >= 0.0 and dropped_at - blocked_at <= (0.5 if kind == "wall" else 2.0), "%s: an impassable checkpoint exits within the original bounded recovery" % kind)
	print("CHECKPOINT_SAMPLE ", JSON.stringify({"kind": kind, "blocked_at": blocked_at, "dropped_at": dropped_at, "completed": completed, "actual_block": actual_block, "premature": premature}))
	await _dispose(f)

func _damage_during_flank() -> void:
	var f: Dictionary = await _fixture(2, true)
	for actor in f.actors:
		var weapon: WeaponData = actor.weapon.duplicate(true)
		weapon.magazine_capacity = 60
		actor.equip_weapon(weapon)
	var original: Dictionary = {}
	var mover
	var received := 0
	var immediate_valid := true
	var canceled := false
	var completed := false
	var fixed := true
	var hit_frame := -12
	for frame in 1500:
		await physics_frame
		if mover != null and received < 8 and frame - hit_frame >= 12:
			var ai = mover.get_node("AI")
			mover.receive_hit(1.0, f.player.global_position)
			received += 1
			hit_frame = frame
			immediate_valid = immediate_valid and ai.current_action == ai.actions[&"cooperate"] and ai.current_action._running
		for actor in f.actors:
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			var task: Dictionary = ai.context.coordination_assignment()
			var action = ai.actions[&"cooperate"]
			if original.is_empty() and task.get("accepted", false) and task.role == &"flank" and action.phase == action.Phase.MOVE:
				original = task.duplicate(true)
				mover = actor
				_check_assigned_escape(ai)
			elif actor == mover:
				canceled = canceled or task.get("assignment_id", 0) != original.assignment_id
				if not canceled:
					fixed = fixed and task.expires_at == original.expires_at
					completed = task.get("complete", false) and ai.context._coordination_execution_completed and actor.global_position.distance_to(task.selected_position) <= 0.35
		if completed or canceled: break
	check(not original.is_empty() and received > 0, "Actual incoming damage reaches the first accepted, released flank")
	check(immediate_valid, "A damage notification preserves a valid assignment until Utility compares real self-preservation choices")
	check(received == 8 and fixed and not canceled and completed, "Eight real hits at automatic-fire cadence cannot repeatedly cancel a legal open-field flank or renew its deadline")
	await _dispose(f)

func _check_assigned_escape(ai) -> void:
	var action = ai.actions[&"cooperate"]
	check(not action.can_interrupt({"urgent": true}, true), "An urgent label cannot interrupt the actual accepted short leg")
	var reload_action = ai.actions[&"reload"]
	var rounds: int = ai.actor.ammo.magazine_rounds
	ai.actor.ammo.magazine_rounds = 0
	var choices: Array[Dictionary] = reload_action.collect_candidates(true)
	var verified := false
	var permitted := false
	for choice in choices:
		choice.assignment_escape_verified = reload_action.assignment_escape(choice, true)
		if choice.assignment_escape_verified:
			verified = true
			permitted = permitted or action.can_interrupt(choice, true)
	ai.actor.ammo.magazine_rounds = rounds
	check(verified and permitted, "A real empty-magazine reload verified by its owner can interrupt that same short leg")
