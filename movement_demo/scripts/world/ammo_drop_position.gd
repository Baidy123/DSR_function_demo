extends RefCounted

## 单次死亡执行有限物理检查，不增加区域或 AI 循环。导航约束排除墙顶／其他楼层。
static func find_ground(region: Node3D, origin: Vector3) -> Vector3:
	var navigation := region.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	if navigation == null or not navigation.enabled or navigation.navigation_mesh == null: return Vector3.INF
	var rid := navigation.get_rid()
	if NavigationServer3D.region_get_iteration_id(rid) == 0: return Vector3.INF
	var anchor := NavigationServer3D.region_get_closest_point(rid, origin)
	if Vector2(anchor.x - origin.x, anchor.z - origin.z).length() > 1.6 or absf(anchor.y - origin.y) > 2.5: return Vector3.INF
	var excluded: Array[RID] = []
	for body in region.enemies + region.players_inside:
		if is_instance_valid(body) and body is CollisionObject3D: excluded.append(body.get_rid())
	var candidates: Array[Vector3] = [origin, anchor]
	for radius in [0.5, 1.0, 1.5]:
		for index in range(8): candidates.append(origin + Vector3(cos(index * TAU / 8), 0, sin(index * TAU / 8)) * radius)
	var space := region.get_world_3d().direct_space_state
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.4, 0.24, 0.3)
	for candidate in candidates:
		var ray := PhysicsRayQueryParameters3D.create(Vector3(candidate.x, maxf(origin.y, anchor.y) + 0.4, candidate.z), Vector3(candidate.x, anchor.y - 0.4, candidate.z), 1, excluded)
		var hit := space.intersect_ray(ray)
		if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.9 or absf(hit.position.y - anchor.y) > 0.35: continue
		var point: Vector3 = hit.position
		var walkable := NavigationServer3D.region_get_closest_point(rid, point)
		if Vector2(walkable.x - point.x, walkable.z - point.z).length() > 0.08 or absf(walkable.y - point.y) > 0.35: continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform.origin = point + Vector3.UP * 0.14
		query.collision_mask = 1
		query.exclude = excluded
		if not space.intersect_shape(query, 1).is_empty(): continue
		var route := NavigationServer3D.map_get_path(navigation.get_navigation_map(), anchor, walkable, true, 1)
		if route.is_empty() or route[-1].distance_to(walkable) > 0.1: continue
		var distance := 0.0
		for i in range(1, route.size()): distance += route[i - 1].distance_to(route[i])
		if distance > 6.0: continue
		return point + Vector3.UP * 0.01
	return Vector3.INF
