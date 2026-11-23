extends SceneTree

const Coverage = preload("res://scripts/enemy/services/enemy_search_coverage.gd")
var checks := 0
var failures := 0

class RouteProbe:
	extends RefCounted
	var map: RID
	var calls := 0
	var blocked := false
	func _path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
		calls += 1
		return PackedVector3Array() if blocked else NavigationServer3D.map_get_path(map, from, to, true, 1)

class ObservationProbe:
	extends RefCounted
	var observable := true
	func can_observe_position(_position: Vector3) -> bool:
		return observable

class ContextProbe:
	extends RefCounted
	var actor: CharacterBody3D
	var agent: NavigationAgent3D
	var navigation_region: NavigationRegion3D
	var cover_selection := RouteProbe.new()
	var perception := ObservationProbe.new()
	var free_queries := 0
	var reports: Array = []
	var evidence_elapsed_seconds := 1.0
	var utility_unseen_seconds := 1.0
	var last_seen_direction := Vector3.ZERO
	var noise_search_origin := Vector3.INF
	func cooperation_target_evidence() -> Dictionary: return {}
	func cooperation_checked_points() -> Array: return []
	func cooperation_search_available(_point: Vector3, _radius: float) -> bool: return true
	func setting(_group, _key, fallback): return fallback
	func has_combat_contact() -> bool: return false
	func _horizontal_distance(point: Vector3) -> float: return _horizontal_distance_between(actor.global_position, point)
	func cooperation_enabled() -> bool:
		return true
	func cooperation_snapshot() -> Dictionary:
		return {"members": [{"id": -1, "can_cooperate": true}]}
	func _horizontal_distance_between(a: Vector3, b: Vector3) -> float:
		return Vector2(a.x - b.x, a.z - b.z).length()
	func is_position_free(_point: Vector3) -> bool:
		free_queries += 1
		return true
	func cooperation_publish_checked(points: PackedVector3Array) -> void:
		reports.append(points)


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1
	print(("PASS " if value else "FAIL ") + label)


func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var region := NavigationRegion3D.new()
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-4, 0.5, -4), Vector3(-4, 0.5, 4), Vector3(4, 0.5, 4), Vector3(4, 0.5, -4)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	world.add_child(region)
	var actor := CharacterBody3D.new()
	world.add_child(actor)
	actor.position = Vector3(-3, 0.5, -3)
	var agent := NavigationAgent3D.new()
	actor.add_child(agent)
	for _frame in 8: await physics_frame
	for _frame in 120:
		if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) > 0: break
		await physics_frame
	NavigationServer3D.map_force_update(agent.get_navigation_map())
	var context := ContextProbe.new()
	context.actor = actor
	context.agent = agent
	context.navigation_region = region
	context.cover_selection.map = agent.get_navigation_map()
	var coverage := Coverage.new()
	var origin := Vector3(0, 0.5, 0)
	coverage.begin_build(context, origin, 2.0, 2.0, 0.65)
	check(context.free_queries == 0 and context.cover_selection.calls == 0, "begin_build only freezes grid inputs, never queries the whole area")
	check(coverage.has_pending_preparation() and coverage.fraction() == 0.0, "Empty warmup is not a completed search")
	var steps := 0
	var bounded := true
	while coverage.has_pending_preparation() and coverage.sample_count == 0 and steps < 30:
		var before: int = context.cover_selection.calls
		coverage.advance_preparation_one()
		bounded = bounded and context.cover_selection.calls - before <= 1
		steps += 1
	check(coverage.sample_count == 1 and coverage.uncovered.size() == 1, "Each accepted incremental sample enters both pending work and personal denominator")
	if coverage.pending.is_empty():
		print("FIXTURE navigation map=", agent.get_navigation_map(), " region_map=", region.get_navigation_map(),
			" iteration=", NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()),
			" closest=", NavigationServer3D.region_get_closest_point(region.get_rid(), origin),
			" path=", context.cover_selection._path_to(actor.global_position, origin), " free_queries=", context.free_queries)
		world.free()
		quit(1)
		return
	coverage.mark(coverage.pending[0])
	check(coverage.fraction() == 0.0 and coverage.uncovered.is_empty(), "Checking the first ready sample cannot complete an unfinished area")
	while coverage.has_pending_preparation() and steps < 100:
		var before: int = context.cover_selection.calls
		coverage.advance_preparation_one()
		bounded = bounded and context.cover_selection.calls - before <= 1
		steps += 1
	check(bounded and steps == 25, "One budget step consumes at most one raw grid point and one strict route query")
	check(coverage.sample_count == 13 and coverage.uncovered.size() == 12, "Preparation retains full original area denominator despite partial observations")
	check(is_equal_approx(coverage.fraction(), 1.0 / 13.0), "Final coverage measures actual personal observations over the whole accepted area")
	var legacy := Coverage.new()
	legacy.build(context, origin, 2.0, 2.0, 0.65)
	check(legacy.sample_count == coverage.sample_count, "Original synchronous single-person geometry density and completed denominator remain equivalent")
	context.perception.observable = false
	var unobserved: int = coverage.uncovered.size()
	coverage.mark(origin)
	check(coverage.uncovered.size() == unobserved and context.reports.size() == 1, "Arrival without actual visibility does not mark samples or publish checks")
	var query_start: int = context.cover_selection.calls
	var denominator: int = coverage.sample_count
	var remaining: int = coverage.pending.size()
	check(coverage.take_next(origin).is_empty() and coverage.has_pending_preparation() and context.cover_selection.calls == query_start,
		"Incremental selection waits for Spatial without doing a route query or ending the round")
	context.cover_selection.blocked = true
	var retry_bounded := true
	for _step in 3:
		var before: int = context.cover_selection.calls
		coverage.advance_preparation_one()
		retry_bounded = retry_bounded and context.cover_selection.calls - before <= 1 and coverage.take_next(origin).is_empty()
	check(retry_bounded and coverage.pending.size() == remaining - 3 and coverage.sample_count == denominator and coverage.uncovered.size() == unobserved,
		"A newly blocked area consumes one retry per budget point and preserves untried work and coverage denominator")
	context.cover_selection.blocked = false
	coverage.advance_preparation_one()
	var selected := coverage.take_next(origin)
	check(not selected.is_empty() and not selected.path.is_empty() and context.cover_selection.calls == query_start + 4,
		"Clearing the obstruction yields a genuinely revalidated destination through the original queue")
	context.cover_selection.blocked = true
	coverage.begin_build(context, origin, 2.0, 2.0, 0.65)
	for _step in 25: coverage.advance_preparation_one()
	check(coverage.sample_count == 0 and coverage.fraction() == 0.0, "Blocked routes remain unverified and an empty prepared area is not complete")
	check(not coverage.advance_preparation_one(), "Completed preparation does no further geometry work")
	coverage.reset()
	check(not coverage.has_pending_preparation() and coverage.sample_count == 0 and coverage.pending.is_empty(), "Reset cancels preparation and personal progress together")
	world.free()
	print("SEARCH PREPARATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
