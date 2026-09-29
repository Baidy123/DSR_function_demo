extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	ai.cover_selection.debug_attack_points = false
	# 隔离区域几何；射程/感知门槛由 attack_point_validation_test 单独覆盖。
	ai.perception.sight_distance = 20.0
	for body in ai.navigation_region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
	for body in get_nodes_in_group("cover_region"):
		body.collision_layer = 0
		body.remove_from_group("cover_region")
	var cover = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, 0)
	var collision = cover.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	collision.shape.size = Vector3(0.8, 2.2, 3.0)
	actor.global_position = Vector3(24, 0, -2)
	for frame in range(5): await physics_frame
	var selection = ai.cover_selection
	# 主场景异步烘焙导航，等待实际路径可用，不能用固定几帧假定已完成。
	for frame in range(120):
		if not selection._path_to(actor.global_position, Vector3(24.5, 0, -2)).is_empty(): break
		await physics_frame
	check(not selection._path_to(actor.global_position, Vector3(24.5, 0, -2)).is_empty(), "场景导航已准备好实际可达路径")
	var tested := 0
	var available := 0
	var peripheral_blocked := false
	var fine_cells := false
	for distance in [3.0, 5.0, 7.0]:
		for degrees in range(0, 360, 45):
			var angle := deg_to_rad(float(degrees))
			var threat: Vector3 = Vector3(22, 0.8, 0) + Vector3(cos(angle), 0, sin(angle)) * distance
			var cells: Array = selection.attack_cells(cover, threat)
			var usable := 0
			var all_partial := true
			var all_outside := true
			var area := 0.0
			var reasons := {}
			for cell in cells:
				fine_cells = fine_cells or cell.depth > 0
				all_outside = all_outside and cell.inner >= cover.attack_inner_radius - 0.0001
				var result: Dictionary = selection.assess_attack_cell(cell, threat, threat)
				reasons[result.reason] = reasons.get(result.reason, 0) + 1
				if not result.usable: continue
				var local: Vector3 = collision.to_local(cell.position)
				var half: Vector3 = collision.shape.size * 0.5
				for x in [-half.x, half.x]:
					for z in [-half.z, half.z]:
						all_outside = all_outside and Vector2(local.x - x, local.z - z).length() >= cover.attack_inner_radius
				usable += 1
				all_partial = all_partial and result.protection >= 0.2 and result.protection <= 0.65
				peripheral_blocked = peripheral_blocked or result.fire_quality < 0.999
				var polygon: PackedVector3Array = result.polygon
				area += (polygon[1] - polygon[0]).cross(polygon[2] - polygon[0]).length() * 0.5
				area += (polygon[2] - polygon[0]).cross(polygon[3] - polygon[0]).length() * 0.5
			tested += 1
			if usable == 0: print("REGION DIAGNOSTIC ", distance, "/", degrees, " ", reasons)
			if usable > 0: available += 1
			check(usable > 0 and area > 0.01, "距离%.0f米/角度%d有实际面积的可用区域，area=%.3f" % [distance, degrees, area])
			check(all_partial and all_outside, "有效区域满足部分遮身并避开内圈")
			await physics_frame
	check(fine_cells, "遮挡边界实际进行局部细分")
	check(peripheral_blocked, "中心能开火的部分遮身位置不会因外围散布擦墙全部淘汰")
	# 玩家侧、全遮挡和远离墙体的站位分别检查，不能为了增加绿色而放宽遮身定义。
	var threat := Vector3(27, 0.8, 0)
	check(selection._attack_body_protection(Vector3(24, 0, 0), threat, cover) == 0.0, "墙在敌人背后不算掩护")
	check(selection._attack_body_protection(Vector3(21, 0, 0), threat, cover) > 0.95, "完全躲在墙后正确识别为全遮挡")
	check(not selection.assess_attack_point(Vector3(21, 0, 0), cover, threat, threat).usable, "全遮挡不是攻击区域")
	var original: Array = cover.get_attack_cells()
	check(original == cover.get_attack_cells(), "静态区域几何缓存保持一致")
	cover.rotation.y = PI / 4.0
	cover.scale = Vector3(1.2, 1.0, 0.9)
	for frame in range(3): await physics_frame
	check(original != cover.get_attack_cells(), "旋转缩放使区域几何缓存失效")
	var rotated_threat := Vector3(22, 0.8, 0) + Vector3(5, 0, 0).rotated(Vector3.UP, PI / 4.0)
	var rotated_cells: Array = selection.attack_cells(cover, rotated_threat)
	check(rotated_cells.any(func(cell): return selection.assess_attack_cell(cell, rotated_threat, rotated_threat).usable), "旋转缩放后的墙仍有部分遮身攻击区域")
	print("ATTACK REGION QUALITY: %d/%d checks, %d/%d views have usable area" % [checks - failures, checks, available, tested])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
