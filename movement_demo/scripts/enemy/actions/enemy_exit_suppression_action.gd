extends "res://scripts/enemy/actions/enemy_suppression_action.gd"

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
var _inference_confidence: float = 0.0
var _exit_geometry: Dictionary = {}
var _exit_memory: Vector3


func reset() -> void:
	super.reset()
	target_cover = null
	first_exit.clear()
	second_exit.clear()
	_next_exit = 0
	_shots_remaining = 0
	_inference_confidence = 0.0
	_exit_geometry.clear()


func _prepare_targets(center: Vector3) -> bool:
	reset()
	_exit_memory = center - Vector3.UP * 0.8
	_exit_geometry = context.cover_selection.suppression_geometry(_exit_memory)
	if _exit_geometry.is_empty(): return false
	target_cover = _exit_geometry.body
	_inference_confidence = _exit_geometry.confidence
	first_exit.assign(_exit_geometry.first)
	second_exit.assign(_exit_geometry.second)
	return not first_exit.is_empty() or not second_exit.is_empty()


func _prepare_cover_exits() -> void:
	_exit_geometry = context.cover_selection._suppression_cover_geometry(target_cover, _exit_memory)
	first_exit.assign(_exit_geometry.get("first", []))
	second_exit.assign(_exit_geometry.get("second", []))


func information_retention() -> float:
	# 封住越多可信出口，等待时目标可能移动的范围越小；并非固定战术优先级。
	var coverage := (float(not first_exit.is_empty()) + float(not second_exit.is_empty())) * 0.5
	var freshness := _freshness()
	var balance: float = _exit_geometry.get("balance", 0.0)
	var passage_fraction := float(_exit_geometry.get("open_sides", 0)) * 0.5
	return 0.65 * _inference_confidence * coverage * freshness * balance * passage_fraction


func _can_reach_target(target: Vector3) -> bool:
	# 出口中心方向必须可见，散布擦到目标掩体不否决整个出口。
	return super._can_reach_target(target) and context.cover_selection.has_clear_line(actor.get_shot_origin(), target)


func _targets_available() -> bool:
	if not is_instance_valid(target_cover):
		return false
	# 本轮只属于启动时确认的墙；新前景遮挡、叠墙或未知归属均结束，不能换压另一面墙。
	if context.cover_selection.confirmed_suppression_cover(_exit_memory) != target_cover:
		return false
	# 动态障碍可封住通道而不挡射线；每次执行同时复核身体通行和实际射界。
	_prepare_cover_exits()
	if first_exit.is_empty() and second_exit.is_empty():
		return false
	if aim_point in first_exit or aim_point in second_exit:
		return true
	_select_aim_point()
	return true


func utility_fire_fraction() -> float:
	# 至少一端有可射样本，实际射击始终分配到可用出口。
	return 1.0


func _select_aim_point() -> void:
	if first_exit.is_empty() and second_exit.is_empty():
		return
	if first_exit.is_empty():
		_next_exit = 1
	elif second_exit.is_empty():
		_next_exit = 0
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

func preference_credit() -> float:
	return 0.0
