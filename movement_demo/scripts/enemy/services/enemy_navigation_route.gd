extends RefCounted

## Shared typed routes. Native link metadata is never treated as ordinary walking.
const Low = preload("res://scripts/world/low_cover_geometry.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const VAULT_LAYER := 2

static func walking(points: PackedVector3Array, revision: int = -1) -> Dictionary:
	if points.is_empty(): return {}
	var segments: Array[Dictionary] = [{"kind": &"walk", "points": points.duplicate()}]
	return _pack(segments, revision, points[-1])

static func query(context, destination: Vector3, from: Vector3 = Vector3.INF, excluded: Array = []) -> Dictionary:
	var capabilities: Array = context.member_capability_snapshot().get("capabilities", []) if context.commanded() else (context.unit.capabilities if context.unit != null else [])
	if context.actor.is_dead or not capabilities.has(&"locomotion"): return {}
	if not from.is_finite(): from = context.actor.global_position
	var registry = context.get("vault_navigation")
	if registry == null or not registry.ready: return {}
	var queries: Dictionary = context.routes.native_queries
	var work: Dictionary = queries.get(destination, {})
	if work.is_empty() or work.revision != registry.revision or work.origin.distance_to(from) > 0.5 or work.excluded != excluded or (work.done and Time.get_ticks_msec() - int(work.created) > 1000):
		work = {"revision": registry.revision, "origin": from, "excluded": excluded.duplicate(), "created": Time.get_ticks_msec(), "frame": -1,
			"segments": [], "needs_query": true, "index": 0, "waypoint": 1, "done": false, "reason": &"", "result": {}}
		if queries.size() >= 32 and not queries.has(destination): queries.erase(queries.keys()[0])
		queries[destination] = work
	if not work.done and work.frame != Engine.get_physics_frames():
		work.frame = Engine.get_physics_frames()
		if context.routes.native_deadline_usec > 0 and Time.get_ticks_usec() >= context.routes.native_deadline_usec: return {}
		if work.needs_query:
			work.segments = _prepare(context, destination, from, excluded, work)
			work.needs_query = false
			if work.has("adjacent"): return {}
		elif work.has("adjacent"):
			_advance_adjacent(context, work, destination)
			if work.has("adjacent"): return {}
		for unit in 4:
			if context.routes.native_deadline_usec > 0 and Time.get_ticks_usec() >= context.routes.native_deadline_usec: break
			context.routes.native_last_units += 1
			if work.segments.is_empty():
				work.done = true
				break
			if not _advance_validation(context, work):
				if work.has("adjacent_pool"):
					_next_adjacent(work)
					work.done = not work.has("adjacent")
				else: work.done = true
				break
			if work.index >= work.segments.size():
				work.result = _pack(work.segments, registry.revision, destination)
				if work.result.is_empty(): work.reason = &"too_many_points"
				work.done = true
				break
		if work.done: work.created = Time.get_ticks_msec()
	return work.result.duplicate(true)

static func pending(context, destination: Vector3) -> bool:
	var work: Dictionary = context.routes.native_queries.get(destination, {})
	return context.get("vault_navigation") != null and not work.is_empty() and work.revision == context.vault_navigation.revision and not work.done

## Parsing native metadata is pure; capsule/arc validation advances four units
## at a time under the caller's existing personal or squad preparation budget.
static func _prepare(context, destination: Vector3, from: Vector3, excluded: Array, work: Dictionary) -> Array[Dictionary]:
	var registry = context.get("vault_navigation")
	if registry == null or not registry.ready or not is_instance_valid(context.navigation_region): return []
	var region: NavigationRegion3D = context.navigation_region
	var target := NavigationServer3D.region_get_closest_point(region.get_rid(), destination)
	if context._horizontal_distance_between(target, destination) > 0.05 or absf(target.y - destination.y) > 0.5: return []
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = region.get_navigation_map()
	parameters.start_position = from
	parameters.target_position = target
	parameters.navigation_layers = context.agent.navigation_layers | VAULT_LAYER
	# Godot 4.7.2 drops link polygons when either region filter is nonempty.
	# Keep native filters empty and verify every returned region/link below.
	parameters.metadata_flags = 7
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	if result.path.size() > 256:
		work.reason = &"too_many_points"
		return []
	if result.path.is_empty() or result.path_types.size() != result.path.size() or result.path_owner_ids.size() != result.path.size(): return []
	if context._horizontal_distance_between(result.path[-1], destination) > 0.05: return []
	var start_nav := NavigationServer3D.region_get_closest_point(region.get_rid(), from)
	var offset := from.y - start_nav.y
	var segments: Array[Dictionary] = []
	var walk := PackedVector3Array([from])
	var index := 0
	var vaults := 0
	while index < result.path.size():
		if result.path_types[index] != NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK:
			if result.path_rids.size() != result.path.size() or result.path_rids[index] != region.get_rid(): return []
			var point: Vector3 = result.path[index] + Vector3.UP * offset
			if absf(point.y - from.y) > 0.5: return []
			if walk[-1].distance_to(point) > 0.01: walk.append(point)
			index += 1
			continue
		var owner: int = result.path_owner_ids[index]
		var connection: Dictionary = registry.resolve_link(owner)
		if connection.is_empty(): return []
		var area_failed: bool = not context.commanded() and excluded.any(func(key): return String(key).begins_with(String(connection.link_key) + ":area:"))
		if excluded.has(connection.link_key) or area_failed:
			_prepare_adjacent(context, connection, excluded, work, destination)
			return []
		var forward: bool = context._horizontal_distance_between(walk[-1], connection.entry) <= context._horizontal_distance_between(walk[-1], connection.exit)
		var entry: Vector3 = connection.get("feet_entry", Vector3(connection.entry.x, from.y, connection.entry.z)) if forward else connection.get("feet_exit", Vector3(connection.exit.x, from.y, connection.exit.z))
		var native_exit: Vector3 = connection.exit if forward else connection.entry
		native_exit.y = entry.y
		if walk[-1].distance_to(entry) > 0.01: walk.append(entry)
		segments.append({"kind": &"walk", "points": walk})
		var direction: Vector3 = connection.direction if forward else -connection.direction
		segments.append({"kind": &"vault", "connection": connection, "entry": entry, "direction": direction})
		vaults += 1
		if vaults > 8:
			work.reason = &"too_many_vaults"
			return []
		walk = PackedVector3Array([native_exit])
		while index < result.path.size() and result.path_types[index] == NavigationPathQueryResult3D.PATH_SEGMENT_TYPE_LINK and result.path_owner_ids[index] == owner:
			index += 1
	if vaults == 0: return []
	segments.append({"kind": &"walk", "points": walk})
	return segments

static func _advance_validation(context, work: Dictionary) -> bool:
	var segment: Dictionary = work.segments[work.index]
	if segment.kind == &"vault":
		var wall = instance_from_id(segment.connection.cover_id)
		if not is_instance_valid(wall): return false
		var vault := Low.query_vault_at(context.actor, wall, segment.entry, segment.direction)
		if not vault.get("valid", false): return false
		work.segments[work.index] = _vault_segment(segment.connection, vault, segment.direction)
		var after: PackedVector3Array = work.segments[work.index + 1].points
		if after.is_empty() or after[0].distance_to(vault.exit) > 0.01: after.insert(0, vault.exit)
		work.segments[work.index + 1].points = after
		work.index += 1
		work.waypoint = 1
		return true
	var points: PackedVector3Array = segment.points
	if points.is_empty(): return false
	var height: float = context.actor.get_posture_body_height(false)
	var radius: float = Low._radius(context.actor)
	if work.waypoint < points.size():
		if not Geometry.can_sweep(context.actor, points[work.waypoint - 1], points[work.waypoint], height, radius, true): return false
		work.waypoint += 1
	else:
		if not Geometry.can_occupy(context.actor, points[-1], height, radius, true): return false
		work.index += 1
		work.waypoint = 1
	return true

static func _vault_segment(connection: Dictionary, vault: Dictionary, direction: Vector3) -> Dictionary:
	var result := {"kind": &"vault", "link_key": connection.link_key, "owner_id": connection.owner_id,
		"cover_id": connection.cover_id, "cover_revision": connection.cover_revision,
		"entry": vault.entry, "exit": vault.exit, "direction": direction,
		"duration": vault.duration, "height": vault.height, "points": vault.points}
	if connection.has("crossing_key"): result.crossing_key = connection.crossing_key
	return result

static func _walk_valid(context, path: PackedVector3Array) -> bool:
	if path.is_empty(): return false
	var actor = context.actor
	var height: float = actor.get_posture_body_height(false)
	var radius: float = Low._radius(actor)
	for index in range(1, path.size()):
		if not Geometry.can_sweep(actor, path[index - 1], path[index], height, radius, true): return false
	return Geometry.can_occupy(actor, path[-1], height, radius, true)

static func _pack(segments: Array[Dictionary], revision: int, destination: Vector3) -> Dictionary:
	var points := PackedVector3Array()
	for segment in segments:
		var leg: PackedVector3Array = segment.points if segment.kind == &"walk" else PackedVector3Array([segment.entry, segment.exit])
		for point in leg:
			if points.is_empty() or points[-1].distance_to(point) > 0.01: points.append(point)
	if points.size() > 256: return {}
	var result := {"version": 1, "geometry_revision": revision, "points": points, "segments": segments, "destination": destination}
	# Read-compatible view for the old single-vault consumers. Segments remain
	# authoritative and contain only values, including numeric cover identity.
	var vaults: Array = segments.filter(func(segment): return segment.kind == &"vault")
	if vaults.size() == 1:
		var split := segments.find(vaults[0])
		result.vault = vaults[0].duplicate(true)
		result.before = segments[split - 1].points.duplicate()
		result.after = segments[split + 1].points.duplicate()
	return result

static func _prepare_adjacent(context, failed: Dictionary, excluded: Array, work: Dictionary, destination: Vector3) -> void:
	var alternatives: Array = context.vault_navigation.connections().filter(func(value): return value.cover_id == failed.cover_id and not excluded.has(value.link_key))
	alternatives.sort_custom(func(a, b): return a.entry.distance_squared_to(failed.entry) < b.entry.distance_squared_to(failed.entry))
	if not context.commanded():
		# A blocked point is not a blocked wall. Refine the wall's continuous
		# crossing area before falling back to the remaining native channels.
		alternatives = context.vault_navigation.area_candidates(failed.owner_id, work.origin, destination, Low._radius(context.actor), excluded) + alternatives
	work.adjacent_pool = alternatives.slice(0, 2)
	work.adjacent_index = -1
	_next_adjacent(work)

static func _next_adjacent(work: Dictionary) -> void:
	work.adjacent_index += 1
	work.adjacent_phase = 0
	work.index = 0
	work.waypoint = 1
	work.segments = []
	if work.adjacent_index < work.adjacent_pool.size(): work.adjacent = true
	else: work.erase("adjacent")

## Each turn issues only one native walk query, then reuses the same bounded
## capsule/arc cursor. At most the two nearest channels are attempted.
static func _advance_adjacent(context, work: Dictionary, destination: Vector3) -> void:
	var connection: Dictionary = work.adjacent_pool[work.adjacent_index]
	var from: Vector3 = work.origin
	var forward: bool = context._horizontal_distance_between(from, connection.entry) <= context._horizontal_distance_between(from, connection.exit)
	var entry: Vector3 = connection.feet_entry if forward else connection.feet_exit
	var exit: Vector3 = connection.feet_exit if forward else connection.feet_entry
	if work.adjacent_phase == 0:
		var before := _owned_walk(context, from, entry)
		if before.is_empty(): _next_adjacent(work); return
		for index in before.size(): before[index].y = from.y
		before[0] = from
		work.adjacent_before = before
		work.adjacent_phase = 1
		return
	var after := _owned_walk(context, exit, destination)
	if after.is_empty() or work.adjacent_before.size() + after.size() > 256: _next_adjacent(work); return
	for index in after.size(): after[index].y = exit.y
	after.insert(0, exit)
	var segments: Array[Dictionary] = [{"kind": &"walk", "points": work.adjacent_before}, {"kind": &"vault", "connection": connection, "entry": entry, "direction": connection.direction if forward else -connection.direction}, {"kind": &"walk", "points": after}]
	work.segments = segments
	work.erase("adjacent")

static func _owned_walk(context, from: Vector3, destination: Vector3) -> PackedVector3Array:
	var parameters := NavigationPathQueryParameters3D.new()
	parameters.map = context.navigation_region.get_navigation_map()
	parameters.start_position = from
	parameters.target_position = destination
	parameters.navigation_layers = context.agent.navigation_layers & ~VAULT_LAYER
	parameters.included_regions = [context.navigation_region.get_rid()]
	var result := NavigationPathQueryResult3D.new()
	NavigationServer3D.query_path(parameters, result)
	if result.path.is_empty() or result.path.size() > 256 or context._horizontal_distance_between(result.path[-1], destination) > 0.05: return PackedVector3Array()
	return result.path

static func current(context, plan: Dictionary) -> bool:
	if plan.is_empty() or context.get("vault_navigation") == null or plan.get("geometry_revision", -1) != context.vault_navigation.revision: return false
	for segment: Dictionary in plan.get("segments", []):
		if segment.kind != &"vault": continue
		var value: Dictionary = context.vault_navigation.resolve_link(segment.owner_id)
		if value.is_empty() or value.cover_revision != segment.cover_revision or value.link_key != segment.link_key: return false
	return true

static func execution_vault(context, segment: Dictionary) -> Dictionary:
	var wall = instance_from_id(segment.cover_id)
	if not is_instance_valid(wall): return {}
	# The existing body entry performs the actual full character-inclusive check.
	return {"valid": true, "cover": wall, "entry": segment.entry, "exit": segment.exit, "duration": segment.duration}

static func seconds(plan: Dictionary, speed: float) -> float:
	var total := 0.0
	for segment: Dictionary in plan.get("segments", []):
		if segment.kind == &"vault":
			total += float(segment.duration)
		else:
			var points: PackedVector3Array = segment.points
			for index in range(1, points.size()): total += points[index - 1].distance_to(points[index]) / maxf(0.01, speed)
	return total

static func assess(context, plan: Dictionary, multiplier: float, threat: Vector3, reload_seconds: float) -> Dictionary:
	var elapsed := 0.0
	var exposure := 0.0
	var vault_seconds := 0.0
	for segment: Dictionary in plan.segments:
		if segment.kind == &"walk":
			var leg: Dictionary = context.spatial.assess_route(context, segment.points, threat, multiplier, reload_seconds + vault_seconds, false, elapsed, segment.points[0])
			elapsed = leg.seconds
			exposure += leg.exposure
		else:
			for index in 4:
				var observed: float = minf(segment.duration / 4.0, maxf(0.0, context.utility_horizon_seconds - elapsed - segment.duration * index / 4.0))
				exposure += context._reload_exposure(Low.sample_vault(segment, (index + 0.5) / 4.0), threat, -1.0, true) * observed
			elapsed += float(segment.duration)
			vault_seconds += float(segment.duration)
	return {"seconds": elapsed, "exposure": exposure, "fire_seconds": 0.0, "vault_seconds": vault_seconds}
