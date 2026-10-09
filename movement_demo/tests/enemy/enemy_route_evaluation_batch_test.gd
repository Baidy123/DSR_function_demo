extends "res://tests/enemy/enemy_geometry_batch_test.gd"

class CountedCover extends "res://scripts/world/cover_region.gd":
	var enumerations := 0
	func get_candidates(threat: Vector3, from: Vector3) -> Array[Dictionary]:
		enumerations += 1
		return super.get_candidates(threat, from)

class CoverQueue extends RefCounted:
	var spatial
	func is_enabled() -> bool: return true
	func evaluation_channel() -> StringName: return &"cover_contract"
	func evaluation_revision() -> int: return 0
	func evaluation_priority_count() -> int: return 0
	func evaluation_weight() -> int: return 1
	func evaluation_points() -> Array: return spatial.cover_points()
	func evaluate_point(_point: Variant) -> Dictionary: return {}

class ExposureProbe extends RefCounted:
	# Observe calls at the actual Context entry. All geometry, timings and
	# nonzero exposure calculations still come from the real scene Context.
	var source
	var queried_points: Array[Vector3] = []
	var force_zero := false
	func _get(property: StringName) -> Variant: return source.get(property)
	func _exposure_geometry() -> Array: return source._exposure_geometry()
	func _horizontal_distance_between(first: Vector3, second: Vector3) -> float: return source._horizontal_distance_between(first, second)
	func _reload_exposure(point: Vector3, threat: Vector3, body_protection: float = -1.0, crouched: bool = false) -> float:
		queried_points.append(point)
		return 0.0 if force_zero else source._reload_exposure(point, threat, body_protection, crouched)

class RouteScopeQueue extends RefCounted:
	var context
	var spatial
	var exposure_probe
	var visits := 0
	var scope_active := false
	var full_result_reused := false
	var exposure_reused := false
	var sample_count := -1
	func is_enabled() -> bool: return true
	func evaluation_channel() -> StringName: return &"route_scope_contract"
	func evaluation_revision() -> int: return 0
	func evaluation_priority_count() -> int: return 0
	func evaluation_weight() -> int: return 1
	func evaluation_points() -> Array: return [context.actor.global_position + Vector3(0, 0, 1)]
	func evaluate_point(point: Variant) -> Dictionary:
		visits += 1
		if visits > 1: return {}
		scope_active = spatial._budget_evaluation_depth == 1
		var path := PackedVector3Array([point])
		var threat: Vector3 = context.actor.global_position - Vector3(5, 0, 0)
		var first: Dictionary = spatial.assess_route(exposure_probe, path, threat, 1.0, 0.0)
		var queries: int = exposure_probe.queried_points.size()
		var rays: int = context.cover_selection.environment_ray_queries
		var identical: Dictionary = spatial.assess_route(exposure_probe, path, threat, 1.0, 0.0)
		full_result_reused = first == identical and exposure_probe.queried_points.size() == queries and spatial._route_cache.size() >= 2
		spatial.assess_route(exposure_probe, path, threat, 2.0, 0.0)
		exposure_reused = exposure_probe.queried_points.size() > queries and context.cover_selection.environment_ray_queries == rays and not context._exposure_cache.is_empty()
		sample_count = spatial._route_sample_cache.size()
		return {}

## Read-only route contracts with real collision geometry, not tactical selection.
func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	var context = ai.context
	var spatial = context.spatial
	var selection = ai.cover_selection
	for body in ai.navigation_region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
	actor.global_position = Vector3(25, 0, 0)
	player.global_position = Vector3(20, 0, -4)
	var wall := StaticBody3D.new()
	var wall_shape := CollisionShape3D.new()
	wall_shape.shape = BoxShape3D.new()
	wall_shape.shape.size = Vector3(0.3, 3, 4)
	wall.add_child(wall_shape)
	scene.add_child(wall)
	wall.global_position = Vector3(22, 1.5, 6)
	for frame in 5: await physics_frame
	var gate := PhysicsGate.new()
	root.add_child(gate)
	await gate.reached
	gate.queue_free()
	var threat := Vector3(20, 0, 0)
	var point: Vector3 = actor.global_position
	var path := PackedVector3Array([point, point + Vector3(0, 0, 2)])
	var travel: float = 2.0 / actor.move_speed
	context.fire.fire_reaction_elapsed = context.fire.fire_reaction_seconds
	context.fire.fire_pause_remaining = 0.0
	var frame_id := Engine.get_physics_frames()
	context.begin_geometry_evaluation()
	var rays_before: int = selection.environment_ray_queries
	var ordinary: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0)
	check(is_equal_approx(ordinary.seconds, travel) and is_equal_approx(ordinary.exposure, travel), "Open straight route preserves original travel time and exposure integral")
	check(selection.environment_ray_queries - rays_before == 12 and context._exposure_cache.size() == 4 and context._exposure_cache.has([point + Vector3(0, 0, 0.25), threat, -1.0, false]) and context._exposure_cache.has([point + Vector3(0, 0, 1.75), threat, -1.0, false]), "All four original half-metre midpoints keep all three physical exposure rays")
	var rays: int = selection.environment_ray_queries
	var fast_reload: Dictionary = spatial.assess_route(context, path, threat, 2.0, travel * 0.5)
	var delayed: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0, false, travel * 0.25)
	check(is_equal_approx(fast_reload.seconds, travel * 0.75) and is_equal_approx(fast_reload.exposure, travel * 0.75), "Reload slowdown receives its own time and exposure integration")
	check(is_equal_approx(delayed.seconds, travel * 1.25) and is_equal_approx(delayed.exposure, travel), "A delayed route keeps its own start time and does not duplicate pre-route exposure")
	check(spatial._route_cache.size() == 3 and selection.environment_ray_queries == rays, "Different timing inputs keep independent results while reusing identical exposure queries")
	context.begin_geometry_evaluation()
	ordinary.exposure = 99.0
	var unchanged: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0)
	check(is_equal_approx(unchanged.exposure, travel), "A consumer cannot mutate another evaluation through its returned result dictionary")
	context.end_geometry_evaluation()
	check(spatial._geometry_evaluation_depth == 1 and spatial._route_cache.size() == 3 and not context._exposure_cache.is_empty(), "Nested evaluation retains outer route and exposure results")
	var shooting: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0, true)
	context.fire.fire_pause_remaining = travel + 1.0
	var paused: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0, true)
	context.fire.fire_pause_remaining = 0.0
	check(shooting.fire_seconds > 0.0 and paused.fire_seconds == 0.0 and shooting.exposure == paused.exposure, "Reused geometry never reuses a prior firing window after real burst pause changes")
	rays = selection.environment_ray_queries
	spatial.assess_route(context, path, threat + Vector3(0, 0, 2), 1.0, 0.0)
	var changed_start: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0, false, 0.0, point - Vector3(0, 0, 1))
	check(selection.environment_ray_queries > rays and is_equal_approx(changed_start.seconds, travel * 1.5), "Different known threat origins and actual starting positions receive fresh geometry and time")
	rays = selection.environment_ray_queries
	var late: Dictionary = spatial.assess_route(context, PackedVector3Array([point + Vector3(0, 0, 3)]), threat, 1.0, 0.0, false, context.utility_horizon_seconds)
	check(late.exposure == 0.0 and late.seconds > context.utility_horizon_seconds and selection.environment_ray_queries == rays, "A route starting after the horizon preserves full time without eagerly tracing unused samples")
	context.end_geometry_evaluation()
	check(spatial._geometry_evaluation_depth == 0 and spatial._route_cache.is_empty() and context._exposure_cache.is_empty() and context._exposure_geometry_cache.is_empty(), "Outermost batch releases route, exposure and posture snapshots")
	_move_body(wall, Vector3(22, 1.5, 0))
	var blocked: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0, true)
	check(blocked.exposure == 0.0 and blocked.fire_seconds == 0.0, "Same-frame wall insertion after batch exit immediately blocks both exposure and firing")
	_move_body(wall, Vector3(22, 1.5, 6))
	var reopened: Dictionary = spatial.assess_route(context, path, threat, 1.0, 0.0, true)
	check(reopened.exposure > 0.0 and reopened.fire_seconds > 0.0 and Engine.get_physics_frames() == frame_id, "Same-frame wall removal restores live results without waiting for a new frame")
	check(spatial._route_cache.is_empty() and context._exposure_cache.is_empty(), "Execution queries do not populate planning caches")
	wall_shape.shape.size = Vector3(0.3, 1.25, 4)
	_move_body(wall, Vector3(22, 0.625, 0))
	context.begin_geometry_evaluation()
	var standing: float = context._reload_exposure(point, threat)
	var crouching: float = context._reload_exposure(point, threat, -1.0, true)
	var protected: float = context._reload_exposure(point, threat, 1.0)
	check(standing > 0.0 and crouching == 0.0 and protected == 0.0, "Standing, crouched and explicit body-protection inputs keep independent exposure results")
	context.end_geometry_evaluation()
	var original_eye: float = actor.standing_eye_height
	actor.standing_eye_height = 0.8
	context.begin_geometry_evaluation()
	check(context._reload_exposure(point, threat) == 0.0, "A new batch captures changed real posture offsets instead of previous-frame geometry")
	context.end_geometry_evaluation()
	actor.standing_eye_height = original_eye
	context.begin_geometry_evaluation()
	check(context._reload_exposure(point, threat) > 0.0, "Restoring posture obtains a fresh snapshot in the same physics frame")
	context.end_geometry_evaluation()
	check(Engine.get_physics_frames() == frame_id, "All invalidation and posture cases are genuine same-frame checks")
	_route_sample_contract(context)
	_route_scope_contract(context)
	_risk_contract(context)
	_cover_generation_contract(scene)
	await _cover_preparation_contract(context, scene)
	print("ROUTE EVALUATION BATCH: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await scene.tree_exited
	quit(1 if failures else 0)

func _route_sample_contract(context) -> void:
	var probe := preload("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new()
	var exposure_probe := ExposureProbe.new()
	exposure_probe.source = context
	probe.context = context
	var original_horizon: float = context.utility_horizon_seconds
	var origin: Vector3 = context.actor.global_position
	var threat := origin - Vector3(5, 0, 0)
	# Include a zero-length segment, fractional lengths and navigation height.
	var path := PackedVector3Array([origin, origin + Vector3(0, 0, 0.7), origin + Vector3(1.1, 0.2, 0.7), origin + Vector3(1.1, 0.2, 1.3)])
	var variants: Array = [[1.0, 0.0, 0.0, original_horizon, false], [2.0, 0.12, 0.0, original_horizon, false],
		[0.6, 0.27, 0.11, original_horizon, false], [1.3, 0.0, original_horizon - 0.16, original_horizon, false],
		[2.0, 0.5, 0.0, 0.22, false], [1.7, 0.08, 0.07, original_horizon, true]]
	var expected: Array[Dictionary] = []
	for variant: Array in variants:
		context.utility_horizon_seconds = variant[3]
		expected.append(probe.assess_route(exposure_probe, path, threat, variant[0], variant[1], variant[4], variant[2]))
	exposure_probe.queried_points.clear()
	context.begin_geometry_evaluation()
	probe.begin_geometry_evaluation()
	var count := 0
	var exact := true
	for index in variants.size():
		var variant: Array = variants[index]
		context.utility_horizon_seconds = variant[3]
		var actual: Dictionary = probe.assess_route(exposure_probe, path, threat, variant[0], variant[1], variant[4], variant[2])
		exact = exact and actual == expected[index]
		if index == 0: count = exposure_probe.queried_points.size()
	check(exact, "Shared samples preserve exact original per-sample floating-point integration for every timing and firing variant")
	check(count > 0 and exposure_probe.queried_points.size() == count and probe._route_sample_cache.size() == 1 and probe._route_cache.size() == variants.size(), "Timing variants reuse observed geometry through the actual Context exposure entry while retaining all complete route results")
	var points_before := exposure_probe.queried_points.duplicate()
	probe.begin_geometry_evaluation()
	probe.end_geometry_evaluation()
	check(not probe._route_sample_cache.is_empty(), "Ending a nested sample batch retains the outer geometry")
	context.utility_horizon_seconds = original_horizon
	var after_fire: Dictionary = probe.assess_route(exposure_probe, path, threat, 1.0, 0.0, false, 0.01)
	check(exposure_probe.queried_points == points_before and is_equal_approx(after_fire.exposure, expected[0].exposure), "Firing height adjustment cannot mutate the shared navigation sample positions")
	probe.end_geometry_evaluation()
	context.end_geometry_evaluation()
	check(probe._route_sample_cache.is_empty() and probe._route_cache.is_empty(), "Outermost exit releases both complete results and sample snapshots")

	# A late first consumer must not precompute exposure for a later early consumer.
	exposure_probe.queried_points.clear()
	context.begin_geometry_evaluation()
	probe.begin_geometry_evaluation()
	var late: Dictionary = probe.assess_route(exposure_probe, path, threat, 1.0, 0.0, false, original_horizon)
	check(late.exposure == 0.0 and late.seconds > original_horizon and exposure_probe.queried_points.is_empty(), "A first consumer after the horizon creates no exposure queries")
	context.utility_horizon_seconds = 0.03
	probe.assess_route(exposure_probe, path, threat, 1.0, 0.0)
	var partial := exposure_probe.queried_points.size()
	check(partial == 1, "A short horizon lazily observes only its first positive-duration sample")
	context.utility_horizon_seconds = original_horizon
	probe.assess_route(exposure_probe, path, threat, 1.0, 0.0)
	check(exposure_probe.queried_points.size() == count, "Extending the horizon fills only previously unobserved sample slots")
	probe.end_geometry_evaluation()
	context.end_geometry_evaluation()
	exposure_probe.queried_points.clear()
	exposure_probe.force_zero = true
	context.begin_geometry_evaluation()
	probe.begin_geometry_evaluation()
	var zero: Dictionary = probe.assess_route(exposure_probe, path, threat, 1.0, 0.0)
	probe.assess_route(exposure_probe, path, threat, 2.0, 0.0)
	check(zero.exposure == 0.0 and exposure_probe.queried_points.size() == count, "Zero physical exposure remains a reusable computed value instead of a cache miss")
	probe.end_geometry_evaluation()
	context.end_geometry_evaluation()
	exposure_probe.force_zero = false
	exposure_probe.queried_points.clear()
	var live: Dictionary = probe.assess_route(exposure_probe, path, threat, 1.0, 0.0)
	check(live == expected[0] and exposure_probe.queried_points.size() == count and probe._route_sample_cache.is_empty(), "After a batch, live evaluation calls the Context exposure entry again and creates no sample cache")
	context.utility_horizon_seconds = original_horizon

func _route_scope_contract(context) -> void:
	var original_spatial = context.spatial
	var probe := preload("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new()
	var exposure_probe := ExposureProbe.new()
	exposure_probe.source = context
	probe.context = context
	context.spatial = probe
	context.routes.reset()
	var queue := RouteScopeQueue.new()
	queue.context = context
	queue.spatial = probe
	queue.exposure_probe = exposure_probe
	probe.register(queue)
	context.begin_geometry_evaluation()
	var origin: Vector3 = context.actor.global_position
	var threat := origin - Vector3(5, 0, 0)
	probe.assess_route(exposure_probe, PackedVector3Array([origin + Vector3(1, 0, 0)]), threat, 1.0, 0.0)
	var outer_samples: Dictionary = probe._route_sample_cache.duplicate(true)
	var outer_results: Dictionary = probe._route_cache.duplicate(true)
	var outer_exposure: Dictionary = context._exposure_cache.duplicate()
	probe.advance_evaluation()
	check(queue.visits > 0 and queue.scope_active and queue.sample_count == outer_samples.size(), "The real budget advance evaluates its points without preparing any new sample arrays")
	check(queue.full_result_reused and queue.exposure_reused, "Budget evaluation retains complete route-result reuse and ordinary exposure-query reuse")
	var preserved := probe._route_sample_cache == outer_samples
	for key in outer_results: preserved = preserved and probe._route_cache.get(key) == outer_results[key]
	for key in outer_exposure: preserved = preserved and context._exposure_cache.get(key) == outer_exposure[key]
	check(preserved and probe._geometry_evaluation_depth == 1 and probe._budget_evaluation_depth == 0, "A nested budget scan preserves all preexisting outer samples, results and exposure snapshots")
	var visits := queue.visits
	probe.advance_evaluation()
	check(queue.visits == visits and probe._geometry_evaluation_depth == 1 and probe._budget_evaluation_depth == 0, "A repeated same-frame advance balances neither scope twice and performs no duplicate scan")
	probe.assess_route(exposure_probe, PackedVector3Array([origin + Vector3(0, 0, 1)]), threat, 1.5, 0.0)
	check(probe._route_sample_cache.size() == outer_samples.size() + 1, "Candidate comparison after advance resumes sample reuse within the same outer batch")
	context.end_geometry_evaluation()
	check(probe._route_sample_cache.is_empty() and probe._route_cache.is_empty() and context._exposure_cache.is_empty() and probe._budget_evaluation_depth == 0, "Outermost exit releases every cache without retaining budget scope")
	context.spatial = original_spatial

func _risk_contract(context) -> void:
	context.actor.health = context.actor.max_health * 0.5
	context.recent_damage_pressure = 0.25
	context.nearby_shot_pressure = 0.1
	context.utility_threat_age_seconds = 1.0
	context.utility_threat_half_life_seconds = 2.0
	context.utility_risk_weight = 3.0
	context.sees_player = true
	context.last_known_position = context.actor.global_position + Vector3(2, 0, 0)
	var safe_distance := maxf(1.0, float(context.setting(&"tactics", &"ranged_min_distance", 4.0)))
	var expected := 3.0 * (pow(0.5, 0.5) * 0.85 + 2.0 * clampf(1.0 - 2.0 / safe_distance, 0.0, 1.0))
	var frame_id := Engine.get_physics_frames()
	context.begin_geometry_evaluation()
	var initial: float = context._reload_risk_aversion()
	check(is_equal_approx(initial, expected) and context._risk_evaluation_cached, "Risk reuse preserves the original health, pressure, age and visible close-distance formula")
	context.begin_geometry_evaluation()
	check(is_equal_approx(context._reload_risk_aversion(), initial), "Nested read-only evaluations share the same risk value")
	context.end_geometry_evaluation()
	check(context._risk_evaluation_cached and is_equal_approx(context._reload_risk_aversion(), initial), "Ending a nested batch retains the outer risk snapshot")
	context.end_geometry_evaluation()
	check(not context._risk_evaluation_cached, "The outermost batch invalidates its risk snapshot")
	context.sees_player = false
	context.actor.health = context.actor.max_health
	context.recent_damage_pressure = 0.0
	context.nearby_shot_pressure = 0.0
	check(context._reload_risk_aversion() == 0.0 and not context._risk_evaluation_cached, "Live execution immediately reads changed pressure and contact in the same frame")
	context.utility_threat_age_seconds = 2.0
	context.recent_damage_pressure = 0.5
	context.utility_risk_weight = 4.0
	context.begin_geometry_evaluation()
	check(is_equal_approx(context._reload_risk_aversion(), 1.0) and Engine.get_physics_frames() == frame_id, "A new same-frame batch captures current age, pressure and risk weight")
	context.end_geometry_evaluation()

func _cover_generation_contract(scene: Node) -> void:
	var cover = preload("res://scripts/world/cover_region.gd").new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(4, 2, 1)
	cover.add_child(collision)
	cover.hide_length_ratio = 0.5
	cover.short_hide_length_ratio = 0.5
	cover.wall_gap = 0.4
	cover.hide_depth = 0.8
	cover.sample_spacing = 1.0
	cover.peek_outset = 0.3
	scene.add_child(cover)
	# Hand-calculated long-face seven points followed by short-face five points.
	var golden: Array[Vector3] = [Vector3(-0.6, -1, -0.9),
		Vector3(-1, -1, -1.1), Vector3(-1, -1, -1.5), Vector3(0, -1, -1.1), Vector3(0, -1, -1.5), Vector3(1, -1, -1.1), Vector3(1, -1, -1.5),
		Vector3(-2.4, -1, 0.25), Vector3(-2.6, -1, -0.25), Vector3(-3.0, -1, -0.25), Vector3(-2.6, -1, 0.25), Vector3(-3.0, -1, 0.25)]
	var transforms: Array[Transform3D] = [Transform3D(Basis.IDENTITY, Vector3(32, 1, 6)),
		Transform3D(Basis(Vector3.UP, 0.67), Vector3(34, 1, 4)),
		Transform3D(Basis(Vector3.UP, -0.4).scaled(Vector3(1.4, 1.0, 0.8)), Vector3(33, 1, 7))]
	for box_transform: Transform3D in transforms:
		cover.global_transform = box_transform
		var candidates: Array = cover.get_candidates(collision.to_global(Vector3(4, 0, 3)), collision.to_global(Vector3(-0.6, -1, 2)))
		var same := candidates.size() == golden.size()
		for index in mini(candidates.size(), golden.size()):
			same = same and candidates[index].hide.is_equal_approx(collision.to_global(golden[index])) and candidates[index].cover == cover and not candidates[index].get("crouch", false)
			var peeks: Array = candidates[index].peeks
			var left := Vector3(-2.3, -1, 0) if index < 7 else Vector3(0, -1, -0.8)
			var right := Vector3(2.3, -1, 0) if index < 7 else Vector3(0, -1, 0.8)
			same = same and peeks.size() == 2 and peeks[0].is_equal_approx(collision.to_global(left)) and peeks[1].is_equal_approx(collision.to_global(right))
		check(same, "All cover points and both peek orders retain their golden geometry after a current transform change")
	cover.global_transform = transforms[0]
	collision.shape.size = Vector3(1, 2, 4)
	var swapped: Array = cover.get_candidates(collision.to_global(Vector3(3, 0, 4)), collision.to_global(Vector3(2, -1, -0.6)))
	var same_swapped := swapped.size() == golden.size()
	for index in mini(swapped.size(), golden.size()):
		var expected := Vector3(golden[index].z, golden[index].y, golden[index].x)
		same_swapped = same_swapped and swapped[index].hide.is_equal_approx(collision.to_global(expected))
	check(same_swapped, "Changing the box long axis immediately swaps all original cover sample coordinates")
	collision.shape.size = Vector3(2, 2, 2)
	var square: Array = cover.get_candidates(collision.to_global(Vector3(4, 0, 3)), collision.to_global(Vector3(-0.6, -1, 2)))
	check(square.size() == 10 and square[0].hide.is_equal_approx(collision.to_global(Vector3(-0.5, -1, -1.4))) and square[5].hide.is_equal_approx(collision.to_global(Vector3(-1.4, -1, 0.5))), "An equal-sided box retains the original X-first face ordering")
	collision.shape.size = Vector3(4, 1, 1)
	cover.low_cover = true
	var low: Array = cover.get_candidates(collision.to_global(Vector3(4, 0, 3)), collision.to_global(Vector3(-0.6, -0.5, 2)))
	check(not low.is_empty() and low.all(func(candidate): return candidate.get("crouch", false) and candidate.stand == candidate.hide and candidate.peeks.is_empty()), "A dynamic low-cover change retains its original crouched-band candidate branch")
	cover.low_cover = false
	collision.shape.size = Vector3(4, 2, 1)
	cover.global_transform = Transform3D.IDENTITY
	var zero_axis: Array = cover.get_candidates(Vector3(0, 0, 3), Vector3(-0.6, -1, 2))
	var near_axis: Array = cover.get_candidates(Vector3(0.0005, 0, 3), Vector3(-0.6, -1, 2))
	var boundary_axis: Array = cover.get_candidates(Vector3(0.001, 0, 3), Vector3(-0.6, -1, 2))
	check(zero_axis.size() == 7 and near_axis.size() == 7 and boundary_axis.size() == 12, "Known-threat face selection preserves the original zero-axis and 0.001 boundary")

func _prepared_points(spatial) -> Array:
	spatial._preparing_cover_points = true
	spatial._prepared_cover_points_ready = false
	spatial._prepared_cover_points = []
	var points: Array = spatial.cover_points()
	spatial._preparing_cover_points = false
	spatial._prepared_cover_points_ready = false
	spatial._prepared_cover_points = []
	return points

func _changed_cover_input(context, cover, description: String) -> void:
	# The ordinary entry performs the original uncached enumeration every time.
	var expected: Array = context.spatial.cover_points()
	var before: int = cover.enumerations
	var actual := _prepared_points(context.spatial)
	check(actual == expected and cover.enumerations == before + 1, description)

func _cover_preparation_contract(context, scene: Node) -> void:
	var spatial = context.spatial
	var original_region = context.navigation_region
	var body_physics: bool = context.actor.is_physics_processing()
	context.actor.set_physics_process(false)
	var region := NavigationRegion3D.new()
	scene.add_child(region)
	var cover := CountedCover.new()
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(4, 2, 1)
	cover.add_child(collision)
	region.add_child(cover)
	context.navigation_region = region
	context.is_alerted = true
	context.noise_search_origin = Vector3.INF
	context.last_known_position = Vector3(4, 0, 3)
	spatial.clear_cover_preparation()
	# Exercise the production end-of-advance release, not just the helper below.
	var advancing = preload("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new()
	advancing.context = context
	var queue := CoverQueue.new()
	queue.spatial = advancing
	advancing.register(queue)
	context.spatial = advancing
	# Wait for actual navigation synchronization rather than assuming a fixed
	# number of frames drains the scene's preceding geometry mutations.
	var previous_iteration := -1
	var stable_frames := 0
	for frame in 30:
		await physics_frame
		var iteration := NavigationServer3D.map_get_iteration_id(context.agent.get_navigation_map())
		stable_frames = stable_frames + 1 if iteration == previous_iteration else 0
		previous_iteration = iteration
		if stable_frames >= 3: break
	check(stable_frames >= 3, "The pure-enumeration fixture starts after actual navigation synchronization")
	advancing.advance_evaluation()
	var first_points: Array = advancing.jobs[0].points.duplicate(true)
	var first_key: Array = advancing._cover_points_key.duplicate(true)
	var first_enumerations: int = cover.enumerations
	check(not first_points.is_empty() and advancing._cover_points_cache == first_points, "A completed real advance retains its full pure cover enumeration")
	context.last_known_position.x += 0.3
	await physics_frame
	advancing.advance_evaluation()
	if advancing.jobs[0].points != first_points or advancing._cover_points_cache != first_points or cover.enumerations != first_enumerations:
		print("COVER_PREPARATION_TRACE first_key=", first_key, " next_key=", advancing._cover_points_key, " counts=", first_enumerations, "/", cover.enumerations, " points=", first_points.size(), "/", advancing.jobs[0].points.size())
	check(advancing.jobs[0].points == first_points and advancing._cover_points_cache == first_points and cover.enumerations == first_enumerations, "The next real same-side rebuild retains all points without enumerating them again")
	context.spatial = spatial
	_changed_cover_input(context, cover, "First preparation exactly matches ordinary cover enumeration and ordering")
	context.last_known_position += Vector3(0.03, 0, 0.02)
	var expected: Array = spatial.cover_points()
	var before: int = cover.enumerations
	var reused := _prepared_points(spatial)
	check(reused == expected and cover.enumerations == before, "Same-side target movement reuses pure enumeration while retaining identical points")
	reused[0].hide = Vector3.INF
	reused[0].crouch = true
	reused.clear()
	check(_prepared_points(spatial) == expected and cover.enumerations == before, "Returned arrays and point dictionaries cannot corrupt later preparations")
	spatial.cover_points()
	spatial.cover_points()
	check(cover.enumerations == before + 2, "Calls outside explicit preparation always enumerate current geometry")
	context.last_known_position.x = -4.0
	_changed_cover_input(context, cover, "Crossing a real cover face rebuilds the original ordered candidates")
	context.actor.global_position += Vector3(0.01, 0, 0)
	_changed_cover_input(context, cover, "Any actual actor displacement refreshes the nearest cover sample")
	collision.shape.size.x += 0.2
	_changed_cover_input(context, cover, "A current box size change cannot reuse old cover points")
	collision.transform = Transform3D(Basis(Vector3.UP, 0.35).scaled(Vector3(1.2, 1, 0.8)), Vector3(0.3, 0.1, -0.2))
	_changed_cover_input(context, cover, "Collision-child translation rotation and scale are full enumeration inputs")
	cover.hide_length_ratio = 0.6
	cover.short_hide_length_ratio = 0.4
	cover.wall_gap += 0.05
	cover.hide_depth += 0.1
	cover.sample_spacing += 0.1
	_changed_cover_input(context, cover, "Current hide-band configuration refreshes all original points")
	collision.transform = Transform3D.IDENTITY
	collision.shape.size = Vector3(4, 1, 1)
	cover.low_cover = true
	context.last_known_position = Vector3(0.000999, 0, 3)
	_changed_cover_input(context, cover, "Switching to actual low cover uses its original continuous-band branch")
	context.last_known_position.x = 0.001
	_changed_cover_input(context, cover, "The low-wall nearest-point threshold retains its exact equality behavior")
	context.last_known_position.x = 0.001001
	# Vector precision may already place literal 0.001 above the strict boundary;
	# compare the real classifications, never force a mathematical equality.
	var boundary_key: Array = spatial._cover_points_key.duplicate(true)
	expected = spatial.cover_points()
	before = cover.enumerations
	var outside := _prepared_points(spatial)
	check(outside == expected and (spatial._cover_points_key == boundary_key or cover.enumerations == before + 1), "Low-wall strict band-side selection always matches the uncached implementation")
	context.last_known_position.x = -0.001
	_changed_cover_input(context, cover, "The opposite signed low-wall threshold cannot reuse a positive-side result")
	cover.attack_sample_spacing += 0.1
	_changed_cover_input(context, cover, "Low-wall attack-band spacing is part of the pure cover enumeration key")
	var box: Shape3D = collision.shape
	collision.shape = null
	_changed_cover_input(context, cover, "A missing shape keeps the original safe empty enumeration")
	collision.shape = SphereShape3D.new()
	_changed_cover_input(context, cover, "A non-box shape cannot reuse an earlier box enumeration")
	cover.remove_child(collision)
	var wrong_child := Node3D.new()
	wrong_child.name = "CollisionShape3D"
	cover.add_child(wrong_child)
	_changed_cover_input(context, cover, "A same-named non-collision child keeps the original safe empty enumeration")
	cover.remove_child(wrong_child)
	wrong_child.free()
	collision.shape = box
	cover.add_child(collision)
	_changed_cover_input(context, cover, "Restoring a valid collision box rebuilds all original candidates")
	var original_eye: float = context.actor.standing_eye_height
	collision.transform = Transform3D(Basis(Vector3.FORWARD, 0.4), Vector3(0, 1, 0))
	context.last_known_position = Vector3(0, 0, 3)
	context.actor.standing_eye_height = 2.0
	_changed_cover_input(context, cover, "Tilted collision boxes classify the actual transformed observer eye")
	context.actor.standing_eye_height = 0.5
	_changed_cover_input(context, cover, "A changed eye height crossing the local face invalidates pure geometry reuse")
	context.actor.standing_eye_height = original_eye
	context.noise_search_origin = Vector3(1, 0, 1)
	check(_prepared_points(spatial).is_empty(), "Noise investigation cannot obtain a cached cover enumeration")
	context.noise_search_origin = Vector3.INF
	context.is_alerted = false
	check(_prepared_points(spatial).is_empty(), "Missing known threat cannot obtain a cached cover enumeration")
	context.is_alerted = true
	var replacement_region := NavigationRegion3D.new()
	scene.add_child(replacement_region)
	cover.reparent(replacement_region, true)
	context.navigation_region = replacement_region
	_changed_cover_input(context, cover, "Replacing the active navigation region refreshes the current region members")
	spatial.reset_evaluation()
	check(spatial._cover_points_key.is_empty() and spatial._cover_points_cache.is_empty() and spatial._prepared_cover_points.is_empty(), "Evaluation reset releases every pure cover preparation reference")
	_prepared_points(spatial)
	var evaluated_before: int = spatial.total_evaluated_count
	context.navigation_region = original_region
	context.detach_environment()
	check(spatial._cover_points_key.is_empty() and spatial._cover_points_cache.is_empty() and not spatial._preparing_cover_points and spatial.total_evaluated_count == evaluated_before, "Environment detach releases pure cover preparation without resetting route statistics")
	context.refresh_environment()
	context.actor.set_physics_process(body_physics)
	region.queue_free()
	replacement_region.queue_free()
