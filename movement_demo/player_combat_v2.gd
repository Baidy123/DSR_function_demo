extends Node

signal weapon_changed(data: WeaponData)
signal shot_fired(hit: bool, probability: float)

## 当前装备的 WeaponData 资源（例如 test_pistol.tres）；保存枪械参数，运行中的精度由 Combat 单独维护。
@export var weapon: WeaponData

var is_aiming: bool = false
var locked_target: Node3D = null
var accuracy: float = 0.5
var shot_cooldown: float = 0.0
var shot_count: int = 0
var last_shot_collider: Object = null
var shot_requested: bool = false
var last_result: String = ""
var accuracy_recovery_timer: float = 0.0

@onready var player = get_parent()
@onready var status: Label = $HUD/Panel/Status


func _ready() -> void:
	equip_weapon(weapon)


## 以后装备菜单调用这个接口。Resource 只保存配置，不保存运行中的精度。
func equip_weapon(data: WeaponData) -> void:
	weapon = data
	accuracy = weapon.initial_accuracy if weapon != null else 0.0
	accuracy_recovery_timer = 0.0
	cancel_aim()
	shot_cooldown = 0.0
	last_result = ""
	weapon_changed.emit(weapon)


func _unhandled_input(event: InputEvent) -> void:
	if player.is_in_dialogue or weapon == null or not can_combat():
		return
	if event.is_action_pressed("fire") and Input.is_action_pressed("aim"):
		shot_requested = true
		get_viewport().set_input_as_handled()


func cancel_aim() -> void:
	is_aiming = false
	locked_target = null
	shot_requested = false
	# 松开再按瞄准不能消除刚刚累积的射击惩罚。
	accuracy = minf(accuracy, weapon.initial_accuracy) if weapon != null else 0.0
	$HUD/Reticle.hide()


func can_combat() -> bool:
	# 查询实际重叠区域；支持多个区域重叠，不需要全局开关。
	for area in get_tree().get_nodes_in_group("combat_zone"):
		if area is Area3D and area.monitoring and area.overlaps_body(player):
			return true
	return false


# Player 在移动前调用：检查锁定，再由 Player 应用朝向。
func begin_frame(delta: float, aim_pressed: bool) -> void:
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	if weapon == null or player.is_in_dialogue or not aim_pressed or not can_combat():
		cancel_aim()
		return
	is_aiming = true
	if is_instance_valid(locked_target) and not _target_visible(locked_target):
		locked_target = null
		accuracy = minf(accuracy, weapon.initial_accuracy)
	if not is_instance_valid(locked_target):
		var new_target: Node3D = _find_target()
		if is_instance_valid(new_target):
			locked_target = new_target
			# 刚锁定到新目标时重新从基础精度开始稳定；
			# 没有锁定目标时则保留持续瞄准积累的精度。
			accuracy = minf(accuracy, weapon.initial_accuracy)
	if is_instance_valid(locked_target):
		var direction: Vector3 = locked_target.global_position - player.global_position
		if Vector2(direction.x, direction.z).length_squared() > 0.0001:
			player.visual.global_rotation.y = atan2(-direction.x, -direction.z)


# Player 移动后调用，以实际位移判断移动惩罚，射击使用本帧的视线。
func end_frame(delta: float, moving: bool) -> void:
	if not can_combat() or player.is_in_dialogue:
		cancel_aim()
	if is_instance_valid(locked_target) and not _target_visible(locked_target):
		locked_target = null
		accuracy = minf(accuracy, weapon.initial_accuracy)
	if weapon != null:
		var recovery: float = (1.0 - weapon.initial_accuracy) / maxf(weapon.stabilize_seconds, 0.01)
		if moving:
			accuracy = minf(accuracy, weapon.moving_accuracy_cap)
			accuracy_recovery_timer = weapon.accuracy_recovery_delay
		else:
			# 只计入延迟结束后剩余的时间，避免低帧率改变恢复速度。
			var recovery_delta: float = maxf(0.0, delta - accuracy_recovery_timer)
			accuracy_recovery_timer = maxf(0.0, accuracy_recovery_timer - delta)
			# 玩家没有实际移动时，延迟结束后按稳定速度恢复到 100%。
			# 未瞄准时 begin_frame 会先把精度限制到初始值；此处仍按本帧时间恢复。
			accuracy = minf(1.0, accuracy + recovery * recovery_delta)
	if shot_requested:
		shot_requested = false
		shoot()
	_update_status()


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dot: float = cos(deg_to_rad(weapon.cone_angle_degrees * 0.5))
	var forward: Vector3 = -player.visual.global_basis.z
	for candidate in get_tree().get_nodes_in_group("combat_target"):
		var direction: Vector3 = candidate.global_position - player.global_position
		direction.y = 0.0
		if direction.is_zero_approx():
			continue
		var alignment: float = forward.dot(direction.normalized())
		if alignment >= best_dot and _target_visible(candidate):
			best = candidate
			best_dot = alignment
	return best


func _target_visible(target: Node3D) -> bool:
	if not target.is_inside_tree() or not target.is_in_group("combat_target"):
		return false
	var offset: Vector3 = target.global_position - player.global_position
	if offset.length() > weapon.aim_range:
		return false
	var hit: Dictionary = _ray_to(target.global_position + Vector3.UP * 0.8)
	return not hit.is_empty() and hit.collider == target


func _ray_to(endpoint: Vector3) -> Dictionary:
	var origin: Vector3 = player.global_position + Vector3.UP * 0.8
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, [player.get_rid()])
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func shoot() -> void:
	if not is_aiming or player.is_in_dialogue or weapon == null or shot_cooldown > 0.0 or not can_combat():
		return
	# 再检查一次，防止输入与物理更新之间出现遮挡。
	if is_instance_valid(locked_target) and not _target_visible(locked_target):
		locked_target = null
		accuracy = minf(accuracy, weapon.initial_accuracy)
	shot_count += 1
	shot_cooldown = weapon.shot_interval
	var probability: float = accuracy
	var origin: Vector3 = player.global_position + Vector3.UP * 0.8
	var direction: Vector3 = -player.visual.global_basis.z
	var has_lock: bool = is_instance_valid(locked_target)
	if has_lock:
		direction = (locked_target.global_position + Vector3.UP * 0.8 - origin).normalized()

	# 有无锁定都使用当前 accuracy 判定这一枪是否准确。
	# 因此无锁定时不再是 100% 直射；持续瞄准后 accuracy 才会逐渐升高。
	var aimed_at_center: bool = randf() < probability
	if not aimed_at_center:
		# 锁定时围绕“目标方向”射偏；无锁定时围绕“玩家当前瞄准方向”射偏。
		direction = _random_direction_in_miss_cone(direction, 8.0, 20.0)
	var endpoint: Vector3 = origin + direction * weapon.aim_range
	var hit: Dictionary = _ray_to(endpoint)
	last_shot_collider = hit.get("collider")
	var target_hit: bool = false
	if not hit.is_empty():
		endpoint = hit.position
		if hit.collider.is_in_group("combat_target"):
			hit.collider.receive_hit(weapon.damage, player.global_position)
			target_hit = true
			if locked_target == hit.collider and not hit.collider.is_in_group("combat_target"):
				locked_target = null
				$HUD/Reticle.hide()
	# 使用实际命中点截断后的线段检测近处来弹；墙后的延长线不会触发。
	for listener in get_tree().get_nodes_in_group("shot_listener"):
		listener.notice_shot(origin, endpoint)
	accuracy = maxf(minf(accuracy, weapon.minimum_accuracy), accuracy - weapon.shot_accuracy_penalty)
	accuracy_recovery_timer = weapon.accuracy_recovery_delay
	last_result = "命中" if target_hit else "未命中"
	_draw_shot(origin, endpoint, target_hit)
	shot_fired.emit(target_hit, probability)
	_update_status()


# 返回围绕 forward 的随机锥形偏移方向。
# min_angle_degrees / max_angle_degrees 控制偏离瞄准中心的最小和最大夹角。
func _random_direction_in_miss_cone(
	forward: Vector3,
	min_angle_degrees: float,
	max_angle_degrees: float
) -> Vector3:
	var cone_axis: Vector3 = forward.normalized()

	# 构造一个与瞄准方向垂直的局部二维平面。
	# 当瞄准方向接近竖直时改用 RIGHT，避免叉乘退化。
	var reference_axis: Vector3 = Vector3.UP
	if absf(cone_axis.dot(reference_axis)) > 0.999:
		reference_axis = Vector3.RIGHT

	var cone_right: Vector3 = cone_axis.cross(reference_axis).normalized()
	var cone_up: Vector3 = cone_right.cross(cone_axis).normalized()

	# phi 决定锥体圆周上的方向，因此上下左右和斜方向都有可能出现。
	var phi: float = randf_range(0.0, TAU)
	var theta: float = deg_to_rad(randf_range(min_angle_degrees, max_angle_degrees))
	var radial: Vector3 = cone_right * cos(phi) + cone_up * sin(phi)

	return (cone_axis * cos(theta) + radial * sin(theta)).normalized()


func _draw_shot(origin: Vector3, endpoint: Vector3, hit: bool) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(origin)
	mesh.surface_add_vertex(endpoint)
	mesh.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.GREEN_YELLOW if hit else Color.ORANGE
	line.material_override = material
	get_tree().current_scene.add_child(line)
	get_tree().create_timer(0.12).timeout.connect(line.queue_free)


func _update_status() -> void:
	$HUD/Panel.visible = not player.is_in_dialogue
	var title: String = weapon.display_name if weapon != null else "未装备"
	var target_name: String = str(locked_target.name) if is_instance_valid(locked_target) else "无"
	var precision: String = "%d%%" % roundi(accuracy * 100.0)
	var hint: String = "右键瞄准 / 左键单发" if can_combat() else "非战斗区域：请进入靶场"
	status.text = "%s　%s\n锁定：%s　命中率：%s\n%s" % [title, hint, target_name, precision, last_result]
