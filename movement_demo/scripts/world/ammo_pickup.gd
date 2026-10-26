extends Area3D

const FALLBACK_MODEL = preload("res://scenes/presentation/ammo/pistol_box.tscn")
const PICKUP_RADIUS := 0.8
var _ammo: AmmoDefinition
var _amount: int = 0
var _claimed: bool = false
var _nearby: Array[Node3D] = []
var _retry_seconds: float = 0.0

func configure(definition: AmmoDefinition, count: int) -> void:
	_ammo = definition.duplicate()
	_amount = count

func _ready() -> void:
	set_physics_process(false)
	if _ammo == null or _amount <= 0:
		invalidate()
		queue_free()
		return
	var model: Node = _ammo.drop_model.instantiate() if _ammo.drop_model != null and _ammo.drop_model.can_instantiate() else null
	if model != null and (not model is Node3D or _has_physics(model)):
		push_warning("弹药 %s：Drop Model 需要不含碰撞的 Node3D 外观，改用通用盒子。" % _ammo.ammo_id)
		model.free()
		model = null
	if model == null: model = FALLBACK_MODEL.instantiate()
	$Visual.add_child(model)
	$Label.text = "%s ×%d" % [_ammo.display_name, _amount]
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)

func _has_physics(node: Node) -> bool:
	if node is CollisionObject3D or node is CollisionShape3D or node is CollisionPolygon3D: return true
	for child in node.get_children():
		if _has_physics(child): return true
	return false

func _on_entered(body: Node3D) -> void:
	if _claimed or not body.is_in_group("player"): return
	if not _nearby.has(body): _nearby.append(body)
	set_physics_process(true)
	_try_pickup(body)

func _on_exited(body: Node3D) -> void:
	_nearby.erase(body)
	if _nearby.is_empty(): set_physics_process(false)

func _physics_process(delta: float) -> void:
	_retry_seconds -= delta
	if _retry_seconds > 0.0: return
	_retry_seconds = 0.15
	for body in _nearby.duplicate():
		if not is_instance_valid(body) or not body.is_inside_tree(): _nearby.erase(body)
		elif _try_pickup(body): return
	if _nearby.is_empty(): set_physics_process(false)

func _try_pickup(player: Node3D) -> bool:
	if _claimed or get_tree().paused or player.is_dead() or player.is_in_dialogue: return false
	var offset := player.global_position - global_position
	if absf(offset.y) > 0.45 or Vector2(offset.x, offset.z).length() > PICKUP_RADIUS: return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 0.25, player.global_position + Vector3.UP * 0.25, 1, [player.get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return false
	var equipment := player.get_node_or_null("Equipment")
	if equipment == null or not equipment.has_method("add_ammo"): return false
	# 同一包只提交一次；失败不消失，后续恢复资格仍可领取。
	_claimed = true
	if equipment.add_ammo(_ammo, _amount) != _amount:
		_claimed = false
		return false
	invalidate()
	queue_free()
	return true

func invalidate() -> void:
	_claimed = true
	_nearby.clear()
	set_physics_process(false)
	set_deferred("monitoring", false)
