@tool
extends StaticBody3D

## 长边面可用于躲藏的长度比例；0.75 对应“长 20，中间 15”，两端留空。
@export_range(0.1, 1.0, 0.05) var hide_length_ratio: float = 0.75
## 短边端面可用于躲藏的长度比例；默认中间 25%，减少靠近墙角时身体露出。
@export_range(0.1, 1.0, 0.05) var short_hide_length_ratio: float = 0.25
## 躲藏区域内沿离墙方向的宽度（米，随节点缩放）。
@export_range(0.1, 2.0, 0.05) var hide_depth: float = 0.4
## 墙面到躲藏区域近边的距离（米，随节点缩放）；应大于敌人的碰撞半径。
@export_range(0.35, 2.0, 0.05) var wall_gap: float = 0.55
## Peek 超出当前面两端的距离（米，随节点缩放）；实际使用还会检查射界和可达性。
@export_range(0.4, 3.0, 0.05) var peek_outset: float = 1.0
## AI 沿各面采样的最大间隔（米）；还会加入距离敌人最近的区域内位置。
@export_range(0.25, 2.0, 0.05) var sample_spacing: float = 0.75
## 仅在编辑器显示青色四面候选区域和黄色 Peek 十字；实际可用性由导航和碰撞过滤。
@export var show_regions_in_editor: bool = true
## 墙角到攻击候选区域内侧的半径（米，随节点缩放）；不是到墙面的距离，身体空间仍需过滤。
@export_range(0.2, 2.0, 0.05) var attack_inner_radius: float = 0.55
## 墙角到区域外侧的半径；实际至少比内半径大0.05米。四角各为墙外270度连续扇环。
@export_range(0.25, 3.0, 0.05) var attack_outer_radius: float = 1.5
## 区域内径向及圆弧采样的最大间距（米，随节点缩放）；越小越密，也增加运行检查量。
@export_range(0.2, 1.0, 0.05) var attack_sample_spacing: float = 0.4
## 仅在编辑器显示橙色连续扇环；运行时再检查站立空间、射界、遮挡和可达性。
@export var show_attack_points_in_editor: bool = true

var _preview_signature: String = ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		add_to_group("cover_region")
	set_process(Engine.is_editor_hint())


# 四面区域均基于碰撞盒的局部坐标，支持现有直立长方体的平移、旋转与缩放。
func _collision() -> CollisionShape3D:
	return get_node_or_null("CollisionShape3D") as CollisionShape3D


func _dimensions() -> Vector2:
	var collision := _collision()
	if collision == null or not collision.shape is BoxShape3D:
		return Vector2.ZERO
	var size: Vector3 = collision.shape.size
	return Vector2(maxf(size.x, size.z), minf(size.x, size.z))


func _local_point(along: float, across: float) -> Vector3:
	var size: Vector3 = _collision().shape.size
	if size.x >= size.z:
		return Vector3(along, -size.y * 0.5, across)
	return Vector3(across, -size.y * 0.5, along)


func _coordinates(world_point: Vector3) -> Vector2:
	var collision := _collision()
	var point := collision.to_local(world_point)
	return Vector2(point.x, point.z) if collision.shape.size.x >= collision.shape.size.z else Vector2(point.z, point.x)


# end_face=true 表示短边端面：交换沿墙方向与离墙方向。
func _face_dimensions(end_face: bool) -> Vector2:
	var dimensions := _dimensions()
	return Vector2(dimensions.y, dimensions.x) if end_face else dimensions


func _hide_half_length(end_face: bool) -> float:
	var ratio := short_hide_length_ratio if end_face else hide_length_ratio
	return _face_dimensions(end_face).x * ratio * 0.5


func _face_coordinates(world_point: Vector3, end_face: bool) -> Vector2:
	var point := _coordinates(world_point)
	return Vector2(point.y, point.x) if end_face else point


func _face_point(along: float, across: float, end_face: bool) -> Vector3:
	return _local_point(across, along) if end_face else _local_point(along, across)


func get_candidates(threat: Vector3, from: Vector3) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if _dimensions().is_zero_approx():
		return candidates
	var collision := _collision()
	for end_face in [false, true]:
		var threat_local := _face_coordinates(threat, end_face)
		# 只使用已知威胁；斜角可对应两个背向面，由 AI 的真实遮挡检查继续筛选。
		if absf(threat_local.y) < 0.001:
			continue
		var side := -signf(threat_local.y)
		var dimensions := _face_dimensions(end_face)
		var half_length := _hide_half_length(end_face)
		var near_edge := dimensions.y * 0.5 + wall_gap
		var from_local := _face_coordinates(from, end_face)
		var samples: Array[Vector2] = [
			Vector2(clampf(from_local.x, -half_length, half_length),
				clampf(from_local.y * side, near_edge, near_edge + hide_depth))
		]
		var steps := maxi(1, ceili(half_length * 2.0 / sample_spacing))
		for index in range(steps + 1):
			var along := lerpf(-half_length, half_length, float(index) / float(steps))
			for depth in [hide_depth * 0.25, hide_depth * 0.75]:
				samples.append(Vector2(along, near_edge + depth))
		var peeks: Array[Vector3] = []
		for point in _local_peeks(end_face):
			peeks.append(collision.to_global(point))
		for sample in samples:
			candidates.append({
				"hide": collision.to_global(_face_point(sample.x, side * sample.y, end_face)),
				"peeks": peeks
			})
	return candidates


# 每对相向面共用两端外的 Peek，向墙厚中线探出，避免斜射线仍穿墙。
func _local_peeks(end_face: bool = false) -> Array[Vector3]:
	var half_length := _face_dimensions(end_face).x * 0.5 + peek_outset
	return [_face_point(-half_length, 0.0, end_face), _face_point(half_length, 0.0, end_face)]


# 在碰撞盒局部XZ平面定义四角，各排除朝墙内的90度；保留墙外相连的270度。
func _attack_sectors() -> Array[Dictionary]:
	var sectors: Array[Dictionary] = []
	if _dimensions().is_zero_approx():
		return sectors
	var half: Vector3 = _collision().shape.size * 0.5
	var corners := [Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1), Vector2(-1, -1)]
	var starts := [0.0, 270.0, 180.0, 90.0]
	for index in range(4):
		sectors.append({"center": Vector3(corners[index].x * half.x, -half.y, corners[index].y * half.z),
			"start": deg_to_rad(starts[index])})
	return sectors


func _attack_radii() -> Vector2:
	var inner := maxf(0.2, attack_inner_radius)
	return Vector2(inner, maxf(inner + 0.05, attack_outer_radius))


func _attack_offset(angle: float, radius: float) -> Vector3:
	return Vector3(cos(angle), 0, sin(angle)) * radius


# 区域保持连续定义，查询时才采样；相邻墙角完全重合的样本不重复检查。
func _local_attack_points() -> Array[Vector3]:
	var points: Array[Vector3] = []
	var seen := {}
	var radii := _attack_radii()
	var spacing := maxf(0.2, attack_sample_spacing)
	var radial_steps := maxi(1, ceili((radii.y - radii.x) / spacing))
	for sector in _attack_sectors():
		for ring in range(radial_steps + 1):
			var radius := lerpf(radii.x, radii.y, float(ring) / radial_steps)
			var angular_steps := maxi(1, ceili(radius * PI * 1.5 / spacing))
			for index in range(angular_steps + 1):
				var angle: float = sector.start + PI * 1.5 * float(index) / angular_steps
				var point: Vector3 = sector.center + _attack_offset(angle, radius)
				var key := point.snapped(Vector3.ONE * 0.001)
				if not seen.has(key):
					seen[key] = true
					points.append(point)
	return points


func get_attack_candidates() -> Array[Vector3]:
	var points: Array[Vector3] = []
	for point in _local_attack_points():
		points.append(_collision().to_global(point))
	return points


func is_hiding_position(point: Vector3, threat: Vector3) -> bool:
	if _dimensions().is_zero_approx():
		return false
	for end_face in [false, true]:
		var threat_local := _face_coordinates(threat, end_face)
		if absf(threat_local.y) < 0.001:
			continue
		var dimensions := _face_dimensions(end_face)
		var local := _face_coordinates(point, end_face)
		var across := local.y * -signf(threat_local.y)
		var near_edge := dimensions.y * 0.5 + wall_gap
		if (
			absf(local.x) <= _hide_half_length(end_face) + 0.02
			and across >= near_edge - 0.02 and across <= near_edge + hide_depth + 0.02
		):
			return true
	return false


func _process(_delta: float) -> void:
	var collision := _collision()
	if collision == null or not collision.shape is BoxShape3D:
		return
	var signature := str(collision.shape.size, hide_length_ratio, short_hide_length_ratio, hide_depth, wall_gap, peek_outset, show_regions_in_editor,
		attack_inner_radius, attack_outer_radius, attack_sample_spacing, show_attack_points_in_editor)
	if signature == _preview_signature:
		return
	_preview_signature = signature
	var preview := collision.get_node_or_null("_CoverPreview") as MeshInstance3D
	if preview == null:
		preview = MeshInstance3D.new()
		preview.name = "_CoverPreview"
		# 辅助节点不写入场景，也不产生碰撞。
		collision.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	preview.visible = show_regions_in_editor or show_attack_points_in_editor
	if not preview.visible:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for end_face in [false, true]:
		if not show_regions_in_editor:
			continue
		var dimensions := _face_dimensions(end_face)
		var half_length := _hide_half_length(end_face)
		var near_edge := dimensions.y * 0.5 + wall_gap
		for side in [-1.0, 1.0]:
			var corners: Array[Vector3] = [
				_face_point(-half_length, side * near_edge, end_face),
				_face_point(half_length, side * near_edge, end_face),
				_face_point(half_length, side * (near_edge + hide_depth), end_face),
				_face_point(-half_length, side * (near_edge + hide_depth), end_face)
			]
			for index in range(4):
				_preview_line(mesh, corners[index], corners[(index + 1) % 4], Color.CYAN)
		for center in _local_peeks(end_face):
			_preview_line(mesh, center - Vector3.RIGHT * 0.18, center + Vector3.RIGHT * 0.18, Color.YELLOW)
			_preview_line(mesh, center - Vector3.FORWARD * 0.18, center + Vector3.FORWARD * 0.18, Color.YELLOW)
	if show_attack_points_in_editor:
		_preview_attack_regions(mesh, false)
	mesh.surface_end()
	if show_attack_points_in_editor:
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_preview_attack_regions(mesh, true)
		mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	preview.mesh = mesh
	preview.material_override = material


# 预览和采样共用四角与半径；轮廓表示整片范围，不随采样密度改变形状。
func _preview_attack_regions(mesh: ImmediateMesh, filled: bool) -> void:
	var radii := _attack_radii()
	for sector in _attack_sectors():
		for index in range(36):
			var a: float = sector.start + PI * 1.5 * float(index) / 36.0
			var b: float = sector.start + PI * 1.5 * float(index + 1) / 36.0
			var inside_a: Vector3 = sector.center + _attack_offset(a, radii.x)
			var outside_a: Vector3 = sector.center + _attack_offset(a, radii.y)
			var inside_b: Vector3 = sector.center + _attack_offset(b, radii.x)
			var outside_b: Vector3 = sector.center + _attack_offset(b, radii.y)
			if filled:
				for point in [inside_a, outside_a, outside_b, inside_a, outside_b, inside_b]:
					mesh.surface_set_color(Color(1.0, 0.65, 0.1, 0.12))
					mesh.surface_add_vertex(point + Vector3.UP * 0.025)
			else:
				_preview_line(mesh, inside_a, inside_b, Color.ORANGE)
				_preview_line(mesh, outside_a, outside_b, Color.ORANGE)
				if index == 0:
					_preview_line(mesh, inside_a, outside_a, Color.ORANGE)
				if index == 35:
					_preview_line(mesh, inside_b, outside_b, Color.ORANGE)


func _preview_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from + Vector3.UP * 0.03)
	mesh.surface_add_vertex(to + Vector3.UP * 0.03)
