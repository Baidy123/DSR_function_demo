extends Node3D

## 只读装备资源的纯外观挂载；不持有弹药、攻击计时或实际枪口。
const Placeholder = preload("res://scenes/presentation/weapon_placeholder.tscn")
var model: Node3D
var using_placeholder := false
var _weapon: Resource
var _source: PackedScene
var _socket: WeakRef
var _fallback_position := Vector3.ZERO
var _model_rest_transform := Transform3D.IDENTITY


func _ready() -> void:
	# 手部骨骼可能在角色动画后端的 process 中更新。
	process_priority = 100


func apply_weapon(weapon: Resource, socket: Node3D = null, fallback_position: Vector3 = Vector3.ZERO) -> void:
	if weapon == null:
		clear()
		return
	var source: PackedScene = weapon.get("visual_model") as PackedScene
	if weapon != _weapon or source != _source or not is_instance_valid(model):
		clear()
		_weapon = weapon
		_source = source
		_build_model()
	_socket = weakref(socket) if is_instance_valid(socket) else null
	_fallback_position = fallback_position
	var offset: Vector3 = weapon.get("visual_position")
	var rotation_offset: Vector3 = weapon.get("visual_rotation_degrees")
	var scale_offset: Vector3 = weapon.get("visual_scale")
	var offset_basis := Basis.from_euler(rotation_offset * (PI / 180.0)) * Basis.from_scale(scale_offset)
	model.transform = Transform3D(offset_basis, offset) * _model_rest_transform
	_update_mount()


func _build_model() -> void:
	var instance: Node = _source.instantiate() if _source != null else null
	if instance != null and (not instance is Node3D or not _prepare_visual(instance)):
		push_warning("WeaponPresentation: 武器模型必须是纯外观 Node3D，已回退方块占位。")
		instance.free()
		instance = null
	using_placeholder = instance == null
	model = Placeholder.instantiate() as Node3D if using_placeholder else instance as Node3D
	_model_rest_transform = model.transform
	# 保留在角色 Presentation 分支，模型重建/替换不会顺带释放武器。
	add_child(model, false, Node.INTERNAL_MODE_BACK)


func _prepare_visual(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D:
		return false
	if node is NavigationAgent3D or node is NavigationRegion3D or node is NavigationObstacle3D or node is NavigationLink3D:
		return false
	if node is AnimationPlayer:
		node.autoplay = ""
		node.stop()
		node.active = false
		node.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	if node is AnimationTree: node.active = false
	for child in node.get_children():
		if not _prepare_visual(child): return false
	return true


func _process(_delta: float) -> void:
	if is_instance_valid(model): _update_mount()


func _update_mount() -> void:
	var socket: Node3D = _socket.get_ref() if _socket != null else null
	# 隐藏或已卸载的外部角色模型不能继续占用手部挂点。
	if is_instance_valid(socket) and socket.is_inside_tree() and socket.is_visible_in_tree() and socket != self and not is_ancestor_of(socket):
		global_transform = socket.global_transform
	else:
		transform = Transform3D(Basis.IDENTITY, _fallback_position)


func clear() -> void:
	if is_instance_valid(model):
		remove_child(model)
		model.queue_free()
	model = null
	_weapon = null
	_source = null
	_socket = null
	_fallback_position = Vector3.ZERO
	_model_rest_transform = Transform3D.IDENTITY
	using_placeholder = false
	transform = Transform3D.IDENTITY


func reset() -> void:
	clear()
