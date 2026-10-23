extends RefCounted

## Coordinator-owned planning geometry, never an executor or target observer.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const ARRIVAL_MARGIN := 0.16

static func sites(context, profile: Dictionary, body: Dictionary, objective: Dictionary, bodies: Dictionary, profiles: Dictionary) -> Array[Dictionary]:
	var target: Vector3 = objective.position
	var away: Vector3 = body.position - target
	away.y = 0.0
	if away.is_zero_approx(): away = Vector3.BACK
	var radius := 5.0
	if profile.firearms:
		var front := Vector3.ZERO
		var count := 0
		for id in bodies:
			if profiles.get(id, {}).get("firearms", true): continue
			front += bodies[id].position - target
			count += 1
		if count > 0:
			front /= float(count)
			front.y = 0.0
			if not front.is_zero_approx(): away = front
			radius = clampf(front.length() + 2.0, 4.0, 8.0)
		# All points still pass original range, lane, body and route validation.
		radius = minf(radius, float(profile.weapon.fire_range) * 0.8)
	var result: Array[Dictionary] = []
	for offset in [0.7, -0.7, 1.25, -1.25, 0.0, PI, 2.1, -2.1]:
		var raw: Vector3 = target + away.normalized().rotated(Vector3.UP, offset) * radius
		var point := raw
		if profile.firearms:
			point = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), raw)
			if Contract.horizontal(point, raw) > 0.4 or absf(point.y - body.position.y) > 0.5: continue
		point.y = body.position.y
		result.append({"position": point, "look_position": target, "site_key": "combat:%s:%s" % [body.get("id", context.actor.get_instance_id()), offset]})
	return result

## Pure joint costs. Crossing briefly can be scheduled; following the same
## muzzle corridor for a long leg is a poor support plan, even with clear ends.
static func team_cost(snapshot: Dictionary, tasks: Dictionary) -> float:
	var target: Vector3 = snapshot.objective.position
	var shooters: Array = []
	var attackers: Array = []
	var available := false
	var retained := false
	for id in tasks:
		var body: Dictionary = snapshot.members[id]
		var ranged: bool = snapshot.profiles[id].get("firearms", false)
		if ranged and body.get("visible", false) and body.get("fire_lane_valid", false) and body.get("can_attack", false) and body.get("rounds", 0) > 0:
			available = true
			if tasks[id].get("tactical", {}).get("sustainable_fire", false) and Contract.horizontal(body.position, tasks[id].position) < 0.2: retained = true
		if not tasks[id].role in [&"engage", &"support", &"flank", &"cover_peek"]: continue
		if ranged: shooters.append(id)
		else: attackers.append(id)
	var cost := 12.0 if available and not retained else 0.0
	for index in shooters.size():
		var id: int = shooters[index]
		var shot: Dictionary = tasks[id]
		var direction: Vector3 = (shot.position - target).normalized()
		if attackers.is_empty():
			for other in shooters.slice(index + 1):
				var peer: Vector3 = (tasks[other].position - target).normalized()
				cost += 10.0 * clampf((direction.dot(peer) - 0.65) / 0.35, 0.0, 1.0)
		else:
			for other in attackers:
				var advance: Dictionary = tasks[other]
				var origin: Vector3 = snapshot.members[other].position - target
				origin.y = 0.0
				if not origin.is_zero_approx(): cost += maxf(0.0, 0.25 - direction.dot(origin.normalized())) * 5.0
				cost += maxf(0.0, Contract.horizontal(advance.position, target) + 1.5 - Contract.horizontal(shot.position, target)) * 3.0
				var lane := PackedVector3Array([shot.position, target])
				var path: PackedVector3Array = advance.route
				for vertex in range(1, path.size()):
					var midpoint := (path[vertex - 1] + path[vertex]) * 0.5
					if Traffic.distance_to_path(midpoint, lane) < float(snapshot.members[other].radius) + 0.2:
						cost += minf(4.0, Contract.horizontal(path[vertex - 1], path[vertex])) * 2.0
	return cost

static func melee_post_valid(context, profile: Dictionary, point: Vector3, target: Vector3, margin: float = 0.0) -> bool:
	var weapon: Dictionary = profile.get("weapon", {})
	if not weapon.get("melee_enabled", false) or not point.is_finite() or not target.is_finite(): return false
	if absf(point.y - target.y) > float(weapon.get("melee_height_tolerance", 0.5)): return false
	if Contract.horizontal(point, target) > float(weapon.get("melee_range", 0.0)) - margin: return false
	return context.cover_selection.has_clear_line(point + Vector3.UP * 0.8, target + Vector3.UP * 0.8)

static func melee_position(context, profile: Dictionary, body: Dictionary, seed_point: Vector3, target: Vector3) -> Vector3:
	# Preserve a current reachable attack, including its normal cooldown/turn.
	if Contract.horizontal(seed_point, body.position) < 0.1 and melee_post_valid(context, profile, body.position, target, ARRIVAL_MARGIN): return body.position
	var away := seed_point - target
	away.y = 0.0
	if away.is_zero_approx(): away = body.position - target
	var reach := float(profile.weapon.get("melee_range", 0.0)) - ARRIVAL_MARGIN
	if reach <= body.radius: return Vector3.INF
	var raw: Vector3 = target + away.normalized() * reach
	var point := NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), raw)
	if absf(point.y - body.position.y) > 0.5: return Vector3.INF
	point.y = body.position.y
	return point if melee_post_valid(context, profile, point, target, ARRIVAL_MARGIN * 0.5) else Vector3.INF
