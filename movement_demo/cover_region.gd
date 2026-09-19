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
	var signature := str(collision.shape.size, hide_length_ratio, short_hide_length_ratio, hide_depth, wall_gap, peek_outset, show_regions_in_editor)
	if signature == _preview_signature:
		return
	_preview_signature = signature
	var preview := collision.get_node_or_null("_CoverPreview") as MeshInstance3D
	if preview == null:
		preview = MeshInstance3D.new()
		preview.name = "_CoverPreview"
		# 辅助节点不写入场景，也不产生碰撞。
		collision.add_child(preview, false, Node.INTERNAL_MODE_BACK)
	preview.visible = show_regions_in_editor
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for end_face in [false, true]:
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
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.no_depth_test = true
	preview.mesh = mesh
	preview.material_override = material


func _preview_line(mesh: ImmediateMesh, from: Vector3, to: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(from + Vector3.UP * 0.03)
	mesh.surface_add_vertex(to + Vector3.UP * 0.03)
