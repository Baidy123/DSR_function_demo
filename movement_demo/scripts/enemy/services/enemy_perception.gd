extends Node

# 感知：判断真实视线与一次性声源；不持续获取隐藏目标位置。
signal noise_heard(position: Vector3)
## 普通视觉感知的最大距离（米）；仍受视角、墙壁和竞技场范围限制。
var sight_distance: float:
	get: return _training_setting(&"sight_distance", 10.0)
	set(value): _set_training_setting(&"sight_distance", value)
## 普通视野的水平总角度（度）；左右各占一半，近身警戒不受此角度限制。
var sight_angle_degrees: float:
	get: return _training_setting(&"sight_angle_degrees", 120.0)
	set(value): _set_training_setting(&"sight_angle_degrees", value)
## 近身警戒不限制方向，但仍检测墙壁遮挡。
var close_awareness_radius: float:
	get: return _training_setting(&"close_awareness_radius", 2.0)
	set(value): _set_training_setting(&"close_awareness_radius", value)

const Actor = preload("res://scripts/enemy/enemy_actor.gd")
var ai:
	get: return get_parent().context
@onready var actor: Actor = get_parent().get_parent()
@onready var agent: NavigationAgent3D = actor.get_node("NavigationAgent3D")


func can_see_player() -> bool:
	if not ai.is_arena_active():
		return false

	var offset: Vector3 = ai.player.global_position - actor.global_position

	if offset.length() > maxf(sight_distance, close_awareness_radius):
		return false

	offset.y = 0.0

	if offset.length() > close_awareness_radius and not offset.is_zero_approx():
		var current_sight_angle: float = sight_angle_degrees
		if ai.state == ai.State.TRACK:
			# 架枪追踪时注意力更集中，但不是视野更窄：保留更宽的周边警觉，
			# 玩家从侧面接近时仍有机会进入真实视觉检测。
			current_sight_angle = maxf(current_sight_angle, float(ai.setting(&"search", &"track_sight_angle_degrees", 220.0)))

		var alignment: float = (-actor.global_basis.z).dot(offset.normalized())
		if alignment < cos(deg_to_rad(current_sight_angle * 0.5)):
			return false

	var query = PhysicsRayQueryParameters3D.create(
		actor.global_position + Vector3.UP * 0.8,
		ai.player.global_position + Vector3.UP * 0.8,
		1,
		[actor.get_rid()]
	)
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == ai.player

# 原属性名转发至Training，避免维护两份配置。
func _training_setting(key: StringName, fallback: Variant) -> Variant:
	return ai.setting(&"perception", key, fallback)


func _set_training_setting(key: StringName, value: Variant) -> void:
	if ai.training != null: ai.training.set_setting(&"perception", key, value)


func _ready() -> void:
	add_to_group("hearing_listener")


func receive_noise(source: Node3D, position: Vector3, radius: float, occluded_multiplier: float) -> void:
	# 必须来自实际玩家；即使队友与玩家共用声音/武器资源，也不会误触发调查。
	if not is_instance_valid(source) or source != ai.player or actor.is_dead or not ai.is_arena_active():
		return
	if not _training_setting(&"hearing_enabled", true) or radius <= 0.0 or not position.is_finite():
		return
	var distance: float = actor.global_position.distance_to(position)
	if distance > radius:
		return
	var query := PhysicsRayQueryParameters3D.create(
		actor.global_position + Vector3.UP * 0.8, position + Vector3.UP * 0.8, 1,
		[actor.get_rid(), source.get_rid()])
	# 角色不作为隔音墙；保留地图实体的碰撞检测。
	for target in get_tree().get_nodes_in_group("combat_target"):
		if target is CollisionObject3D:
			var excluded: Array[RID] = query.exclude
			excluded.append(target.get_rid())
			query.exclude = excluded
	var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
	var effective_radius: float = radius * clampf(occluded_multiplier, 0.0, 1.0) if not hit.is_empty() else radius
	if effective_radius > 0.0 and distance <= effective_radius:
		noise_heard.emit(position)
