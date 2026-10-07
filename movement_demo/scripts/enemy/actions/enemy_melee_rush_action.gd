extends "res://scripts/enemy/actions/enemy_melee_action.gd"

var _burst_remaining := 0.0
var _ready_at := 0.0
var _memory_generation := -1

func cooldown_remaining() -> float:
	if context == null or context.memory_generation != _memory_generation: return 0.0
	return maxf(0.0, _ready_at - context.evidence_elapsed_seconds)

func collect_candidates(visible: bool) -> Array[Dictionary]:
	if not is_enabled() or not actor.can_move() or actor.melee_active or actor.move_speed <= 0.0 or actor.weapon == null or not actor.weapon.melee_enabled: return []
	if not visible and context.observed_reload_window() <= 0.0: return []
	if _running:
		if _burst_remaining <= 0.0: return []
	elif cooldown_remaining() > 0.0:
		return []
	var distance: float = context._horizontal_distance(context.last_known_position)
	if distance <= Approach.stopping_distance(context) + 0.1: return []
	if not _running and context.observed_reload_window() <= 0.0 and distance > float(_setting(&"rush_distance", 3.5)): return []
	var path: PackedVector3Array = Approach.contact_path(context)
	if path.is_empty(): return []
	var multiplier := maxf(1.0, float(_setting(&"rush_speed_multiplier", 2.5)))
	var duration := maxf(0.0, float(_setting(&"rush_seconds", 1.0)))
	var length: float = selection._path_length_from_path(path)
	if not _running and length > actor.move_speed * multiplier * duration: return []
	var candidate := option({}, 0.0, 0.0, 0.0, &"burst")
	candidate.outcome = Approach.contact_outcome(context, path, multiplier, _burst_remaining if _running else duration)
	return [candidate]

func validate(_candidate: Dictionary, visible: bool) -> bool:
	return not collect_candidates(visible).is_empty()

func valid(visible: bool) -> bool:
	return _running and _burst_remaining > 0.0 and is_enabled() and (visible or context.observed_reload_window() > 0.0)

func begin(candidate: Dictionary, visible: bool) -> bool:
	if cooldown_remaining() > 0.0: return false
	super.begin(candidate, visible)
	_burst_remaining = maxf(0.0, float(_setting(&"rush_seconds", 1.0)))
	_memory_generation = context.memory_generation
	_ready_at = context.evidence_elapsed_seconds + _burst_remaining + maxf(0.0, float(_setting(&"rush_cooldown_seconds", 4.0)))
	return true

func tick(delta: float, visible: bool) -> Dictionary:
	_burst_remaining = maxf(0.0, _burst_remaining - maxf(0.0, delta))
	if not valid(visible) or context._horizontal_distance(context.last_known_position) <= Approach.stopping_distance(context) + 0.1:
		_running = false
		return motion(Vector3.ZERO)
	if agent.target_position.distance_to(context.last_known_position) > 0.25:
		agent.target_position = context.last_known_position
	var next: Vector3 = agent.get_next_path_position()
	if agent.is_navigation_finished():
		_running = false
		return motion(Vector3.ZERO)
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return motion(direction.normalized(), maxf(1.0, float(_setting(&"rush_speed_multiplier", 2.5))), direction)

func reset() -> void:
	_burst_remaining = 0.0
	# 截止时间属于本动作，取消不返还；区域复位由记忆代际使旧截止时间失效。

func state_label() -> String:
	return "抓住换弹突进" if context.observed_reload_window() > 0.0 else "短程突进"
