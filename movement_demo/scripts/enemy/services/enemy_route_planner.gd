extends RefCounted

## Read-only one-vault alternatives. No target reads, action state or navigation writes.
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var context
var _cache: Dictionary = {}
var _pending: Array[Vector3] = []
var _origin := Vector3.INF
var _iteration := -1
var _cached_at := 0
var _vault_only: Dictionary = {}

func alternatives(destination: Vector3) -> Array[Dictionary]:
	var iteration := NavigationServer3D.map_get_iteration_id(context.agent.get_navigation_map())
	if not _origin.is_finite() or _origin.distance_to(context.actor.global_position) > 0.5 or iteration != _iteration or Time.get_ticks_msec() - _cached_at > 1000:
		_cached_at = Time.get_ticks_msec()
		_origin = context.actor.global_position
		_iteration = iteration
		_cache.clear()
		_pending.clear()
		_vault_only.clear()
	if _cache.has(destination): return _cache[destination]
	if not _pending.has(destination) and _pending.size() < 32: _pending.append(destination)
	return []

func has_pending() -> bool:
	return not _pending.is_empty()

func advance_one() -> void:
	if _pending.is_empty(): return
	var destination: Vector3 = _pending.pop_front()
	_cache[destination] = _evaluate(destination)
	# A moving actor can leave the cache's origin tolerance before the next
	# periodic decision. Announce newly ready alternatives while they are valid;
	# the selector still owns its normal hold time and switching advantage.
	if not _cache[destination].is_empty(): context.invalidate_utility()

func _evaluate(destination: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var actor = context.actor
	if actor.is_vaulting() or actor.global_position.distance_to(destination) < 1.0: return result
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
		var vault := LowCover.query_vault_at(actor, cover, entry, -collision.global_basis[axis] * signf(start[axis]))
		if not vault.get("valid", false): continue
		var before: PackedVector3Array = context.cover_selection._path_to(actor.global_position, entry)
		var after: PackedVector3Array = context.cover_selection._path_to(vault.exit, destination)
		if before.is_empty() or after.is_empty(): continue
		if context._horizontal_distance_between(before[before.size() - 1], entry) > 0.15 or context._horizontal_distance_between(after[0], vault.exit) > 0.3: continue
		result.append({"vault": vault, "before": before, "after": after, "destination": destination})
	return result

func assessment(route: Dictionary, multiplier: float, threat: Vector3, reload_seconds: float) -> Dictionary:
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
	_cache.clear()
	_pending.clear()
	_vault_only.clear()
	_origin = Vector3.INF
	_iteration = -1

func planning_path(from: Vector3, destination: Vector3) -> PackedVector3Array:
	var walk: PackedVector3Array = context.cover_selection._path_to(from, destination)
	if context._horizontal_distance_between(from, context.actor.global_position) > 0.1: return walk
	_vault_only[destination] = walk.is_empty()
	if not walk.is_empty(): return walk
	var routes := alternatives(destination)
	if routes.is_empty(): return walk
	_vault_only[destination] = true
	# Geometry-only connected path. Candidate expansion removes the nonexistent ordinary route.
	var combined: PackedVector3Array = routes[0].before.duplicate()
	combined.append_array(routes[0].after)
	return combined

func requires_vault(destination: Vector3) -> bool:
	return _vault_only.get(destination, false)
