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


## 普通交战仍检查完整散布，不把压制的宽松条件用于精确选位。

func has_clear_firing_lane(origin: Vector3, direction: Vector3, distance: float) -> bool:
	if direction.is_zero_approx() or distance <= 0.0:
		return false
	var axis := direction.normalized()
	var endpoint := origin + axis * distance
	if not context.cover_selection.has_clear_line(origin, endpoint):
		return false
	var start := Vector2(origin.x, origin.z)
	var end := Vector2(endpoint.x, endpoint.z)
	var spread: float = actor.get_max_shot_deviation_degrees()
	var radius: float = distance * tan(deg_to_rad(spread)) + 0.1
	for body in context.get_tree().get_nodes_in_group("cover_region"):
		if not context.navigation_region.is_ancestor_of(body):
			continue
		var collision: CollisionShape3D = body.get_node_or_null("CollisionShape3D")
		if collision == null or not collision.shape is BoxShape3D:
			continue
		var center := Vector2(collision.global_position.x, collision.global_position.z)
		var extent: float = (collision.shape.size * collision.global_basis.get_scale()).length() * 0.5
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center, start, end)) > radius + extent:
			continue
		if not context.cover_selection.has_clear_shot_cone(origin, axis, spread, distance, body):
			return false
	return true


## 统一决策可用同一条件复核固定目的地；路径失效直接触发重评。
