extends SceneTree

## Runtime groups use the original AI loop, scoring and saved weapon cadence.
## Explicit transaction/interrupt fault injection is labelled as a contract;
## it is not evidence that Utility autonomously selects that particular action.
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

class BeginProbe:
	extends "res://scripts/enemy/actions/enemy_action.gd"
	var reject_begin := false
	var invalidate_commit := false
	var begins := 0
	func begin(candidate: Dictionary, visible: bool) -> bool:
		begins += 1
		if reject_begin: return false
		super.begin(candidate, visible)
		if invalidate_commit:
			context.coordination_configuration_changed()
			context._publish_coordination_versions()
		return true

class EmptySelector:
	extends RefCounted
	func assess_options(_ai, _visible: bool) -> Array[Dictionary]: return []
	func choose_option(_options: Array[Dictionary], _current: Dictionary) -> Dictionary: return {}
	func same_option(_first: Dictionary, _second: Dictionary) -> bool: return false

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	await _basic_runtime()
	for enabled in [false, true]: await _solo_runtime(enabled)
	await _transaction_contract()
	await _melee_interrupt_contract()
	print("TEAM BASIC RUNTIME: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _fixture(count: int, advanced: bool) -> Dictionary:
	var scene = preload("res://tests/enemy/enemy_fire_fixture.gd").legacy_scene()
	var arena = scene.get_node("Arena")
	for child in arena.get_children():
		if child.has_node("AI"): child.free()
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	mesh.vertices = PackedVector3Array([Vector3(-8, 0.5, -8), Vector3(8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	var floor_body: StaticBody3D = region.get_node("Environment/Floor")
	var collision: CollisionShape3D = floor_body.get_node("CollisionShape3D")
	var shape: BoxShape3D = collision.shape.duplicate()
	var center: Vector3 = floor_body.position + collision.position
	shape.size.x = maxf(shape.size.x, 2.0 * (9.0 + absf(center.x)))
	shape.size.z = maxf(shape.size.z, 2.0 * (9.0 + absf(center.z)))
	collision.shape = shape
	for body in region.get_node("Environment").get_children():
		if body is StaticBody3D and body != floor_body:
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	var actors: Array = []
	for index in count:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
		actor.get_node("Training").profile = actor.get_node("Training").profile.duplicate(true)
		actor.position = Vector3(4, 0, (index - (count - 1) * 0.5) * 1.5)
		arena.add_child(actor)
		actors.append(actor)
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(1.5, 0, 0))
	for actor in actors:
		var ai = actor.get_node("AI")
		ai.training.profile.selected_tactics.clear()
		if advanced: ai.training.profile.selected_tactics.append(&"cooperate")
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		ai.cover_selection.debug_cover_selection = false
		ai.cover_selection.debug_attack_points = false
		actor.debug_shooting = false
		actor.look_at(player.global_position)
	for frame in 8: await physics_frame
	check(actors.all(func(actor): return actor.get_node("AI").context.is_arena_active() and not actor.get_node("AI").is_physics_processing()), "Fixture uses active real actors with only explicit normal AI ticks")
	return {"scene": scene, "arena": arena, "player": player, "actors": actors, "board": arena.cooperation}

func _dispose(fixture: Dictionary) -> void:
	fixture.scene.queue_free()
	await fixture.scene.tree_exited
	await process_frame

func _separated(entries: Array) -> bool:
	for first in entries.size():
		for second in range(first + 1, entries.size()):
			var a: Dictionary = entries[first]
			var b: Dictionary = entries[second]
			if a.actor_id == b.actor_id: continue
			var delta: Vector3 = a.position - b.position
			if absf(delta.y) >= maxf(a.height, b.height): continue
			if Vector2(delta.x, delta.z).length() + 0.001 < float(a.radius) + float(b.radius) + maxf(a.margin, b.margin): return false
	return true

func _basic_runtime() -> void:
	var fixture: Dictionary = await _fixture(2, false)
	var first = fixture.actors[0]
	var second = fixture.actors[1]
	var receiver = second.get_node("AI")
	second.look_at(second.global_position + Vector3.RIGHT)
	var start: Array[Vector3] = [first.global_position, second.global_position]
	var moved: Array[float] = [0.0, 0.0]
	var shared := false
	var unseen_shared := false
	var personal: Array[bool] = [false, false]
	var separated := true
	var accepted := false
	var no_advanced := true
	var frozen_player: Vector3 = fixture.player.global_position
	var player_still := true
	for frame in 480:
		await physics_frame
		for index in 2:
			var actor = fixture.actors[index]
			var ai = actor.get_node("AI")
			ai._physics_process(STEP)
			moved[index] = maxf(moved[index], actor.global_position.distance_to(start[index]))
			personal[index] = personal[index] or ai.utility_current.get("id", &"") in [&"engage", &"search", &"reload"]
			no_advanced = no_advanced and not ai.context.cooperation_enabled() and ai.utility_current.get("id", &"") != &"cooperate"
		shared = shared or receiver.context.team_visual_contact
		unseen_shared = unseen_shared or (receiver.context.team_visual_contact and not receiver.context.sees_player)
		var entries: Array = fixture.board.reservation_snapshot(receiver.context)
		separated = separated and _separated(entries)
		accepted = accepted or entries.any(func(entry): return entry.phase == &"accepted")
		player_still = player_still and fixture.player.global_position.distance_to(frozen_player) < 0.001
	check(shared and unseen_shared, "Advanced OFF shares a real ally observation before the receiver personally sees the target")
	check(no_advanced and personal.all(func(value): return value), "Advanced OFF keeps legal personal actions without a tactical assignment")
	check(moved[0] > 0.25 and moved[1] > 0.25 and first.shot_count > 0 and second.shot_count > 0, "Both OFF actors autonomously move and actually fire under unchanged personal scores")
	check(accepted and separated, "Normal AI commits basic destinations whose real capsule margins never overlap")
	check(player_still, "Runtime contact and movement are not caused by an accidentally moving player fixture")
	print("TEAM_BASIC_OFF moved=", moved, " shots=", [first.shot_count, second.shot_count], " accepted=", accepted)
	# Leaving the arena membership must remove old team metadata, not hold solo.
	first.queue_free()
	await first.tree_exited
	await process_frame
	var no_solo_offer := true
	var no_solo_lease := true
	var shots_before: int = second.shot_count
	var recheck_frames: int = ceili(receiver.utility_recheck_seconds / STEP) + 2
	for frame in 240:
		await physics_frame
		receiver._physics_process(STEP)
		if frame >= recheck_frames:
			no_solo_offer = no_solo_offer and not receiver.utility_current.has("coordination_offer")
			no_solo_lease = no_solo_lease and fixture.board.reservation_snapshot(receiver.context).is_empty()
	check(fixture.board.registered_member_count() == 1 and no_solo_offer and no_solo_lease and second.shot_count > shots_before, "Multi-to-solo removes old offers and reservations while real individual fire continues")
	await _dispose(fixture)

func _solo_runtime(advanced: bool) -> void:
	var fixture: Dictionary = await _fixture(1, advanced)
	var actor = fixture.actors[0]
	var ai = actor.get_node("AI")
	var start: Vector3 = actor.global_position
	var moved := 0.0
	var independent := true
	for frame in 360:
		await physics_frame
		ai._physics_process(STEP)
		moved = maxf(moved, actor.global_position.distance_to(start))
		independent = independent and not ai.utility_current.has("coordination_offer") and ai.utility_current.get("id", &"") != &"cooperate" and fixture.board.reservation_snapshot(ai.context).is_empty() and not ai.context.team_visual_contact
	check(ai.context.cooperation_enabled() == advanced and independent, "Solo advanced=%s has no fictitious ally, reservation or partner wait" % advanced)
	check(actor.shot_count > 0 and moved > 0.25, "Solo advanced=%s preserves autonomous movement and actual firing" % advanced)
	await _dispose(fixture)

func _contract_candidate(ai, point: Vector3) -> Dictionary:
	var path: PackedVector3Array = ai.context.routes.planning_path(ai.actor.global_position, point)
	var original := {"id": &"engage", "plan": &"basic_contract", "cost": 0.0, "destination": {"position": point, "path": path}}
	var options: Array[Dictionary] = [original]
	var choices: Array[Dictionary] = ai.context.coordination_choices(options)
	return choices[0] if not path.is_empty() and not choices.is_empty() else {}

func _transaction_contract() -> void:
	var fixture: Dictionary = await _fixture(2, false)
	var actor = fixture.actors[0]
	var ai = actor.get_node("AI")
	var original = ai.actions[&"engage"]
	var probe := BeginProbe.new()
	probe.setup(ai.context)
	probe.action_id = &"engage"
	ai.actions[&"engage"] = probe
	var point: Vector3 = fixture.arena.to_global(Vector3(5.5, 0, -2.0))
	var candidate := _contract_candidate(ai, point)
	check(not candidate.is_empty() and candidate.has("coordination_offer") and probe.validate(candidate, true), "Transaction contract starts from a live walkable, unoccupied destination")
	if not candidate.is_empty():
		probe.reject_begin = true
		ai._start_utility_option(candidate, true)
		check(probe.begins == 1 and ai.current_action == null and fixture.board.reservation_snapshot(ai.context).is_empty(), "Contract: begin failure rolls back the pending reservation and leaves no phantom execution")
		probe.reject_begin = false
		candidate = _contract_candidate(ai, point)
		ai._start_utility_option(candidate, true)
		var entries: Array = fixture.board.reservation_snapshot(ai.context)
		check(ai.current_action == probe and entries.size() == 1 and entries[0].phase == &"accepted", "Contract: successful begin commits exactly one accepted destination")
		var stale := candidate.duplicate(true)
		stale.coordination_offer.valid_until = ai.context.evidence_elapsed_seconds - 0.1
		var begins_before: int = probe.begins
		ai._start_utility_option(stale, true)
		check(ai.current_action == probe and probe.begins == begins_before and fixture.board.reservation_snapshot(ai.context).size() == 1, "Contract: rejected prepare preserves the old accepted execution")
		probe.reject_begin = true
		candidate = _contract_candidate(ai, point + Vector3(0, 0, -1.5))
		ai._start_utility_option(candidate, true)
		check(ai.current_action == null and fixture.board.reservation_snapshot(ai.context).is_empty(), "Contract: replacement begin failure releases cancelled old execution and new pending lease")
		probe.reject_begin = false
		probe.invalidate_commit = true
		candidate = _contract_candidate(ai, point)
		ai._start_utility_option(candidate, true)
		check(ai.current_action == null and fixture.board.reservation_snapshot(ai.context).is_empty(), "Contract: a version change during begin rejects commit and cancels the begun action")
		probe.invalidate_commit = false
		candidate = _contract_candidate(ai, point)
		var transaction: Dictionary = ai.context.prepare_coordination_choice(candidate)
		check(ai.context.commit_coordination_choice(transaction), "Contract: fixed accepted reservation is available for solo transition")
		var partner = fixture.actors[1]
		partner.queue_free()
		await partner.tree_exited
		await process_frame
		var continuing: Array[Dictionary] = [candidate]
		var choices: Array[Dictionary] = ai.context.coordination_choices(continuing)
		check(choices.size() == 1 and not choices[0].has("coordination_offer") and choices[0].cost == candidate.cost and candidate.has("coordination_offer"), "Contract: solo strips old offer without changing score or mutating its source candidate")
		check(ai.context.maintain_coordination_choice(choices[0]) and fixture.board.reservation_snapshot(ai.context).is_empty(), "Contract: continuing solo execution releases its previous accepted team lease")
	ai.actions[&"engage"] = original
	await _dispose(fixture)

func _melee_interrupt_contract() -> void:
	var fixture: Dictionary = await _fixture(2, false)
	var actor = fixture.actors[0]
	var ai = actor.get_node("AI")
	fixture.player.global_position = actor.global_position + Vector3(-1.0, 0, 0)
	actor.look_at(fixture.player.global_position)
	for frame in 3: await physics_frame
	var visible: bool = ai.perception.can_see_player()
	ai.context.update_evidence(STEP, visible)
	var candidate := {"id": &"engage", "plan": &"melee", "destination": {}, "cost": 0.0}
	var legal: bool = ai.actions[&"engage"].validate(candidate, visible)
	check(visible and legal, "Melee interrupt contract has real personal sight, range and body eligibility")
	if legal:
		ai._start_utility_option(candidate, visible)
		var action = ai.current_action
		var selector = ai.action_selector
		ai.action_selector = EmptySelector.new()
		var windup := false
		var recovery := false
		var protected := true
		var no_windup_move := true
		var before_shots: int = actor.shot_count
		for frame in 120:
			await physics_frame
			var output: Dictionary = action.execute_tick(STEP, true)
			ai.context.melee.update(STEP, true, output.get("melee", {}))
			if ai.context.melee.phase == ai.context.melee.Phase.READY: break
			windup = windup or ai.context.melee.phase == ai.context.melee.Phase.WINDUP
			recovery = recovery or ai.context.melee.phase == ai.context.melee.Phase.RECOVERY
			ai._utility_timer = 0.0
			ai._update_utility_decision(STEP, true)
			protected = protected and ai.current_action == action and actor.melee_active
			if ai.context.melee.phase == ai.context.melee.Phase.WINDUP:
				var before: Vector3 = actor.global_position
				actor.move_character(Vector3.RIGHT, STEP)
				no_windup_move = no_windup_move and actor.global_position.distance_to(before) < 0.001
			ai.context.fire.update(STEP, true, false, {})
		check(windup and recovery and protected, "Contract: missing asynchronous candidates never interrupt real melee windup or recovery")
		check(no_windup_move and actor.shot_count == before_shots and actor.melee_count > 0, "Contract: protected melee retains body movement/fire gates and really executes its strike")
		ai.action_selector = selector
	await _dispose(fixture)
