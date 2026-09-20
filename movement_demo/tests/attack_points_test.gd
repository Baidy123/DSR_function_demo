extends SceneTree

var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var wall = load("res://cover_region.gd").new()
	root.add_child(wall)
	_check("提供候选攻击点接口", wall.has_method("get_attack_candidates"))
	if not checks.values().all(func(value): return value):
		wall.free()
		_finish()
		return
	_check("无碰撞盒时无候选", wall.get_attack_candidates().is_empty())
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(4, 2, 1)
	collision.position.y = 1.0
	wall.add_child(collision)
	var before: Array = wall.get_candidates(Vector3(0, 0, 4), Vector3(0, 0, -4))
	var points: Array = wall.get_attack_candidates()
	_check("四角各有两面候选且不重复", points.size() == 8 and _unique_count(points) == 8)
	_check("脚底位于碰撞盒底面", points.all(func(point): return is_zero_approx(point.y)))
	_check("身体中心与实体保持距离", points.all(func(point):
		return Vector2(maxf(absf(point.x) - 2.0, 0.0), maxf(absf(point.z) - 0.5, 0.0)).length() >= 0.54))
	wall.position = Vector3(6, 0.4, -3)
	wall.rotation.y = 0.71
	wall.scale = Vector3(1.3, 1.2, 0.8)
	collision.rotation.y = -0.23
	collision.position.x = 0.3
	var transformed: Array = wall.get_attack_candidates()
	var follows := true
	for index in points.size():
		follows = follows and transformed[index].is_equal_approx(collision.to_global(points[index] - Vector3.UP))
	_check("跟随掩体及碰撞盒的平移旋转缩放", follows)
	wall.transform = Transform3D.IDENTITY
	collision.transform = Transform3D(Basis.IDENTITY, Vector3.UP)
	wall.attack_wall_gap = 0.8
	var wider: Array = wall.get_attack_candidates()
	_check("离墙参数调整候选位置", not wider[0].is_equal_approx(points[0]))
	wall.attack_corner_offset = -0.15
	var inward: Array = wall.get_attack_candidates()
	_check("沿墙偏移独立于离墙距离", is_equal_approx(inward[0].z, wider[0].z) and not is_equal_approx(inward[0].x, wider[0].x))
	_check("调整攻击点不改变躲藏及Peek", before == wall.get_candidates(Vector3(0, 0, 4), Vector3(0, 0, -4)))
	wall.show_attack_points_in_editor = false
	_check("关闭辅助显示不影响候选数据", inward == wall.get_attack_candidates())
	collision.shape.size = Vector3(1, 2, 4)
	_check("支持Z方向长墙", wall.get_attack_candidates().size() == 8)
	collision.shape = SphereShape3D.new()
	_check("非长方体不生成候选", wall.get_attack_candidates().is_empty())
	wall.free()
	var packed: PackedScene = load("res://cover.tscn")
	var first = packed.instantiate()
	var second = packed.instantiate()
	root.add_child(first)
	root.add_child(second)
	_check("独立掩体场景自带碰撞及点位", first.has_node("Mesh") and first.has_node("CollisionShape3D") and first.get_attack_candidates().size() == 8 and first.is_in_group("cover_region"))
	_check("新实例的外观与碰撞尺寸一致", first.get_node("Mesh").mesh.size == first.get_node("CollisionShape3D").shape.size)
	first.attack_wall_gap = 1.0
	first.get_node("CollisionShape3D").shape.size.x = 5.0
	_check("实例参数及形状资源相互独立", is_equal_approx(second.attack_wall_gap, 0.55) and is_equal_approx(second.get_node("CollisionShape3D").shape.size.x, 3.0))
	first.free()
	second.free()
	var arena = load("res://arena.tscn").instantiate()
	var all_instances := true
	var geometry_matches := true
	for cover_name in ["CoverA", "CoverB", "CoverC", "CoverD", "CoverE", "CoverF"]:
		var existing = arena.get_node("NavigationRegion3D/Environment/" + cover_name)
		all_instances = all_instances and existing.scene_file_path == "res://cover.tscn"
		var mesh = existing.get_node("Mesh")
		var body = existing.get_node("CollisionShape3D")
		geometry_matches = geometry_matches and mesh.transform.is_equal_approx(body.transform) and mesh.mesh.size.is_equal_approx(body.shape.size)
	_check("竞技场六个现有掩体使用公共场景", all_instances)
	_check("竞技场六个掩体外观与碰撞一致", geometry_matches)
	var cover_b = arena.get_node("NavigationRegion3D/Environment/CoverB")
	var cover_d = arena.get_node("NavigationRegion3D/Environment/CoverD")
	cover_b.get_node("CollisionShape3D").shape.size.x = 9.0
	cover_b.get_node("Mesh").mesh.size.x = 9.0
	_check("原地图标准掩体尺寸资源不再共享", is_equal_approx(cover_d.get_node("CollisionShape3D").shape.size.x, 3.0) and is_equal_approx(cover_d.get_node("Mesh").mesh.size.x, 3.0))
	arena.free()
	_finish()


func _unique_count(points: Array) -> int:
	var unique := {}
	for point in points:
		unique[point] = true
	return unique.size()


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	var passed := checks.values().all(func(value): return value)
	print("攻击点检查：", checks.size(), " 项，", "通过" if passed else "失败")
	quit(0 if passed else 1)
