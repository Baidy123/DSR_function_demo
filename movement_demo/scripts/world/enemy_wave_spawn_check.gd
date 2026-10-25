extends RefCounted

## 波次控制器私有的只读部署检查；不选新位置、不改身体、没有更新循环。
static func inspect(region: Node3D, deployments: Array[Dictionary]) -> Dictionary:
	var navigation := region.get_node_or_null("NavigationRegion3D") as NavigationRegion3D
	var zone := region.get_node_or_null("CombatZone/CollisionShape3D") as CollisionShape3D
	if navigation == null or zone == null or not zone.shape is BoxShape3D:
		return _result("error", "区域需要 NavigationRegion3D 和盒形 CombatZone/CollisionShape3D。")
	if not navigation.is_inside_tree() or not navigation.enabled or navigation.navigation_mesh == null or zone.disabled:
		return _result("wait", "等待本区域导航和战斗区启用。")
	var map := navigation.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0 or NavigationServer3D.region_get_iteration_id(navigation.get_rid()) == 0:
		return _result("wait", "等待本区域导航同步。")
	var bodies: Array[Dictionary] = []
	for deployment in deployments:
		var parent: Node = deployment.parent.get_ref()
		if not is_instance_valid(parent) or not parent.is_inside_tree() or (parent != region and not region.is_ancestor_of(parent)):
			return _result("error", "小队的部署父节点已离开本区域。")
		if parent.get_node_or_null(NodePath(str(deployment.root.name))) != null:
			return _result("error", "小队部署路径被同名节点占用：%s" % deployment.root.name)
		for enemy in deployment.members:
			var pose := _world_transform(enemy, parent)
			var collision := enemy.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collision == null or not collision.shape is CapsuleShape3D:
				return _result("error", "%s：需要原敌人胶囊碰撞体。" % enemy.name)
			var collision_pose := pose * collision.transform
			# 原身体初始化会恢复站高和胶囊中心Y，检查同一实际站姿。
			var height: float = enemy.get_posture_body_height(false)
			var offset: Vector3 = collision.position
			offset.y = height * 0.5
			collision_pose.origin = pose * offset
			if not pose.is_finite() or not collision_pose.basis.get_scale().is_equal_approx(Vector3.ONE) or not collision_pose.basis.y.is_equal_approx(Vector3.UP):
				return _result("error", "%s：角色须直立且不缩放；请移动或水平旋转部署。" % enemy.name)
			if enemy.top_level or collision.top_level:
				return _result("error", "%s：部署角色与碰撞体不能启用 Top Level。" % enemy.name)
			var inside := AABB(-zone.shape.size * 0.5, zone.shape.size).has_point(zone.to_local(pose.origin + Vector3.UP * height * 0.5))
			var point := NavigationServer3D.region_get_closest_point(navigation.get_rid(), pose.origin)
			if not inside or Vector2(point.x - pose.origin.x, point.z - pose.origin.z).length() > 0.05 or absf(point.y - pose.origin.y) > 0.5:
				return _result("error", "%s：刷新点不在本区域的可站立导航范围内，请调整场景部署。" % enemy.name)
			var capsule := CapsuleShape3D.new()
			capsule.radius = collision.shape.radius
			capsule.height = height
			var body := {"shape": capsule, "pose": collision_pose, "mask": enemy.collision_mask, "layer": enemy.collision_layer, "name": enemy.name}
			for other in bodies:
				if ((body.mask & other.layer) != 0 or (other.mask & body.layer) != 0) and _overlaps(body, other):
					return _result("error", "%s 与 %s：同波部署的胶囊重叠，请分开摆放。" % [body.name, other.name])
			bodies.append(body)
	var space := region.get_world_3d().direct_space_state
	for body in bodies:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = body.shape
		query.transform = body.pose
		# 完整半径／站高，只上移1厘米避开地板接触；不排除玩家或任何现有角色。
		query.transform.origin.y += 0.01
		query.collision_mask = body.mask
		query.margin = 0.001
		var hits := space.intersect_shape(query, 16)
		for hit in hits:
			if hit.collider is StaticBody3D:
				return _result("error", "%s：刷新身体与静态障碍 %s 相交，请调整部署。" % [body.name, hit.collider.name])
		if not hits.is_empty(): return _result("wait", "%s：刷新点被角色或可移动物体占用，等待让开。" % body.name)
	return _result("ready", "")

static func _world_transform(node: Node3D, parent: Node) -> Transform3D:
	var pose := node.transform
	var ancestor := node.get_parent()
	while ancestor != null:
		if ancestor is Node3D: pose = ancestor.transform * pose
		ancestor = ancestor.get_parent()
	# 待生成根还在树外；它未来父节点的世界变换在这里接上。
	var spatial_parent := parent
	while spatial_parent != null and not spatial_parent is Node3D: spatial_parent = spatial_parent.get_parent()
	return spatial_parent.global_transform * pose if spatial_parent != null else pose

static func _overlaps(a: Dictionary, b: Dictionary) -> bool:
	var first: Vector3 = a.pose.origin
	var second: Vector3 = b.pose.origin
	var half_a: float = maxf(0.0, a.shape.height * 0.5 - a.shape.radius)
	var half_b: float = maxf(0.0, b.shape.height * 0.5 - b.shape.radius)
	var gap_y := maxf(0.0, absf(first.y - second.y) - half_a - half_b)
	var distance_squared := Vector2(first.x - second.x, first.z - second.z).length_squared() + gap_y * gap_y
	return distance_squared < pow(a.shape.radius + b.shape.radius + 0.001, 2.0)

static func _result(kind: String, reason: String) -> Dictionary:
	return {"kind": kind, "reason": reason}
