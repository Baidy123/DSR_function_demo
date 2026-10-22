extends RefCounted

## Locally validated slots for one coordinator-owned inspection order. No body
## movement, target reads, assignments or fire authority live in this helper.
const Geometry = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd")

## Navigation capability query only. The coordinator chooses the partition;
## these two checked ingress costs do not assign or move a member.
static func entry_travel_seconds(contexts: Dictionary, sample: Dictionary) -> Dictionary:
	var result := {}
	for id: int in contexts:
		var context = contexts[id]
		var geometry: Dictionary = Geometry.describe(context, sample.clue, false)
		var state: Dictionary = context.coordination_motion_state()
		var costs := {}
		for side in [-1, 1]:
			var head: Dictionary = sample.duplicate(true)
			head.merge({"side": side, "row": 0, "depth": 1}, true)
			var preview := route(context, geometry, head)
			costs[side] = INF if preview.is_empty() else context.cover_selection._path_length_from_path(preview.approach) / maxf(0.1, state.move_speed)
		result[id] = costs
	return result

## Called once by the squad for a layout. Members receive concrete destinations,
## routes and a passage order; no member chooses its own stagger after dispatch.
static func prepare_slots(contexts: Dictionary, slots: Dictionary) -> void:
	var largest = contexts[contexts.keys()[0]]
	for context in contexts.values():
		if _radius(context) > _radius(largest): largest = context
	var sample: Dictionary = slots.values()[0]
	var geometry: Dictionary = Geometry.describe(largest, sample.clue, false) if sample.kind == &"cover" else {}
	var ordered: Array = []
	for side in [-1, 1]:
		var members: Array = slots.keys().filter(func(id): return slots[id].side == side)
		var costs := {}
		for id in members:
			var head: Dictionary = slots[id].duplicate(true)
			head.row = 0
			var local_geometry: Dictionary = geometry if sample.kind == &"cover" else point_geometry(contexts[id], head.clue, head)
			var preview := route(contexts[id], local_geometry, head)
			costs[id] = contexts[id].cover_selection._path_length_from_path(preview.approach) if not preview.is_empty() else INF
		if sample.kind == &"cover":
			members.sort_custom(func(a, b): return costs[a] < costs[b] if costs[a] != costs[b] else a < b)
		else:
			members.sort_custom(func(a, b): return slots[a].row < slots[b].row)
		for row in members.size():
			var id: int = members[row]
			var slot: Dictionary = slots[id]
			slot.row = row
			var local_geometry: Dictionary = geometry if sample.kind == &"cover" else point_geometry(contexts[id], slot.clue, slot)
			var prepared := route(contexts[id], local_geometry, slot)
			slot.route_planned = true
			if prepared.is_empty(): continue
			slot.entry = prepared.entry
			slot.peek = prepared.peek
			slot.stagger = prepared.stagger
			slot.approach = prepared.approach
			slot.crossing = contexts[id].cover_selection._query_path_to(slot.entry, slot.peek)
			ordered.append({"id": id, "row": row, "cost": contexts[id].cover_selection._path_length_from_path(prepared.approach)})
	# Crossing order follows the columns. Assembly has a separate order: a
	# rear rank may have to clear its initial position before a leader can fit.
	ordered.sort_custom(func(a, b): return a.row < b.row if sample.kind == &"cover" and a.row != b.row else (a.cost < b.cost if a.cost != b.cost else a.id < b.id))
	for index in ordered.size(): slots[ordered[index].id].crossing_priority = index
	if ordered.size() != slots.size():
		for slot: Dictionary in slots.values(): slot.erase("entry")
		return
	var positions := {}
	for id: int in slots: positions[id] = contexts[id].coordination_motion_state().position
	var assembly_seconds := 0.0
	var crossing_seconds := 0.0
	for id: int in slots:
		var speed: float = maxf(0.1, contexts[id].coordination_motion_state().move_speed)
		var lag: float = float(slots[id].row) * float(slots[id].spacing) / speed if sample.kind == &"cover" else 0.0
		crossing_seconds = maxf(crossing_seconds, contexts[id].cover_selection._path_length_from_path(slots[id].crossing) / speed + lag)
	for priority in slots.size():
		var selected := -1
		for index in ordered.size():
			var id: int = ordered[index].id
			var slot: Dictionary = slots[id]
			var occupied: Array = []
			for other: int in positions:
				if other != id: occupied.append(positions[other])
			var path: PackedVector3Array = contexts[id].inspection_route(slot, slot.entry, occupied, slot.approach)
			if path.is_empty(): continue
			slot.approach = path
			slot.passage_priority = priority
			positions[id] = slot.entry
			selected = index
			break
		if selected < 0:
			# A partial allocation is not a squad plan. The original finite layout
			# fallback will try a column; nobody starts on a half-prepared layout.
			for slot: Dictionary in slots.values(): slot.erase("entry")
			return
		ordered.remove_at(selected)
	assembly_seconds = estimate_assembly(contexts, slots)
	if not is_finite(assembly_seconds):
		# Routes were validated in this passage order with the other bodies at
		# their initial/final positions. If simultaneous departures interlock,
		# reserve the conflicting corridor until its predecessor has cleared it.
		# This still permits unrelated approaches to run together.
		for slot: Dictionary in slots.values(): slot.ordered_departures = true
		assembly_seconds = estimate_assembly(contexts, slots)
	# Estimate actual corridor waits; a route intersection does not mean waiting
	# for the predecessor's entire journey before beginning one's own approach.
	if assembly_seconds + crossing_seconds + 0.5 > float(sample.get("expires_at", INF)) - float(sample.get("issued_at", 0.0)):
		for slot: Dictionary in slots.values(): slot.erase("entry")
	else:
		for slot: Dictionary in slots.values(): slot.scheduled_seconds = assembly_seconds + crossing_seconds

## Bounded value-only preview of the same passage constraints. No body, clock,
## reservation or action is changed. Normal walking makes the estimate include
## waits without assuming that the short pursuit speed window is still active.
static func estimate_assembly(contexts: Dictionary, slots: Dictionary) -> float:
	var positions := {}
	var speeds := {}
	var ready_delays := {}
	var done := {}
	var order: Array = slots.keys()
	order.sort_custom(func(a, b): return slots[a].passage_priority < slots[b].passage_priority)
	for id: int in order:
		var state: Dictionary = contexts[id].coordination_motion_state()
		positions[id] = state.position
		speeds[id] = maxf(0.1, state.move_speed)
		ready_delays[id] = maxf(0.0, float(state.get("available_in", 0.0)))
		slots[id].staging_wait_for = []
	for step in 300:
		var advanced := false
		for id: int in order:
			if done.has(id): continue
			if step * 0.1 < float(ready_delays[id]):
				advanced = true # Bounded, measured occupancy is not a traffic cycle.
				continue
			var slot: Dictionary = slots[id]
			var position: Vector3 = positions[id]
			if position.distance_to(slot.entry) <= 0.025:
				done[id] = true
				slot.staging_seconds = step * 0.1
				continue
			var path := remaining_path(position, slot.approach)
			var next: Vector3 = path[1] if path.size() > 1 else slot.entry
			var distance := position.distance_to(next)
			var allowed := distance
			for other: int in order:
				if other == id: continue
				var point: Vector3 = positions[other]
				var clearance: float = slot.spacing - 0.06
				allowed = minf(allowed, corridor_entry(position, next, point, point, clearance, true))
				if slots[other].passage_priority >= slot.passage_priority: continue
				var other_path := remaining_path(point, slots[other].approach)
				if slot.get("ordered_departures", false) and paths_conflict(path, other_path, clearance):
					allowed = 0.0
					if not slot.staging_wait_for.has(other): slot.staging_wait_for.append(other)
					continue
				var clears := true
				for i in range(1, other_path.size()):
					if slot.entry.distance_to(Geometry3D.get_closest_point_to_segment(slot.entry, other_path[i - 1], other_path[i])) < clearance: clears = false
				for i in range(1, other_path.size()):
					var available := corridor_entry(position, next, other_path[i - 1], other_path[i], clearance, clears)
					allowed = minf(allowed, available)
					if available <= 0.01 and not slot.staging_wait_for.has(other): slot.staging_wait_for.append(other)
			if allowed <= 0.01: continue
			positions[id] = position.move_toward(next, minf(allowed, speeds[id] * 0.1))
			advanced = true
		if done.size() == order.size(): return step * 0.1
		if not advanced: return INF
	return INF

## A departure is released by actual corridor clearance, never an elapsed
## delay or a declared arrival. Paths have already been flattened by remaining_path.
static func paths_conflict(first: PackedVector3Array, second: PackedVector3Array, clearance: float) -> bool:
	for a in range(1, first.size()):
		for b in range(1, second.size()):
			var nearest := Geometry3D.get_closest_points_between_segments(first[a - 1], first[a], second[b - 1], second[b])
			if nearest[0].distance_to(nearest[1]) < clearance: return true
	return false

static func _radius(context) -> float:
	return context.coordination_motion_state().radius

## A finite local proposal for vacating a blocked slot. The coordinator chooses
## who yields and when they return; this helper supplies only checked routes.
static func yield_route(context, slot: Dictionary, occupied: Array, destinations: Array) -> PackedVector3Array:
	var start: Vector3 = context.coordination_motion_state().position
	var clearance: float = slot.spacing - 0.06
	var front: Vector3 = slot.entry - slot.peek
	front.y = 0.0
	for radius in [float(slot.spacing) * 1.25, float(slot.spacing) * 2.0]:
		for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0]:
			var point: Vector3 = start + front.normalized().rotated(Vector3.UP, angle) * radius
			if destinations.any(func(goal): return Vector2(point.x - goal.x, point.z - goal.z).length() < clearance): continue
			var route: PackedVector3Array = context.inspection_route(slot, point, occupied, PackedVector3Array([start, point]))
			if not route.is_empty(): return route
	return PackedVector3Array()

## Bounded repair for an occupied ingress. The squad holds the other members
## while this route is used. The graph surrounds measured bodies, not hidden
## targets; every chosen edge still needs the original navigation/body checks.
static func repair_route(context, slot: Dictionary, goal: Vector3, occupied: Array, original: PackedVector3Array) -> PackedVector3Array:
	var start: Vector3 = context.coordination_motion_state().position
	goal.y = start.y
	var clearance: float = float(slot.spacing) - 0.06
	for center: Vector3 in occupied:
		var difference: Vector3 = goal - center
		difference.y = 0.0
		if difference.length() < clearance: return PackedVector3Array()
	var geometry: Dictionary = Geometry.describe(context, slot.clue, false) if slot.kind == &"cover" else point_geometry(context, slot.clue, slot)
	if geometry.is_empty(): return PackedVector3Array()
	var remaining := remaining_path(start, original)
	var clear_route := true
	for index in range(1, remaining.size()):
		for center: Vector3 in occupied:
			if corridor_entry(remaining[index - 1], remaining[index], center, center, clearance, index == 1) < remaining[index - 1].distance_to(remaining[index]) - 0.001:
				clear_route = false
	if clear_route and Geometry._walkable_path(context, remaining, geometry.radius): return remaining
	var points: Array[Vector3] = [start, goal]
	# Ring vertices alone miss a narrow free slot between two parked ranks.
	# Approach the actual destination along the formation axes as well.
	var forward: Vector3 = (slot.entry - slot.peek).normalized()
	for axis in [forward, -forward, Vector3.UP.cross(forward), -Vector3.UP.cross(forward)]:
		var point: Vector3 = goal + axis * (clearance * 1.2)
		if Geometry._on_navigation(context, point): points.append(point)
	var nearby: Array = occupied.duplicate()
	nearby.sort_custom(func(a, b): return start.distance_squared_to(a) < start.distance_squared_to(b))
	# Limit the repair graph; all bodies, including those outside the graph,
	# are still checked as obstacles. Never silently ignore their occupancy.
	for center: Vector3 in nearby.slice(0, 6):
		for index in 8:
			var offset := Vector3.RIGHT.rotated(Vector3.UP, TAU * index / 8.0)
			var point: Vector3 = center + offset * (clearance / cos(PI / 8.0) + 0.04)
			point.y = start.y
			if Geometry._on_navigation(context, point): points.append(point)
	for vertex: Vector3 in remaining_path(start, original):
		if points.size() >= 66: break
		if not points.any(func(point): return point.distance_to(vertex) < 0.06): points.append(vertex)
	var edges := {}
	for first in points.size():
		for second in points.size():
			if first == second: continue
			var length: float = points[first].distance_to(points[second])
			var clear := true
			for center: Vector3 in occupied:
				if corridor_entry(points[first], points[second], center, center, clearance, first == 0) < length - 0.001:
					clear = false
					break
			if clear: edges[Vector2i(first, second)] = length
	var verified := {}
	# Lazy edge validation keeps expensive navigation/sweep work bounded.
	# An obstructed edge is removed and the same finite graph is searched again.
	for attempt in 12:
		var costs := {0: 0.0}
		var previous := {}
		var closed := {}
		for step in points.size():
			var best := -1
			for index in costs:
				if not closed.has(index) and (best < 0 or costs[index] < costs[best]): best = index
			if best < 0 or best == 1: break
			closed[best] = true
			for index in points.size():
				var edge := Vector2i(best, index)
				if closed.has(index) or not edges.has(edge): continue
				var cost: float = costs[best] + edges[edge]
				if cost < float(costs.get(index, INF)):
					costs[index] = cost
					previous[index] = best
		if not previous.has(1): return PackedVector3Array()
		var indices: Array[int] = [1]
		while indices[0] != 0: indices.push_front(previous[indices[0]])
		var result := PackedVector3Array([start])
		var valid := true
		for index in range(1, indices.size()):
			var edge := Vector2i(indices[index - 1], indices[index])
			if not verified.has(edge):
				var path: PackedVector3Array = context.cover_selection._query_path_to(points[edge.x], points[edge.y])
				# An edge cannot secretly take a different navigation detour through
				# a reserved body or the other end of the cover.
				verified[edge] = not path.is_empty() and context.cover_selection._path_length_from_path(path) <= edges[edge] + 0.05
			if not verified[edge]:
				edges.erase(edge)
				valid = false
				break
			result.append(points[edge.y])
			if not Geometry._walkable_path(context, result, geometry.radius) or not Geometry.approach_uses_assigned_end(geometry, result, slot.side):
				edges.erase(edge)
				valid = false
				break
		if valid: return result
	return PackedVector3Array()

## Remaining frozen route from the actual body. Pure segment projection; it
## does not replace the route with a new shortest path through another queue.
static func remaining_path(position: Vector3, path: PackedVector3Array) -> PackedVector3Array:
	if path.is_empty(): return PackedVector3Array()
	var nearest := INF
	var start := 0
	var projection := position
	for i in range(1, path.size()):
		var a := Vector3(path[i - 1].x, position.y, path[i - 1].z)
		var b := Vector3(path[i].x, position.y, path[i].z)
		var point := Geometry3D.get_closest_point_to_segment(position, a, b)
		var distance := position.distance_squared_to(point)
		if distance <= nearest:
			nearest = distance
			start = i
			projection = point
	var result := PackedVector3Array([position])
	# Combat or an external displacement can leave the body beside the baked
	# corridor. Preserve its entry segment instead of cutting straight to the
	# next corner (which may cross a wall or remain outside navigation).
	if projection.distance_to(position) > 0.025: result.append(projection)
	for i in range(start, path.size()):
		var point := Vector3(path[i].x, position.y, path[i].z)
		if point.distance_to(result[-1]) > 0.06: result.append(point)
	return result

## First intersection of a finite movement segment with a reserved horizontal
## corridor (rectangle plus endpoint circles). Returns travel distance, not a
## permission to pass through bodies. Used by the owning squad at execution.
static func corridor_entry(origin: Vector3, target: Vector3, a: Vector3, b: Vector3, radius: float, allow_departure: bool = false) -> float:
	a.y = origin.y
	b.y = origin.y
	target.y = origin.y
	var distance := origin.distance_to(target)
	if distance < 0.001: return 0.0
	var axis := (target - origin) / distance
	var away := origin - Geometry3D.get_closest_point_to_segment(origin, a, b)
	# An already close body may leave the occupied corridor. Freezing both
	# participants inside the clearance boundary would prevent recovery.
	if allow_departure and away.length_squared() < radius * radius and away.dot(axis) > 0.00001: return distance
	var allowed := distance
	for point in [a, b]:
		var offset: Vector3 = point - origin
		var along: float = offset.dot(axis)
		var lateral: float = offset.length_squared() - along * along
		if lateral >= radius * radius: continue
		var reach := sqrt(maxf(0.0, radius * radius - lateral))
		if along + reach > 0.0: allowed = minf(allowed, maxf(0.0, along - reach))
	var length := a.distance_to(b)
	if length < 0.001: return allowed
	var forward := (b - a) / length
	var normal := Vector3.UP.cross(forward)
	var interval := Vector2(0.0, distance)
	for band in [[normal, -radius, radius], [forward, 0.0, length]]:
		var offset: float = (origin - a).dot(band[0])
		var rate: float = axis.dot(band[0])
		if absf(rate) < 0.00001:
			if offset < band[1] or offset > band[2]: return allowed
			continue
		var first: float = (band[1] - offset) / rate
		var last: float = (band[2] - offset) / rate
		interval.x = maxf(interval.x, minf(first, last))
		interval.y = minf(interval.y, maxf(first, last))
		if interval.x > interval.y: return allowed
	return minf(allowed, interval.x)

## No associated wall: assemble a compact front on the observer's side of the
## shared clue, then advance together to observe it. This is still one mission.
static func point_geometry(context, evidence: Dictionary, order: Dictionary) -> Dictionary:
	var front: Vector3 = order.front_axis
	front.y = 0.0
	if front.is_zero_approx(): return {}
	front = front.normalized()
	var right: Vector3 = Vector3.UP.cross(front)
	var rank: float = float(order.row) - float(order.depth - 1) * 0.5
	var known: Vector3 = evidence.position
	var peek: Vector3 = known + front * 1.2 + right * rank * float(order.spacing)
	var entry: Vector3 = peek + front * 2.0
	entry.y = context.actor.global_position.y
	peek.y = entry.y
	var shape: CollisionShape3D = context.actor.get_node("CollisionShape3D")
	var radius: float = shape.shape.radius * maxf(shape.global_basis.x.length(), shape.global_basis.z.length())
	return {"kind": &"point", "cover_id": 0, "known": known, "radius": radius,
		"navigation_iteration": NavigationServer3D.map_get_iteration_id(context.agent.get_navigation_map()),
		"ends": {1: {"entry": entry, "peek": peek}}, "inspection_id": evidence.id, "target_id": evidence.target_id}

static func route(context, geometry: Dictionary, order: Dictionary) -> Dictionary:
	if order.is_empty() or not Geometry.valid(context, geometry): return {}
	if order.get("route_planned", false):
		if not order.has("entry"): return {}
		return _route_at(context, geometry, order, order.entry, order.peek, order.stagger)
	var end: int = order.side
	var row: int = order.row
	var depth: int = order.depth
	var spacing: float = order.spacing
	if not geometry.ends.has(end): return {}
	var endpoints: Dictionary = geometry.ends[end]
	if geometry.get("kind") == &"point":
		var prepared: Dictionary = Geometry.route(context, geometry, end)
		if not prepared.is_empty(): prepared.merge({"formation": order.duplicate(true), "stagger": 0.0})
		return prepared
	var front: Vector3 = (endpoints.entry - endpoints.peek).normalized()
	var box: CollisionShape3D = geometry.cover.get_ref().get_node("CollisionShape3D")
	var outward: Vector3 = (box.global_basis.x if geometry.along_x else box.global_basis.z).normalized() * end
	# Do not park a leader on the remembered point itself: its capsule would
	# permanently hide that point from the other queue. Move the whole lane's
	# final ranks together, preserving their longitudinal spacing.
	var nearest: Vector3 = endpoints.peek - geometry.known
	nearest.y = 0.0
	var observation_clearance: float = geometry.radius + 0.45 + 0.18
	var advance := 0.0
	if nearest.length() < observation_clearance:
		var lateral: float = absf(nearest.dot(outward))
		advance = maxf(0.0, sqrt(maxf(0.0, observation_clearance * observation_clearance - lateral * lateral)) - nearest.dot(-front))
	# Rear ranks alternate lateral offsets. A blocked stagger falls back to the
	# same validated lane, retaining longitudinal body clearance.
	for stagger in [0.45 if row % 2 == 1 and order.get("layout", 0) == 0 else 0.0, 0.0]:
		var entry: Vector3 = endpoints.entry + front * spacing * row + outward * stagger
		var peek: Vector3 = endpoints.peek - front * (spacing * (depth - row - 1) + advance) + outward * stagger
		var prepared := _route_at(context, geometry, order, entry, peek, stagger)
		if not prepared.is_empty(): return prepared
	return {}

static func _route_at(context, geometry: Dictionary, order: Dictionary, entry: Vector3, peek: Vector3, stagger: float) -> Dictionary:
	if not Geometry._on_navigation(context, entry) or not Geometry._on_navigation(context, peek): return {}
	var approach: PackedVector3Array = remaining_path(context.actor.global_position, order.approach) if order.has("approach") else context.cover_selection._query_path_to(context.actor.global_position, entry)
	var crossing: PackedVector3Array = context.cover_selection._query_path_to(entry, peek)
	if approach.is_empty() or crossing.is_empty() or not Geometry.approach_uses_assigned_end(geometry, approach, order.side): return {}
	var path := approach.duplicate()
	for point in crossing:
		if path.is_empty() or path[-1].distance_to(point) > 0.01: path.append(point)
	if not Geometry._walkable_path(context, path, geometry.radius): return {}
	return {"entry": entry, "peek": peek, "path": path, "approach": approach,
		"length": context.cover_selection._path_length_from_path(path), "end": order.side,
		"geometry": geometry, "formation": order.duplicate(true), "stagger": stagger}
