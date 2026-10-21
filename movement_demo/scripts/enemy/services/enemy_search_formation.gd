extends RefCounted

## Locally validated slots for one coordinator-owned inspection order. No body
## movement, target reads, assignments or fire authority live in this helper.
const Geometry = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd")

static func route(context, geometry: Dictionary, order: Dictionary) -> Dictionary:
	if order.is_empty() or not Geometry.valid(context, geometry): return {}
	var end: int = order.side
	var row: int = order.row
	var depth: int = order.depth
	var spacing: float = order.spacing
	var endpoints: Dictionary = geometry.ends[end]
	var front: Vector3 = (endpoints.entry - endpoints.peek).normalized()
	var outward: Vector3 = (geometry.ends[end].entry - geometry.ends[-end].entry).normalized()
	# Rear ranks alternate lateral offsets. A blocked stagger falls back to the
	# same validated lane, retaining longitudinal body clearance.
	for stagger in [0.45 if row % 2 == 1 else 0.0, 0.0]:
		var entry: Vector3 = endpoints.entry + front * spacing * row + outward * stagger
		var peek: Vector3 = endpoints.peek - front * spacing * (depth - row - 1) + outward * stagger
		if not Geometry._on_navigation(context, entry) or not Geometry._on_navigation(context, peek): continue
		var approach: PackedVector3Array = context.cover_selection._query_path_to(context.actor.global_position, entry)
		var crossing: PackedVector3Array = context.cover_selection._query_path_to(entry, peek)
		if approach.is_empty() or crossing.is_empty(): continue
		var path := approach.duplicate()
		for point in crossing:
			if path.is_empty() or path[-1].distance_to(point) > 0.01: path.append(point)
		if not Geometry._walkable_path(context, path, geometry.radius): continue
		return {"entry": entry, "peek": peek, "path": path, "approach": approach,
			"length": context.cover_selection._path_length_from_path(path), "end": end,
			"geometry": geometry, "formation": order.duplicate(true), "stagger": stagger}
	return {}
