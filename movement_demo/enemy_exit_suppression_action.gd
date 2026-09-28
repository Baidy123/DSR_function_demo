extends "res://enemy_suppression_action.gd"

## 最后目击位置离掩体实体表面的最大水平距离；只推测邻近掩体，不追踪墙后玩家。
var cover_inference_distance: float:
	get: return _setting(&"cover_inference_distance", 1.75)
	set(value): _set_setting(&"cover_inference_distance", value)
## 每侧随机连续打出的枪数范围；仅实际开火才计数，冷却和连射停顿不换边。
var shots_per_exit_min: int:
	get: return _setting(&"shots_per_exit_min", 2)
	set(value): _set_setting(&"shots_per_exit_min", value)
var shots_per_exit_max: int:
	get: return _setting(&"shots_per_exit_max", 5)
	set(value): _set_setting(&"shots_per_exit_max", value)

var target_cover: StaticBody3D
var first_exit: Array[Vector3] = []
var second_exit: Array[Vector3] = []
var _next_exit: int = 0
var _shots_remaining: int = 0


func reset() -> void:
	super.reset()
	target_cover = null
	first_exit.clear()
	second_exit.clear()
	_next_exit = 0
	_shots_remaining = 0


func _prepare_targets(center: Vector3) -> bool:
	reset()
	if not tactics.can_suppress_exits:
		return false
	var nearest := INF
	var ground := center - Vector3.UP * 0.8
	# 距离按碰撞盒表面计算，适配现有掩体的旋转与缩放。
	for region in ai.get_tree().get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(region):
			continue
		var collision: CollisionShape3D = region.get_node_or_null("CollisionShape3D")
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var half: Vector3 = collision.shape.size * 0.5
		var local: Vector3 = collision.to_local(ground)
		var surface: Vector3 = collision.to_global(Vector3(clampf(local.x, -half.x, half.x), local.y, clampf(local.z, -half.z, half.z)))
		var distance := Vector2(surface.x - ground.x, surface.z - ground.z).length()
		if distance <= cover_inference_distance and distance < nearest:
			nearest = distance
			target_cover = region
	if not is_instance_valid(target_cover):
		return false
	var box: CollisionShape3D = target_cover.get_node("CollisionShape3D")
	var size: Vector3 = box.shape.size
	var along_x := size.x >= size.z
	var half_length := (size.x if along_x else size.z) * 0.5
	# 使用原墙角攻击区域的样本，但目标必须处在长轴两端之外，不能打向墙面中部。
	for point in target_cover.get_attack_candidates():
		var local: Vector3 = box.to_local(point)
		var along: float = local.x if along_x else local.z
		if absf(along) < half_length:
			continue
		var target: Vector3 = point + Vector3.UP * 0.8
		if actor.get_shot_origin().distance_to(target) > actor.weapon.fire_range:
			continue
		if not ai.cover_selection.has_clear_line(actor.get_shot_origin(), target):
			continue
		if along < 0.0:
			first_exit.append(target)
		else:
			second_exit.append(target)
	# 两端都能射到才采用这个动作，否则交回普通最后目击区域压制。
	return not first_exit.is_empty() and not second_exit.is_empty()


func _targets_available() -> bool:
	return tactics.can_suppress_exits and is_instance_valid(target_cover) and ai.cover_selection.has_clear_line(actor.get_shot_origin(), aim_point)


func utility_fire_fraction() -> float:
	# 入选前已确认两端都有可射样本，射击只从这些可见点中取样。
	return 1.0


func _select_aim_point() -> void:
	if _shots_remaining <= 0:
		var minimum := maxi(1, mini(shots_per_exit_min, shots_per_exit_max))
		var maximum := maxi(minimum, maxi(shots_per_exit_min, shots_per_exit_max))
		_shots_remaining = randi_range(minimum, maximum)
	var points: Array[Vector3] = first_exit if _next_exit == 0 else second_exit
	aim_point = points[randi_range(0, points.size() - 1)]


func on_shot_fired() -> void:
	_shots_remaining -= 1
	if _shots_remaining <= 0:
		_next_exit = 1 - _next_exit
	_select_aim_point()


func state_label() -> String:
	return "掩体出口压制"
