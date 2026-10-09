extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	await _autonomous_approach(0.0, false)
	await _autonomous_approach(1.3, true)
	await _frozen_report_contract()
	await _contact_boundaries()
	print("SHARED COMBAT CONTACT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _mesh() -> NavigationMesh:
	# A real navigation hole surrounds the blocking wall and its body clearance.
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	var vertices := PackedVector3Array()
	for z: float in [-8.0, -1.6, 1.6, 8.0]:
		for x: float in [-8.0, 2.7, 3.7, 8.0]: vertices.append(Vector3(x, 0.5, z))
	mesh.vertices = vertices
	for row in 3:
		for column in 3:
			if row == 1 and column == 1: continue
			var start: int = row * 4 + column
			mesh.add_polygon(PackedInt32Array([start, start + 1, start + 5, start + 4]))
	return mesh

func _fixture(receiver_z: float = 0.0) -> Dictionary:
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var observer = arena.get_node("Enemy")
	for child in arena.get_children():
		if child != observer and child.has_node("AI"): child.free()
	observer.position = Vector3(4, 0, 4)
	var receiver = load("res://scenes/enemy/enemy.tscn").instantiate()
	receiver.position = Vector3(5, 0, receiver_z)
	arena.add_child(receiver)
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	region.navigation_mesh = _mesh()
	for body in region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	var floor_collision: CollisionShape3D = region.get_node("Environment/Floor/CollisionShape3D")
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(18, 0.5, 18)
	floor_collision.position = Vector3.ZERO
	floor_collision.shape = floor_shape
	var wall := StaticBody3D.new()
	wall.position = Vector3(3.2, 1.5, 0)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 3.0, 2.5)
	collision.shape = shape
	wall.add_child(collision)
	region.add_child(wall)
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.global_position = Vector3(20, 0, 0)
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	for actor in [observer, receiver]:
		Fixture.configure_timing(actor)
		var ai = actor.get_node("AI")
		ai.training.profile.selected_tactics.clear()
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		actor.debug_shooting = false
		actor.look_at(player.global_position)
	for frame in 12: await physics_frame
	var a = observer.get_node("AI").context
	var b = receiver.get_node("AI").context
	a.update_evidence(STEP, a.perception.can_see_player())
	b.update_evidence(STEP, b.perception.can_see_player())
	check(a.sees_player and not b.sees_player and not b.has_visual_memory and not b.fresh_shared_contact().is_empty(), "The observer really sees the player while a hard wall leaves the receiver with shared contact only")
	check(not a.cooperation_enabled() and not b.cooperation_enabled(), "Combat contact sharing works with advanced cooperation disabled")
	return {"scene": scene, "arena": arena, "observer": observer, "receiver": receiver, "player": player}

func _autonomous_approach(receiver_z: float, expect_shared: bool) -> void:
	var fixture: Dictionary = await _fixture(receiver_z)
	var observer_ai = fixture.observer.get_node("AI")
	var ai = fixture.receiver.get_node("AI")
	var context = ai.context
	var start: Vector3 = fixture.receiver.global_position
	var first_shots: int = fixture.receiver.shot_count
	var saw_shared_approach := false
	var saw_shared_candidate := false
	var truthful_estimates := true
	var no_unseen_fire := true
	var no_unseen_memory := true
	var acquired_personally := false
	var shared_move := 0.0
	var contact_move := 0.0
	var combat_label := false
	var grounded := true
	for frame in 480:
		await physics_frame
		observer_ai._physics_process(STEP)
		var before: Vector3 = fixture.receiver.global_position
		ai._physics_process(STEP)
		contact_move = maxf(contact_move, fixture.receiver.global_position.distance_to(start))
		grounded = grounded and absf(fixture.receiver.global_position.y) < 0.1
		if not context.sees_player and not acquired_personally:
			combat_label = combat_label or (ai.current_action != null and ai.current_action.state_label() in ["共享接敌", "战斗接敌"])
			no_unseen_fire = no_unseen_fire and fixture.receiver.shot_count == first_shots
			no_unseen_memory = no_unseen_memory and not context.has_visual_memory
			for candidate: Dictionary in ai.utility_options:
				if candidate.get("plan", &"") != &"shared_contact": continue
				saw_shared_candidate = true
				truthful_estimates = truthful_estimates and is_equal_approx(candidate.outcome.unavailable_seconds, context.utility_horizon_seconds) and is_zero_approx(candidate.breakdown.get("cooperation_seconds", -1.0))
				truthful_estimates = truthful_estimates and candidate.destination.position.distance_to(candidate.known_position) >= 3.9
		if ai.utility_current.get("plan", &"") == &"shared_contact":
			saw_shared_approach = true
			shared_move += fixture.receiver.global_position.distance_to(before)
			no_unseen_fire = no_unseen_fire and context.fire.request.is_empty()
		acquired_personally = acquired_personally or context.sees_player
		if acquired_personally and fixture.receiver.shot_count > first_shots: break
	check(saw_shared_candidate and truthful_estimates, "Shared approaches preserve the firing distance band and have no personal or team fire credit before sight")
	if expect_shared:
		check(saw_shared_approach and shared_move > 0.25, "Normal Utility selects the cheaper wall-edge shared approach and physically moves under that action")
	else:
		check(combat_label and contact_move > 0.25, "The central-wall case accepts a genuinely faster combat investigation that actively restores sight")
	check(no_unseen_fire and no_unseen_memory, "The receiver neither fires nor acquires personal visual memory while it only has a shared report")
	check(acquired_personally and fixture.receiver.shot_count > first_shots, "The same receiver reacquires personally and then resumes ordinary real firing")
	check(grounded and fixture.player.global_position.distance_to(Vector3(20, 0, 0)) < 0.001, "Autonomous combat approach keeps real bodies on the physical floor and the target fixed")
	print("SHARED_CONTACT_RUNTIME ", JSON.stringify({"receiver_z": receiver_z, "expect_shared": expect_shared, "selected": saw_shared_approach, "shared_move": shared_move, "contact_move": contact_move}))
	await _dispose(fixture)

func _frozen_report_contract() -> void:
	var fixture: Dictionary = await _fixture()
	var a = fixture.observer.get_node("AI").context
	var ai = fixture.receiver.get_node("AI")
	var b = ai.context
	var engage = ai.actions[&"engage"]
	var search = ai.actions[&"search"]
	var report: Dictionary = b.fresh_shared_contact()
	var original_clock_offset: float = b.cooperation.elapsed - b.evidence_elapsed_seconds
	var original_capture: float = report.captured_at + original_clock_offset
	var original_deadline: float = report.valid_until + original_clock_offset
	var original_lifetime: float = report.valid_until - b.evidence_elapsed_seconds
	var horizon: float = b.utility_horizon_seconds
	check(is_equal_approx(b.shared_contact_information(fixture.receiver.global_position, 0.0, report), horizon), "Standing behind the hard wall cannot claim immediate recovery of observation")
	check(engage.assess_engagement_point(fixture.receiver.global_position, report.position).is_empty(), "Shared engagement rejects staying at the current position behind the hard wall")
	var legal: Dictionary = {}
	for point: Vector3 in engage.get_engagement_candidate_points():
		var assessed: Dictionary = engage.assess_engagement_point(point, report.position)
		if not assessed.is_empty():
			var route: Dictionary = b.spatial.assess_route(b, assessed.path, report.position, 1.0, 0.0, false)
			if b.shared_contact_information(point, route.seconds, report) < horizon:
				legal = {"position": point, "seconds": route.seconds}
				break
	check(not legal.is_empty(), "The fixture contains an actually reachable observation position outside the blocked navigation hole")
	if not legal.is_empty():
		var original_transform: Transform3D = fixture.receiver.global_transform
		fixture.receiver.global_position = legal.position
		fixture.receiver.look_at(legal.position + (legal.position - report.position))
		var turn_information: float = b.shared_contact_information(legal.position, 0.0, report)
		fixture.receiver.look_at(report.position)
		check(turn_information > 0.0 and turn_information < horizon and is_zero_approx(b.shared_contact_information(legal.position, 0.0, report)), "A clear current position accounts for turning toward the frozen target rather than inventing a shot or waiting behind a wall")
		fixture.receiver.global_transform = original_transform
	var search_candidates: Array[Dictionary] = search.collect_candidates(false)
	var consistent := not search_candidates.is_empty()
	for candidate: Dictionary in search_candidates:
		var point: Vector3 = candidate.get("route_target", fixture.receiver.global_position)
		var path: PackedVector3Array = b.routes.planning_path(fixture.receiver.global_position, point)
		var arrival := 0.0
		if candidate.has("route_target"):
			var route: Dictionary = b.spatial.assess_route(b, path, report.position, search.movement_multiplier(), 0.0, false)
			arrival = route.seconds
		consistent = consistent and is_equal_approx(candidate.outcome.information_loss, b.shared_contact_information(point, arrival, report))
	check(consistent, "Search and shared engagement charge the same factual observation-recovery time without changing weights")
	check(search.state_label() == "战斗接敌", "A fresh team report is labelled as combat contact investigation")
	var points_before: Array[Vector3] = engage.get_engagement_candidate_points()
	fixture.observer.look_at(fixture.observer.global_position + Vector3.BACK)
	fixture.player.global_position = Vector3(20, 0, -0.75)
	for frame in 3: await physics_frame
	a.update_evidence(STEP, a.perception.can_see_player())
	b.update_evidence(STEP, b.perception.can_see_player())
	check(not a.sees_player and not b.sees_player, "The frozen-report contract has genuine visual loss for both observers")
	var frozen: Dictionary = b.fresh_shared_contact()
	# The fixture pauses individual context updates while arena physics advances.
	# Compare timestamps in their original arena clock, not two remapped clocks.
	var current_clock_offset: float = b.cooperation.elapsed - b.evidence_elapsed_seconds
	var same_event: bool = not frozen.is_empty() and frozen.id == report.id and is_equal_approx(frozen.captured_at + current_clock_offset, original_capture) and is_equal_approx(frozen.valid_until + current_clock_offset, original_deadline)
	check(same_event and frozen.position == report.position and frozen.aim_position == report.aim_position and engage.get_engagement_candidate_points() == points_before, "Hidden target movement changes neither the frozen report nor the shared engagement points")
	check(not frozen.is_empty() and frozen.valid_until - b.evidence_elapsed_seconds < original_lifetime, "A remapped shared report loses real remaining lifetime instead of renewing its observation")
	var expiry: float = maxf(0.0, float(report.valid_until) - b.evidence_elapsed_seconds) + 0.1
	b.cooperation.advance(expiry)
	a.update_evidence(expiry, a.perception.can_see_player())
	b.update_evidence(expiry, b.perception.can_see_player())
	check(b.fresh_shared_contact().is_empty() and engage.evaluation_points().is_empty() and engage.collect_candidates(false).is_empty(), "Expired team contact cannot authorize new shared engagement or renew itself")
	var expired_search: Array[Dictionary] = search.collect_candidates(false)
	check(not expired_search.is_empty() and is_zero_approx(expired_search[0].outcome.information_loss) and search.state_label() == "失联搜索", "After expiry the original search remains available with its original score and lost-contact label")
	search.noise_search_origin = Vector3(24, 0, -2)
	check(search.state_label() == "噪声调查", "An explicit noise investigation remains distinguishable from combat contact")
	await _dispose(fixture)

func _contact_boundaries() -> void:
	var fixture: Dictionary = await _fixture()
	var receiver = fixture.receiver
	var ai = receiver.get_node("AI")
	var context = ai.context
	var engage = ai.actions[&"engage"]
	var original_group: StringName = receiver.communication_group
	var original_faction: StringName = receiver.faction_id
	receiver.communication_group = &"isolated_contact_test"
	context.update_evidence(STEP, context.perception.can_see_player())
	check(context.fresh_shared_contact().is_empty() and not context.has_combat_contact() and engage.collect_candidates(false).is_empty(), "Changing radio group revokes shared combat approaches as well as the underlying report")
	receiver.communication_group = original_group
	context.update_evidence(STEP, context.perception.can_see_player())
	check(not context.fresh_shared_contact().is_empty(), "Rejoining the original group restores its still fresh observation without personal sight")
	receiver.faction_id = &"neutral_contact_test"
	context.update_evidence(STEP, context.perception.can_see_player())
	check(context.fresh_shared_contact().is_empty() and not context.has_combat_contact() and engage.collect_candidates(false).is_empty(), "A neutral faction cannot turn another faction's report into shared combat contact")
	receiver.faction_id = original_faction
	context.update_evidence(STEP, context.perception.can_see_player())
	var report: Dictionary = context.fresh_shared_contact()
	check(not report.is_empty(), "Restoring the friendly faction retains the original valid report")
	context.player = fixture.observer
	check(context.fresh_shared_contact().is_empty() and engage.collect_candidates(false).is_empty() and is_equal_approx(context.shared_contact_information(receiver.global_position, 0.0, report), context.utility_horizon_seconds), "A report for one target cannot authorize contact or observation credit for another")
	context.player = fixture.player
	# A legitimate report can outlive its sender. A fresh solo encounter begins
	# with the real arena reset, not by pretending that received history vanished.
	fixture.observer.queue_free()
	await process_frame
	await physics_frame
	context.cooperation.reset()
	context.cooperation.advance(STEP)
	context.update_evidence(STEP, context.perception.can_see_player())
	check(context.cooperation.registered_member_count() == 1 and context.fresh_shared_contact().is_empty() and not context.has_combat_contact() and engage.collect_candidates(false).is_empty(), "A new solo encounter cannot manufacture shared contact or a shared engagement plan")
	receiver.global_position = Vector3(24, 0, 4)
	receiver.look_at(fixture.player.global_position)
	for frame in 3: await physics_frame
	context.update_evidence(STEP, context.perception.can_see_player())
	var personally_seen: bool = context.sees_player
	receiver.look_at(receiver.global_position + Vector3.BACK)
	context.update_evidence(STEP, context.perception.can_see_player())
	var personal: Dictionary = context.cooperation_target_evidence()
	check(personally_seen and not context.sees_player and context.has_visual_memory and not personal.is_empty() and not personal.get("shared", true) and context.fresh_shared_contact().is_empty() and engage.collect_candidates(false).is_empty(), "A solo actor's own real visual loss remains personal memory and never becomes a teammate report")
	await _dispose(fixture)

func _dispose(fixture: Dictionary) -> void:
	fixture.scene.queue_free()
	await process_frame
	await physics_frame
