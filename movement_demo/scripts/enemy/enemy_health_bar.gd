extends Node3D

## 临时生命条，只读真实生命；不显示数字，也不参与碰撞、锁定或 AI。
@export var enabled: bool = true
## 条的世界宽度（米）。
@export_range(0.2, 3.0, 0.05, "suffix:m") var bar_width: float = 0.9
## 条的世界高度（米）。
@export_range(0.03, 0.3, 0.01, "suffix:m") var bar_height: float = 0.09
## 相对当前站姿／蹲姿头顶的高度（米）。
@export_range(0.0, 1.0, 0.05, "suffix:m") var head_offset: float = 0.5

var _actor: Node3D
var _fill: MeshInstance3D
var _material: StandardMaterial3D
var ratio := 1.0

func _ready() -> void:
	_actor = get_parent() as Node3D
	_add_quad(Vector2(bar_width + 0.04, bar_height + 0.04), Color(0.06, 0.07, 0.08))
	_fill = _add_quad(Vector2(bar_width, bar_height), Color(0.35, 0.85, 0.35))
	_fill.position.z = 0.005
	_material = _fill.material_override
	_actor.hit_received.connect(_on_hit)
	_actor.reset_completed.connect(_sync)
	_actor.died.connect(_sync)
	_sync()

func _add_quad(dimensions: Vector2, color: Color) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = dimensions
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = material
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(visual)
	return visual

func _on_hit(_damage: float, _attacker_position: Vector3) -> void:
	_sync()

func _sync() -> void:
	ratio = clampf(_actor.health / maxf(_actor.max_health, 0.001), 0.0, 1.0)
	_fill.scale.x = maxf(ratio, 0.001)
	_fill.position.x = -bar_width * (1.0 - ratio) * 0.5
	_material.albedo_color = Color(0.9, 0.22, 0.18).lerp(Color(0.35, 0.85, 0.35), ratio)
	visible = enabled and not _actor.is_dead

func _process(_delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	visible = enabled and not _actor.is_dead and camera != null
	if not visible: return
	position = Vector3(0.0, _actor.get_body_height() + head_offset, 0.0)
	global_basis = camera.global_basis.orthonormalized()

func _exit_tree() -> void:
	if not is_instance_valid(_actor): return
	if _actor.hit_received.is_connected(_on_hit): _actor.hit_received.disconnect(_on_hit)
	if _actor.reset_completed.is_connected(_sync): _actor.reset_completed.disconnect(_sync)
	if _actor.died.is_connected(_sync): _actor.died.disconnect(_sync)
