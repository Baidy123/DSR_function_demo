extends RefCounted

## Stateless coordinator geometry. Goals come from the squad; members only
## validate actual navigation/capsules. No action selection or body control.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const CoverGeometry = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd")
const BodyGeometry = preload("res://scripts/systems/character_geometry.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")

static func sites(context, objective: Dictionary, count: int, attempt: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var center: Vector3 = objective.get("position", context.actor.global_position)
	var phase: StringName = objective.get("phase", &"patrol")
	if phase == &"search":
		var clue = objective.duplicate(true)
		clue.id = objective.get("objective_id", 0)
		if not clue.has("cover"):
			clue.merge(CoverGeometry.nearby_investigation_cover(context, clue))
		var geometry = CoverGeometry.describe(context, clue, false)
		if not geometry.is_empty():
			for side in geometry.ends:
				var end: Dictionary = geometry.ends[side]
				var outward: Vector3 = (geometry.cover_transform.basis.x if geometry.along_x else geometry.cover_transform.basis.z).normalized() * float(side)
				var axis: Vector3 = (end.peek - end.entry).normalized()
				for rank in maxi(2, count):
					# Separate observation lanes along the wall end; a rear post
					# aimed through a parked teammate can never finish observing.
					var offset: Vector3 = outward * float(rank) * 1.4
					# Shift the entire lane outward when a previous layout failed.
					var lateral: Vector3 = (end.entry - geometry.observer_position).normalized() * float(attempt % 3) * 0.35
					lateral.y = 0.0
					result.append({"position": end.peek + offset + lateral, "via": end.entry + offset + lateral,
						"look_position": end.peek + offset + (axis - outward) * 2.0 + lateral, "site_key": "cover:%s:%s:%s" % [geometry.cover_id, side, rank], "side": side})
			if attempt < 3: return result
		# A failed formation keeps the objective and uses other reachable posts.
		result.append({"position": center, "look_position": center, "site_key": "last_seen"})
	if phase == &"patrol": center = context._spawn_position
	var radial: Vector3 = context.actor.global_position - center
	radial.y = 0.0
	if radial.is_zero_approx(): radial = Vector3.BACK
	var angle = atan2(radial.z, radial.x)
	if phase == &"patrol": angle = 0.0
	var radius = 5.0 if phase == &"contact" else 2.0 + float(attempt / 3) * 1.5
	if phase == &"patrol": radius = 3.0
	for i in 12:
		var direction = Vector3(cos(angle + TAU * i / 12.0), 0, sin(angle + TAU * i / 12.0))
		var point = center + direction * radius
		var projected = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), point)
		if Contract.horizontal(point, projected) > 0.4: continue
		projected.y = context.actor.global_position.y
		result.append({"position": projected, "look_position": center if phase == &"contact" else projected + direction,
			"site_key": "%s:%s:%s" % [phase, 0 if phase == &"patrol" else attempt / 3, i]})
	# The shared static index contributes connected search sectors, not targets.
	if phase == &"search" and context.tactical_map != null:
		for sector in context.tactical_map.query_sectors(center, 12.0, context.agent.navigation_layers, 6):
			var point: Vector3 = sector.get("position", sector.get("center", Vector3.INF))
			if point.is_finite(): result.append({"position": point, "look_position": point, "site_key": str(sector.sector_key)})
	return result

static func route(context, destination: Vector3, via: Vector3 = Vector3.INF) -> PackedVector3Array:
	var path = PackedVector3Array([context.actor.global_position])
	var from: Vector3 = context.actor.global_position
	for point: Vector3 in ([via, destination] if via.is_finite() else [destination]):
		var leg: PackedVector3Array = context.cover_selection._path_to(from, point)
		if leg.is_empty(): return PackedVector3Array()
		for vertex in leg:
			vertex.y = context.actor.global_position.y
			if path[-1].distance_to(vertex) > 0.01: path.append(vertex)
		from = point
	var radius: float = context.coordination_motion_state().radius
	if not CoverGeometry._walkable_path(context, path, radius): return PackedVector3Array()
	if not BodyGeometry.can_occupy(context.actor, destination, context.actor.get_body_height(), radius, true): return PackedVector3Array()
	return path

static func candidate(context, profile: Dictionary, body: Dictionary, site: Dictionary, objective: Dictionary, previous: Dictionary) -> Dictionary:
	var phase: StringName = objective.get("phase", &"patrol")
	var role: StringName = &"search" if phase == &"search" else (&"engage" if phase == &"contact" else &"patrol")
	role = site.get("role", role)
	if body.reloading or body.can_reload and body.rounds == 0: role = &"reload"
	var action = Contract.executor(profile, role)
	if action.is_empty():
		role = &"guard"
		action = Contract.executor(profile, role)
	if action.is_empty(): return {}
	var point: Vector3 = site.position
	if role == &"patrol" and Contract.horizontal(point, body.position) < 0.75: return {}
	if phase == &"contact" and role in [&"engage", &"support", &"flank"]:
		if profile.firearms:
			var origin: Vector3 = context.actor.get_posture_muzzle_position(false, point)
			var aim: Vector3 = objective.get("aim_position", objective.position + Vector3.UP)
			# Seeing a target does not imply the observer's current muzzle has a
			# usable shot. Estimate future posts from known feet in that case;
			# actual fire still requires a fresh personal visible aim point.
			if not aim.is_finite(): aim = objective.position + Vector3.UP
			if origin.distance_to(aim) > profile.weapon.fire_range or not context.fire.has_clear_firing_lane(origin, aim - origin, origin.distance_to(aim)): return {}
		else:
			# Melee members receive actual contact-range posts from the same
			# known target, never a ranged support label.
			var away: Vector3 = (point - objective.position).normalized()
			point = objective.position + away * maxf(0.5, float(profile.weapon.get("melee_range", 1.3)) * 0.8)
	var path = route(context, point, site.get("via", Vector3.INF))
	if path.is_empty(): return {}
	if role == &"flank" and profile.firearms and Traffic.distance_to_path(objective.position, path) < 1.5:
		var approach: Vector3 = body.position - objective.position
		approach.y = 0.0
		var detour = PackedVector3Array()
		for side in [-1.0, 1.0]:
			var via: Vector3 = objective.position + approach.normalized().rotated(Vector3.UP, side * PI * 0.5) * 5.0
			var alternative = route(context, point, via)
			if not alternative.is_empty() and Traffic.distance_to_path(objective.position, alternative) >= 1.5:
				if detour.is_empty() or context.cover_selection._path_length_from_path(alternative) < context.cover_selection._path_length_from_path(detour): detour = alternative
		if detour.is_empty(): return {}
		path = detour
	var parameters: Dictionary = profile.actions[action].parameters
	var speed = maxf(0.1, float(parameters.get("focused_search_speed_multiplier", 1.0))) if role == &"search" else 1.0
	var seconds: float = context.cover_selection._path_length_from_path(path) / maxf(0.1, body.move_speed * speed)
	var estimate: float = seconds + (0.0 if previous.get("position", Vector3.INF).distance_to(point) < 0.2 else 0.6)
	if role == &"guard" and phase != &"patrol": estimate += 8.0
	if role in [&"engage", &"support", &"flank"] and body.visible and Contract.horizontal(point, body.position) < 0.2: estimate = 0.0
	if role == &"flank" and not body.visible:
		var approach = (body.position - objective.position).normalized()
		var flank = (point - objective.position).normalized()
		estimate += maxf(0.0, approach.dot(flank)) * 4.0
	return {"action": action, "role": role, "position": point, "route": path,
		"look_position": site.get("look_position", objective.get("position", point)),
		"staging_position": site.get("via", point if role == &"search" else Vector3.INF), "site_key": site.get("site_key", str(point)),
		"estimate": estimate, "travel_seconds": seconds, "speed_multiplier": speed, "objective_id": objective.get("objective_id", 0),
		"evidence_id": objective.get("id", 0), "target_id": objective.get("target_id", 0), "side": site.get("side", 0)}

static func yield_sites(context, body: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for radius in [1.4, 2.4]:
		for i in 8:
			var point: Vector3 = body.position + Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * radius
			var path = route(context, point)
			if not path.is_empty(): result.append({"position": point, "route": path, "site_key": "yield:%s" % point})
	return result
