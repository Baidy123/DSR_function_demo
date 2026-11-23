extends RefCounted

## 无动作状态的几何查询。区域细分只用已知威胁和墙角投影，不进行物理查询。
func cells(context, region: StaticBody3D, threat: Vector3) -> Array[Dictionary]:
	return refine(context, region, threat, region.get_attack_cells())

func refine(context, region: StaticBody3D, threat: Vector3, source: Array[Dictionary]) -> Array[Dictionary]:
	var pending: Array[Dictionary] = source.duplicate()
	var result: Array[Dictionary] = []
	var collision: CollisionShape3D = context.actor.get_node("CollisionShape3D")
	var radius: float = collision.shape.radius * maxf(collision.global_basis.x.length(), collision.global_basis.z.length()) if collision.shape is CapsuleShape3D else 0.35
	var levels: int = clampi(int(context.setting(&"selection", &"attack_refinement_levels", 1)), 0, 2)
	while not pending.is_empty():
		var cell: Dictionary = pending.pop_back()
		# 低墙沿完整外围带采样，没有高墙墙角的极坐标或投影边界。
		if cell.get("kind") == &"low_cover_band":
			result.append(cell)
			continue
		if cell.depth < levels and _near_silhouette_edge(cell, threat, radius):
			pending.append_array(region.subdivide_attack_cell(cell))
		else:
			result.append(cell)
	return result

func _near_silhouette_edge(cell: Dictionary, threat: Vector3, radius: float) -> bool:
	var corner := Vector2(cell.corner.x, cell.corner.z)
	var origin := Vector2(threat.x, threat.z)
	var direction := corner - origin
	if direction.is_zero_approx(): return false
	direction = direction.normalized()
	var center := Vector2(cell.position.x, cell.position.z)
	var extent := 0.0
	for vertex: Vector3 in cell.polygon:
		extent = maxf(extent, center.distance_to(Vector2(vertex.x, vertex.z)))
	# 只有墙角之后、玩家到墙角的投影边界附近，才可能遮住身体一侧。
	return (center - corner).dot(direction) >= -radius - extent and absf(direction.cross(center - corner)) <= radius + extent

## 将真实胶囊轮廓投影到面向威胁的平面。五层七列射线，按每层实际宽度加权。
## 每根射线止于身体采样位置，只统计所属墙在身体之前的遮挡。
func protection(context, point: Vector3, threat: Vector3, region: StaticBody3D) -> float:
	var actor = context.actor
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	if not collision.shape is CapsuleShape3D: return -1.0
	var center: Vector3 = point + Vector3.UP * actor.get_posture_body_height(false) * 0.5
	var forward := center - threat
	forward.y = 0.0
	if forward.is_zero_approx(): return 0.0
	var side := forward.normalized().cross(Vector3.UP)
	var radius: float = collision.shape.radius * minf(collision.global_basis.x.length(), collision.global_basis.z.length())
	var half_height: float = actor.get_posture_body_height(false) * 0.5 * collision.global_basis.y.length()
	var cap_height: float = collision.shape.radius * collision.global_basis.y.length()
	var cylinder := maxf(0.0, half_height - cap_height)
	var blocked := 0.0
	var total := 0.0
	var query: PhysicsRayQueryParameters3D = context.cover_selection._ray_query(threat, center)
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	var wall: CollisionShape3D = region.get_node("CollisionShape3D")
	var wall_box := AABB(-wall.shape.size * 0.5, wall.shape.size)
	var wall_inverse := wall.global_transform.affine_inverse()
	var local_threat: Vector3 = wall_inverse * threat
	for row in 5:
		var height := lerpf(-half_height, half_height, (float(row) + 0.5) / 5.0)
		var cap := maxf(0.0, absf(height) - cylinder) / maxf(0.001, cap_height)
		var width := radius * sqrt(maxf(0.0, 1.0 - cap * cap))
		for column in 7:
			var lateral := lerpf(-width, width, (float(column) + 0.5) / 7.0)
			var target := center + Vector3.UP * height + side * lateral
			total += width
			# A segment missing the assigned box cannot count as its protection.
			# Intersections still use physics, so nearer walls retain precedence.
			if not wall_box.intersects_segment(local_threat, wall_inverse * target): continue
			query.to = target
			var hit: Dictionary = space.intersect_ray(query)
			if not hit.is_empty() and hit.collider == region: blocked += width
	return blocked / maxf(0.001, total)
