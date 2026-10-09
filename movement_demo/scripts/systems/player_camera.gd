extends Camera3D

## 保留 Phantom Camera 的位置跟随，只消费现有装备通知和处理遮挡外观。
const Occlusion = preload("res://scripts/systems/camera_occlusion.gd")

@export var player_path: NodePath = ^"../Player"
@export_group("遮挡透明")
## 只处理 camera_fadeable 组的天花板／装饰；玩法掩体始终排除。
@export var occlusion_enabled: bool = true
## 挡住角色时保留的不透明度；0完全透明，1不改变外观。
@export_range(0.0, 1.0, 0.05) var occluded_opacity: float = 0.25
## 从完整外观到遮挡透明、或恢复完整外观所用的秒数；0立即切换。
@export_range(0.0, 2.0, 0.05, "suffix:s") var occlusion_fade_seconds: float = 0.2
## 标记装饰物的3D显示层筛选，同时受相机 Cull Mask 限制；不使用物理层。
@export_flags_3d_render var occlusion_mask: int = 1

var _actor: Node3D
var _combat: Node
var _base_size: float
var _from_size: float
var _target_size: float
var _transition_seconds: float = 0.0
var _elapsed: float = 0.0
var _occlusion = Occlusion.new()


func _ready() -> void:
	_base_size = size
	_from_size = size
	_target_size = size
	_actor = get_node_or_null(player_path) as Node3D
	if _actor == null: return
	_combat = _actor.get_node_or_null("Combat")
	if _combat == null or not _combat.has_signal("weapon_changed"): return
	_combat.weapon_changed.connect(_on_weapon_changed)
	# 装备早于相机就绪时仍读取当前枪；不依赖已发出的出生通知。
	_on_weapon_changed(_combat.get("weapon") as WeaponData)
	size = _target_size
	_elapsed = _transition_seconds


func _process(delta: float) -> void:
	if _elapsed >= _transition_seconds: return
	_elapsed = minf(_elapsed + delta, _transition_seconds)
	var weight := smoothstep(0.0, 1.0, _elapsed / _transition_seconds)
	size = lerpf(_from_size, _target_size, weight)


func _physics_process(delta: float) -> void:
	if not occlusion_enabled or not is_current() or not is_instance_valid(_actor):
		_occlusion.clear()
		return
	var height: float = _actor.get_body_height() if _actor.has_method("get_body_height") else 1.75
	_occlusion.update(self, _actor, height, delta, occluded_opacity, occlusion_fade_seconds, occlusion_mask)


func _on_weapon_changed(data: WeaponData) -> void:
	_from_size = size
	_target_size = _base_size
	_transition_seconds = 0.25
	if data != null:
		if is_finite(data.camera_view_size) and data.camera_view_size > 0.0:
			_target_size = maxf(0.1, data.camera_view_size)
		if is_finite(data.camera_transition_seconds):
			_transition_seconds = maxf(0.0, data.camera_transition_seconds)
	_elapsed = 0.0
	if is_zero_approx(_transition_seconds):
		_transition_seconds = 0.0
		size = _target_size


func _exit_tree() -> void:
	if is_instance_valid(_combat) and _combat.has_signal("weapon_changed") and _combat.weapon_changed.is_connected(_on_weapon_changed):
		_combat.weapon_changed.disconnect(_on_weapon_changed)
	_occlusion.clear()
