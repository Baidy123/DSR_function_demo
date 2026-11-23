extends Node3D

## 纯表现星环：身体快照给出位置和经过时间，本组件不推进任何玩法计时。
const ORBIT_RADIUS := 0.26
var _stars: Array[MeshInstance3D] = []

func _ready() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.8, 0.15)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var ring := ImmediateMesh.new()
	ring.surface_begin(Mesh.PRIMITIVE_LINES)
	for segment in 48:
		for step in [segment, segment + 1]:
			var angle := TAU * float(step) / 48.0
			ring.surface_add_vertex(Vector3(cos(angle), 0.0, sin(angle)) * ORBIT_RADIUS)
	ring.surface_end()
	_visual(ring, material)
	var star_mesh := ImmediateMesh.new()
	star_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for point in 10:
		star_mesh.surface_add_vertex(Vector3.ZERO)
		for vertex in [point, point + 1]:
			var angle := TAU * float(vertex) / 10.0 - PI * 0.5
			var radius := 0.085 if vertex % 2 == 0 else 0.038
			star_mesh.surface_add_vertex(Vector3(cos(angle), sin(angle), 0.0) * radius)
	star_mesh.surface_end()
	var star_material := material.duplicate() as StandardMaterial3D
	star_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	for index in 3:
		_stars.append(_visual(star_mesh, star_material))

func show_state(head_position: Vector3, elapsed: float) -> void:
	global_position = head_position
	global_basis = Basis.IDENTITY
	visible = true
	for index in _stars.size():
		var angle := elapsed * 5.0 + TAU * float(index) / float(_stars.size())
		_stars[index].position = Vector3(cos(angle) * ORBIT_RADIUS, sin(angle * 2.0) * 0.035, sin(angle) * ORBIT_RADIUS)

func _visual(mesh: Mesh, material: Material) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return visual
