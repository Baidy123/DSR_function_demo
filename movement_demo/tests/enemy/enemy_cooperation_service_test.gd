extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const Board = preload("res://scripts/enemy/services/enemy_cooperation.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var arena = scene.get_node("Arena")
	var first = arena.get_node("Enemy")
	var second = load("res://scenes/enemy/enemy.tscn").instantiate()
	arena.add_child(second)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	var a = first.get_node("AI").context
	var b = second.get_node("AI").context
	for actor in [first, second]:
		var ai = actor.get_node("AI")
		ai.set_physics_process(false)
		Fixture.configure_timing(actor)
		ai.training.profile.selected_tactics.clear()
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.refresh_configuration(true)
		actor.debug_shooting = false
	first.global_position = Vector3(18, 0, 0)
	second.global_position = Vector3(18, 0, 3)
	player.global_position = Vector3(23, 0, 0)
	first.look_at(player.global_position)
	second.look_at(second.global_position + Vector3.LEFT)
	for frame in 5: await physics_frame
	a.update_evidence(STEP, a.perception.can_see_player())
	b.update_evidence(STEP, b.perception.can_see_player())
	check(a.sees_player and not b.sees_player and b.team_visual_contact and not b.has_visual_memory, "default intel is shared without granting personal sight or advanced training")
	check(not a.cooperation_enabled() and not b.cooperation_enabled(), "default sharing does not unlock advanced tactics")
	var report: Dictionary = b.cooperation_target_evidence()
	check(report.get("observer_id", 0) == first.get_instance_id() and report.get("target_id", 0) == player.get_instance_id(), "shared observation retains its source and target identity")
	check(report.get("aim_position", Vector3.INF).is_finite() and report.aim_position == a.last_seen_aim_position, "untrained firearm observers share a genuinely visible aim sample without gaining a suppression action")
	var original: Vector3 = report.get("position", Vector3.INF)
	var deadline: float = report.get("valid_until", -1.0)
	first.look_at(first.global_position + Vector3.LEFT)
	player.global_position = Vector3(24, 0, 0)
	a.cooperation.advance(0.2)
	a.update_evidence(0.2, false)
	b.update_evidence(0.2, false)
	check(b.cooperation_target_evidence().position == original and b.cooperation_target_evidence().valid_until == deadline, "forwarded observation neither follows a hidden target nor refreshes its deadline")
	var target_before = b.player
	b.player = first
	check(b.cooperation_target_evidence().is_empty(), "cached evidence for one target cannot authorize a different target")
	b.player = target_before
	second.communication_group = &"separate"
	b.update_evidence(STEP, false)
	check(not b.team_visual_contact and b.cooperation_target_evidence().is_empty(), "changing communication group revokes old shared authority")
	check(a.cooperation.can_share_space(first.get_instance_id(), second.get_instance_id()), "friendly physical yielding does not depend on a shared radio group")
	second.communication_group = &""
	b.update_evidence(STEP, false)
	check(b.team_visual_contact, "joining the original group can read its still valid observation")
	var original_board = b.cooperation
	b.cooperation = Board.new()
	b.cooperation.register(b)
	b._cooperation_identity.clear()
	b.update_evidence(STEP, false)
	check(not b.team_visual_contact and b.cooperation_target_evidence().is_empty(), "a separate arena board has no access to another area's observations")
	b.cooperation = original_board
	b._cooperation_identity.clear()
	second.faction_id = &"outsider"
	b.update_evidence(STEP, false)
	check(not b.team_visual_contact and not original_board.is_hostile(&"enemy", &"outsider"), "unknown factions neither share intel nor automatically become hostile")
	check(not original_board.can_share_space(first.get_instance_id(), second.get_instance_id()), "neutral strangers cannot issue friendly yielding requests")
	original_board.set_relation(&"enemy", &"outsider", &"allied")
	b.update_evidence(STEP, false)
	check(b.team_visual_contact, "an explicit allied relation grants intel sharing")
	check(original_board.can_share_space(first.get_instance_id(), second.get_instance_id()), "an explicit allied relation also authorizes physical yielding")
	original_board.set_relation(&"enemy", &"outsider", &"neutral")
	b.update_evidence(STEP, false)
	check(not b.team_visual_contact and b.cooperation_target_evidence().is_empty(), "revoking the relation removes cached shared evidence")
	check(not original_board.can_share_space(first.get_instance_id(), second.get_instance_id()), "revoking an alliance immediately revokes friendly yielding")
	second.faction_id = &"enemy"
	b.update_evidence(STEP, false)
	for actor in [first, second]: Fixture.set_training_action(actor.get_node("AI"), &"cooperate", true)
	var task := {"kind": &"search", "position": Vector3(22, 0, 1), "duration": 1.0, "owner_action": &"search"}
	var owned: Dictionary = a.cooperation_claim(task)
	check(not owned.is_empty() and b.cooperation_claim(task).is_empty(), "atomic task claims allow only one searcher at the same point")
	var expiry: float = owned.get("expires_at", -1.0)
	a.cooperation_update(owned, {"duration": 999.0, "ready": true})
	check(a.cooperation_snapshot().claims[0].expires_at == expiry and a.cooperation_snapshot().supports.is_empty(), "updates cannot renew a claim or fabricate support readiness")
	a.cooperation_release(owned)
	var next: Dictionary = b.cooperation_claim(task)
	check(not next.is_empty(), "release makes the position available to another member")
	original_board.advance(1.1)
	check(not b.cooperation_update(next, {}) and not a.cooperation_claim(task).is_empty(), "expired ownership cannot be renewed and another member can claim the task")
	Fixture.set_training_action(first.get_node("AI"), &"cooperate", false)
	original_board.advance(0.01)
	check(b.cooperation_snapshot().claims.is_empty(), "revoking training clears outstanding cooperation tasks")
	Fixture.set_training_action(first.get_node("AI"), &"cooperate", true)
	owned = a.cooperation_claim(task)
	original_board.reset()
	check(not a.cooperation_update(owned, {}) and b.cooperation_snapshot().claims.is_empty(), "arena reset invalidates tokens from the prior generation")
	var advance: Dictionary = a.cooperation_claim({"kind": &"advance", "lane_id": &"position:22:1", "position": Vector3(22, 0, 1), "duration": 1.0, "owner_action": &"cooperate"})
	var observed: Dictionary = b.cooperation_snapshot()
	check(not advance.is_empty() and observed.claims[0].lane_id == &"position:22:1" and observed.requests[0].lane_id == &"target", "support request conversion preserves the exclusive position lane in the claim snapshot")
	a.cooperation_release(advance)

	# The support gate is measured by the actual fire controller and actor.
	first.global_position = Vector3(18, 0, 0)
	second.global_position = Vector3(18, 0, 3)
	player.global_position = Vector3(23, 0, 0)
	first.look_at(player.global_position)
	first.move_speed = 0.0
	first.aim_turn_speed_degrees = 3600.0
	var real_support := false
	for frame in 90:
		await physics_frame
		first.get_node("AI")._physics_process(STEP)
		b.cooperation_publish_execution({})
		real_support = real_support or not b.cooperation_snapshot().supports.is_empty()
		if real_support and first.shot_count > 0: break
	check(real_support and first.shot_count > 0, "actual aimed firing publishes usable support")
	second.ammo.magazine_rounds = 2
	second.request_reload()
	b.cooperation_publish_execution({})
	var request_id: int = a.cooperation_snapshot().requests[0].request_id
	second.ammo.reload_progress = 1.0 - 0.2 / second.weapon.reload_seconds
	b.cooperation_publish_execution({})
	check(a.cooperation_snapshot().requests[0].request_id == request_id, "continued reload status preserves one request identity despite fresh observations")
	var delayed := {"outcome": {"unavailable_seconds": 1.0}, "cooperation": {"kind": &"support", "lane_id": &"target", "support_seconds": 1.0, "estimated_start_seconds": 1.0}}
	check(is_zero_approx(a.cooperation_candidate_seconds(delayed)), "support arriving after the actual reload request ends receives no credit")
	second.ammo.reload_progress = 0.0
	b.cooperation_publish_execution({})
	var credit: float = a.cooperation_candidate_seconds(delayed)
	check(credit > 0.0 and credit <= 1.0 and is_equal_approx(credit, a.cooperation_candidate_seconds(delayed)), "only overlapping demand is credited and repeated evaluation preserves the provider's own value")
	second.cancel_reload()
	b.cooperation_publish_execution({})
	second.request_reload()
	b.cooperation_publish_execution({})
	check(a.cooperation_snapshot().requests[0].request_id != request_id, "a later actual reload receives a new request identity without depending on a suppression preview")
	second.cancel_reload()
	first.ammo.magazine_rounds = 0
	check(b.cooperation_snapshot().supports.is_empty(), "running out of ammunition immediately invalidates previous support")
	first.is_dead = true
	original_board.advance(STEP)
	check(b.cooperation_snapshot().members.all(func(member): return member.id != first.get_instance_id()), "dead members cannot retain a support slot")
	check(not original_board.can_share_space(first.get_instance_id(), second.get_instance_id()), "dead or unregistered bodies cannot retain yielding authority")
	var training := EnemyTrainingProfile.new()
	training.set_setting(&"exit_suppression", &"duration_min", 1.7)
	check(is_equal_approx(training.setting(&"suppression", &"exit_duration_min"), 1.7), "legacy explicit exit settings survive unified suppression")
	training.set_setting(&"suppression", &"exit_duration_min", 2.4)
	check(is_equal_approx(training.setting(&"suppression", &"exit_duration_min"), 2.4), "new explicit suppression settings override legacy values")
	scene.queue_free()
	await process_frame
	print("COOPERATION SERVICE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
