extends RefCounted

const MAX_LEG_LENGTH := 2.0
const INNER_RADIUS := 5.0
const FAR_RADIUS := 6.5
const MAX_ANCHOR_ANGLE := 70.0

## Finite arc proposals. Navigation still owns every walking leg; a path cutting
## through the known threat's immediate space is not a flank.
static func proposals(context, opportunity: Dictionary) -> Array:
	if int(opportunity.get("remaining_slots", 0)) <= 0: return []
	var anchor: Vector3 = opportunity.anchor
	var radial: Vector3 = context.actor.global_position - anchor
	radial.y = 0.0
	if radial.length() < 1.5: return []
	var distance_budget := _distance_budget(context)
	if distance_budget <= 0.0: return []
	var axis: Vector3 = opportunity.front_axis
	var result: Array = []
	for turn in [-1.0, 1.0]:
		for radius in [clampf(radial.length(), 3.0, 5.0), clampf(radial.length() + 1.5, 4.5, 6.5)]:
			var final_axis := axis.rotated(Vector3.UP, deg_to_rad(140.0) * turn)
			var angle := radial.normalized().signed_angle_to(final_axis, Vector3.UP)
			if angle * turn < 0.0: angle += TAU * turn
			if absf(angle) > deg_to_rad(220.0): continue
			# Far members first approach a useful orbit instead of spending most of
			# their deadline sweeping the distant radius (often outside the arena).
			var entry_radius: float = minf(radius, INNER_RADIUS) if radial.length() > FAR_RADIUS else radial.length()
			if radial.length() - entry_radius > distance_budget: continue
			var geometry := PackedVector3Array([context.actor.global_position])
			if entry_radius < radial.length():
				var entry := anchor + radial.normalized() * entry_radius
				entry.y = context.actor.global_position.y
				geometry.append(entry)
			# Sparse directional anchors leave navigation room to go around cover.
			# Execution leg spacing is derived from the resulting real path below.
			var legs := maxi(1, ceili(absf(angle) / deg_to_rad(MAX_ANCHOR_ANGLE) - 0.000001))
			for index in range(1, legs + 1):
				var ratio := float(index) / legs
				var point := anchor + radial.normalized().rotated(Vector3.UP, angle * ratio) * lerpf(entry_radius, radius, ratio)
				point.y = context.actor.global_position.y
				geometry.append(point)
			if _length(geometry) > distance_budget: continue
			var checkpoints := _short_checkpoints(geometry)
			result.append({"position": checkpoints[-1], "checkpoints": checkpoints, "route_anchors": geometry.slice(1),
				"flank_anchor": anchor, "flank_axis": axis, "flank_round_id": opportunity.round_id})
	return result

static func _distance_budget(context) -> float:
	return maxf(0.0, float(context.setting(&"cooperation", &"flank_plan_seconds", 14.0)) - 1.0) * maxf(0.0, context.actor.move_speed)

static func _length(path: PackedVector3Array) -> float:
	var total := 0.0
	for index in range(1, path.size()): total += path[index - 1].distance_to(path[index])
	return total

## Measure along the whole polyline. Tiny navigation corners are internal to
## a walking leg, not a new tactical stop; assess revalidates its complete path.
static func _short_checkpoints(path: PackedVector3Array) -> PackedVector3Array:
	var result := PackedVector3Array()
	var remaining := MAX_LEG_LENGTH
	for index in range(1, path.size()):
		var start := path[index - 1]
		var end := path[index]
		var distance := start.distance_to(end)
		while distance >= remaining:
			start = start.lerp(end, remaining / distance)
			result.append(start)
			distance = start.distance_to(end)
			remaining = MAX_LEG_LENGTH
		remaining -= distance
	if not path.is_empty():
		if result.is_empty() or result[-1].distance_to(path[-1]) > 0.001: result.append(path[-1])
		else: result[-1] = path[-1]
	return result

static func safe_path(path: PackedVector3Array, anchor: Vector3) -> bool:
	if path.is_empty(): return false
	for index in range(1, path.size()):
		var start := Vector2(path[index - 1].x, path[index - 1].z)
		var end := Vector2(path[index].x, path[index].z)
		var threat := Vector2(anchor.x, anchor.z)
		if Geometry2D.get_closest_point_to_segment(threat, start, end).distance_to(threat) < 1.5: return false
	return true

static func assess(context, point: Dictionary) -> Dictionary:
	var anchors: PackedVector3Array = point.get("route_anchors", point.get("checkpoints", PackedVector3Array()))
	var distance_budget := _distance_budget(context)
	if anchors.is_empty() or distance_budget <= 0.0 or context.actor.global_position.distance_to(anchors[-1]) > distance_budget: return {}
	var walking := PackedVector3Array([context.actor.global_position])
	var from: Vector3 = context.actor.global_position
	var total := 0.0
	for index in anchors.size():
		var checkpoint: Vector3 = anchors[index]
		var optional_anchor: bool = point.has("route_anchors") and index < anchors.size() - 1
		# An ideal intermediate point in a navigation hole is not an executable
		# checkpoint. Try the next finite anchor instead; never move/snap this one.
		if not context.is_position_free(checkpoint):
			if optional_anchor: continue
			return {}
		var path: PackedVector3Array = context.cover_selection._path_to(from, checkpoint)
		if path.is_empty() and optional_anchor: continue
		if not safe_path(path, point.flank_anchor): return {}
		total += context.cover_selection._path_length_from_path(path)
		if total > distance_budget: return {}
		for vertex: Vector3 in path:
			# Existing destinations use feet height; baked navigation is slightly
			# raised. Keep the same vertical tolerance and strict horizontal path.
			var feet := Vector3(vertex.x, context.actor.global_position.y, vertex.z)
			if walking[-1].distance_to(feet) > 0.001: walking.append(feet)
		if walking[-1].distance_to(checkpoint) > 0.001: walking.append(checkpoint)
		from = checkpoint
	if walking.size() < 2: return {}
	var checkpoints := _short_checkpoints(walking)
	var first_path := PackedVector3Array()
	from = context.actor.global_position
	total = 0.0
	for checkpoint: Vector3 in checkpoints:
		if not context.is_position_free(checkpoint): return {}
		var path: PackedVector3Array = context.cover_selection._path_to(from, checkpoint)
		if not safe_path(path, point.flank_anchor): return {}
		var length: float = context.cover_selection._path_length_from_path(path)
		if length > MAX_LEG_LENGTH + 0.01: return {}
		if first_path.is_empty():
			if not departure_clear(context, path): return {}
			first_path = path
		total += length
		if total > distance_budget: return {}
		from = checkpoint
	var result := point.duplicate(true)
	result.checkpoints = checkpoints
	result.path = first_path
	result.route_seconds = total / maxf(0.1, context.actor.move_speed)
	return result

static func departure_clear(context, path: PackedVector3Array) -> bool:
	for member: Dictionary in context.cooperation_snapshot().get("members", []):
		if member.id == context.actor.get_instance_id(): continue
		var position: Vector3 = member.position
		if absf(position.y - context.actor.global_position.y) > 1.0: continue
		for index in range(1, path.size()):
			var start := Vector2(path[index - 1].x, path[index - 1].z)
			var end := Vector2(path[index].x, path[index].z)
			var other := Vector2(position.x, position.z)
			if Geometry2D.get_closest_point_to_segment(other, start, end).distance_to(other) < 0.75: return false
	return true
