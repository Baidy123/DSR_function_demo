extends "res://scripts/enemy/actions/enemy_cover_action.gd"

const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")

var _advanced_cover: WeakRef
var _advanced_target := Vector3.INF
var _advance_until := 0.0
var _advance_generation := -1
var _entry_position := Vector3.INF
var _planned_exit := Vector3.INF
var _charge_remaining := 0.0
var _low_hide_remaining := -1.0

func evaluation_channel() -> StringName:
	return &"melee_cover_geometry"

func evaluation_points() -> Array:
	if not _has_recent_target(): return []
	var target: Vector3 = context.last_known_position
	var minimum := maxf(0.1, float(_setting(&"cover_minimum_progress", 0.6)))
	var distance: float = context._horizontal_distance(target)
	var points: Array = super.evaluation_points().filter(func(point): return distance - context._horizontal_distance_between(point.hide, target) >= minimum or context._horizontal_distance(point.hide) <= 0.6)
	points.sort_custom(func(a, b): return actor.global_position.distance_squared_to(a.hide) < actor.global_position.distance_squared_to(b.hide))
	return points

func evaluation_priority_count() -> int:
	# 首次扫描先准备一个前进候选，避免基础躲藏已能选而升级仍在扫后方无关点。
	# 只分配原预算内的计算顺序；仍与所有动作按原 Utility 比较。
	return 1

func evaluate_point(point: Variant) -> Dictionary:
	if not _has_recent_target() or not _valid_cover(point): return {}
	var incoming: PackedVector3Array = context.routes.planning_path(actor.global_position, point.hide)
	var best := _choose_exit(_exit_options(point, incoming, actor.global_position))
	if best.is_empty(): return {}
	var destination: Dictionary = point.duplicate()
	destination.exit = best.position
	var candidate := _advance_candidate(destination, false)
	if candidate.is_empty(): return {}
	var outcome: Dictionary = candidate.outcome
	return {"destination": candidate.destination, "cost": context.spatial.score(outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss)}

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	if _charge_remaining > 0.0:
		var charge := _charge_candidate(plan.destination, _charge_remaining, visible)
		if not charge.is_empty(): candidates.append(charge)
		return candidates
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
	return continuing and _running and transfer.timer > 0.0 and (transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH] or (_is_low_cover(transfer.active_cover_body) and transfer.phase == transfer.Phase.HIDE))

func _advance_candidate(destination: Dictionary, continuing: bool) -> Dictionary:
	if not _has_recent_target(continuing) or actor.move_speed <= 0.0 or not _valid_cover(destination): return {}
	if not continuing and _recently_advanced(destination.body): return {}
	if continuing and transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH]:
		return _reacquire_candidate(destination)
	var target: Vector3 = context.last_known_position
	var progress: float = context._horizontal_distance(target) - context._horizontal_distance_between(destination.hide, target)
	var minimum := maxf(0.1, float(_setting(&"cover_minimum_progress", 0.6)))
	var low := _is_low_cover(destination.body)
	var sheltered_start: bool = context._horizontal_distance(destination.hide) <= 0.6 and selection._center_hidden_by_cover(actor.global_position, actor.get_posture_eye_position(false, target) if low else target + Vector3.UP * 0.8, destination.body, low)
	if not continuing and progress < minimum and not sheltered_start: return {}
	var path: PackedVector3Array = context.routes.planning_path(actor.global_position, destination.hide)
	var exit_point: Vector3 = _planned_exit if continuing else destination.get("exit", Vector3.INF)
	if not exit_point.is_finite(): return {}
	# 可以从已到达的掩体继续进攻；仍要求出口能推进，不重新跑回原地躲藏。
	if not continuing and not (low and sheltered_start) and progress < minimum and context._horizontal_distance(target) - context._horizontal_distance_between(exit_point, target) < minimum: return {}
	var assessment := _exit_assessment(destination, exit_point, path)
	if assessment.is_empty(): return {}
	var candidate := option(destination, 0.0, 0.0, 0.0, &"advance")
	candidate.outcome = assessment.outcome
	candidate.conceals = true
	return candidate

func _recently_advanced(body: Object) -> bool:
	return _advanced_cover != null and _advanced_cover.get_ref() == body and _advance_generation == context.memory_generation and context.evidence_elapsed_seconds < _advance_until and context._horizontal_distance_between(context.last_known_position, _advanced_target) < maxf(0.1, float(_setting(&"cover_minimum_progress", 0.6)))

func _reacquire_candidate(destination: Dictionary) -> Dictionary:
	if context.sees_player and (not _is_low_cover(destination.body) or actor.body_motion.amount <= 0.0001):
		return _charge_candidate(destination, _charge_seconds(), true)
	var point: Vector3 = transfer.peek_position
	if context.is_utility_destination_blocked(point) or not context.is_position_free(point): return {}
	var path: PackedVector3Array = context.routes.planning_path(actor.global_position, point)
	if path.is_empty() or not selection._peek_has_los(point, transfer.look_position): return {}
	var route: Dictionary = context.spatial.assess_route(context, path, transfer.look_position, transfer.movement_multiplier() if transfer.phase == transfer.Phase.PEEK_OUT else _exit_speed(), 0.0)
	var horizon: float = context.utility_horizon_seconds
	var exposed: float = route.exposure + context._reload_exposure(point, transfer.look_position) * maxf(0.0, horizon - route.seconds)
	var information: float = minf(horizon, route.seconds + (transfer.timer if transfer.phase == transfer.Phase.WATCH else 0.0))
	if _is_low_cover(destination.body): information = minf(horizon, information + actor.posture_seconds * actor.body_motion.amount)
	# 保留同一推进方案的标识，只按实际剩余的绕出／观察路段重新估计。
	var candidate := option(destination, horizon, Approach.opportunity_exposure(context, exposed), information, &"advance")
	candidate.conceals = true
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	return _has_recent_target() and not _advance_candidate(candidate.destination, false).is_empty() and super.validate(candidate, visible)

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	_charge_remaining = 0.0
	_low_hide_remaining = -1.0
	_planned_exit = candidate.destination.get("exit", Vector3.INF)
	_entry_position = Vector3.INF if selection._center_hidden_by_cover(actor.global_position, transfer.threat_origin, transfer.active_cover_body, transfer.crouch_hide) else actor.global_position
	context.state = context.State.APPROACH
	return true

func valid(visible: bool) -> bool:
	if _charge_remaining > 0.0:
		return _running and not _charge_candidate(plan.destination, _charge_remaining, visible).is_empty()
	return _has_recent_target(true) and is_instance_valid(transfer.active_cover_body) and super.valid(visible)

func tick(delta: float, visible: bool) -> Dictionary:
	if _charge_remaining > 0.0: return _tick_charge(delta, visible)
	if visible and transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH]:
		if not _is_low_cover(transfer.active_cover_body): return _start_charge(delta, visible)
		# 先完成真实站姿，再沿用原掩体升级的有限奔跑；仍允许共同决策接管。
		if actor.body_motion.amount <= 0.0001: return _start_charge(delta, visible)
	if transfer.phase == transfer.Phase.RUN_TO_COVER and is_instance_valid(transfer.active_cover_body) and not selection._center_hidden_by_cover(actor.global_position, transfer.threat_origin, transfer.active_cover_body, transfer.crouch_hide):
		_entry_position = actor.global_position
	var output := super.tick(delta, visible)
	# 主动走入遮挡不代表丢失接敌意图；同一段推进先绕出恢复观察。
	if transfer.phase == transfer.Phase.HIDE:
		if _is_low_cover(transfer.active_cover_body): return _tick_low_hide(delta)
		# 到位后记住已推进的掩体，避免刚绕出又选回同一墙后的相邻落点。
		_advanced_cover = weakref(transfer.active_cover_body)
		_advanced_target = context.last_known_position
		_advance_until = context.evidence_elapsed_seconds + maxf(0.0, float(_setting(&"cover_memory_seconds", 5.0)))
		_advance_generation = context.memory_generation
		if visible: return _start_charge(delta, visible)
		_running = _start_reacquire()
		output.running = _running
	return output

func _start_reacquire() -> bool:
	var destination := {"body": transfer.active_cover_body, "hide": transfer.hide_position}
	var best := _choose_exit(_exit_options(destination, PackedVector3Array([actor.global_position]), _entry_position))
	if best.is_empty(): return false
	_planned_exit = best.position
	destination.position = best.position
	if _is_low_cover(destination.body):
		destination.crouch = true
		destination.stand_peek = true
	transfer.start_utility_peek(destination, context.last_known_position, _exit_speed())
	context.invalidate_utility()
	return true

func _is_low_cover(body: Object) -> bool:
	return is_instance_valid(body) and body.is_low_cover()

func _low_hide_seconds() -> float:
	return maxf(0.0, float(context.setting(&"cover", &"low_cover_hide_seconds", 0.6)))

func _tick_low_hide(delta: float) -> Dictionary:
	if _low_hide_remaining < 0.0:
		_low_hide_remaining = _low_hide_seconds()
		# 只在首次到位时设置；姿态被动态障碍阻塞也不能不断续期。
		transfer.timer = _low_hide_remaining + maxf(1.0, actor.posture_seconds * 3.0)
	transfer.timer = maxf(0.0, transfer.timer - maxf(0.0, delta))
	if transfer.timer <= 0.0: return _finish_low_advance()
	if actor.is_crouching(): _low_hide_remaining = maxf(0.0, _low_hide_remaining - maxf(0.0, delta))
	if actor.is_crouching() and _low_hide_remaining <= 0.0:
		_advanced_cover = weakref(transfer.active_cover_body)
		_advanced_target = context.last_known_position
		_advance_until = context.evidence_elapsed_seconds + maxf(0.0, float(_setting(&"cover_memory_seconds", 5.0)))
		_advance_generation = context.memory_generation
		_running = _start_reacquire()
	var output := motion(Vector3.ZERO)
	output.crouch = transfer.phase == transfer.Phase.HIDE
	return output

func _finish_low_advance() -> Dictionary:
	_running = false
	transfer.reset()
	context.invalidate_utility()
	return motion(Vector3.ZERO)

func _exit_speed() -> float:
	return maxf(0.1, float(_setting(&"cover_exit_speed_multiplier", 2.0)))

func _charge_seconds() -> float:
	return maxf(0.0, float(_setting(&"cover_charge_seconds", 2.0)))

## 只评估当前掩体已有出口；进掩体前的评估由原空间预算调度。
## 不读隐藏玩家坐标，不写导航、入口记录或移动计时。
func _exit_options(destination: Dictionary, incoming: PackedVector3Array, entry: Vector3) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_instance_valid(destination.get("body")) or incoming.is_empty(): return result
	if _is_low_cover(destination.body):
		var standing := _exit_assessment(destination, destination.hide, incoming)
		if not standing.is_empty(): result.append(standing)
		return result
	var points: Array[Vector3] = []
	var nearest_face := INF
	for sample in destination.body.get_candidates(context.last_known_position + Vector3.UP * 0.8, destination.hide):
		var distance: float = context._horizontal_distance_between(sample.hide, destination.hide)
		if distance < nearest_face:
			nearest_face = distance
			points.assign(sample.peeks)
	var entrance := Vector3.INF
	for point in points:
		if entry.is_finite() and (not entrance.is_finite() or entry.distance_squared_to(point) < entry.distance_squared_to(entrance)):
			entrance = point
	for point in points:
		var assessment := _exit_assessment(destination, point, incoming)
		if assessment.is_empty(): continue
		var center: Vector3 = destination.body.get_node("CollisionShape3D").global_position
		var toward_exit: Vector3 = point - center
		var toward_entry: Vector3 = entrance - center if entrance.is_finite() else Vector3.ZERO
		toward_exit.y = 0.0
		toward_entry.y = 0.0
		assessment.opposite = entrance.is_finite() and toward_exit.normalized().dot(toward_entry.normalized()) < -0.5
		result.append(assessment)
	return result

func _exit_assessment(destination: Dictionary, point: Vector3, incoming: PackedVector3Array) -> Dictionary:
	if incoming.is_empty() or context.is_utility_destination_blocked(point) or not context.is_position_free(point) or not selection._peek_has_los(point, context.last_known_position): return {}
	if context.utility_rejected_attack_points.any(func(previous): return previous.distance_to(point) < 0.25): return {}
	var outgoing: PackedVector3Array = selection._path_to(incoming[incoming.size() - 1], point)
	if outgoing.is_empty(): return {}
	var contact: PackedVector3Array = Approach.contact_path(context, point)
	var low := _is_low_cover(destination.body)
	if low and contact.is_empty(): return {}
	var path := incoming.duplicate()
	path.append_array(outgoing)
	path.append_array(contact)
	var speed: float = maxf(0.01, actor.move_speed)
	var entering: float = selection._path_length_from_path(incoming) / (speed * maxf(0.1, transfer.run_speed_multiplier))
	var emerging: float = selection._path_length_from_path(outgoing) / (speed * _exit_speed())
	var remaining: float = selection._path_length_from_path(contact)
	var fast_distance := minf(remaining, speed * _exit_speed() * _charge_seconds())
	var seconds := entering + emerging + fast_distance / (speed * _exit_speed()) + (remaining - fast_distance) / speed
	# 分段速度决定到达时间；与原突进相同，以等效速度近似整条路径的暴露。
	var multiplier: float = selection._path_length_from_path(path) / (speed * maxf(0.01, seconds))
	var route: Dictionary = {} if low else context.spatial.assess_route(context, path, context.last_known_position, multiplier, 0.0)
	var horizon: float = context.utility_horizon_seconds
	var posture_exposure := 0.0
	if low:
		# 计入真实蹲稳、起身，以及本动作原有的有限奔跑；不预支独立突进。
		var entry_route: Dictionary = context.spatial.assess_route(context, incoming, context.last_known_position, transfer.run_speed_multiplier, 0.0)
		entering = entry_route.seconds
		emerging = _low_hide_seconds() + actor.posture_seconds * 2.0
		var available: float = maxf(0.0, horizon - entering)
		var upright: float = minf(available, actor.posture_seconds * 2.0)
		posture_exposure = context._reload_exposure(point, context.last_known_position) * upright
		posture_exposure += context._reload_exposure(point, context.last_known_position, -1.0, true) * minf(_low_hide_seconds(), maxf(0.0, available - upright))
		var contact_seconds: float = fast_distance / (speed * _exit_speed()) + (remaining - fast_distance) / speed
		var contact_multiplier: float = remaining / (speed * contact_seconds) if contact_seconds > 0.0 else 1.0
		route = context.spatial.assess_route(context, contact, context.last_known_position, contact_multiplier, 0.0, false, entering + emerging, point).duplicate()
		route.exposure += entry_route.exposure
		seconds = route.seconds
	var ready := horizon
	if not contact.is_empty() and actor.weapon != null and actor.weapon.melee_enabled and actor.can_equip_weapon(actor.weapon):
		ready = maxf(seconds, actor.melee_cooldown) + maxf(0.0, actor.weapon.melee_windup_seconds)
	var endpoint: Vector3 = path[path.size() - 1]
	var exposed: float = route.exposure + posture_exposure + context._reload_exposure(endpoint, context.last_known_position) * maxf(0.0, horizon - seconds)
	var outcome := {"unavailable_seconds": minf(horizon, ready), "exposed_seconds": Approach.opportunity_exposure(context, exposed), "information_loss": minf(horizon, entering + emerging)}
	return {"position": point, "outcome": outcome, "seconds": seconds, "observe_seconds": entering + emerging, "contact": not contact.is_empty(),
		"cost": context.spatial.score(outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss)}

func _choose_exit(options: Array[Dictionary]) -> Dictionary:
	var best: Dictionary = {}
	var has_contact: bool = options.any(func(candidate): return candidate.contact)
	for candidate in options:
		if has_contact and not candidate.contact: continue
		if best.is_empty() or candidate.cost < best.cost or (is_equal_approx(candidate.cost, best.cost) and candidate.seconds < best.seconds):
			best = candidate
	if best.is_empty(): return best
	var tolerance := maxf(0.0, float(_setting(&"cover_exit_side_tolerance_seconds", 0.25)))
	var cost_limit: float = best.cost + tolerance * maxf(0.0, context.utility_fire_weight)
	var time_limit: float = best.seconds + tolerance
	for candidate in options:
		if has_contact and not candidate.contact: continue
		if candidate.get("opposite", false) and candidate.cost <= cost_limit and candidate.seconds <= time_limit:
			if not best.get("opposite", false) or candidate.cost < best.cost or (is_equal_approx(candidate.cost, best.cost) and candidate.seconds < best.seconds): best = candidate
	return best

func _charge_candidate(destination: Dictionary, remaining: float, visible: bool) -> Dictionary:
	if not _running or not is_enabled() or not visible or remaining <= 0.0 or not actor.can_move() or context.melee.can_request(visible): return {}
	var path := _charge_path(destination)
	if path.is_empty(): return {}
	var candidate := option(destination, 0.0, 0.0, 0.0, &"advance")
	candidate.outcome = Approach.contact_outcome(context, path, _exit_speed(), remaining)
	candidate.conceals = false
	# 这段已离开入掩体路线，不再向旧 hide 扩展翻越；接敌／突进的现有
	# route 候选仍参与同一次共同评分，并可随时接管有限奔跑。
	if _is_low_cover(destination.body): candidate.route_target = Vector3.INF
	return candidate

func _charge_path(destination: Dictionary) -> PackedVector3Array:
	var path: PackedVector3Array = Approach.contact_path(context)
	if path.is_empty() or not _is_low_cover(destination.body): return path
	# 接敌规划可能拼接一次翻越；本段只执行普通导航，必须真实可步行。
	# 校验实际接敌落点，保留玩家在导航外时已有的近侧停靠回退。
	var walk: PackedVector3Array = selection._path_to(actor.global_position, path[path.size() - 1]).duplicate()
	for index in walk.size(): walk[index].y = actor.global_position.y
	return walk

func _start_charge(delta: float, visible: bool) -> Dictionary:
	transfer.reset()
	_charge_remaining = _charge_seconds()
	context.invalidate_utility()
	return _tick_charge(delta, visible)

func _tick_charge(delta: float, visible: bool) -> Dictionary:
	_charge_remaining = maxf(0.0, _charge_remaining - maxf(0.0, delta))
	if _charge_candidate(plan.destination, _charge_remaining, visible).is_empty():
		_running = false
		return motion(Vector3.ZERO)
	var path := _charge_path(plan.destination)
	agent.target_position = path[path.size() - 1]
	var next: Vector3 = agent.get_next_path_position()
	if agent.is_navigation_finished():
		_running = false
		return motion(Vector3.ZERO)
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return motion(direction.normalized(), _exit_speed(), direction)

func reset() -> void:
	super.reset()
	_entry_position = Vector3.INF
	_planned_exit = Vector3.INF
	_charge_remaining = 0.0
	_low_hide_remaining = -1.0

func can_interrupt(next: Dictionary, visible: bool) -> bool:
	if _charge_remaining > 0.0: return true
	var outcome: Dictionary = next.get("outcome", {})
	# 换弹证据只为能更早接敌的方案放行，不能单凭机会让搜索打断有效推进。
	var exploits_reload: bool = context.observed_reload_window() > 0.0 and (visible or float(outcome.get("unavailable_seconds", context.utility_horizon_seconds)) < context.utility_horizon_seconds)
	if _is_low_cover(transfer.active_cover_body) and (transfer.phase == transfer.Phase.HIDE or (transfer.phase == transfer.Phase.PEEK_OUT and actor.body_motion.amount > 0.0001)):
		# 选中前已经计入的换弹机会不能每次重评都跳过短姿态段。
		# 真实伤害、紧急方案、当下可执行的近战仍可立即接管。
		return next.get("urgent", false) or _transfer_reconsider or context.melee.can_request(visible)
	if transfer.phase in [transfer.Phase.PEEK_OUT, transfer.Phase.WATCH]:
		# 当前绕出／观察受原路段时限约束；新线索仍可触发重评。
		return visible or next.get("urgent", false) or _transfer_reconsider or exploits_reload
	return exploits_reload or context.melee.can_request(visible) or super.can_interrupt(next, visible)

func hold_released() -> bool:
	return context.observed_reload_window() > 0.0 or context.melee.can_request(context.sees_player)

func state_label() -> String:
	if _is_low_cover(transfer.active_cover_body):
		if transfer.phase == transfer.Phase.HIDE: return "半身掩体后蹲藏接敌"
		if transfer.phase == transfer.Phase.PEEK_OUT: return "半身掩体后起身观察"
	if _charge_remaining > 0.0: return "出掩体奔跑接敌"
	if transfer.phase == transfer.Phase.PEEK_OUT: return "绕出掩体接敌"
	if transfer.phase == transfer.Phase.WATCH: return "观察接敌方向"
	return "绕行接近掩体" if transfer.cover_detour_active else "掩体接近"
