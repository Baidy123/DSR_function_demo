extends SceneTree

## Board contracts use real registered Context/Actor instances. No selected
## action is forced, no navigation is performed by the board, and this suite
## does not claim the later coordinator has entered the AI loop.
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0
var scene
var arena
var board
var actors: Array = []
var contexts: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	await _setup()
	_basic_transaction()
	_physical_isolation()
	_lifecycle()
	_pairwise_teams()
	_solo()
	_reload_lifecycle()
	print("TEAM BOARD: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	await process_frame
	quit(1 if failures else 0)

func _setup() -> void:
	scene = preload("res://tests/enemy/enemy_fire_fixture.gd").legacy_scene()
	arena = scene.get_node("Arena")
	var first = preload("res://tests/enemy/enemy_fire_fixture.gd").primary_enemy(arena)
	for child in arena.get_children():
		if child != first and child.has_node("AI"): child.free()
	actors = [first]
	for index in 2:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		arena.add_child(actor)
		actors.append(actor)
	root.add_child(scene)
	current_scene = scene
	arena.set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, -4))
	for cover in get_nodes_in_group("cover_region"):
		cover.collision_layer = 0
		cover.remove_from_group("cover_region")
	var points := [Vector3(-5, 0, -5), Vector3(5, 0, -5), Vector3(5, 0, 5)]
	for index in actors.size():
		var actor = actors[index]
		Fixture.configure_timing(actor)
		var ai = actor.get_node("AI")
		ai.training.profile.selected_tactics.clear()
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		actor.set_physics_process(false)
		actor.debug_shooting = false
		actor.global_position = arena.to_global(points[index])
		contexts.append(ai.context)
	board = arena.cooperation
	for frame in 6: await physics_frame
	board.reset()
	for context in contexts:
		board.register(context)
		context.evidence_elapsed_seconds = 0.0

func _versions(context, value: int = 1) -> bool:
	return board.publish_member_versions(context, {"config_revision": value, "environment_revision": 1, "navigation_revision": 1})

func _offer(context, point: Vector3, key: String = "point", summary: Dictionary = {}) -> Dictionary:
	var result: Dictionary = board.coordination_identity(context)
	result.merge({"scope": &"basic", "role": &"independent_position", "owner_action": &"engage",
		"offer_key": key, "position_set_key": key, "position": point, "path_summary": summary,
		"target_id": 0, "evidence_id": 0, "captured_at": context.evidence_elapsed_seconds,
		"valid_until": context.evidence_elapsed_seconds + 2.0}, true)
	return result

func _advance(seconds: float) -> void:
	for context in contexts: context.evidence_elapsed_seconds += seconds
	board.advance(seconds)

func _point(x: float, z: float = 0.0) -> Vector3:
	return arena.to_global(Vector3(x, 0, z))

func _basic_transaction() -> void:
	var a = contexts[0]
	var b = contexts[1]
	check(contexts.all(func(context): return not context.cooperation_enabled()), "Fixture keeps all advanced cooperation OFF")
	check(board.claim(a, {"kind": &"search", "owner_action": &"search", "position": _point(-2)}).is_empty(), "Basic reservations do not weaken the existing advanced tactical claim gate")
	check(board.prepare_reservation(a, _offer(a, _point(-2))).is_empty(), "An unpublished version cannot silently authorize a zero-version reservation")
	for context in contexts: _versions(context)
	var identity: Dictionary = board.coordination_identity(a)
	var before: int = board.revision
	board.register(a)
	_versions(a)
	check(identity == board.coordination_identity(a) and before == board.revision, "Identical registration and version publication preserve member/team identity")
	check(a.is_position_free(_point(-2)), "The locally supplied basic position is physically free")
	var offer: Dictionary = _offer(a, _point(-2))
	before = board.revision
	var snapshot_before: Array = board.reservation_snapshot(a)
	var previews_allowed := true
	for index in 8: previews_allowed = previews_allowed and board.reservation_offer_available(a, offer)
	check(previews_allowed and board.revision == before and board.reservation_snapshot(a) == snapshot_before, "Repeated candidate filtering creates no reservation, expiry extension or revision")
	var first: Dictionary = board.prepare_reservation(a, _offer(a, _point(-2)), 4.0)
	check(not first.is_empty() and first.phase == &"pending" and not first.has("assignment_id"), "Advanced OFF prepares an independent pending position without a tactical assignment")
	check(board.prepare_reservation(b, _offer(b, _point(-2), "other-key")).is_empty(), "Different candidate keys cannot reserve the same physical destination")
	var expiry: float = first.expires_at
	_advance(0.2)
	var repeated: Dictionary = board.prepare_reservation(a, _offer(a, _point(-2)), 20.0)
	check(repeated.reservation_id == first.reservation_id and repeated.expires_at == expiry, "Repeated prepare retains its original reservation ID and fixed deadline")
	board.clear_execution(actors[0].get_instance_id())
	check(board.validate_reservation(a, first), "Clearing the previous action preserves the newly prepared reservation")
	check(board.commit_reservation(a, first) and board.reservation_snapshot(a).size() == 1, "Successful begin commits the same single physical reservation")
	var second: Dictionary = board.prepare_reservation(a, _offer(a, _point(0), "second"))
	board.rollback_reservation(a, second)
	check(board.validate_reservation(a, first) and board.reservation_snapshot(a).size() == 1, "Failed validation before cancellation rolls back only the new pending reservation")
	second = board.prepare_reservation(a, _offer(a, _point(0), "second"))
	board.clear_execution(actors[0].get_instance_id())
	board.rollback_reservation(a, second)
	check(board.reservation_snapshot(a).is_empty() and not board.validate_reservation(a, first), "Rollback after cancellation does not pretend the old execution or reservation has resumed")
	first = board.prepare_reservation(a, _offer(a, _point(-2)))
	var foreign := first.duplicate(true)
	board.rollback_reservation(b, foreign)
	check(not board.commit_reservation(b, foreign) and board.validate_reservation(a, first), "Another actor cannot commit or roll back the owner's token")
	var forged := first.duplicate(true)
	forged.position = _point(2)
	check(not board.validate_reservation(a, forged), "Changing a token's immutable position does not authorize a different destination")
	var snapshot: Array = board.reservation_snapshot(b)
	snapshot[0].position = _point(7)
	check(board.validate_reservation(a, first), "Mutating a returned snapshot cannot mutate stored occupancy")
	board.release_reservation(a, first)
	check(not board.prepare_reservation(b, _offer(b, _point(-2))).is_empty(), "Exact release makes the physical position available to another actor")
	board.reset()
	first = board.prepare_reservation(a, _offer(a, _point(-2)))
	var collision: CollisionShape3D = actors[0].get_node("CollisionShape3D")
	var original: Shape3D = collision.shape
	collision.shape = original.duplicate()
	collision.shape.radius = 0.5
	var current: Array = board.reservation_snapshot(a)
	check(is_equal_approx(float(current[0].radius), 0.5) and not board.reservation_offer_available(b, _offer(b, _point(-0.75), "size-neighbour")), "Snapshot and destination filtering use the current body footprint after a shape change")
	collision.shape = original
	actors[0].request_crouch(true)
	for index in 30: actors[0].body_motion.update_posture(1.0 / 60.0)
	current = board.reservation_snapshot(a)
	check(actors[0].is_crouching() and is_equal_approx(float(current[0].height), actors[0].get_body_height()), "Occupancy snapshots follow the body's real crouch transition rather than a prepared standing height")
	actors[0].request_crouch(false)
	for index in 30: actors[0].body_motion.update_posture(1.0 / 60.0)
	board.reset()

func _physical_isolation() -> void:
	var a = contexts[0]
	var b = contexts[1]
	actors[1].communication_group = &"another_radio"
	_versions(b)
	check(not board.can_share_intel(actors[0].get_instance_id(), actors[1].get_instance_id()) and board.can_share_space(actors[0].get_instance_id(), actors[1].get_instance_id()), "Physical coordination crosses friendly radio groups without sharing intelligence")
	var first: Dictionary = board.prepare_reservation(a, _offer(a, _point(-2)))
	var other: Dictionary = _offer(b, _point(-2), "different-target")
	other.target_id = b.cooperation_target_id()
	check(board.prepare_reservation(b, other).is_empty(), "A different target and communication group cannot occupy the same friendly slot")
	var public: Array = board.reservation_snapshot(b)
	check(public.size() == 1 and not public[0].has("target_id") and not public[0].has("evidence_id") and not public[0].has("path_summary"), "Cross-group occupancy snapshots contain no target, evidence or firing-lane endpoint")
	board.release_reservation(a, first)
	check(board.prepare_reservation(a, _offer(a, actors[1].global_position, "body")).is_empty(), "A real friendly body blocks a destination without any tactical claim")
	first = board.prepare_reservation(a, _offer(a, _point(-2), "left", {"corridor_key": "narrow", "exclusive_corridor": true}))
	check(board.prepare_reservation(b, _offer(b, _point(2), "right", {"corridor_key": "narrow"})).is_empty(), "Separated destinations still reject an explicitly exclusive shared corridor")
	board.release_reservation(a, first)
	var lane := {"origin": _point(-3) + Vector3.UP, "endpoint": _point(3) + Vector3.UP}
	first = board.prepare_reservation(a, _offer(a, _point(-3), "shooter", {"firing_lane": lane}))
	check(not first.is_empty() and board.prepare_reservation(b, _offer(b, _point(0), "gunline")).is_empty(), "A planned friendly firing segment excludes an obvious body position in its lane")
	board.reset()
	actors[1].faction_id = &"neutral_stranger"
	_versions(b)
	first = board.prepare_reservation(a, _offer(a, _point(-2)))
	check(not board.prepare_reservation(b, _offer(b, _point(-2), "neutral")).is_empty(), "Neutral units are not falsely given friendly reservation authority; local collision remains separate")
	board.reset()
	actors[1].faction_id = &"enemy"
	actors[1].communication_group = &""
	_versions(b)

func _lifecycle() -> void:
	var a = contexts[0]
	var b = contexts[1]
	var pending: Dictionary = board.prepare_reservation(a, _offer(a, _point(-2)), 4.0)
	_advance(2.1)
	check(not board.commit_reservation(a, pending), "An unaccepted offer cannot be committed after its original offer deadline")
	pending = board.prepare_reservation(a, _offer(a, _point(-2)), 4.0)
	check(board.commit_reservation(a, pending), "A fresh position can be committed after the previous pending reservation expires")
	_advance(2.1)
	check(board.validate_reservation(a, pending), "An accepted real execution does not expire merely because its preview offer aged out")
	_advance(2.0)
	check(not board.validate_reservation(a, pending) and board.reservation_snapshot(a).is_empty(), "Accepted execution has a finite original reservation deadline")
	pending = board.prepare_reservation(a, _offer(a, _point(-2)))
	actors[0].communication_group = &"moved_group"
	check(not board.validate_reservation(a, pending), "Changing communication identity revokes an old pending token immediately")
	check(not board.can_share_intel(actors[0].get_instance_id(), actors[1].get_instance_id()), "An unpublished live radio change immediately rejects old intelligence membership")
	_versions(a)
	actors[0].communication_group = &""
	_versions(a)
	var original_faction: StringName = actors[0].faction_id
	actors[0].faction_id = &"unpublished_faction"
	check(board.coordination_identity(a).is_empty() and not board.can_share_intel(actors[1].get_instance_id(), actors[0].get_instance_id()), "An unpublished live faction change rejects both identity and received intelligence")
	actors[0].faction_id = original_faction
	check(not board.coordination_identity(a).is_empty() and board.can_share_intel(actors[0].get_instance_id(), actors[1].get_instance_id()), "Restoring the exact live domain restores eligibility without stale cached decisions")
	pending = board.prepare_reservation(a, _offer(a, _point(-2)))
	_versions(a, 2)
	check(not board.validate_reservation(a, pending), "Published configuration changes invalidate stale local offers and reservations")
	pending = board.prepare_reservation(a, _offer(a, _point(-2)))
	var permission: Variant = a.permitted[&"engage"]
	a.permitted.erase(&"engage")
	check(not board.validate_reservation(a, pending), "Removing the owning action revokes the reservation without requiring advanced permission")
	a.permitted[&"engage"] = permission
	board.release_member(actors[0].get_instance_id())
	pending = board.prepare_reservation(a, _offer(a, _point(-2)))
	var old_generation: int = pending.member_generation
	actors[0].is_dead = true
	board.advance(0.0)
	check(not board.validate_reservation(a, pending), "Death unregisters and releases all pending and accepted occupancy")
	actors[0].is_dead = false
	_versions(a, 2)
	check(board.coordination_identity(a).member_generation != old_generation, "Re-registering a living instance after death creates a new member generation")
	pending = board.prepare_reservation(a, _offer(a, _point(-2)))
	var old_board = a.cooperation
	a.cooperation = null
	check(not board.validate_reservation(a, pending), "A detached Context cannot retain a reservation on its former board")
	a.cooperation = old_board
	board.release_member(actors[0].get_instance_id())
	pending = board.prepare_reservation(a, _offer(a, _point(-2)))
	var previous: Vector3 = actors[1].global_position
	actors[1].global_position = pending.position
	check(not board.validate_reservation(a, pending) and not board.commit_reservation(a, pending), "A real ally entering the pending destination is checked again before commit")
	actors[1].global_position = previous
	check(board.validate_reservation(a, pending), "A moved-away ally restores availability without renewing the reservation")
	board.reset()
	check(not board.commit_reservation(a, pending) and not board.prepare_reservation(b, _offer(b, _point(-2))).is_empty(), "Arena reset invalidates old generations and clears occupancy")
	board.reset()

func _pairwise_teams() -> void:
	for index in actors.size():
		actors[index].faction_id = StringName("faction_%d" % index)
		_versions(contexts[index])
	board.set_relation(&"faction_0", &"faction_1", &"allied")
	board.set_relation(&"faction_1", &"faction_2", &"allied")
	var ids: Array = contexts.map(func(context): return board.coordination_identity(context).team_id)
	check(ids[0] == ids[1] and ids[0] != ids[2], "Non-transitive alliances produce pairwise teams, not one connected component")
	var a_generation: int = board.coordination_identity(contexts[0]).member_generation
	for context in contexts:
		board.register(context)
		_versions(context, int(board.coordination_identity(context).config_revision))
	check(ids == contexts.map(func(context): return board.coordination_identity(context).team_id) and board.coordination_identity(contexts[0]).member_generation == a_generation, "Repeated identity heartbeats do not churn pairwise teams or member generations")
	for index in actors.size():
		actors[index].faction_id = &"enemy"
		_versions(contexts[index])
	board.reset()

func _reload_lifecycle() -> void:
	var a = contexts[0]
	var b = contexts[1]
	for index in 2:
		var ai = actors[index].get_node("AI")
		Fixture.set_training_action(ai, &"cooperate", true)
		ai.set_physics_process(false)
		_versions(contexts[index], 3)
	actors[1].ammo.magazine_rounds = 1
	check(actors[1].request_reload(), "Lifecycle contract starts a real body reload")
	b.cooperation_publish_execution({})
	var id: int = board._members[actors[1].get_instance_id()].status.get("reload_request_id", 0)
	var support: Dictionary = board.claim(a, {"kind": &"support", "owner_action": &"cooperate", "target_id": a.cooperation_target_id(), "beneficiary_id": actors[1].get_instance_id(), "duration": 2.0})
	var pending: Dictionary = board.prepare_reservation(b, _offer(b, _point(-2)))
	board.clear_execution(actors[1].get_instance_id())
	b.cooperation_publish_execution({})
	check(not support.is_empty() and board.coordination_debug_snapshot(&"_claims").has(support.id) and actors[1].ammo.is_reloading, "Ordinary action cleanup preserves a teammate's support lease and the real reload")
	check(id > 0 and board._members[actors[1].get_instance_id()].status.get("reload_request_id", 0) == id and board.validate_reservation(b, pending), "Preparing a new position preserves both pending ownership and continuous reload request identity")
	board.release_member(actors[1].get_instance_id())
	check(not board.coordination_debug_snapshot(&"_claims").has(support.id) and not board.validate_reservation(b, pending), "True member release clears pending positions and dependent support claims")
	actors[1].cancel_reload()

func _solo() -> void:
	for index in [1, 2]: board.unregister(actors[index].get_instance_id())
	var context = contexts[0]
	var pending: Dictionary = board.prepare_reservation(context, _offer(context, _point(-2)))
	check(board.registered_member_count() == 1 and not pending.is_empty() and board.commit_reservation(context, pending), "A solo OFF actor can commit its own legal position without a partner or tactical barrier")
	board.release_reservation(context, pending)
	for index in [1, 2]: _versions(contexts[index])
