extends Node

# 感知：只判断真实视线；不生成墙后目标位置。
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

const Actor = preload("res://enemy_actor.gd")
@onready var ai = get_parent()
@onready var actor: Actor = get_parent().get_parent()
@onready var agent: NavigationAgent3D = actor.get_node("NavigationAgent3D")


func can_see_player() -> bool:
	if not is_instance_valid(ai.player) or not ai.arena_zone.overlaps_body(ai.player):
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
			current_sight_angle = maxf(current_sight_angle, ai.search.track_sight_angle_degrees)

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
func _training_setting(key: StringName, _fallback: Variant) -> Variant:
	return get_node("../../Training").get("perception_" + String(key))


func _set_training_setting(key: StringName, value: Variant) -> void:
	get_node("../../Training").set("perception_" + String(key), value)
