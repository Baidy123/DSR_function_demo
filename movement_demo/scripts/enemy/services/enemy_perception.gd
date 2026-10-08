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
	if not _position_in_sight(ai.player.global_position):
		return false

	var points: PackedVector3Array = ai.player.get_visibility_points() if ai.player.has_method("get_visibility_points") else PackedVector3Array([ai.player.global_position + Vector3.UP * 0.8])
	for point in points:
		if _sees_point(point): return true
	return false

func _sees_point(point: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(actor.get_eye_position(), point, 1, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == ai.player



## 查询地面样本是否在当前实际站位的视野内；不探测或更新隐藏玩家位置。
func can_observe_position(position: Vector3) -> bool:
	return _position_in_sight(position) and ai.cover_selection.has_clear_line(
		actor.get_eye_position(), actor.get_posture_eye_position(true, position))


func _position_in_sight(position: Vector3) -> bool:
	var offset: Vector3 = position - actor.global_position
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

	return true

# 原属性名转发至Training，避免维护两份配置。
func _training_setting(key: StringName, fallback: Variant) -> Variant:
	return ai.setting(&"perception", key, fallback)


func _set_training_setting(key: StringName, value: Variant) -> void:
	if ai.training != null: ai.training.set_setting(&"perception", key, value)


## 由已完成的视觉检测授权读取，只提供正在换弹这一外部可观察事实。
func observes_reload(visible: bool) -> bool:
	if not visible or not is_instance_valid(ai.player): return false
	var torso: Vector3 = ai.player.get_torso_position() if ai.player.has_method("get_torso_position") else ai.player.global_position + Vector3.UP * 0.8
	if not _sees_point(torso): return false
	var combat = ai.player.get_node_or_null("Combat")
	return combat != null and combat.ammo != null and combat.ammo.is_reloading


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
		actor.get_eye_position(), position + Vector3.UP * 0.8, 1,
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


const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var _contact_latched := false
var _contact_exit_seconds := 0.0
var _contact_cooldown := 0.0

func reset_contact() -> void:
	_contact_latched = false
	_contact_exit_seconds = 0.0
	_contact_cooldown = 0.0

func update_close_cover(delta: float) -> void:
	_contact_cooldown = maxf(0.0, _contact_cooldown - delta)
	if not _training_setting(&"close_cover_intelligence_enabled", true): return
	var distance := float(_training_setting(&"close_cover_intelligence_distance", 2.0))
	# Contact rearming uses physical separation, never a crouch toggle or visibility toggle.
	if _contact_latched:
		if actor.global_position.distance_to(ai.player.global_position) > distance + 0.5:
			_contact_exit_seconds += delta
		else: _contact_exit_seconds = 0.0
		if _contact_exit_seconds >= 0.5 and _contact_cooldown <= 0.0: _contact_latched = false
		return
	if ai.sees_player: return
	var result := LowCover.proximity_cover(actor, ai.player, distance)
	if result.is_empty(): return
	_contact_latched = true
	_contact_exit_seconds = 0.0
	_contact_cooldown = float(_training_setting(&"close_cover_intelligence_cooldown", 4.0))
	ai.receive_exact_cover_clue(result.position, result.cover)

func visible_aim_position(visible_authorized: bool = false) -> Vector3:
	if not visible_authorized: return Vector3.INF
	var points: PackedVector3Array = ai.player.get_visibility_points()
	points.insert(0, ai.player.get_torso_position())
	for point in points:
		if not _sees_point(point): continue
		var origin: Vector3 = actor.get_muzzle_position()
		if ai.fire.has_clear_firing_lane(origin, point - origin, origin.distance_to(point)): return point
	return Vector3.INF

## Only the last observed foot point and public static geometry classify a lost-contact event.
func last_observed_cover(feet: Vector3) -> Object:
	var point: Vector3 = actor.get_posture_eye_position(true, feet)
	var query: PhysicsRayQueryParameters3D = ai.cover_selection._ray_query(actor.get_eye_position(), point)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	var cover: Object = hit.get("collider")
	if not hit.is_empty() and (not cover.has_method("is_low_cover") or not cover.is_low_cover()): return cover
	# A standing target can leave sight without crouching. The eye-level ray can
	# pass above its low wall; classify the remembered foot point against the
	# same static geometry instead of reading the hidden target's current pose.
	if hit.is_empty():
		query = ai.cover_selection._ray_query(actor.get_eye_position(), feet + Vector3.UP * 0.15)
		hit = actor.get_world_3d().direct_space_state.intersect_ray(query)
		cover = hit.get("collider")
	if not is_instance_valid(cover) or not cover.has_method("is_low_cover") or not cover.is_low_cover(): return null
	var shape: CollisionShape3D = cover.get_node_or_null("CollisionShape3D")
	if shape == null or not shape.shape is BoxShape3D: return null
	var local: Vector3 = shape.to_local(feet)
	var half: Vector3 = shape.shape.size * 0.5
	var gap := Vector2(maxf(0.0, absf(local.x) - half.x) * shape.global_basis.x.length(), maxf(0.0, absf(local.z) - half.z) * shape.global_basis.z.length())
	return cover if gap.length() <= float(ai.setting(&"selection", &"cover_inference_distance", 1.75)) else null
