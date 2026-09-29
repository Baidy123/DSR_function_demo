extends RefCounted

signal shot_fired
var context
var request: Dictionary = {}
var fire_reaction_elapsed := 0.0
var fire_burst_shots := 0
var fire_pause_remaining := 0.0
var fire_decision = preload("res://scripts/enemy/services/enemy_fire_decision.gd").new()
var actor:
	get: return context.actor
var fire_while_moving: bool:
	get: return context.setting(&"tactics", &"fire_while_moving", true)
var fire_reaction_seconds: float:
	get: return context.setting(&"tactics", &"fire_reaction_seconds", 0.3)
var fire_stability_target: float:
	get: return context.setting(&"tactics", &"fire_stability_target", 0.7)
var burst_shot_count: int:
	get: return context.setting(&"tactics", &"burst_shot_count", 3)
var burst_pause_seconds: float:
	get: return context.setting(&"tactics", &"burst_pause_seconds", 1.0)
var ranged_min_distance: float:
	get: return context.setting(&"tactics", &"ranged_min_distance", 4.0)

func setup(shared_context) -> void:
	context = shared_context
	fire_decision.setup(context, &"fire_decision")
	actor.hit_received.connect(_on_hit_received)
	context.event_received.connect(_on_evidence_event)


func detach() -> void:
	if actor.hit_received.is_connected(_on_hit_received):
		actor.hit_received.disconnect(_on_hit_received)
	if context.event_received.is_connected(_on_evidence_event):
		context.event_received.disconnect(_on_evidence_event)
	fire_decision.context = null
	context = null

func _on_hit_received(damage: float, _attacker_position: Vector3) -> void:
	if is_finite(damage) and damage > 0.0:
		actor.apply_aim_penalty(float(context.setting(&"tactics", &"damage_accuracy_penalty", 0.15)))

func _on_evidence_event(event: StringName, _data: Dictionary) -> void:
	if event == &"near_shot":
		actor.apply_aim_penalty(float(context.setting(&"tactics", &"nearby_shot_accuracy_penalty", 0.02)))

func update(delta: float, visible: bool, moving: bool, intent: Dictionary) -> void:
	request = intent
	update_shooting(delta, visible, moving)

func _has_authorized_fire_action() -> bool:
	return not request.is_empty() and context.can_use_action(request.get("owner", &""))


func update_shooting(delta: float, sees_player: bool, movement_requested: bool) -> void:
	# 自然计时独立于动作授权；搜索、躲藏期间也会消耗已有连射停顿。
	var elapsed: float = maxf(0.0, delta)
	fire_pause_remaining = maxf(0.0, fire_pause_remaining - elapsed)
	if not _has_authorized_fire_action():
		fire_reaction_elapsed = 0.0
		fire_decision.reset()
		actor.update_weapon(delta)
		return
	if request.get("mode") == &"memory":
		_update_suppression_shooting(delta, movement_requested)
		return
	var visible_target: bool = (
		actor.can_use_firearms() and context.is_arena_active() and sees_player
		and not context.player.is_dead() and not context.player.is_in_dialogue
	)
	# 身体刚移动过，射击前再核实实际视线，避免用移动前的可见结果隔墙射击。
	visible_target = visible_target and context.perception.can_see_player()
	if not visible_target:
		fire_reaction_elapsed = 0.0
		fire_decision.reset()
		actor.update_weapon(delta)
		return
	var point: Vector3 = context.player.global_position + Vector3.UP * 0.8
	if actor.get_shot_origin().distance_to(point) > actor.weapon.fire_range:
		fire_reaction_elapsed = 0.0
		fire_decision.reset()
		actor.update_weapon(delta)
		return
	# 反应与停顿期间仍然跟枪；两者只阻止开火，不阻止移动、转身或瞄准。
	var previous_stability: float = _current_firing_stability()
	actor.update_weapon(delta, point)
	var reaction_seconds: float = maxf(0.0, fire_reaction_seconds)
	fire_reaction_elapsed = minf(reaction_seconds, fire_reaction_elapsed + elapsed)
	if fire_reaction_elapsed < reaction_seconds or fire_pause_remaining > 0.0:
		fire_decision.reset()
		return
	var moving: bool = movement_requested or Vector2(actor.velocity.x, actor.velocity.z).length() > 0.05
	if moving and not fire_while_moving:
		fire_decision.reset()
		return
	if not actor.can_fire():
		fire_decision.reset()
		return
	# 墙角站位按目标方向选出后，实际枪口仍可能在跟转；等它转出墙面再开火。
	if not has_clear_firing_lane(actor.get_shot_origin(), actor.aim_direction, actor.get_shot_origin().distance_to(point)):
		fire_decision.reset()
		context.invalidate_utility()
		return
	if request.get("bypass_steady", false):
		fire_decision.reset()
	else:
		var stability: float = _current_firing_stability()
		var recovery_rate: float = maxf(0.0, stability - previous_stability) / maxf(elapsed, 0.0001)
		var distance: float = actor.get_shot_origin().distance_to(point)
		var close_pressure: float = clampf(1.0 - distance / maxf(ranged_min_distance, 0.01), 0.0, 1.0)
		if fire_decision.choose_action(elapsed, stability, fire_stability_target, recovery_rate, close_pressure) != fire_decision.Action.FIRE:
			return
	if actor.try_fire():
		fire_decision.on_shot_fired()
		_record_burst_shot()
		shot_fired.emit()

func _update_suppression_shooting(delta: float, movement_requested: bool) -> void:
	fire_decision.reset()
	# 压制不保留旧目击的反应进度；重新看到目标仍需遵守原反应时间。
	fire_reaction_elapsed = 0.0
	# 仅此动作允许未目击时按记忆开火；不读取墙后玩家的当前坐标。
	if not actor.can_use_firearms() or not context.is_arena_active() or context.player.is_dead() or context.player.is_in_dialogue:
		actor.update_weapon(delta)
		return
	var point: Vector3 = request.get("point", Vector3.INF)
	actor.update_weapon(delta, point)
	var moving: bool = movement_requested or Vector2(actor.velocity.x, actor.velocity.z).length() > 0.05
	if actor.get_shot_origin().distance_to(point) > actor.weapon.fire_range or fire_pause_remaining > 0.0 or (moving and not fire_while_moving):
		return
	# aim_acquired 记录曾经跟上过目标，换点后仍可能为true；必须核实当前方向。
	var desired: Vector3 = point - actor.get_shot_origin()
	if desired.is_zero_approx() or actor.aim_direction.angle_to(desired) > actor.AIM_ACQUIRE_ANGLE:
		return
	if not has_clear_suppression_lane(actor.get_shot_origin(), actor.aim_direction, actor.get_shot_origin().distance_to(point)):
		context.invalidate_utility()
		return
	if actor.try_fire():
		_record_burst_shot()
		shot_fired.emit()

func _record_burst_shot() -> void:
	fire_burst_shots += 1
	if fire_burst_shots >= maxi(1, burst_shot_count):
		fire_burst_shots = 0
		fire_pause_remaining = maxf(0.0, burst_pause_seconds)

func _current_firing_stability() -> float:
	return actor.get_center_probability()

func reset_fire_timing() -> void:
	fire_decision.reset()
	fire_reaction_elapsed = 0.0
	fire_burst_shots = 0
	fire_pause_remaining = 0.0


## 只给统一评分器提供合法落脚点；不打分、不抽随机数、不修改导航或状态。
## 普通接敌和墙角攻击占位一样，先比较完整路线，再执行选中的准确位置。

func has_clear_suppression_lane(origin: Vector3, direction: Vector3, distance: float) -> bool:
	if direction.is_zero_approx() or distance <= 0.0:
		return false
	return context.cover_selection.has_clear_line(origin, origin + direction.normalized() * minf(0.5, distance))


## 中心弹道与近枪口空间是硬条件；远处外围散布擦墙只降低质量。

var _lane_frame := -1
var _lane_cache: Dictionary = {}
var _muzzle_shape := ConvexPolygonShape3D.new()
var _muzzle_query := PhysicsShapeQueryParameters3D.new()
var _muzzle_dimensions := Vector2.INF

func has_clear_firing_lane(origin: Vector3, direction: Vector3, distance: float) -> bool:
	if _lane_frame != Engine.get_physics_frames():
		_lane_frame = Engine.get_physics_frames()
		_lane_cache.clear()
	var key := [origin, direction, distance, actor.get_max_shot_deviation_degrees()]
	if not _lane_cache.has(key):
		_lane_cache[key] = _query_clear_firing_lane(origin, direction, distance)
	return _lane_cache[key]

func _query_clear_firing_lane(origin: Vector3, direction: Vector3, distance: float) -> bool:
	if direction.is_zero_approx() or distance <= 0.0:
		return false
	var axis := direction.normalized()
	var endpoint := origin + axis * distance
	if not context.cover_selection.has_clear_line(origin, endpoint):
		return false
	var spread: float = actor.get_max_shot_deviation_degrees()
	var near_distance := minf(0.5, distance)
	# 一次凸体查询覆盖枪口前半米的真实三维散布空间，普通障碍也参与。
	var dimensions := Vector2(spread, near_distance)
	if dimensions != _muzzle_dimensions:
		_muzzle_dimensions = dimensions
		var points := PackedVector3Array()
		var radius := 0.08 + near_distance * tan(deg_to_rad(spread))
		for index in 12:
			var angle := TAU * index / 12.0
			var radial := Vector3(cos(angle), sin(angle), 0) / cos(PI / 12.0)
			points.append(radial * 0.08)
			points.append(radial * radius + Vector3.FORWARD * near_distance)
		_muzzle_shape.points = points
	var query := _muzzle_query
	query.shape = _muzzle_shape
	query.transform = Transform3D(Basis.looking_at(axis, Vector3.UP if absf(axis.y) < 0.999 else Vector3.RIGHT), origin)
	query.collision_mask = 1
	query.exclude = context.cover_selection._ray_query(origin, endpoint).exclude
	var space: PhysicsDirectSpaceState3D = actor.get_world_3d().direct_space_state
	return space.intersect_shape(query, 1).is_empty()

## 水平外围弹道的通畅比例参与候选的有效火力估计，不要求极端散布全部避墙。
## 以训练期望的中心命中概率估计，不随当前转身或单发后精度波动重画区域。
func firing_lane_quality(origin: Vector3, direction: Vector3, distance: float) -> float:
	if direction.is_zero_approx() or distance <= 0.0: return 0.0
	var axis := direction.normalized()
	var clear := 0.0
	for fraction in [-1.0, -0.66, -0.33, 0.33, 0.66, 1.0]:
		var ray := axis.rotated(Vector3.UP, deg_to_rad(actor.get_max_shot_deviation_degrees() * fraction))
		if context.cover_selection.has_clear_line(origin, origin + ray * distance): clear += 1.0
	var center := clampf(fire_stability_target, 0.0, 1.0)
	return center + (1.0 - center) * clear / 6.0


## 统一决策可用同一条件复核固定目的地；路径失效直接触发重评。
