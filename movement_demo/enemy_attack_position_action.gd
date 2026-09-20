extends Node

# 主动交火占位，与躲藏／探头动作互斥；只通过AI已有目击信息查询位置。
enum Phase { NONE, FIND, MOVE, HOLD }
var phase: Phase = Phase.NONE
var destination: Vector3
var active_cover: StaticBody3D
var _candidates: Array[Dictionary] = []
var _cursor: int = 0
var _query_target: Vector3
var _best_length: float = INF
var _recheck: float = 0.0
var _remaining: float = 0.0
var _waypoint: Vector3
var _best_distance: float = INF
var _stuck: float = 0.0

@onready var tactics = get_parent()
@onready var ai = get_parent().get_parent()
@onready var actor = ai.get_parent()
@onready var selection = ai.get_node("Cover")


func is_active() -> bool:
	return phase != Phase.NONE


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


# 仅由首次／重新目击事件调用，持续可见及当前动作中不重复抽概率。
func on_player_seen() -> void:
	if is_active() or tactics.cover.is_active() or not tactics.can_use_attack_positions:
		return
	if actor.is_dead or not ai.is_arena_active() or not ai.has_visual_memory or actor.weapon == null or ai.combat_type != ai.CombatType.RANGED:
		return
	if randf() >= clampf(tactics.attack_position_chance, 0.0, 1.0):
		return
	reset()
	_query_target = ai.last_seen_position + Vector3.UP * 0.8
	for region in get_tree().get_nodes_in_group("cover_region"):
		if ai.navigation_region.is_ancestor_of(region):
			for point in region.get_attack_candidates():
				_candidates.append({"position": point, "cover": region})
	phase = Phase.FIND
	ai.state = ai.State.REPOSITION
	actor.agent.target_position = actor.global_position
	if selection.debug_cover_selection:
		print("[AI][攻击占位] 新目击触发，开始检查墙角区域")


func step(delta: float, sees_player: bool) -> Vector3:
	if not is_active():
		return Vector3.ZERO
	if actor.is_dead or not ai.is_arena_active() or tactics.cover.is_active():
		reset()
		return Vector3.ZERO
	if not tactics.can_use_attack_positions or actor.weapon == null or ai.combat_type != ai.CombatType.RANGED:
		_finish(sees_player)
		return Vector3.ZERO
	if phase == Phase.FIND:
		_find_position(sees_player)
		return Vector3.ZERO
	_recheck -= delta
	if _recheck <= 0.0:
		_recheck = 0.25
		if not _usable(destination):
			_finish(sees_player)
			return Vector3.ZERO
	if phase == Phase.HOLD:
		if not sees_player or not _usable(actor.global_position):
			_finish(sees_player)
		return Vector3.ZERO
	_remaining -= delta
	if _remaining <= 0.0:
		_finish(sees_player)
		return Vector3.ZERO
	var distance: float = ai._horizontal_distance(destination)
	if distance <= 0.12:
		# 不能提前停在墙后；实际脚下也必须合格才算完成占位。
		if _usable(actor.global_position):
			if not sees_player:
				_finish(false)
				return Vector3.ZERO
			phase = Phase.HOLD
			ai.state = ai.State.HOLD_POSITION
			actor.agent.target_position = actor.global_position
			if selection.debug_cover_selection:
				print("[AI][攻击占位] 到位，保持射击位置 ", actor.global_position)
			return Vector3.ZERO
		if distance <= 0.02:
			_finish(sees_player)
			return Vector3.ZERO
	# 来弹／受击可能更新普通导航目标；未进入躲藏时继续当前攻击目的地。
	if actor.agent.target_position.distance_to(destination) > 0.01:
		actor.agent.target_position = destination
	var next: Vector3 = actor.agent.get_next_path_position()
	var finishing: bool = distance <= 0.7 and _final_segment_clear()
	if finishing:
		next = destination
	elif actor.agent.is_navigation_finished():
		_finish(sees_player)
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
		_finish(sees_player)
		return Vector3.ZERO
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return direction.normalized() * minf(1.0, distance / maxf(0.001, actor.move_speed * delta))


func _find_position(sees_player: bool) -> void:
	# 与调试显示独立。每帧最多64点／约2.5毫秒；整轮基于触发时的目击位置。
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
	if is_inf(_best_length) or not _usable(destination):
		_finish(sees_player)
		return
	phase = Phase.MOVE
	ai.state = ai.State.REPOSITION
	_remaining = _best_length / maxf(0.1, actor.move_speed) + 3.0
	actor.agent.target_position = destination
	if selection.debug_cover_selection:
		print("[AI][攻击占位] 前往 ", active_cover.name, " 位置=", destination)


func _usable(point: Vector3) -> bool:
	if not is_instance_valid(active_cover):
		return false
	if not _within_sight_range(point, ai.last_seen_position):
		return false
	var target: Vector3 = ai.last_seen_position + Vector3.UP * 0.8
	return selection.assess_attack_point(point, active_cover, target, target).usable


# 射程够但感知距离不够的点，到位仍不能发现／攻击目标，不作为主动占位目的地。
func _within_sight_range(point: Vector3, known_position: Vector3) -> bool:
	return point.distance_to(known_position) <= maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius)


func _final_segment_clear() -> bool:
	var count := maxi(1, ceili(ai._horizontal_distance(destination) / 0.1))
	for index in range(1, count + 1):
		if not ai.is_position_free(actor.global_position.lerp(destination, float(index) / count)):
			return false
	return true


func _finish(sees_player: bool) -> void:
	reset()
	tactics.ranged_has_destination = false
	tactics.ranged_repath_timer = 0.0
	actor.agent.target_position = actor.global_position
	if sees_player:
		ai.state = ai.State.REPOSITION
	else:
		ai.last_known_position = ai.last_seen_position
		ai.search.begin_tracking_or_search(true)
	if selection.debug_cover_selection:
		print("[AI][攻击占位] 结束，回到交战／追踪流程")


func state_label() -> String:
	return ["", "查找墙角攻击位置", "前往墙角攻击位置", "墙角占位射击"][phase]
