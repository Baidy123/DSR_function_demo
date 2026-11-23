extends RefCounted

## Bounded hypotheses from legal observations. Never reads the player body,
## changes memory, reserves a post or chooses an action.
static func observation(context, memory_seconds: float) -> Dictionary:
	var evidence: Dictionary = context.cooperation_target_evidence()
	if evidence.get("source") not in [&"visual", &"shared_visual"]: return {}
	if context.evidence_elapsed_seconds - float(evidence.get("captured_at", -INF)) > memory_seconds: return {}
	var velocity: Vector3 = evidence.get("velocity", Vector3.ZERO)
	velocity.y = 0.0
	if velocity.length() < 0.8 or not velocity.is_finite(): return {}
	return evidence

static func propose(context, parameters: Dictionary, fraction: float) -> Dictionary:
	var evidence := observation(context, minf(0.35, parameters.memory))
	if evidence.is_empty() or context.actor.weapon == null or not context.actor.weapon.melee_enabled: return {}
	var origin: Vector3 = context.actor.global_position
	var seen: Vector3 = evidence.position
	var velocity: Vector3 = evidence.velocity
	velocity.y = 0.0
	var reach: float = context.actor.weapon.melee_range
	var toward := seen - origin
	toward.y = 0.0
	if toward.length() <= reach + 0.3 or velocity.dot(toward.normalized()) < 0.2: return {}
	var horizon: float = minf(parameters.horizon * fraction, parameters.distance / velocity.length())
	var age: float = maxf(0.0, context.evidence_elapsed_seconds - float(evidence.captured_at))
	if horizon - age < 0.3: return {}
	var raw := seen + velocity * horizon
	var region: RID = context.navigation_region.get_rid()
	var start := NavigationServer3D.region_get_closest_point(region, seen)
	var finish := NavigationServer3D.region_get_closest_point(region, raw)
	if context._horizontal_distance_between(start, seen) > 0.5 or context._horizontal_distance_between(finish, raw) > 0.5: return {}
	if absf(start.y - seen.y) > 0.5 or absf(finish.y - seen.y) > 0.5: return {}
	var forecast: PackedVector3Array = NavigationServer3D.map_get_path(context.agent.get_navigation_map(), start, finish, true, context.agent.navigation_layers)
	if forecast.is_empty() or context._horizontal_distance_between(forecast[-1], finish) > 0.05: return {}
	for index in forecast.size(): forecast[index].y = origin.y
	var future := _along(forecast, velocity.length() * horizon)
	# Reach the side of the crossing, instead of running up the target's back
	# and entering an ordinary attack before ever occupying its forward route.
	var forward := velocity.normalized()
	var side := origin - seen
	side.y = 0.0
	side -= forward * side.dot(forward)
	if side.length() < 0.1: side = forward.cross(Vector3.UP)
	var point := future + side.normalized() * maxf(0.1, reach - 0.35)
	point.y = origin.y
	var projected := NavigationServer3D.region_get_closest_point(region, point)
	if context._horizontal_distance_between(projected, point) > 0.15 or absf(projected.y - point.y) > 0.5: return {}
	projected.y = origin.y
	point = projected
	if (point - seen).dot(velocity.normalized()) < 0.5: return {}
	if not context.is_position_free(point) or context.is_utility_destination_blocked(point): return {}
	if not context.cover_selection.has_clear_line(point + Vector3.UP * 0.8, future + Vector3.UP * 0.8): return {}
	# A shoulder waypoint keeps the approach beside the fleeing target. Merely
	# aiming ahead along its current lane still collapses into a rear chase.
	var shoulder := seen.lerp(future, 0.65) + side.normalized() * (reach + 0.6)
	shoulder.y = origin.y
	var path: PackedVector3Array = context.cover_selection._path_to(origin, shoulder).duplicate()
	var finish_path: PackedVector3Array = context.cover_selection._path_to(shoulder, point)
	if path.is_empty() or finish_path.is_empty(): return {}
	path.append_array(finish_path.slice(1))
	for index in path.size(): path[index].y = origin.y
	var arrival: float = context.cover_selection._path_length_from_path(path) / maxf(0.1, context.actor.move_speed * parameters.speed)
	if arrival + 0.1 > horizon - age: return {}
	var closing: float = context.actor.move_speed - velocity.dot(toward.normalized())
	var pursuit: float = minf(context.utility_horizon_seconds, maxf(0.0, toward.length() - reach) / maxf(0.1, closing))
	var gain: float = pursuit - (horizon - age)
	if gain < parameters.gain: return {}
	return {"position": point, "path": path, "forecast": forecast, "future": future,
		"origin": seen, "velocity": velocity, "captured_at": evidence.captured_at,
		"crossing_at": float(evidence.captured_at) + horizon,
		"until": float(evidence.captured_at) + horizon + 0.35,
		"generation": context.memory_generation, "target_id": evidence.target_id,
		"arrival": arrival, "gain": gain}

static func valid(context, prediction: Dictionary, memory_seconds: float) -> bool:
	if prediction.is_empty() or prediction.get("generation") != context.memory_generation or prediction.get("target_id") != context.cooperation_target_id(): return false
	if context.evidence_elapsed_seconds >= float(prediction.get("until", -INF)): return false
	var evidence := observation(context, memory_seconds)
	if evidence.is_empty(): return false
	var velocity: Vector3 = evidence.velocity
	velocity.y = 0.0
	if velocity.normalized().dot(prediction.velocity.normalized()) < 0.5: return false
	if (evidence.position - prediction.position).dot(prediction.velocity.normalized()) > 0.8: return false
	# A turn away from the hypothesised corridor invalidates the plan without
	# consulting the hidden target or moving the original observation.
	return preload("res://scripts/enemy/services/squad_traffic.gd").distance_to_path(evidence.position, prediction.forecast) <= 0.9

static func _along(path: PackedVector3Array, distance: float) -> Vector3:
	for index in range(1, path.size()):
		var length := path[index - 1].distance_to(path[index])
		if distance <= length: return path[index - 1].move_toward(path[index], distance)
		distance -= length
	return path[-1]
