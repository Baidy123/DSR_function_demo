extends Node3D

## 纯表现接口，不查找目标、不执行伤害。局部 -Z 为挥击正面。
@export_range(0.05, 0.5, 0.01) var lifetime: float = 0.14
var elapsed: float = 0.0
var _material: StandardMaterial3D


func start(origin: Vector3, direction: Vector3, reach: float, angle_degrees: float) -> void:
	global_position = origin
	global_rotation.y = atan2(-direction.x, -direction.z)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var radius := maxf(0.1, reach * 0.85)
	var half_angle := deg_to_rad(clampf(angle_degrees, 1.0, 180.0) * 0.5)
	for segment in 24:
		var a := lerpf(-half_angle, half_angle, float(segment) / 24.0)
		var b := lerpf(-half_angle, half_angle, float(segment + 1) / 24.0)
		var first := Vector3(sin(a), 0.0, -cos(a))
		var second := Vector3(sin(b), 0.0, -cos(b))
		for band in 2:
			var inner := radius * (0.72 if band == 0 else 0.92)
			var outer := radius * (0.92 if band == 0 else 1.0)
			var inside := Color(0.25, 0.75, 1.0, 0.0) if band == 0 else Color(0.85, 0.98, 1.0, 0.95)
			var outside := Color(0.85, 0.98, 1.0, 0.95) if band == 0 else Color(0.3, 0.85, 1.0, 0.0)
			_vertex(mesh, first * inner, inside)
			_vertex(mesh, first * outer, outside)
			_vertex(mesh, second * outer, outside)
			_vertex(mesh, first * inner, inside)
			_vertex(mesh, second * outer, outside)
			_vertex(mesh, second * inner, inside)
	mesh.surface_end()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = _material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	add_to_group("melee_effect")


func _vertex(mesh: ImmediateMesh, point: Vector3, color: Color) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(point)


func _process(delta: float) -> void:
	elapsed += maxf(0.0, delta)
	var progress := clampf(elapsed / maxf(0.05, lifetime), 0.0, 1.0)
	if _material != null: _material.albedo_color.a = 1.0 - progress
	scale = Vector3.ONE * lerpf(0.9, 1.05, progress)
	if progress >= 1.0: queue_free()
