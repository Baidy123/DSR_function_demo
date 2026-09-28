extends Node3D

@onready var debug_settings = get_node("/root/DebugSettings")

## 只显示实际发生的声音事件；外圈无遮挡，内圈隔墙衰减后。
## 圆环不是绕墙后的精确轮廓，真实听觉仍逐个敌人检测墙壁。
const PLAYER_COLOR := Color(0.2, 0.75, 1.0)
const ENEMY_COLOR := Color(1.0, 0.5, 0.15)
const LIFETIME := 0.4
const SEGMENTS := 96
var enabled: bool = false
var _requested: bool = true


func _ready() -> void:
	top_level = true
	add_to_group("hearing_listener")
	debug_settings.changed.connect(_apply_debug_mode)
	_apply_debug_mode(debug_settings.enabled)


func set_enabled(value: bool) -> void:
	_requested = value
	_apply_debug_mode(debug_settings.enabled)


func _apply_debug_mode(debug_enabled: bool) -> void:
	enabled = _requested and debug_enabled
	if not enabled:
		for pulse in get_children():
			pulse.free()
	set_process(enabled)


func receive_noise(source: Node3D, source_position: Vector3, radius: float, occluded_multiplier: float) -> void:
	if not enabled or not OS.is_debug_build() or not is_instance_valid(source):
		return
	if radius <= 0.0 or not is_finite(radius) or not source_position.is_finite():
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_ring(mesh, radius, false)
	var reduced := radius * clampf(occluded_multiplier, 0.0, 1.0)
	if reduced > 0.0 and not is_equal_approx(reduced, radius):
		_add_ring(mesh, reduced, true)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = PLAYER_COLOR if source.is_in_group("player") else ENEMY_COLOR
	var pulse := MeshInstance3D.new()
	pulse.mesh = mesh
	pulse.material_override = material
	pulse.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pulse.set_meta("remaining", LIFETIME)
	add_child(pulse)
	pulse.global_position = source_position + Vector3.UP * 0.08


func _process(delta: float) -> void:
	for pulse in get_children():
		var remaining: float = pulse.get_meta("remaining") - delta
		if remaining <= 0.0:
			pulse.free()
		else:
			pulse.set_meta("remaining", remaining)
			pulse.material_override.albedo_color.a = remaining / LIFETIME


func _add_ring(mesh: ImmediateMesh, radius: float, dashed: bool) -> void:
	var inside := maxf(0.0, radius - 0.045)
	for segment in range(SEGMENTS):
		if dashed and segment % 2 == 0:
			continue
		var angle := TAU * segment / SEGMENTS
		var next_angle := TAU * (segment + 1) / SEGMENTS
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var next_direction := Vector3(cos(next_angle), 0.0, sin(next_angle))
		for vertex in [direction * radius, next_direction * radius, direction * inside,
				next_direction * radius, next_direction * inside, direction * inside]:
			mesh.surface_add_vertex(vertex)
