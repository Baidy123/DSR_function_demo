extends RefCounted

## Budgeted typed routes with legacy single-vault compatibility. No target reads,
## action ownership or navigation writes.
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const NavigationRoute = preload("res://scripts/enemy/services/enemy_navigation_route.gd")
# Bounded local adjustment of a generated entry, not a relaxed path tolerance.
const MAX_ENTRY_PROJECTION := 0.35
var context
var _cache: Dictionary = {}
var _pending: Array[Vector3] = []
var _priority_pending: Array[Vector3] = []
var _origin := Vector3.INF
var _iteration := -1
var _cached_at := 0
var _vault_only: Dictionary = {}
var _ready_position := Vector3.INF
var _failed_links: Dictionary = {}
var native_queries: Dictionary = {}
var native_deadline_usec := 0
var native_last_units := 0

func alternatives(destination: Vector3, priority: bool = false) -> Array[Dictionary]:
	var iteration := NavigationServer3D.map_get_iteration_id(context.agent.get_navigation_map())
	if not _origin.is_finite() or _origin.distance_to(context.actor.global_position) > 0.5 or iteration != _iteration or Time.get_ticks_msec() - _cached_at > 1000:
		_cached_at = Time.get_ticks_msec()
		_origin = context.actor.global_position
		_iteration = iteration
		_cache.clear()
		_pending.clear()
		_priority_pending.clear()
		_vault_only.clear()
		_ready_position = Vector3.INF
	if _cache.has(destination): return _cache[destination]
	if priority:
		# A moving, known objective must not queue behind optional cover points
		# or all of its own older positions. Only pending work is coalesced;
		# completed paths still belong to their exact checked destinations.
		for old in _priority_pending.duplicate():
			if old != destination and context._horizontal_distance_between(old, destination) <= 0.5 and absf(old.y - destination.y) <= 0.5:
				_priority_pending.erase(old)
				_pending.erase(old)
		if not _priority_pending.has(destination): _priority_pending.append(destination)
		if _priority_pending.size() > 4: _pending.erase(_priority_pending.pop_front())
		if not _pending.has(destination):
			if _pending.size() >= 32: _priority_pending.erase(_pending.pop_back())
			_pending.append(destination)
	elif not _pending.has(destination) and _pending.size() < 32:
		_pending.append(destination)
	return []

func has_pending() -> bool:
	return not _pending.is_empty()

func has_priority_pending() -> bool:
	return not _priority_pending.is_empty()

func advance_one(deadline_usec: int = 0) -> int:
	if _pending.is_empty(): return 0
	var destination: Vector3 = _priority_pending.pop_front() if not _priority_pending.is_empty() else _pending[0]
	_pending.erase(destination)
	native_deadline_usec = deadline_usec
	native_last_units = 0
	var evaluated := _evaluate(destination)
	native_deadline_usec = 0
	if NavigationRoute.pending(context, destination):
		_pending.append(destination)
		_priority_pending.append(destination)
		return maxi(1, native_last_units)
	_cache[destination] = evaluated
	# At rest, announce the first usable route and let the ordinary timer consume
	# the rest of this batch. A moving actor still needs each newly ready route
	# before leaving its origin tolerance (including a late, shorter vault).
	var point: Vector3 = context.actor.global_position
	var moved: bool = not _ready_position.is_finite() or Vector2(point.x - _ready_position.x, point.z - _ready_position.z).length_squared() > 0.000001
	if moved and not _cache[destination].is_empty():
		_ready_position = point
		context.invalidate_utility()
	return maxi(1, native_last_units)

func _evaluate(destination: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actor = context.actor
	if actor.is_vaulting() or actor.global_position.distance_to(destination) < 1.0: return result
	if context.vault_navigation != null and context.vault_navigation.ready and not context.vault_navigation.connections().is_empty():
		var route := NavigationRoute.query(context, destination, Vector3.INF, failed_links())
		if not route.is_empty():
			if route.has("vault"): route.vault.cover = instance_from_id(route.vault.cover_id)
			result.append(route)
		return result
	var covers: Array = context.spatial.regions().filter(func(body): return body.is_low_cover() and body.vault_enabled and body.global_position.distance_to(actor.global_position) < 8.0)
	covers.sort_custom(func(a, b): return a.global_position.distance_squared_to(actor.global_position) < b.global_position.distance_squared_to(actor.global_position))
	for cover in covers.slice(0, 2):
		var collision: CollisionShape3D = cover.get_node("CollisionShape3D")
		var half: Vector3 = collision.shape.size * 0.5
		var axis: int = 0 if half.x * collision.global_basis.x.length() < half.z * collision.global_basis.z.length() else 2
		var other: int = 2 if axis == 0 else 0
		var start := collision.to_local(actor.global_position)
		var finish := collision.to_local(destination)
		if start[axis] * finish[axis] >= 0.0: continue
		var crossing := start.lerp(finish, absf(start[axis]) / maxf(0.001, absf(start[axis]) + absf(finish[axis])))
		crossing[other] = clampf(crossing[other], -half[other] + 0.45 / collision.global_basis[other].length(), half[other] - 0.45 / collision.global_basis[other].length())
		crossing[axis] = signf(start[axis]) * (half[axis] + 0.6 / collision.global_basis[axis].length())
		var entry := collision.to_global(crossing)
		entry.y = actor.global_position.y
		entry = _navigation_entry(entry, collision, axis, signf(start[axis]))
		if not entry.is_finite(): continue
		var vault := LowCover.query_vault_at(actor, cover, entry, -collision.global_basis[axis] * signf(start[axis]))
		if not vault.get("valid", false): continue
		var before: PackedVector3Array = context.cover_selection._path_to(actor.global_position, entry)
		var after: PackedVector3Array = context.cover_selection._path_to(vault.exit, destination)
		if before.is_empty() or after.is_empty(): continue
		if context._horizontal_distance_between(before[before.size() - 1], entry) > 0.15 or context._horizontal_distance_between(after[0], vault.exit) > 0.3: continue
		result.append({"vault": vault, "before": before, "after": after, "destination": destination})
	return result

func _navigation_entry(nominal: Vector3, collision: CollisionShape3D, axis: int, side: float) -> Vector3:
	var projected: Vector3 = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), nominal)
	if context._horizontal_distance_between(projected, nominal) > MAX_ENTRY_PROJECTION or absf(projected.y - nominal.y) > 0.5:
		return Vector3.INF
	# Baking raises the navigation surface; the vault still starts on the actual
	# feet plane. Do not snap onto the other side of this wall or another floor.
	projected.y = nominal.y
	var local: Vector3 = collision.to_local(projected)
	if local[axis] * side <= collision.shape.size[axis] * 0.5: return Vector3.INF
	var actor = context.actor
	if not Geometry.can_occupy(actor, projected, actor.get_posture_body_height(false), LowCover._radius(actor), true):
		return Vector3.INF
	return projected

func assessment(route: Dictionary, multiplier: float, threat: Vector3, reload_seconds: float) -> Dictionary:
	if route.has("segments"): return NavigationRoute.assess(context, route, multiplier, threat, reload_seconds)
	var before: Dictionary = context.spatial.assess_route(context, route.before, threat, multiplier, reload_seconds)
	var duration: float = route.vault.duration
	var horizon: float = context.utility_horizon_seconds
	var exposed := 0.0
	for index in 4:
		var point := LowCover.sample_vault(route.vault, (index + 0.5) / 4.0)
		var observed := minf(duration / 4.0, maxf(0.0, horizon - before.seconds - duration * index / 4.0))
		exposed += context._reload_exposure(point, threat, -1.0, true) * observed
	# assess_route accepts an explicit start point so the post-landing walk cannot include a phantom return leg.
	var after: Dictionary = context.spatial.assess_route(context, route.after, threat, multiplier, reload_seconds + duration, false, before.seconds + duration, route.vault.exit)
	return {"seconds": after.seconds, "exposure": before.exposure + exposed + after.exposure, "fire_seconds": 0.0, "vault_seconds": duration}

func reset() -> void:
	_ready_position = Vector3.INF
	_cache.clear()
	_pending.clear()
	_priority_pending.clear()
	_vault_only.clear()
	_origin = Vector3.INF
	_iteration = -1
	_failed_links.clear()
	native_queries.clear()

func failed_links() -> Array:
	var now := Time.get_ticks_msec()
	for key in _failed_links.keys():
		if now >= _failed_links[key]: _failed_links.erase(key)
	return _failed_links.keys()

func reject_link(key: String) -> void:
	_failed_links[key] = Time.get_ticks_msec() + 500
	_cache.clear()
	context.invalidate_utility()

func planning_path(from: Vector3, destination: Vector3) -> PackedVector3Array:
	var walk: PackedVector3Array = context.cover_selection._path_to(from, destination)
	if context._horizontal_distance_between(from, context.actor.global_position) > 0.1: return walk
	_vault_only[destination] = walk.is_empty()
	if not walk.is_empty(): return walk
	var routes := alternatives(destination, true)
	if routes.is_empty(): return walk
	_vault_only[destination] = true
	# Geometry-only connected path. Candidate expansion removes the nonexistent ordinary route.
	if routes[0].has("segments"): return routes[0].points.duplicate()
	var combined: PackedVector3Array = routes[0].before.duplicate()
	combined.append_array(routes[0].after)
	return combined

func requires_vault(destination: Vector3) -> bool:
	return _vault_only.get(destination, false)
