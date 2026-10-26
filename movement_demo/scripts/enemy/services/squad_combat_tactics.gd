extends RefCounted

## Coordinator-owned planning geometry, never an executor or target observer.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const Scoring = preload("res://scripts/enemy/services/squad_scoring.gd")
const ARRIVAL_MARGIN := 0.16

## Refresh a short-lived contact endpoint from the latest legal observation
## at commitment, after budgeted preparation has finished. No action choice.
static func refresh_contact_post(context, profile: Dictionary, body: Dictionary, task: Dictionary, target: Vector3) -> bool:
	if not task.get("contact_post", false) or target.distance_to(task.look_position) < 0.02: return true
	# A legal observation can move inside the existing strike margin. Keep
	# that validated endpoint/route instead of queuing another navigation job
	# and rejecting the entire team's commit while it is pending.
	if melee_post_valid(context, profile, task.position, target, ARRIVAL_MARGIN * 0.5):
		task.look_position = target
		return true
	var seed_point: Vector3 = target + (task.position - task.look_position)
	if melee_post_valid(context, profile, body.position, target, ARRIVAL_MARGIN): seed_point = body.position
	var point := melee_position(context, profile, body, seed_point, target)
	if not point.is_finite(): return false
	var description: Dictionary = preload("res://scripts/enemy/services/enemy_search_formation.gd").route_plan(context, point)
	var path: PackedVector3Array = description.get("points", PackedVector3Array())
	if path.is_empty(): return false
	task.position = point
	task.route = path
	if description.get("geometry_revision", -1) >= 0: task.route_plan = description
	else: task.erase("route_plan")
	task.look_position = target
	return true

static func sites(context, profile: Dictionary, body: Dictionary, objective: Dictionary, bodies: Dictionary, profiles: Dictionary, recovery_round: int = 0) -> Array[Dictionary]:
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
	# A complete unsuccessful pass rotates one finite page, not an ever larger
	# pool. Stalled members use their own approach and different radial bands;
	# healthy teammates keep their existing geometry and firing posts.
	var angle_shift := 0.0
	if recovery_round > 0:
		away = body.position - target
		away.y = 0.0
		if away.is_zero_approx(): away = Vector3.BACK
		var ids := bodies.keys()
		ids.sort()
		angle_shift = (float(ids.find(body.get("id", context.actor.get_instance_id()))) + 1.0) * 0.23 + float(recovery_round) * 0.31
		if profile.firearms:
			var scale: float = [0.75, 1.25, 1.0][(recovery_round - 1) % 3]
			radius = minf(maxf(3.2, radius * scale), float(profile.weapon.fire_range) * 0.8)
	var result: Array[Dictionary] = []
	if recovery_round % 2 == 1:
		# A nearby lateral/backward step can open a muzzle around a corner even
		# when the usual target-centred ring is occupied. It still needs a real
		# firing lane, a complete route and the same whole-team checks.
		var distance := 1.4 + float(recovery_round - 1) * 0.5
		for index in 8:
			var angle := TAU * float(index) / 8.0
			var raw: Vector3 = body.position + Vector3(cos(angle), 0.0, sin(angle)) * distance
			var point := NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), raw)
			if Contract.horizontal(point, raw) > 0.4 or absf(point.y - body.position.y) > 0.5: continue
			point.y = body.position.y
			result.append({"position": point, "look_position": target, "site_key": "combat:%s:local:%s:%s" % [body.get("id", context.actor.get_instance_id()), recovery_round, index]})
		return result
	for offset in [0.7, -0.7, 1.25, -1.25, 0.0, PI, 2.1, -2.1]:
		var raw: Vector3 = target + away.normalized().rotated(Vector3.UP, offset + angle_shift) * radius
		var point := raw
		if profile.firearms:
			point = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), raw)
			if Contract.horizontal(point, raw) > 0.4 or absf(point.y - body.position.y) > 0.5: continue
		point.y = body.position.y
		var key := "combat:%s:%s" % [body.get("id", context.actor.get_instance_id()), offset]
		if recovery_round > 0: key += ":recovery:%s" % recovery_round
		result.append({"position": point, "look_position": target, "site_key": key})
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
	var weights: Dictionary = snapshot.get("scoring", {})
	var cost := (12.0 if available and not retained else 0.0) * Scoring.weight(weights, &"score_fire_continuity_weight")
	for index in shooters.size():
		var id: int = shooters[index]
		var shot: Dictionary = tasks[id]
		var direction: Vector3 = (shot.position - target).normalized()
		if attackers.is_empty():
			for other in shooters.slice(index + 1):
				var peer: Vector3 = (tasks[other].position - target).normalized()
				cost += 10.0 * clampf((direction.dot(peer) - 0.65) / 0.35, 0.0, 1.0) * Scoring.weight(weights, &"score_crossfire_weight")
		else:
			for other in attackers:
				var advance: Dictionary = tasks[other]
				var origin: Vector3 = snapshot.members[other].position - target
				origin.y = 0.0
				var coordination_weight := Scoring.weight(weights, &"score_melee_support_weight")
				if not origin.is_zero_approx(): cost += maxf(0.0, 0.25 - direction.dot(origin.normalized())) * 5.0 * coordination_weight
				cost += maxf(0.0, Contract.horizontal(advance.position, target) + 1.5 - Contract.horizontal(shot.position, target)) * 3.0 * coordination_weight
				var lane := PackedVector3Array([shot.position, target])
				var path: PackedVector3Array = advance.route
				for vertex in range(1, path.size()):
					var midpoint := (path[vertex - 1] + path[vertex]) * 0.5
					if Traffic.distance_to_path(midpoint, lane) < float(snapshot.members[other].radius) + 0.2:
						cost += minf(4.0, Contract.horizontal(path[vertex - 1], path[vertex])) * 2.0 * coordination_weight
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
