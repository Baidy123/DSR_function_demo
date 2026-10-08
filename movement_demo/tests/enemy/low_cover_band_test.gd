extends SceneTree

var checks := 0
var failures := 0

class PreviewContext extends RefCounted:
	var is_alerted := true
	var has_visual_memory := true
	var last_seen_position := Vector3(26, 0, 3)
	var navigation_region: Node
	var samples := PackedVector3Array([Vector3(26, 1.65, 3), Vector3(26.2, 1.3, 3)])
	var snapshot_calls := 0
	func is_arena_active() -> bool: return true
	func known_target_point(feet: Vector3) -> Vector3: return feet + Vector3.UP
	func known_target_points(_feet: Vector3) -> PackedVector3Array:
		snapshot_calls += 1
		return samples.duplicate()

class PreviewSelection extends RefCounted:
	var ai: PreviewContext
	var enemy: Node3D
	var debug_attack_points := true
	var wall: Node3D
	var cell: Dictionary
	var received: Array[PackedVector3Array] = []
	var direct_samples := PackedVector3Array()
	func attack_cells(region: Node3D, _threat: Vector3) -> Array[Dictionary]:
		var cells: Array[Dictionary] = []
		if region == wall:
			for index in 130: cells.append(cell)
		return cells
	func assess_attack_cell(candidate: Dictionary, _threat: Vector3, _target: Vector3, samples: PackedVector3Array = PackedVector3Array()) -> Dictionary:
		received.append(samples.duplicate())
		return {"cover": wall, "polygon": candidate.polygon, "usable": true, "reason": "可用"}
	func get_attack_assessments(_threat: Vector3, _target: Vector3, samples: PackedVector3Array = PackedVector3Array()) -> Array[Dictionary]:
		direct_samples = samples.duplicate()
		return []

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
	var wall = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var box: CollisionShape3D = wall.get_node("CollisionShape3D")
	var cells: Array = wall.get_attack_cells()
	check(not cells.is_empty() and cells.all(func(cell): return cell.get("kind") == &"low_cover_band" and cell.polygon.size() == 4 and cell.body == wall and cell.cover == wall), "低墙使用四边形环带单元及原公共查询字段")
	if cells.is_empty() or cells[0].get("kind") != &"low_cover_band":
		_finish()
		return
	check(cells.all(func(cell): return not cell.has("corner") and cell.depth == 0), "低墙单元不伪装成墙角扇环")
	_check_band(wall, "原始低墙")
	var points: Array = wall.get_attack_candidates()
	check(points.size() == cells.size() and cells.all(func(cell): return points.any(func(point): return point.is_equal_approx(cell.position))), "站立攻击点与外围环带格中心一致")
	check(wall.get_attack_exclusion_polygons().is_empty(), "低墙不再提供墙角禁用扇形")
	var geometry = ai.cover_selection.attack_geometry
	var refined: Array = geometry.refine(ai.context, wall, box.to_global(Vector3(8, 1, 5)), cells)
	check(refined.size() == cells.size() and refined.all(func(cell): return cell.depth == 0 and cells.has(cell)), "低墙沿既有密度消费环带，不进入墙角自适应细分")
	var half: Vector3 = box.shape.size * 0.5
	var from := box.to_global(Vector3(0, -half.y, -half.z - wall.wall_gap - wall.hide_depth * 0.5))
	var candidates: Array = wall.get_candidates(box.to_global(Vector3(0, 1, 8)), from)
	check(not candidates.is_empty() and candidates.all(func(candidate): return candidate.get("crouch", false) and candidate.stand == candidate.hide and candidate.peeks.is_empty() and _in_band(wall, box.to_local(candidate.hide))), "低墙蹲藏与站起共用环带，同点且没有绕角Peek")
	check(candidates.all(func(candidate): return box.to_local(candidate.hide).z <= -half.z - wall.wall_gap + 0.0001), "正面威胁只提供背向墙面的蹲藏点")
	check(candidates.any(func(candidate): return candidate.hide.is_equal_approx(from)), "已在环带内的真实落点保留，不强迫跳到网格中心")
	var diagonal: Array = wall.get_candidates(box.to_global(Vector3(8, 1, 8)), from)
	check(diagonal.any(func(candidate): return box.to_local(candidate.hide).x < -half.x - wall.wall_gap) and diagonal.any(func(candidate): return box.to_local(candidate.hide).z < -half.z - wall.wall_gap), "斜向威胁可使用环带两个背向面")
	var independent: Array = wall.get_attack_cells()
	independent.clear()
	check(wall.get_attack_cells().size() == cells.size(), "清空调用方数组不破坏静态环带缓存")
	var initial_transform: Transform3D = wall.transform
	var original_local: Array[Vector3] = []
	for cell in cells: original_local.append(box.to_local(cell.position))
	wall.rotation.y += 0.47
	wall.scale = Vector3(1.3, 1.0, 0.8)
	var transformed: Array = wall.get_attack_cells()
	var follows := transformed.size() == original_local.size()
	for index in mini(transformed.size(), original_local.size()):
		follows = follows and transformed[index].position.is_equal_approx(box.to_global(original_local[index]))
	check(follows and transformed != cells, "环带缓存随真实碰撞盒旋转缩放更新")
	_check_band(wall, "旋转缩放低墙")
	wall.transform = initial_transform
	var old_gap: float = wall.wall_gap
	var old_depth: float = wall.hide_depth
	wall.wall_gap += 0.15
	wall.hide_depth += 0.2
	check(wall.get_attack_cells() != cells, "离墙间距与环带宽度变化使缓存失效")
	_check_band(wall, "调节宽度低墙")
	wall.wall_gap = old_gap
	wall.hide_depth = old_depth
	var old_spacing: float = wall.attack_sample_spacing
	wall.attack_sample_spacing = 0.2
	check(wall.get_attack_cells().size() > cells.size(), "环带采样间距仍控制密度")
	wall.attack_sample_spacing = old_spacing
	wall.low_cover = false
	var corners: Array = wall.get_attack_cells()
	check(not corners.is_empty() and corners.all(func(cell): return cell.has("corner") and cell.get("kind") != &"low_cover_band"), "关闭低墙标记后恢复原高墙扇环协议")
	wall.low_cover = true
	check(wall.get_attack_cells() == cells, "重新启用低墙不会复用旧墙角缓存")
	var high = scene.get_node("Arena/NavigationRegion3D/Environment/CoverA")
	check(high.get_attack_cells().all(func(cell): return cell.has("corner")) and not high.get_attack_exclusion_polygons().is_empty(), "原高掩体继续保留墙角与内圈定义")
	var threat := box.to_global(Vector3(0, 1.65, 8))
	var no_samples: Dictionary = ai.cover_selection.assess_attack_cell(cells[0], threat, threat, PackedVector3Array())
	check(not no_samples.usable and no_samples.reason == "无效位置" and no_samples.polygon == cells[0].polygon, "明确没有合法身体样本时低墙不可用，不退回未授权目标")
	var legacy: Dictionary = ai.cover_selection.assess_attack_cell(cells[0], threat, threat)
	var original: Dictionary = ai.cover_selection.assess_attack_point(cells[0].position, wall, threat, threat)
	original.polygon = cells[0].polygon
	check(legacy == original, "未传身体快照的旧标量评估接口保留原语义")
	_check_preview_snapshot(ai, actor, wall, cells[0])
	scene.queue_free()
	await process_frame
	_finish()

func _check_preview_snapshot(ai, actor, wall, cell: Dictionary) -> void:
	# 这里只替换查询出口，真实预览节点的批次生命周期、绘制和总开关照常运行。
	var preview = ai.cover_selection.get_node("AttackPreview")
	var settings = root.get_node("DebugSettings")
	var old_enabled: bool = settings.enabled
	var original_selection = preview.selection
	var context := PreviewContext.new()
	context.navigation_region = ai.context.navigation_region
	var selection := PreviewSelection.new()
	selection.ai = context
	selection.enemy = actor
	selection.wall = wall
	selection.cell = cell
	preview.selection = selection
	settings.enabled = true
	preview.set_physics_process(false)
	preview.clear()
	var first_samples := context.samples.duplicate()
	preview._physics_process(1.0 / 60.0)
	check(not preview._pending.is_empty() and selection.received.size() <= 64, "预览样本仍按原预算分帧处理")
	context.last_seen_position += Vector3(3, 0, -2)
	context.samples = PackedVector3Array([context.last_seen_position + Vector3.UP * 1.55])
	for frame in 140:
		if preview._pending.is_empty(): break
		preview._physics_process(1.0 / 60.0)
	check(selection.received.size() == 130 and context.snapshot_calls == 1 and selection.received.all(func(points): return points == first_samples), "目击点和姿态中途变化不污染同一预览批次")
	preview.refresh()
	check(context.snapshot_calls == 2 and selection.direct_samples == context.samples and preview._last_known_feet == context.last_seen_position, "同步刷新也冻结同一份新目击位置与身体采样")
	context.samples = PackedVector3Array()
	preview.refresh()
	check(context.snapshot_calls == 3 and selection.direct_samples.is_empty(), "合法样本全被遮住时同步预览保留显式空快照")
	preview.clear()
	check(preview._known_target_points.is_empty(), "清空预览同时丢弃旧目击身体快照")
	preview.selection = original_selection
	settings.enabled = old_enabled

func _in_band(wall, point: Vector3) -> bool:
	var half: Vector3 = wall.get_node("CollisionShape3D").shape.size * 0.5
	var inner := Vector2(half.x + wall.wall_gap, half.z + wall.wall_gap)
	var outer: Vector2 = inner + Vector2.ONE * wall.hide_depth
	return absf(point.x) <= outer.x + 0.0001 and absf(point.z) <= outer.y + 0.0001 and (absf(point.x) >= inner.x - 0.0001 or absf(point.z) >= inner.y - 0.0001)

func _check_band(wall, label: String) -> void:
	var box: CollisionShape3D = wall.get_node("CollisionShape3D")
	var half: Vector3 = box.shape.size * 0.5
	var polygons: Array[PackedVector2Array] = []
	var area := 0.0
	var floor_ok := true
	for cell in wall.get_attack_cells():
		var polygon := PackedVector2Array()
		for vertex: Vector3 in cell.polygon:
			var local := box.to_local(vertex)
			floor_ok = floor_ok and absf(local.y + half.y) < 0.0001
			polygon.append(Vector2(local.x, local.z))
		polygons.append(polygon)
		for index in range(1, polygon.size() - 1):
			area += absf((polygon[index] - polygon[0]).cross(polygon[index + 1] - polygon[0])) * 0.5
	var inner := Vector2(half.x + wall.wall_gap, half.z + wall.wall_gap)
	var outer: Vector2 = inner + Vector2.ONE * wall.hide_depth
	var expected: float = 4.0 * (outer.x * outer.y - inner.x * inner.y)
	check(floor_ok and absf(area - expected) < 0.0001, label + "的单元总面积等于独立矩形环面积且贴合墙底")
	var rng := RandomNumberGenerator.new()
	rng.seed = 90813
	var exact_coverage := true
	for index in 400:
		var point := Vector2(rng.randf_range(-outer.x - 0.1, outer.x + 0.1), rng.randf_range(-outer.y - 0.1, outer.y + 0.1))
		var count := 0
		for polygon in polygons:
			if Geometry2D.is_point_in_polygon(point, polygon): count += 1
		var expected_count := int(_in_band(wall, Vector3(point.x, -half.y, point.y)))
		exact_coverage = exact_coverage and count == expected_count
	check(exact_coverage, label + "四周连续覆盖且没有重叠、内圈填充或墙角扇形外溢")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _finish() -> void:
	print("LOW COVER BAND: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
