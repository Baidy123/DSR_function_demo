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
	_show_in_foreground(model)
	$Label.text = "%s ×%d" % [_ammo.display_name, _amount]
	body_entered.connect(_on_entered)
	body_exited.connect(_on_exited)

## 只改当前掉落实例的绘制层级；不修改共享模型／材质，也不抬高地面位置。
func _show_in_foreground(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		node.ignore_occlusion_culling = true
		if node.material_override != null:
			node.material_override = _foreground_material(node.material_override)
		else:
			for surface in range(node.mesh.get_surface_count()):
				node.set_surface_override_material(surface, _foreground_material(node.get_active_material(surface)))
		if node.material_overlay != null: node.material_overlay = _foreground_material(node.material_overlay)
	elif node is Label3D:
		node.no_depth_test = true
		node.render_priority = Material.RENDER_PRIORITY_MAX
	for child in node.get_children(): _show_in_foreground(child)

func _foreground_material(source: Material) -> BaseMaterial3D:
	# 标准／ORM材质复制原贴图与颜色；无材质或自定义Shader使用标准材质保证可见。
	var material: BaseMaterial3D = source.duplicate() if source is BaseMaterial3D else StandardMaterial3D.new()
	material.no_depth_test = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	# 深度关闭还需进入透明队列，才能稳定在尸体等不透明几何之后绘制。
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.render_priority = Material.RENDER_PRIORITY_MAX - 1
	if material.next_pass != null: material.next_pass = _foreground_material(material.next_pass)
	return material

func is_available() -> bool:
	return not _claimed and is_inside_tree() and not is_queued_for_deletion()

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
