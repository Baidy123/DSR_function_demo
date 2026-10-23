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
	var path = remaining(bodies[id].position, tasks[id].route)
	# Only the next short corridor is held, not an entire long route.
	if path.size() > 1:
		var length: float = minf(1.4, Contract.horizontal(path[0], path[1]))
		path = PackedVector3Array([path[0], path[0].move_toward(path[1], length)])
	for other in bodies:
		if other == id: continue
		var clearance: float = bodies[id].radius + bodies[other].radius + maxf(bodies[id].spacing_margin, bodies[other].spacing_margin)
		if distance_to_path(bodies[other].position, path) < clearance - 0.03:
			if path.size() > 1 and Contract.horizontal(path[-1], bodies[other].position) > Contract.horizontal(path[0], bodies[other].position) + 0.01: continue
			blocked.append(other)
	return blocked
