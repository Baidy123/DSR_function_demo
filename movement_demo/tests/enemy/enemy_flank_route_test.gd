extends SceneTree

const Route = preload("res://scripts/enemy/services/enemy_flank_route.gd")
const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

class ProposalActor extends Node3D:
	var move_speed := 2.0

class ProposalContext extends RefCounted:
	var actor
	func setting(_section: StringName, _key: StringName, fallback: Variant = null) -> Variant: return fallback

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	_proposal_contract()
	await _blocked_endpoint_contract()
	await _information_contract()
	for distance in [9.7, 12.5]:
		await _real_navigation(distance)
	print("FINITE FAR FLANK ROUTES: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _proposals(context, anchor: Vector3 = Vector3.ZERO) -> Array:
	return Route.proposals(context, {"remaining_slots": 1, "anchor": anchor, "front_axis": Vector3.RIGHT, "round_id": 0})

func _proposal_contract() -> void:
	var actor := ProposalActor.new()
	root.add_child(actor)
	var context := ProposalContext.new()
	context.actor = actor
	actor.position = Vector3(5, 0, 0)
	var nearby: Array = _proposals(context)
	var left := 0
	var right := 0
	for proposal: Dictionary in nearby:
		if proposal.position.z < 0.0: left += 1
		if proposal.position.z > 0.0: right += 1
	check(nearby.size() == 4 and left == 2 and right == 2, "Nearby flanks retain both signed turns and both original endpoint radii")
	var tiny_corners := PackedVector3Array([Vector3.ZERO, Vector3(0.025, 0, 0), Vector3(0.092, 0, 0), Vector3(0.092, 0, 1), Vector3(1.6, 0, 1)])
	var measured: PackedVector3Array = Route._short_checkpoints(tiny_corners)
	check(measured.size() == 2 and measured[0].distance_to(Vector3(1, 0, 1)) < 0.001 and measured[-1] == tiny_corners[-1], "Tiny navigation corners stay inside a leg whose endpoint follows two metres of actual polyline instead of becoming immediate tactical stops")
	for distance in [9.7, 12.5]:
		actor.position = Vector3(distance, 0, 0)
		# The previous formula discards both radii on both turns before navigation.
		var old_legs: int = ceili(deg_to_rad(140.0) * distance / 2.0)
		var proposals: Array = _proposals(context)
		check(old_legs > 10 and proposals.size() == 4, "%.1fm no longer loses every otherwise bounded route to the former ten-leg cutoff" % distance)
		var bounded := true
		var inward := true
		for proposal: Dictionary in proposals:
			var previous: Vector3 = actor.position
			var total := 0.0
			for point: Vector3 in proposal.checkpoints:
				var length: float = previous.distance_to(point)
				bounded = bounded and length <= 2.001
				total += length
				previous = point
			bounded = bounded and total <= 26.001 and proposal.checkpoints.size() <= 24 and proposal.position.x < -0.5
			inward = inward and proposal.route_anchors[0].is_equal_approx(Vector3(5, 0, 0))
			var polyline := PackedVector3Array([actor.position])
			polyline.append_array(proposal.checkpoints)
			bounded = bounded and Route.safe_path(polyline, Vector3.ZERO)
		check(bounded and inward, "%.1fm approaches the inner orbit before turning, with short finite legs and unchanged target clearance" % distance)
	actor.position = Vector3(100, 0, 0)
	check(_proposals(context).is_empty(), "Travel that cannot fit the unchanged deadline is rejected by actual distance rather than allocated unbounded checkpoints")
	actor.position = Vector3(9.7, 0, 0)
	actor.move_speed = 0.1
	check(_proposals(context).is_empty(), "The finite route budget uses the actor's actual speed")
	actor.free()

func _fixture(distance: float, anchor_z: float = 0.0) -> Dictionary:
	seed(9137)
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	var flanker = arena.get_node("Enemy")
	for child in arena.get_children():
		if child != flanker and child.has_node("AI"): child.free()
	flanker.position = Vector3(distance, 0, anchor_z)
	var front = load("res://scenes/enemy/enemy.tscn").instantiate()
	front.position = Vector3(4, 0, anchor_z)
	arena.add_child(front)
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.velocity = Vector3.ZERO
	player.global_position = arena.to_global(Vector3(0, 0, anchor_z))
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	for actor in [front, flanker]:
		Fixture.configure_timing(actor)
		var ai = actor.get_node("AI")
		ai.training.profile.selected_tactics.assign([&"cover", &"covering_retreat", &"attack_position", &"suppression"])
		# Different training is a real configuration, not an injected role: the
		# front retains its ordinary Utility while the distant actor can flank.
		if actor == flanker: ai.training.profile.selected_tactics.append(&"cooperate")
		ai.training.profile.set_setting(&"perception", &"sight_distance", 8.0)
		ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
		ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
		ai.training.profile.set_setting(&"tactics", &"burst_shot_count", 10)
		ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 1.5)
		var weapon: WeaponData = actor.weapon.duplicate(true)
		weapon.magazine_capacity = 20
		weapon.shot_interval = 0.2
		weapon.reload_seconds = 3.5
		actor.equip_weapon(weapon)
		ai.refresh_configuration(true)
		ai.set_physics_process(false)
		ai.cover_selection.debug_cover_selection = false
		actor.debug_shooting = false
		actor.look_at(player.global_position)
	for frame in 12: await physics_frame
	var a = front.get_node("AI").context
	var b = flanker.get_node("AI").context
	a.update_evidence(STEP, a.perception.can_see_player())
	b.update_evidence(STEP, b.perception.can_see_player())
	check(a.sees_player and not b.sees_player and not b.fresh_shared_contact().is_empty(), "%.1fm fixture starts with real front sight and a frozen shared report, using the saved arena navigation and walls" % distance)
	check(a.is_arena_active() and b.is_arena_active() and not front.get_node("AI").is_physics_processing() and not flanker.get_node("AI").is_physics_processing(), "%.1fm fixture uses valid real spawns and exactly one explicit normal AI driver" % distance)
	return {"scene": scene, "arena": arena, "player": player, "front": front, "flanker": flanker}

func _real_navigation(distance: float) -> void:
	var fixture: Dictionary = await _fixture(distance)
	var context = fixture.flanker.get_node("AI").context
	var anchor: Vector3 = fixture.player.global_position
	var proposals: Array = _proposals(context, anchor)
	var accepted := 0
	var south := false
	var short_real_paths := true
	var has_bent_leg := false
	for proposal: Dictionary in proposals:
		var assessment: Dictionary = Route.assess(context, proposal)
		if assessment.is_empty(): continue
		accepted += 1
		south = south or assessment.position.z > anchor.z
		var previous: Vector3 = fixture.flanker.global_position
		var total := 0.0
		for checkpoint: Vector3 in assessment.checkpoints:
			var path: PackedVector3Array = context.cover_selection._path_to(previous, checkpoint)
			var length: float = context.cover_selection._path_length_from_path(path)
			short_real_paths = short_real_paths and not path.is_empty() and length <= 2.011 and Route.safe_path(path, anchor)
			has_bent_leg = has_bent_leg or (path.size() > 2 and length > previous.distance_to(checkpoint) + 0.01)
			total += length
			previous = checkpoint
		short_real_paths = short_real_paths and assessment.position.is_equal_approx(proposal.position) and is_equal_approx(assessment.route_seconds, total / fixture.flanker.move_speed) and assessment.route_seconds <= 13.001
	check(accepted > 0 and south, "%.1fm has a genuinely reachable southern flank through the existing arena, rather than only a mathematical proposal" % distance)
	check(accepted > 0 and short_real_paths, "%.1fm actual navigation corners remain short safe execution legs with truthful total time and an unchanged final destination" % distance)
	check(accepted > 0 and has_bent_leg, "%.1fm short-leg paths retain real obstacle corners rather than walking the chord between checkpoint endpoints" % distance)
	var outside: Vector3 = fixture.arena.to_global(Vector3(0, 0, -5.3))
	var invalid := {"position": outside, "checkpoints": PackedVector3Array([outside]), "flank_anchor": anchor}
	check(Route.assess(context, invalid).is_empty(), "%.1fm still rejects a mathematical point beyond the actual northern arena boundary" % distance)
	print("FAR_FLANK_GEOMETRY ", JSON.stringify({"distance": distance, "proposals": proposals.size(), "accepted": accepted, "south": south}))
	await _dispose(fixture)

func _blocked_endpoint_contract() -> void:
	var fixture: Dictionary = await _fixture(12.5, 1.5)
	var context = fixture.flanker.get_node("AI").context
	var action = fixture.flanker.get_node("AI").actions[&"cooperate"]
	var blocked := 0
	for proposal: Dictionary in _proposals(context, fixture.player.global_position):
		if Route.assess(context, proposal).is_empty(): continue
		var origin: Vector3 = fixture.flanker.get_posture_muzzle_position(false, proposal.position)
		var target: Vector3 = context.known_target_point(fixture.player.global_position)
		if context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)): continue
		if action._assess_flank(proposal).is_empty(): blocked += 1
	check(blocked > 0, "The former z=1.5 runtime setup retains its real navigation but rejects a western endpoint whose complete gun line is blocked by CoverA")
	await _dispose(fixture)

func _information_contract() -> void:
	var fixture: Dictionary = await _fixture(12.5, 3.0)
	var context = fixture.flanker.get_node("AI").context
	var action = fixture.flanker.get_node("AI").actions[&"cooperate"]
	var assessment: Dictionary = {}
	for proposal: Dictionary in _proposals(context, fixture.player.global_position):
		assessment = action._assess_flank(proposal)
		if not assessment.is_empty(): break
	check(not assessment.is_empty(), "Shared flank information contract begins with a real geometrically legal final firing lane")
	if not assessment.is_empty():
		var endpoint: Vector3 = assessment.destination.path[-1]
		var candidate: Dictionary = action._fresh_flank_candidate(assessment)
		check(endpoint.distance_to(fixture.player.global_position) > context.perception.sight_distance and is_equal_approx(assessment.information, context.utility_horizon_seconds) and is_equal_approx(candidate.outcome.information_loss, context.utility_horizon_seconds), "Both initial and refreshed shared flank predictions keep the full information loss when the next short segment is outside sight range")
	var hidden: Vector3 = fixture.arena.to_global(Vector3(-5, 0, 1.5))
	var report: Dictionary = context.fresh_shared_contact()
	var eye: Vector3 = fixture.flanker.get_posture_eye_position(false, hidden)
	check(not report.is_empty() and hidden.distance_to(report.position) < context.perception.sight_distance and not context.cover_selection.has_clear_line(eye, report.aim_position) and is_equal_approx(action._flank_information(hidden, 0.25), context.utility_horizon_seconds), "A short shared flank arrival behind a real hard wall cannot claim restored observation")
	var clear: Vector3 = fixture.arena.to_global(Vector3(3, 0, 3))
	check(action._flank_information(clear, 0.25) < context.utility_horizon_seconds, "A reachable in-range clear observation point retains its actual shared information recovery")
	await _dispose(fixture)

func _dispose(fixture: Dictionary) -> void:
	fixture.scene.queue_free()
	await process_frame
	await physics_frame
