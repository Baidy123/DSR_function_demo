extends "res://scripts/enemy/actions/enemy_melee_action.gd"

var _burst_remaining := 0.0
var _ready_at := 0.0
var _memory_generation := -1
var _command_burst_started := false

func command_roles() -> Array[StringName]:
	return [&"engage", &"flank"] if actor.weapon != null and actor.weapon.melee_enabled else []

func command_default_assignment() -> bool:
	return false

func command_site_offer(query: Dictionary, site: Dictionary) -> Dictionary:
	if query.body.get("firearms", true) or not _command_window(query.body, query.objective.position): return {}
	var offer := super.command_site_offer(query, site)
	if offer.is_empty() or offer.get("retry_detour", false): return offer
	var length: float = selection._path_length_from_path(offer.route)
	var speed: float = _setting(&"rush_speed_multiplier", 2.5)
	var seconds: float = length / maxf(0.1, query.body.move_speed * speed)
	var remaining: float = _burst_remaining if _command_burst_started else float(_setting(&"rush_seconds", 1.0))
	if length < 0.2 or seconds > remaining: return {}
	var saved: float = maxf(0.0, float(offer.travel_seconds) - seconds)
	offer.estimate = maxf(0.0, float(offer.estimate) - saved * (1.0 + float(offer.tactical.get("exposure", 0.0))))
	offer.travel_seconds = seconds
	offer.tactical.travel = seconds
	if _command_burst_started: offer.burst_until = context.evidence_elapsed_seconds + _burst_remaining
	return offer

func _command_window(body: Dictionary, target: Vector3) -> bool:
	if not body.get("visible", false) and body.get("observed_reload", 0.0) <= 0.0: return false
	if _command_burst_started:
		if _burst_remaining <= 0.0: return false
	elif cooldown_remaining() > 0.0: return false
	var distance: float = context._horizontal_distance_between(body.position, target)
	return distance > Approach.stopping_distance(context) + 0.1 and (body.get("observed_reload", 0.0) > 0.0 or distance <= float(_setting(&"rush_distance", 3.5)))

func validate_command_offer(query: Dictionary, offer: Dictionary) -> Dictionary:
	var result := super.validate_command_offer(query, offer)
	var target: Vector3 = context.last_known_position if query.body.get("visible", false) else offer.look_position
	result.valid = result.valid and _command_window(query.body, target)
	return result

func freeze_command_capability() -> Dictionary:
	var result := super.freeze_command_capability()
	var defaults := {&"rush_distance": 3.5, &"rush_speed_multiplier": 2.5, &"rush_seconds": 1.0, &"rush_cooldown_seconds": 4.0}
	for key in defaults:
		_battle_settings[key] = _setting(key, defaults[key])
	result.parameters = _battle_settings.duplicate(true)
	return result

func command_runtime_state() -> Dictionary:
	return {"ready": cooldown_remaining() <= 0.0, "active": _running and _command_burst_started and _burst_remaining > 0.0,
		"finished": _command_burst_started and _burst_remaining <= 0.0, "task_id": command.get("task_id", 0)}

func begin_command(task: Dictionary) -> bool:
	_command_burst_started = false
	_burst_remaining = 0.0
	if not super.begin_command(task): return false
	var until: float = task.get("burst_until", -INF)
	if until > context.evidence_elapsed_seconds and until <= _ready_at:
		_command_burst_started = true
		_burst_remaining = until - context.evidence_elapsed_seconds
	return true

func execute_command(delta: float, visible: bool) -> Dictionary:
	if _command_burst_started: _burst_remaining = maxf(0.0, _burst_remaining - maxf(0.0, delta))
	var output := super.execute_command(delta, visible)
	if not output.get("melee", {}).is_empty() or not visible and context.observed_reload_window() <= 0.0:
		_burst_remaining = 0.0
		return output
	if output.direction.is_zero_approx(): return output
	if not _command_burst_started:
		_command_burst_started = true
		if cooldown_remaining() > 0.0: return output
		_burst_remaining = maxf(0.0, float(_setting(&"rush_seconds", 1.0)))
		_memory_generation = context.memory_generation
		_ready_at = context.evidence_elapsed_seconds + _burst_remaining + maxf(0.0, float(_setting(&"rush_cooldown_seconds", 4.0)))
	if _burst_remaining > 0.0:
		output.multiplier = maxf(float(output.multiplier), float(_setting(&"rush_speed_multiplier", 2.5)))
		output.multiplier = minf(output.multiplier, context._horizontal_distance(output.stop_position) / maxf(0.001, actor.move_speed * delta))
	return output

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
	candidate.route_target = path[path.size() - 1]
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
	_command_burst_started = false
	# 截止时间属于本动作，取消不返还；区域复位由记忆代际使旧截止时间失效。

func state_label() -> String:
	return "抓住换弹突进" if context.observed_reload_window() > 0.0 else "短程突进"

func route_multiplier() -> float:
	return maxf(1.0, float(_setting(&"rush_speed_multiplier", 2.5)))

func route_tick(delta: float, visible: bool) -> Dictionary:
	_burst_remaining = maxf(0.0, _burst_remaining - delta)
	if not valid(visible): _running = false
	return motion(Vector3.ZERO, route_multiplier())
