extends "res://scripts/enemy/actions/enemy_cover_action.gd"

const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")

var _advanced_cover: WeakRef
var _advanced_target := Vector3.INF
var _advance_until := 0.0
var _advance_generation := -1

func evaluation_channel() -> StringName:
	return &"melee_cover_geometry"

func evaluate_point(point: Variant) -> Dictionary:
	var candidate := _advance_candidate(point, false)
	if candidate.is_empty(): return {}
	var outcome: Dictionary = candidate.outcome
	return {"destination": candidate.destination, "cost": context.spatial.score(outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss)}

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if not _has_recent_target(true) or context.melee.can_request(visible): return candidates
	for destination in transfer_candidates():
		var continuing: bool = _running and transfer.is_active() and destination.body == transfer.active_cover_body and destination.hide.is_equal_approx(transfer.hide_position)
		var candidate := _advance_candidate(destination, continuing)
		if not candidate.is_empty(): candidates.append(candidate)
	return candidates

func _has_recent_target(continuing: bool = false) -> bool:
	if not is_enabled() or not context.has_visual_memory or not context.is_alerted or context.noise_search_origin.is_finite(): return false
	if context.utility_unseen_seconds <= maxf(0.0, float(_setting(&"cover_memory_seconds", 5.0))): return true
	# 旧证据不能开始新推进；已开始的绕出／观察按移动组件的剩余时限完成。
	# 不刷新目击时间，不重选出口，也不延长原路线或观察计时。
	return continuing and _running and transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH] and transfer.timer > 0.0

func _advance_candidate(destination: Dictionary, continuing: bool) -> Dictionary:
	if not _has_recent_target(continuing) or actor.move_speed <= 0.0 or not _valid_cover(destination): return {}
	if not continuing and _recently_advanced(destination.body): return {}
	if continuing and transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH]:
		return _reacquire_candidate(destination)
	var target: Vector3 = context.last_known_position
	var progress: float = context._horizontal_distance(target) - context._horizontal_distance_between(destination.hide, target)
	if not continuing and progress < maxf(0.1, float(_setting(&"cover_minimum_progress", 0.6))): return {}
	var path: PackedVector3Array = selection._path_to(actor.global_position, destination.hide)
	var route: Dictionary = context.spatial.assess_cover_route(path, target, transfer.run_speed_multiplier, 0.0)
	var horizon: float = context.utility_horizon_seconds
	var exposed: float = route.exposure + context._reload_exposure(destination.hide, target) * maxf(0.0, horizon - route.seconds)
	var candidate := option(destination, horizon, Approach.opportunity_exposure(context, exposed), horizon if not context.sees_player else maxf(0.0, horizon - route.seconds), &"advance")
	candidate.conceals = true
	return candidate

func _recently_advanced(body: Object) -> bool:
	return _advanced_cover != null and _advanced_cover.get_ref() == body and _advance_generation == context.memory_generation and context.evidence_elapsed_seconds < _advance_until and context._horizontal_distance_between(context.last_known_position, _advanced_target) < maxf(0.1, float(_setting(&"cover_minimum_progress", 0.6)))

func _reacquire_candidate(destination: Dictionary) -> Dictionary:
	var point: Vector3 = transfer.peek_position
	if context.is_utility_destination_blocked(point) or not context.is_position_free(point): return {}
	var path: PackedVector3Array = selection._path_to(actor.global_position, point)
	if path.is_empty() or not selection._peek_has_los(point, transfer.look_position): return {}
	var route: Dictionary = context.spatial.assess_route(context, path, transfer.look_position, transfer.peek_speed_multiplier, 0.0)
	var horizon: float = context.utility_horizon_seconds
	var exposed: float = route.exposure + context._reload_exposure(point, transfer.look_position) * maxf(0.0, horizon - route.seconds)
	var information: float = minf(horizon, route.seconds + (transfer.timer if transfer.phase == transfer.Phase.WATCH else 0.0))
	# 保留同一推进方案的标识，只按实际剩余的绕出／观察路段重新估计。
	var candidate := option(destination, horizon, Approach.opportunity_exposure(context, exposed), information, &"advance")
	candidate.conceals = true
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	return _has_recent_target() and not _advance_candidate(candidate.destination, false).is_empty() and super.validate(candidate, visible)

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	context.state = context.State.APPROACH
	return true

func valid(visible: bool) -> bool:
	return _has_recent_target(true) and is_instance_valid(transfer.active_cover_body) and super.valid(visible)

func tick(delta: float, visible: bool) -> Dictionary:
	var output := super.tick(delta, visible)
	# 主动走入遮挡不代表丢失接敌意图；同一段推进先绕出恢复观察。
	if transfer.phase == transfer.Phase.HIDE:
		# 到位后记住已推进的掩体，避免刚绕出又选回同一墙后的相邻落点。
		_advanced_cover = weakref(transfer.active_cover_body)
		_advanced_target = context.last_known_position
		_advance_until = context.evidence_elapsed_seconds + maxf(0.0, float(_setting(&"cover_memory_seconds", 5.0)))
		_advance_generation = context.memory_generation
		_running = not visible and _start_reacquire()
		output.running = _running
	return output

func _start_reacquire() -> bool:
	var options: Array[Dictionary] = []
	_assess_peek(context.last_known_position, context.utility_horizon_seconds, false, options)
	var best: Dictionary = {}
	var cost := INF
	for candidate in options:
		var outcome: Dictionary = candidate.outcome
		var next_cost: float = context.spatial.score(outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss)
		if next_cost < cost:
			best = candidate
			cost = next_cost
	if best.is_empty(): return false
	transfer.start_utility_peek(best.destination, context.last_known_position)
	context.invalidate_utility()
	return true

func can_interrupt(next: Dictionary, visible: bool) -> bool:
	var outcome: Dictionary = next.get("outcome", {})
	# 换弹证据只为能更早接敌的方案放行，不能单凭机会让搜索打断有效推进。
	var exploits_reload: bool = context.observed_reload_window() > 0.0 and (visible or float(outcome.get("unavailable_seconds", context.utility_horizon_seconds)) < context.utility_horizon_seconds)
	if transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH]:
		# 当前绕出／观察受原路段时限约束；新线索仍可触发重评。
		return visible or next.get("urgent", false) or _transfer_reconsider or exploits_reload
	return exploits_reload or context.melee.can_request(visible) or super.can_interrupt(next, visible)

func hold_released() -> bool:
	return context.observed_reload_window() > 0.0 or context.melee.can_request(context.sees_player)

func state_label() -> String:
	if transfer.phase == transfer.Phase.PEEK_OUT: return "绕出掩体接敌"
	if transfer.phase == transfer.Phase.WATCH: return "观察接敌方向"
	return "绕行接近掩体" if transfer.cover_detour_active else "掩体接近"
