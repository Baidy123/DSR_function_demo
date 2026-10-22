extends "res://tests/enemy/enemy_team_tactical_board_test.gd"

## One real task contract replaces the removed claim/round allocator.
## Autonomous movement remains covered by the flank runtime suites.

func _run() -> void:
	await _setup()
	_tactical_setup()
	for count in [1, 2, 3, 4, 6]:
		_team(count)
		_capacity(count)
	for change in [&"training", &"group", &"unregister", &"relation", &"reset", &"evidence", &"expiry", &"dead"]:
		_team(4)
		_invalidation(change)
	_team(3, 2)
	_source_contract()
	_reset_tactical()
	_flank_facts()
	_reset_tactical()
	_lifecycle_and_repair()
	_reset_tactical()
	_geometry_contract()
	_test_support_credit()
	_test_support_cycle()
	print("COOPERATION FLANK SERVICE: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	quit(1 if failures else 0)

func _reset_tactical() -> void:
	board.reset()
	for index in actors.size():
		var actor = actors[index]
		actor.global_position = _point((index - (actors.size() - 1) * 0.5) * 2.5, -6)
		actor.communication_group = &"tactical_test"
		actor.is_dead = false
		actor.cancel_reload()
		var context = contexts[index]
		context.evidence_elapsed_seconds = 0.0
		context.sees_player = false
		context.is_alerted = true
		context.last_seen_position = _point(0)
		board.register(context)
		_versions(context)

func _team(count: int, level: int = 1) -> void:
	while actors.size() > count:
		contexts.pop_back()
		actors.pop_back().free()
	while actors.size() < count:
		var actor = load("res://scenes/enemy/enemy.tscn").instantiate()
		actor.weapon = WeaponData.new()
		arena.add_child(actor)
		actors.append(actor)
		contexts.append(actor.get_node("AI").context)
	arena.team_cooperation_bindings[-1].profile.level = level
	arena.enemy_environment()
	for actor in actors:
		actor.is_dead = false
		actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
		Fixture.configure_timing(actor)
		Fixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
		actor.get_node("AI").set_physics_process(false)
		actor.set_physics_process(false)
	_reset_tactical()

func _advice(index: int, source: Dictionary, point: Vector3) -> Dictionary:
	var key := "flank-%s" % index
	var offer := _tactical_offer(contexts[index], &"flank", point, key, source)
	if not board.submit_offers(contexts[index], [offer]): return {}
	contexts[index]._coordinator()._install_coordination_proposal(source.team_id, source, {"operation": &"recommend", "recommendations": [
		{"actor_id": actors[index].get_instance_id(), "owner_action": &"cooperate", "role": &"flank", "allowed_offer_keys": [key], "reserved_position_sets": [key], "reserved_offers": [offer]}]})
	return board.assignment(contexts[index])

func _capacity(count: int) -> void:
	var source := _source(contexts[0])
	var revision: int = board.revision
	var serial: int = contexts[0]._coordinator()._serial
	for repeat in 20: board.coordination_source(contexts[0], contexts[0].cooperation_target_id())
	check(board.revision == revision and contexts[0]._coordinator()._serial == serial and board.reservation_values().is_empty(), "%s members: previews cannot create ownership or renew time" % count)
	var jobs: Array = []
	for index in count: jobs.append(_advice(index, source, _point((index - (count - 1) * 0.5) * 2.5, 6)))
	check(board.reservation_values().is_empty(), "%s members: unaccepted ordinary tasks reserve no positions" % count)
	var accepted := 0
	for index in count:
		if not jobs[index].is_empty() and not _accept(index).is_empty(): accepted += 1
	check(accepted == floori(count / 2.0), "%s members: commits preserve floor(N/2) flank quota and a front" % count)
	check(contexts.filter(func(context): return board.assignment(context).get("accepted", false)).size() == accepted, "%s members: ownership equals successful execution transactions" % count)

func _invalidation(change: StringName) -> void:
	var source := _source(contexts[0], Vector3.INF, 1.0 if change == &"expiry" else 20.0)
	_advice(0, source, _point(-2, 6))
	var task := _accept(0)
	check(not task.is_empty(), "%s invalidation starts with an accepted task" % change)
	if task.is_empty(): return
	match change:
		&"training":
			var profile = actors[0].get_node("UnitType").profile.duplicate(true)
			profile.tactical_actions.assign(profile.tactical_actions.filter(func(action): return action.action_id != &"cooperate"))
			actors[0].get_node("UnitType").profile = profile
			actors[0].get_node("AI").refresh_configuration(true)
		&"group":
			actors[0].communication_group = &"elsewhere"
			board.register(contexts[0])
		&"unregister": board.unregister(actors[0].get_instance_id())
		&"relation": board.set_relation(&"enemy", &"outsider", &"neutral")
		&"reset": board.reset()
		&"evidence": _source(contexts[1], _point(0, 3))
		&"expiry": _advance(1.1)
		&"dead": actors[0].is_dead = true
	check(board.assignment(contexts[0]).is_empty() and not board.report_assignment(contexts[0], task), "%s revokes old ownership and feedback without deadline renewal" % change)

func _publish(context, extra: Dictionary = {}) -> void:
	var status := {"target_id": context.cooperation_target_id(), "position": context.actor.global_position,
		"ready": false, "moving": false, "reloading": false, "support_seconds": 0.0, "firearms": true, "lane_id": &"target"}
	status.merge(extra, true)
	board.publish_status(context, status)

func _test_support_credit() -> void:
	_team(2)
	var provider = contexts[0]
	var recipient = contexts[1]
	_publish(provider, {"ready": true, "support_seconds": 4.0})
	_publish(recipient, {"support_request": {"kind": &"advance", "duration": 3.0}})
	var stationary := {"outcome": {"unavailable_seconds": 0.0}, "destination": {}}
	var moving := {"outcome": {"unavailable_seconds": 0.0}, "destination": {"position": provider.actor.global_position + Vector3.RIGHT * 2.0}}
	var moving_hide := {"outcome": {"unavailable_seconds": 0.0}, "destination": {"hide": provider.actor.global_position + Vector3.RIGHT * 2.0}}
	var stationary_hide := {"outcome": {"unavailable_seconds": 0.0}, "destination": {"hide": provider.actor.global_position}}
	check(board.candidate_seconds(provider, stationary) > 0.0 and is_zero_approx(board.candidate_seconds(provider, moving)), "only the stationary ordinary option can claim stationary advance-cover credit")
	check(is_zero_approx(board.candidate_seconds(provider, moving_hide)), "a hide-only cover transfer cannot impersonate stationary advance support")
	check(board.candidate_seconds(provider, stationary_hide) > 0.0, "a hide-only destination at the actual current body position preserves stationary support")
	board.clear_execution(recipient.actor.get_instance_id())
	recipient.actor.ammo.is_reloading = true
	_publish(recipient, {"reloading": true, "reload_seconds": 3.0})
	check(board.candidate_seconds(provider, moving) > 0.0, "permitted moving fire can still cover a real reload request")
	check(board.candidate_seconds(provider, moving_hide) > 0.0, "a real hide-only transfer retains permitted moving reload-cover credit")
	provider.training.set_setting(&"tactics", &"fire_while_moving", false)
	check(is_zero_approx(board.candidate_seconds(provider, moving)), "disallowed moving fire cannot inherit the current stationary firing window")
	check(is_zero_approx(board.candidate_seconds(provider, moving_hide)), "a hide-only transfer cannot inherit stationary fire when moving fire is disabled")
	provider.training.set_setting(&"tactics", &"fire_while_moving", true)
	recipient.actor.ammo.is_reloading = false
	_publish(recipient, {"support_request": {"kind": &"retreat", "duration": 3.0}})
	check(board.candidate_seconds(provider, moving) > 0.0, "permitted moving fire retains retreat-cover value")
	_publish(recipient, {"support_request": {"kind": &"flank", "duration": 3.0}})
	check(is_zero_approx(board.candidate_seconds(provider, moving)), "opposite-flank requests require stationary cover too")
	provider.actor.ammo.magazine_rounds = 0
	check(is_zero_approx(board.candidate_seconds(provider, stationary)), "an empty magazine never promises stationary support")

func _test_support_cycle() -> void:
	_team(2)
	var provider = contexts[0]
	var observer = contexts[1]
	_publish(provider, {"support_cycle_valid": true, "support_resume_seconds": 0.8})
	board.advance(0.2)
	var snapshot: Dictionary = board.snapshot(observer, observer.cooperation_target_id())
	var member: Dictionary = snapshot.members.filter(func(value): return value.id == provider.actor.get_instance_id())[0]
	check(member.support_cycle_valid and is_equal_approx(member.support_resume_seconds, 0.6) and not member.ready and snapshot.supports.is_empty(), "a burst-pause estimate ages without becoming present firing support")
	for blocker in [&"reload", &"empty", &"shooting", &"melee"]:
		provider.actor.ammo.is_reloading = blocker == &"reload"
		provider.actor.ammo.magazine_rounds = 0 if blocker == &"empty" else 40
		provider.actor.shooting_enabled = blocker != &"shooting"
		provider.actor.melee_active = blocker == &"melee"
		snapshot = board.snapshot(observer, observer.cooperation_target_id())
		member = snapshot.members.filter(func(value): return value.id == provider.actor.get_instance_id())[0]
		check(not member.support_cycle_valid and member.support_resume_seconds < 0.0 and not member.ready and snapshot.supports.is_empty(), "%s immediately revokes an old pause-recovery estimate" % blocker)
