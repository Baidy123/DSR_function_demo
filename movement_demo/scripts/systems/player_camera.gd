extends Camera3D

## 保留 Phantom Camera 的位置跟随，只消费现有装备通知和处理遮挡外观。
const Occlusion = preload("res://scripts/systems/camera_occlusion.gd")

## 相对于相机根节点；地面锚点与武器视野共用这一玩家引用。
@export_node_path("Node3D") var player_path: NodePath = ^"../Player"
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
var _weapon: WeaponData
var _occlusion = Occlusion.new()


func _ready() -> void:
	_base_size = size
	_from_size = size
	_target_size = size
	get_viewport().size_changed.connect(_on_viewport_resized)
	_actor = get_follow_actor()
	if _actor == null: return
	if not _actor.is_node_ready():
		_actor.ready.connect(_bind_combat, CONNECT_ONE_SHOT)
	else:
		_bind_combat()


func get_follow_actor() -> Node3D:
	return get_node_or_null(player_path) as Node3D


func _bind_combat() -> void:
	if not is_instance_valid(_actor): return
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
	_weapon = data
	_from_size = size
	_target_size = _base_size
	_transition_seconds = 0.25
	if data != null:
		if data.camera_follows_aim_range and projection == Camera3D.PROJECTION_ORTHOGONAL and is_finite(data.aim_range) and data.aim_range > 0.0:
			_target_size = _size_for_lock_range(data.aim_range)
		elif not data.camera_follows_aim_range and is_finite(data.camera_view_size) and data.camera_view_size > 0.0:
			_target_size = maxf(0.1, data.camera_view_size)
		if is_finite(data.camera_transition_seconds):
			_transition_seconds = maxf(0.0, data.camera_transition_seconds)
	_elapsed = 0.0
	# 两个方向都从当前显示大小平滑过渡；快速切换也不跳回上一目标值。
	if is_zero_approx(_transition_seconds):
		size = _target_size

func _on_viewport_resized() -> void:
	if _weapon != null and _weapon.camera_follows_aim_range: _on_weapon_changed(_weapon)

## 以玩家为圆心，让地面至站立角色高度的画面四角落入锁定圆，并留0.5米身体边缘余量。
## 使用原跟随偏移，不改 Phantom Camera 的位置、倾角或翻越地面锚点。
func _size_for_lock_range(distance: float) -> float:
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.y <= 0.0: return _base_size
	var forward := -global_basis.z.normalized()
	if forward.y >= -0.1: return _base_size
	var phantom := get_node_or_null("PhantomCamera3D")
	var offset: Vector3 = phantom.follow_offset if phantom != null else global_position - _actor.global_position
	var aspect := viewport_size.x / viewport_size.y
	var low := 0.1
	var high := maxf(low, distance * 2.0)
	var limit := maxf(0.1, distance - 0.5)
	for iteration in 24:
		var candidate := (low + high) * 0.5
		var width := candidate * aspect if keep_aspect == Camera3D.KEEP_HEIGHT else candidate
		var height := candidate if keep_aspect == Camera3D.KEEP_HEIGHT else candidate / aspect
		var fits := true
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				var origin: Vector3 = offset + global_basis.x * (x * width * 0.5 + h_offset) + global_basis.y * (y * height * 0.5 + v_offset)
				for elevation in [0.0, 1.75]:
					var point: Vector3 = origin + forward * ((elevation - origin.y) / forward.y)
					if Vector2(point.x, point.z).length() > limit: fits = false
		if fits: low = candidate
		else: high = candidate
	return low


func _exit_tree() -> void:
	if get_viewport().size_changed.is_connected(_on_viewport_resized):
		get_viewport().size_changed.disconnect(_on_viewport_resized)
	if is_instance_valid(_actor) and _actor.ready.is_connected(_bind_combat):
		_actor.ready.disconnect(_bind_combat)
	if is_instance_valid(_combat) and _combat.has_signal("weapon_changed") and _combat.weapon_changed.is_connected(_on_weapon_changed):
		_combat.weapon_changed.disconnect(_on_weapon_changed)
	_occlusion.clear()
