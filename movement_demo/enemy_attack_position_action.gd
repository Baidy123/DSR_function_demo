extends "res://enemy_action.gd"

# 主动交火占位，与躲藏／探头动作互斥；只使用已有目击或本次受击估计位置。
signal phase_changed(current_phase: int)
signal finished(sees_player: bool, known_position: Vector3, reason: String)

enum Phase { NONE, FIND, MOVE, HOLD }
var phase: Phase = Phase.NONE
var destination: Vector3
var active_cover: StaticBody3D
var _candidates: Array[Dictionary] = []
var _cursor: int = 0
var _query_target: Vector3
var _using_hit_memory: bool = false
var _best_length: float = INF
var _recheck: float = 0.0
var _remaining: float = 0.0
var _waypoint: Vector3
var _best_distance: float = INF
var _stuck: float = 0.0



func is_active() -> bool:
	return phase != Phase.NONE


# 取消／复位只清理本动作，不覆盖接管方的导航与决策。
func reset() -> void:
	phase = Phase.NONE
	active_cover = null
	_candidates.clear()
	_cursor = 0
	_best_length = INF
	_recheck = 0.0
	_remaining = 0.0
	_stuck = 0.0
	_best_distance = INF
	_using_hit_memory = false


# 只查询条件，不抽概率、不修改动作。权限暂读原配置，后续再迁入Training。
func can_start() -> bool:
	if not is_enabled():
		return false
	if is_active() or tactics.cover.is_active() or tactics.suppression.is_active() or not tactics.can_use_attack_positions:
		return false
	if actor.is_dead or not ai.is_arena_active() or actor.weapon == null or ai.combat_type != ai.CombatType.RANGED:
		return false
	return true


# 调用方提供已有记忆的脚底位置；受击快照直到重新目击前不会追踪隐藏玩家。
func start(known_position: Vector3, from_hit: bool = false) -> bool:
	if not can_start():
		return false
	reset()
	_using_hit_memory = from_hit
	_query_target = known_position + Vector3.UP * 0.8
	for region in ai.get_tree().get_nodes_in_group("cover_region"):
		if ai.navigation_region.is_ancestor_of(region):
			for point in region.get_attack_candidates():
				_candidates.append({"position": point, "cover": region})
	phase = Phase.FIND
	phase_changed.emit(phase)
	actor.agent.target_position = actor.global_position
	return true


func step(delta: float, sees_player: bool) -> Vector3:
	if not is_active():
		return Vector3.ZERO
	if actor.is_dead or not ai.is_arena_active() or tactics.cover.is_active():
		reset()
		return Vector3.ZERO
	if not is_enabled() or not tactics.can_use_attack_positions or actor.weapon == null or ai.combat_type != ai.CombatType.RANGED:
		_finish(sees_player, "能力关闭、无武器或非远程")
		return Vector3.ZERO
	# 主AI已在本帧更新真实目击；之后即使再失视，也沿用该目击记忆。
	if sees_player:
		_using_hit_memory = false
	if phase == Phase.FIND:
		_find_position(sees_player)
		return Vector3.ZERO
	# 到位后已经站在实际落脚点，不再用早先的采样目的地决定是否离开。
	if phase == Phase.HOLD:
		if not sees_player:
			_finish(false, "占位后失去真实视线")
		else:
			var reason := _unusable_reason(actor.global_position)
			if not reason.is_empty():
				_finish(true, "实际站位失效：" + reason)
		return Vector3.ZERO
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.25
		var reason := _unusable_reason(destination)
		if not reason.is_empty():
			_finish(sees_player, "前往的目的地失效：" + reason)
			return Vector3.ZERO
	_remaining -= delta
	if _remaining <= 0.0:
		_finish(sees_player, "转移超时")
		return Vector3.ZERO
	var distance: float = ai._horizontal_distance(destination)
	if distance <= 0.12:
		# 不能提前停在墙后；实际脚下也必须合格才算完成占位。
		if _usable(actor.global_position):
			if not sees_player:
				_finish(false, "到点仍未看见玩家")
				return Vector3.ZERO
			phase = Phase.HOLD
			phase_changed.emit(phase)
			actor.agent.target_position = actor.global_position
			if selection.debug_cover_selection:
				print("[AI][攻击占位] 到位，保持射击位置 ", actor.global_position)
			return Vector3.ZERO
		if distance <= 0.02:
			_finish(sees_player, "抵达但实际站位不合格")
			return Vector3.ZERO
	# 来弹／受击可能更新普通导航目标；未进入躲藏时继续当前攻击目的地。
	if actor.agent.target_position.distance_to(destination) > 0.01:
		actor.agent.target_position = destination
	var next: Vector3 = actor.agent.get_next_path_position()
	var finishing: bool = distance <= 0.7 and _final_segment_clear()
	if finishing:
		next = destination
	elif actor.agent.is_navigation_finished():
		_finish(sees_player, "导航提前结束且最后一段不通")
		return Vector3.ZERO
	# 卡住时退出本次行动，不持续向同一堵墙走，也不重新抽概率。
	var waypoint_distance: float = ai._horizontal_distance(next)
	if ai._horizontal_distance_between(next, _waypoint) > 0.25:
		_waypoint = next
		_best_distance = INF
	if waypoint_distance < _best_distance - 0.05:
		_best_distance = waypoint_distance
		_stuck = 0.0
	else:
		_stuck += delta
	if _stuck >= 2.0:
		_finish(sees_player, "路径连续两秒无进展")
		return Vector3.ZERO
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * delta))


## Utility已经比较了具体点与路线；执行该点，不能再按另一套最近距离重选。
func start_evaluated(candidate: Dictionary, known_position: Vector3) -> bool:
	if not can_start() or not is_instance_valid(candidate.get("body")):
		return false
	reset()
	destination = candidate.position
	active_cover = candidate.body
	_query_target = known_position + Vector3.UP * 0.8
	_using_hit_memory = true
	if not _usable(destination):
		reset()
		return false
	var length: float = selection._path_length(actor.global_position, destination)
	if not is_finite(length):
		reset()
		return false
	_remaining = length / maxf(0.1, actor.move_speed) + 3.0
	phase = Phase.MOVE
	phase_changed.emit(phase)
	actor.agent.target_position = destination
	return true


func _find_position(sees_player: bool) -> void:
	# 与调试显示独立。每帧最多64点／约2.5毫秒；整轮基于触发时已知的位置。
	var started := Time.get_ticks_usec()
	var end := mini(_cursor + 64, _candidates.size())
	while _cursor < end:
		var candidate := _candidates[_cursor]
		_cursor += 1
		if is_instance_valid(candidate.cover):
			var result: Dictionary = selection.assess_attack_point(candidate.position, candidate.cover, _query_target, _query_target)
			if result.usable and _within_sight_range(candidate.position, _query_target - Vector3.UP * 0.8):
				var length: float = selection._path_length(actor.global_position, candidate.position)
				if length < _best_length:
					_best_length = length
					destination = candidate.position
					active_cover = candidate.cover
		if Time.get_ticks_usec() - started >= 2500:
			break
	if _cursor < _candidates.size():
		return
	_candidates.clear()
	# 查找期间玩家可能移动，提交时再按最新真实目击复核所选点。
	if is_inf(_best_length):
		_finish(sees_player, "本轮没有合格候选（含感知距离限制）")
		return
	var reason := _unusable_reason(destination)
	if not reason.is_empty():
		_finish(sees_player, "查找期间目标变化，原选点失效：" + reason)
		return
	phase = Phase.MOVE
	phase_changed.emit(phase)
	_remaining = _best_length / maxf(0.1, actor.move_speed) + 3.0
	actor.agent.target_position = destination
	if selection.debug_cover_selection:
		print("[AI][攻击占位] 前往 ", active_cover.name, " 位置=", destination)


func _usable(point: Vector3) -> bool:
	return _unusable_reason(point).is_empty()


func _unusable_reason(point: Vector3) -> String:
	if not is_instance_valid(active_cover):
		return "所属掩体失效"
	if not _within_sight_range(point, _known_position()):
		return "超过感知距离"
	var target: Vector3 = _known_position() + Vector3.UP * 0.8
	var origin: Vector3 = point + actor.get_shot_origin() - actor.global_position
	if not tactics.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
		return "完整射界被掩体遮挡"
	var result: Dictionary = selection.assess_attack_point(point, active_cover, target, target)
	return "" if result.usable else result.reason


func _known_position() -> Vector3:
	return _query_target - Vector3.UP * 0.8 if _using_hit_memory else ai.last_seen_position


# 射程够但感知距离不够的点，到位仍不能发现／攻击目标，不作为主动占位目的地。
func _within_sight_range(point: Vector3, known_position: Vector3) -> bool:
	return point.distance_to(known_position) <= maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius)


func _final_segment_clear() -> bool:
	var count := maxi(1, ceili(ai._horizontal_distance(destination) / 0.1))
	for index in range(1, count + 1):
		if not ai.is_position_free(actor.global_position.lerp(destination, float(index) / count)):
			return false
	return true


func _finish(sees_player: bool, reason: String = "结束行动") -> void:
	var known_position := _known_position()
	reset()
	finished.emit(sees_player, known_position, reason)


func state_label() -> String:
	return ["", "查找墙角攻击位置", "前往墙角攻击位置", "墙角占位射击"][phase]
