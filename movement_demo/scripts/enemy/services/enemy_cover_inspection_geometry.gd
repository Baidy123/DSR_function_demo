extends RefCounted

## Frozen-clue walking geometry. No target body reads, fire requests or leases.
const BodyGeometry = preload("res://scripts/systems/character_geometry.gd")

static func describe(context, evidence: Dictionary) -> Dictionary:
	if evidence.is_empty() or not evidence.get("position", Vector3.INF).is_finite(): return {}
	var cover = evidence.get("cover")
	if cover is WeakRef: cover = cover.get_ref()
	if not is_instance_valid(cover): cover = context.cover_selection.confirmed_suppression_cover(evidence.position)
	if not is_instance_valid(cover) or not cover is StaticBody3D or not cover.is_in_group("cover_region") or not context.navigation_region.is_ancestor_of(cover): return {}
	var box := cover.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if box == null or box.disabled or not box.shape is BoxShape3D or (cover.collision_layer & 1) == 0: return {}
	if box.global_basis.y.normalized().dot(Vector3.UP) < 0.999: return {}
	var half: Vector3 = box.shape.size * 0.5
	var observer: Vector3 = evidence.get("observer_position", Vector3.INF)
	if not observer.is_finite(): return {}
	var origin: Vector3 = box.to_local(observer)
	var known: Vector3 = box.to_local(evidence.position)
	var surface: Vector3 = box.to_global(Vector3(clampf(known.x, -half.x, half.x), known.y, clampf(known.z, -half.z, half.z)))
	if context._horizontal_distance_between(surface, evidence.position) > float(context.setting(&"selection", &"cover_inference_distance", 1.75)): return {}
	var along_x := absf(origin.z) / maxf(0.01, half.z) >= absf(origin.x) / maxf(0.01, half.x)
	var side := signf(origin.z if along_x else origin.x)
	if is_zero_approx(side): return {}
	var across := half.z if along_x else half.x
	var along := half.x if along_x else half.z
	var known_across: float = known.z if along_x else known.x
	# A remembered point in front of the middle of a wall is not evidence of
	# somebody behind it. End/corner clues remain a legitimate investigation.
	if known_across * side > across and absf(known.x if along_x else known.z) < along: return {}
	var shape: CollisionShape3D = context.actor.get_node("CollisionShape3D")
	var radius: float = shape.shape.radius * maxf(shape.global_basis.x.length(), shape.global_basis.z.length())
	var along_scale: float = (box.global_basis.x if along_x else box.global_basis.z).length()
	var across_scale: float = (box.global_basis.z if along_x else box.global_basis.x).length()
	var margin_along: float = (radius + 0.25) / along_scale
	var margin_across: float = (radius + 0.25) / across_scale
	var ends: Dictionary = {}
	for end in [-1, 1]:
		var entry_local := Vector3(end * (along + margin_along), -half.y, side * (across + margin_across))
		var peek_local := Vector3(entry_local.x, entry_local.y, -entry_local.z)
		if not along_x:
			entry_local = Vector3(entry_local.z, entry_local.y, entry_local.x)
			peek_local = Vector3(peek_local.z, peek_local.y, peek_local.x)
		var entry: Vector3 = box.to_global(entry_local)
		var peek: Vector3 = box.to_global(peek_local)
		entry.y = context.actor.global_position.y
		peek.y = entry.y
		if not _on_navigation(context, entry) or not _on_navigation(context, peek): continue
		if not BodyGeometry.can_sweep(context.actor, entry, peek, context.actor.get_body_height(), radius, true): continue
		ends[end] = {"entry": entry, "peek": peek}
	if ends.size() != 2: return {}
	return {"cover": weakref(cover), "cover_id": cover.get_instance_id(), "cover_transform": box.global_transform,
		"cover_size": box.shape.size, "known": evidence.position, "observer_position": observer, "along_x": along_x,
		"front_sign": side, "half_along": along, "half_across": across, "radius": radius,
		"ends": ends, "inspection_id": int(evidence.get("id", 0)), "target_id": evidence.target_id}

static func valid(context, geometry: Dictionary) -> bool:
	if geometry.is_empty(): return false
	var cover = geometry.cover.get_ref()
	if not is_instance_valid(cover) or not context.navigation_region.is_ancestor_of(cover): return false
	var box := cover.get_node_or_null("CollisionShape3D") as CollisionShape3D
	return box != null and not box.disabled and box.shape is BoxShape3D and (cover.collision_layer & 1) != 0 and box.global_transform == geometry.cover_transform and box.shape.size == geometry.cover_size

static func route(context, geometry: Dictionary, end: int) -> Dictionary:
	if not valid(context, geometry) or not geometry.ends.has(end): return {}
	var endpoints: Dictionary = geometry.ends[end]
	var approach: PackedVector3Array = context.cover_selection._path_to(context.actor.global_position, endpoints.entry)
	var inspect: PackedVector3Array = context.cover_selection._path_to(endpoints.entry, endpoints.peek)
	if approach.is_empty() or inspect.is_empty(): return {}
	var cover = geometry.cover.get_ref()
	var box: CollisionShape3D = cover.get_node("CollisionShape3D")
	# A different endpoint is insufficient: the actual approach cannot already
	# wrap around the opposite end and enter through the other inspector's lane.
	for point in approach:
		var local: Vector3 = box.to_local(point)
		var across: float = local.z if geometry.along_x else local.x
		var along: float = local.x if geometry.along_x else local.z
		if across * float(geometry.front_sign) < -float(geometry.half_across) and along * end < 0.0: return {}
	var path := approach.duplicate()
	for point in inspect:
		if path.is_empty() or path[-1].distance_to(point) > 0.01: path.append(point)
	if not _walkable_path(context, path, geometry.radius): return {}
	var length: float = context.cover_selection._path_length_from_path(path)
	return {"entry": endpoints.entry, "peek": endpoints.peek, "path": path,
		"approach": approach, "length": length, "end": end, "geometry": geometry}

static func _on_navigation(context, point: Vector3) -> bool:
	var projected: Vector3 = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), point)
	return context._horizontal_distance_between(point, projected) <= 0.05 and absf(point.y - projected.y) <= 0.5

static func _walkable_path(context, path: PackedVector3Array, radius: float) -> bool:
	var previous: Vector3 = context.actor.global_position
	for vertex in path:
		var point := Vector3(vertex.x, previous.y, vertex.z)
		if not _on_navigation(context, point) or not BodyGeometry.can_sweep(context.actor, previous, point, context.actor.get_body_height(), radius, true): return false
		previous = point
	return true
