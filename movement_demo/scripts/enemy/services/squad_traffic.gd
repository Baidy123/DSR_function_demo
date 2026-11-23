extends RefCounted

## Pure finite traffic search. A complete departure order must leave every
## parked destination outside the routes still to be traversed.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const MAX_TRIALS := 2048

static func distance_to_path(point: Vector3, path: PackedVector3Array) -> float:
	if path.size() == 1: return Contract.horizontal(point, path[0])
	var nearest = INF
	for index in range(1, path.size()):
		nearest = minf(nearest, Contract.horizontal(point, Geometry3D.get_closest_point_to_segment(point, path[index - 1], path[index])))
	return nearest

static func remaining(position: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	if path.size() < 2: return PackedVector3Array([position])
	var nearest = INF
	var selected = 1
	for index in range(1, path.size()):
		var distance = Contract.horizontal(position, Geometry3D.get_closest_point_to_segment(position, path[index - 1], path[index]))
		if distance < nearest:
			nearest = distance
			selected = index
	var result = PackedVector3Array([position])
	result.append_array(path.slice(selected))
	return result

static func conflicts(a: PackedVector3Array, b: PackedVector3Array, clearance: float) -> bool:
	for i in range(1, a.size()):
		for j in range(1, b.size()):
			var points = Geometry3D.get_closest_points_between_segments(a[i - 1], a[i], b[j - 1], b[j])
			if Contract.horizontal(points[0], points[1]) < clearance: return true
	return false

static func prefix(path: PackedVector3Array, distance: float) -> PackedVector3Array:
	if path.is_empty(): return path
	var result = PackedVector3Array([path[0]])
	for index in range(1, path.size()):
		var length = Contract.horizontal(path[index - 1], path[index])
		result.append(path[index - 1].move_toward(path[index], minf(distance, length)))
		distance -= length
		if distance <= 0.0: break
	return result

static func schedule(tasks: Dictionary, bodies: Dictionary) -> Dictionary:
	var ids: Array = tasks.keys()
	ids.sort()
	var budget = {"trials": 0}
	var order = _order(tasks, bodies, ids, [], budget)
	if order.size() != ids.size(): return {"valid": false, "reason": &"occupied_corridor", "trials": budget.trials}
	var dependencies = {}
	for i in order.size():
		var id = order[i]
		dependencies[id] = []
		for earlier in order.slice(0, i):
			var clearance: float = bodies[id].radius + bodies[earlier].radius + maxf(bodies[id].spacing_margin, bodies[earlier].spacing_margin)
			if conflicts(tasks[id].route, tasks[earlier].route, clearance): dependencies[id].append(earlier)
	return {"valid": true, "order": order, "dependencies": dependencies, "trials": budget.trials}

static func approach(task: Dictionary) -> PackedVector3Array:
	var path: PackedVector3Array = task.route
	var staging: Vector3 = task.get("staging_position", Vector3.INF)
	for index in path.size():
		if Contract.horizontal(path[index], staging) <= 0.05: return path.slice(0, index + 1)
	return PackedVector3Array()

## Nearest-segment trimming around a corner can otherwise drop the entry
## vertex before release. Keep that mandatory vertex until rendezvous ends.
static func remaining_preparation(position: Vector3, task: Dictionary) -> PackedVector3Array:
	var entry := approach(task)
	if entry.is_empty(): return remaining(position, task.route)
	var path := remaining(position, entry)
	if path[-1].distance_to(task.staging_position) > 0.001: path.append(task.staging_position)
	path.append_array(task.route.slice(entry.size()))
	return path

## Strong search must also be feasible while everyone is parked at their
## preparation posts. Final destinations alone cannot prove that rendezvous.
static func plan(tasks: Dictionary, bodies: Dictionary, synchronize_search: bool = false) -> Dictionary:
	var result = schedule(tasks, bodies)
	if not result.valid or not synchronize_search: return result
	var groups = {}
	for id in tasks:
		var key = tasks[id].get("sync_key", "")
		if tasks[id].role != &"search" or key.is_empty(): continue
		if not groups.has(key): groups[key] = []
		groups[key].append(id)
	var members: Array = []
	var synchronized: Array = []
	for group in groups.values():
		if group.size() >= 2:
			synchronized.append(group)
			members.append_array(group)
	if members.size() < 2: return result
	for id in members:
		var sightline = PackedVector3Array([tasks[id].position, tasks[id].look_position])
		for other in tasks:
			if id != other and distance_to_path(tasks[other].position, sightline) < bodies[other].radius + 0.1:
				return {"valid": false, "reason": &"observation_occupied"}
	var preparing = tasks.duplicate(true)
	var departing = tasks.duplicate(true)
	var staged_bodies = bodies.duplicate(true)
	for id in members:
		var path = approach(tasks[id])
		if path.is_empty(): return {"valid": false, "reason": &"missing_preparation_route"}
		preparing[id].route = path
		preparing[id].position = tasks[id].staging_position
		staged_bodies[id].position = tasks[id].staging_position
		departing[id].route = tasks[id].route.slice(path.size() - 1)
	var arrival = schedule(preparing, bodies)
	if not arrival.valid: return {"valid": false, "reason": &"preparation_occupied"}
	var departure = schedule(departing, staged_bodies)
	if not departure.valid: return {"valid": false, "reason": &"departure_occupied"}
	result.dependencies = departure.dependencies
	result.preparation_dependencies = arrival.dependencies
	result.synchronized_members = members
	result.synchronized_groups = synchronized
	return result

static func _order(tasks: Dictionary, bodies: Dictionary, pending: Array, ordered: Array, budget: Dictionary) -> Array:
	if pending.is_empty(): return ordered
	for id in pending:
		budget.trials += 1
		if budget.trials > MAX_TRIALS: return []
		var clear = true
		for other in tasks:
			if other == id: continue
			var parked: Vector3 = tasks[other].position if ordered.has(other) else bodies[other].position
			var clearance: float = bodies[id].radius + bodies[other].radius + maxf(bodies[id].spacing_margin, bodies[other].spacing_margin)
			if distance_to_path(parked, tasks[id].route) < clearance - 0.03:
				# Leaving an initially crowded position is legal only while
				# increasing separation; the destination must clear the body.
				if not _leaves_crowding(tasks[id].route, parked, clearance):
					clear = false
					break
		if not clear: continue
		var next = pending.duplicate()
		next.erase(id)
		var prefix = ordered.duplicate()
		prefix.append(id)
		var result = _order(tasks, bodies, next, prefix, budget)
		if not result.is_empty(): return result
	return []

static func _leaves_crowding(path: PackedVector3Array, parked: Vector3, clearance: float) -> bool:
	if path.size() < 2 or Contract.horizontal(path[0], parked) >= clearance or Contract.horizontal(path[-1], parked) < clearance: return false
	var previous = Contract.horizontal(path[0], parked)
	for index in range(1, path.size()):
		var nearest = Contract.horizontal(parked, Geometry3D.get_closest_point_to_segment(parked, path[index - 1], path[index]))
		if nearest < minf(previous, clearance) - 0.01: return false
		previous = Contract.horizontal(path[index], parked)
	return true

static func blockers(id: int, tasks: Dictionary, bodies: Dictionary) -> Array:
	var blocked: Array = []
	if not tasks.has(id) or not bodies.has(id): return blocked
	var path = prefix(remaining(bodies[id].position, tasks[id].route), 1.4)
	# Only the next short corridor is held, not an entire long route.
	for other in bodies:
		if other == id: continue
		var clearance: float = bodies[id].radius + bodies[other].radius + maxf(bodies[id].spacing_margin, bodies[other].spacing_margin)
		if distance_to_path(bodies[other].position, path) < clearance - 0.03:
			if path.size() > 1 and Contract.horizontal(path[-1], bodies[other].position) > Contract.horizontal(path[0], bodies[other].position) + 0.01: continue
			blocked.append(other)
	return blocked

## Ordinary sweeping has no rendezvous barrier. A leader only slows when its
## next motion would increase a real gap to a travelling search participant.
static func cohesion(id: int, tasks: Dictionary, bodies: Dictionary) -> Dictionary:
	var task: Dictionary = tasks.get(id, {})
	if task.get("role") != &"search" or not task.get("sync_key", "").is_empty(): return {"speed_scale": 1.0}
	var path := remaining(bodies[id].position, task.route)
	if path.size() < 2: return {"speed_scale": 1.0}
	var direction: Vector3 = (path[1] - path[0]).normalized()
	var scale := 1.0
	var waiting: Array = []
	for other in tasks:
		if other == id or not bodies.has(other): continue
		if tasks[other].role != &"search" or bodies[other].get("occupied", false): continue
		if not tasks[other].get("sync_key", "").is_empty(): continue
		var gap: Vector3 = bodies[id].position - bodies[other].position
		if absf(gap.y) > 1.0 or gap.length() < 4.0 or direction.dot(gap.normalized()) < 0.5: continue
		# A follower is actually heading towards this member's corridor. Search
		# groups examining opposite exits do not lock one another across walls.
		var following := remaining(bodies[other].position, tasks[other].route)
		if following.size() < 2 or (following[1] - following[0]).normalized().dot(gap.normalized()) < 0.25: continue
		scale = minf(scale, clampf((7.0 - gap.length()) / 3.0, 0.0, 1.0))
		waiting.append(other)
	return {"speed_scale": scale, "waiting_for": waiting}
