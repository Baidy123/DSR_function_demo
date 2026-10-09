extends "res://scripts/enemy/actions/enemy_action.gd"

## Bounded fire for a personal disappearance, close threat or real support request.
var duration_min: float:
	get: return _setting(&"duration_min", 3.0)
	set(value): _set_setting(&"duration_min", value)
var duration_max: float:
	get: return _setting(&"duration_max", 5.0)
	set(value): _set_setting(&"duration_max", value)
var target_radius: float:
	get: return _setting(&"target_radius", 0.75)
	set(value): _set_setting(&"target_radius", value)

var active := false
var remaining := 0.0
var target_center := Vector3.INF
var aim_point := Vector3.INF
var _clear_targets: Array[Vector3] = []
var _evidence: Dictionary = {}
var _mode: StringName = &""
var _reason: StringName = &""
var _shots_remaining := 0
var _claim: Dictionary = {}
var _request_id := 0
var _spent_requests: Dictionary = {}
var _close_available_at := 0.0
var _generation := -1

func default_mode() -> StringName:
	return &"point"

func _current_mode() -> StringName:
	return default_mode() if _mode.is_empty() else _mode

func _sync_generation() -> void:
	if _generation == context.memory_generation: return
	_generation = context.memory_generation
	_spent_requests.clear()
	_close_available_at = 0.0

func _fresh_basis() -> Dictionary:
	_sync_generation()
	var personal: Dictionary = context.suppression_basis()
	if context.utility_suppression_pending and context.suppression_available(personal): return personal
	var shared: Dictionary = context.cooperation_target_evidence()
	return shared if shared.get("shared", false) and _evidence_live(shared) else personal

func _basis() -> Dictionary:
	return _evidence if active else _fresh_basis()

func _evidence_live(basis: Dictionary) -> bool:
	return not basis.is_empty() and basis.get("position", Vector3.INF).is_finite() and context.evidence_elapsed_seconds < float(basis.get("valid_until", -INF))

func _basis_aim(basis: Dictionary, diagnostic: bool = false) -> Vector3:
	if basis.has("aim_position"): return basis.aim_position
	# Old hand-written diagnostic fixtures may inspect geometry, but cannot start fire.
	return basis.get("position", Vector3.INF) + Vector3.UP * 0.8 if diagnostic else Vector3.INF

func _support_request(preferred: int = 0) -> Dictionary:
	if not context.cooperation_enabled(): return {}
	var snapshot: Dictionary = context.cooperation_snapshot()
	for item: Dictionary in snapshot.get("requests", []):
		var id: int = item.get("request_id", item.get("id", 0))
		if id == 0 or (preferred != 0 and id != preferred): continue
		if item.get("target_id", 0) != context.cooperation_target_id() or item.get("beneficiary_id", 0) == actor.get_instance_id(): continue
		if String(item.get("lane_id", "target")) != "target": continue
		if _spent_requests.has(id) and (not active or id != _request_id): continue
		var covered := 0.0
		for support: Dictionary in snapshot.get("supports", []):
			if support.get("owner_id", 0) != actor.get_instance_id() and String(support.get("lane_id", "target")) == "target":
				covered = maxf(covered, float(support.get("support_seconds", 0.0)))
		if minf(context.utility_horizon_seconds, float(item.get("remaining", 0.0))) > covered + 0.01: return item
	return {}

func _purpose(mode: StringName, basis: Dictionary, preferred: int = 0) -> Dictionary:
	if not _evidence_live(basis) or not _basis_aim(basis).is_finite(): return {}
	# A committed wave keeps its original reason and beneficiary. A different
	# opportunity may enter a new Utility decision only after this wave ends.
	if active:
		if _reason == &"personal_loss": return {"reason": &"personal_loss"} if mode == &"point" else {}
		if _reason == &"close": return {"reason": &"close"} if mode == &"visible" and context.fire.close_suppression_pressure() > 0.0 else {}
		if _reason == &"support" and _request_id != 0:
			var committed := _support_request(_request_id)
			return {"reason": &"support", "request": committed} if not committed.is_empty() else {}
		return {}
	if mode == &"point":
		if not basis.get("shared", false) and basis.get("source") == &"visual_loss" and context.utility_suppression_pending and context.suppression_available(basis):
			return {"reason": &"personal_loss"}
	elif mode == &"visible":
		if context.fire.close_suppression_pressure() > 0.0 and context.evidence_elapsed_seconds >= _close_available_at:
			return {"reason": &"close"}
	else: return {}
	var request := _support_request(preferred)
	return {"reason": &"support", "request": request} if not request.is_empty() else {}

func _point_reachable(target: Vector3, _full_line: bool = true) -> bool:
	var origin: Vector3 = actor.get_shot_origin()
	return target.is_finite() and actor.weapon != null and origin.distance_to(target) <= actor.weapon.fire_range and context.fire.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)) and context.cooperation_line_safe(origin, target)

func _preview(mode: StringName, basis: Dictionary, diagnostic: bool = false) -> Dictionary:
	if mode not in [&"point", &"visible"] or not _evidence_live(basis) or not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading: return {}
	var center: Vector3 = context.perception.visible_aim_position(context.sees_player) if mode == &"visible" else _basis_aim(basis, diagnostic)
	# The observed region itself must be reachable. A sample outside its blocking
	# wall is not permission to invent an exit lane or shoot beyond the obstacle.
	if not center.is_finite() or not _point_reachable(center): return {}
	var targets: Array[Vector3] = [center]
	if mode == &"point":
		for offset: Vector3 in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var point: Vector3 = center + offset * maxf(0.0, target_radius)
			if _point_reachable(point): targets.append(point)
	return {"targets": targets, "center": center}

func is_active() -> bool:
	return active

func utility_available() -> bool:
	return is_enabled() and not _preview(_current_mode(), _basis(), true).is_empty()

func information_retention() -> float:
	return 1.0 if _current_mode() == &"visible" and context.sees_player else 0.0

func utility_fire_fraction() -> float:
	return 1.0 if utility_available() else 0.0

func _support_prediction(mode: StringName, preview: Dictionary, duration: float, supporting: bool = false) -> Dictionary:
	var point: Vector3 = aim_point if active and mode == _current_mode() and mode == &"point" and aim_point.is_finite() else preview.targets[0]
	var desired: Vector3 = point - actor.get_shot_origin()
	var turning: float = 0.0 if desired.is_zero_approx() else maxf(0.0, actor.aim_direction.angle_to(desired) - actor.AIM_ACQUIRE_ANGLE) / maxf(0.01, deg_to_rad(actor.aim_turn_speed_degrees))
	var delay: float = maxf(turning, maxf(context.fire.shot_wait_seconds(), context.fire.fire_pause_remaining))
	if mode == &"visible":
		delay = maxf(delay, maxf(0.0, context.fire.fire_reaction_seconds - context.fire.fire_reaction_elapsed))
		delay += context.fire.estimated_steady_wait(true)
	var rounds: int = _shots_remaining if active else context.fire.burst_shots_remaining(supporting)
	var window: float = mini(rounds, actor.ammo.magazine_rounds) * context.fire.shot_interval_seconds()
	if actor.ammo.is_reloading: window = 0.0
	return {"support_seconds": minf(window, maxf(0.0, minf(context.utility_horizon_seconds, duration) - delay)), "estimated_start_seconds": delay}

func _cooperation(purpose: Dictionary) -> Dictionary:
	if purpose.get("reason") != &"support": return {}
	var request: Dictionary = purpose.request
	return {"target_id": context.cooperation_target_id(), "kind": &"support", "lane_id": &"target", "position": actor.global_position,
		"beneficiary_id": request.beneficiary_id, "request_id": request.get("request_id", request.get("id", 0)), "quality": 1.0}

func _slot_available(task: Dictionary) -> bool:
	if task.is_empty(): return true
	for claim: Dictionary in context.cooperation_snapshot(task.get("target_id", 0)).get("claims", []):
		if claim.get("owner_id", 0) != actor.get_instance_id() and claim.get("kind") == &"support" and String(claim.get("lane_id", "")) == "target": return false
	return true

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_enabled() or not actor.can_use_firearms() or context.is_executing_cover_plan(): return result
	_sync_generation()
	var mode: StringName = _current_mode() if active else &"visible" if visible else &"point"
	if (mode == &"visible") != visible: return result
	var basis: Dictionary = _basis() if active or not visible else context.cooperation_target_evidence()
	if _purpose(mode, basis, _request_id if active else 0).is_empty(): return result
	var candidate := preview_candidate(mode, basis)
	if not candidate.is_empty() and _slot_available(candidate.get("cooperation", {})): result.append(candidate)
	return result

## Diagnostic fallback never authorizes execution of a legacy foot-only fixture.
func preview_candidate(mode: StringName, basis: Dictionary = {}, duration: float = -1.0) -> Dictionary:
	if basis.is_empty(): basis = _basis()
	var preview := _preview(mode, basis, true)
	if preview.is_empty(): return {}
	if duration < 0.0: duration = remaining if active else maxf(0.1, duration_min)
	duration = minf(duration, maxf(0.0, float(basis.valid_until) - context.evidence_elapsed_seconds))
	var purpose := _purpose(mode, basis, _request_id if active else 0)
	var prediction := _support_prediction(mode, preview, duration, purpose.get("reason", &"") == &"support")
	var horizon: float = context.utility_horizon_seconds
	var available: float = float(prediction.support_seconds)
	var candidate := option({}, horizon - available, context.spatial._exposure(context, actor.global_position, context._known_reload_threat()) * horizon, 0.0 if mode == &"visible" else minf(horizon, duration), mode)
	candidate.suppression_evidence = basis.duplicate(true)
	candidate.target_id = context.cooperation_target_id()
	candidate.outcome.preference_credit = _point_preference(basis) if mode == &"point" else 0.0
	candidate.suppression_reason = purpose.get("reason", &"")
	var task: Dictionary = plan.get("cooperation", {}).duplicate(true) if active else _cooperation(purpose)
	if not task.is_empty():
		task.merge(prediction, true)
		candidate.cooperation = task
	if mode == &"visible": candidate.support_intent = true
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	if not is_enabled() or candidate.get("target_id", context.cooperation_target_id()) != context.cooperation_target_id(): return false
	var mode: StringName = candidate.get("plan", default_mode())
	var basis: Dictionary = candidate.get("suppression_evidence", _basis())
	if (mode == &"visible") != visible or _preview(mode, basis).is_empty(): return false
	var purpose := _purpose(mode, basis, int(candidate.get("cooperation", {}).get("request_id", 0)))
	return not purpose.is_empty() and purpose.get("reason") == candidate.get("suppression_reason", purpose.get("reason")) and _slot_available(candidate.get("cooperation", {}))

func begin(candidate: Dictionary, visible: bool) -> bool:
	if not validate(candidate, visible): return false
	var mode: StringName = candidate.get("plan", default_mode())
	var basis: Dictionary = candidate.get("suppression_evidence", _basis())
	if active:
		if mode != _current_mode() or basis != _evidence: return false
		if not _claim.is_empty() and not context.cooperation_update(_claim, {}): return false
		super.begin(candidate.duplicate(true), visible)
		return true
	var purpose := _purpose(mode, basis, int(candidate.get("cooperation", {}).get("request_id", 0)))
	var preview := _preview(mode, basis)
	var claim: Dictionary = {}
	var task: Dictionary = candidate.get("cooperation", {}).duplicate(true)
	if not task.is_empty():
		task.owner_action = action_id
		task.duration = minf(maxf(0.1, duration_max), float(basis.valid_until) - context.evidence_elapsed_seconds)
		claim = context.cooperation_claim(task)
		if claim.is_empty(): return false
	reset()
	_claim = claim
	_mode = mode
	_reason = purpose.reason
	_evidence = basis.duplicate(true)
	_request_id = int(task.get("request_id", 0))
	if _request_id != 0: _spent_requests[_request_id] = true
	if _reason == &"personal_loss": context.consume_suppression(basis)
	if _reason == &"close": _close_available_at = context.evidence_elapsed_seconds + maxf(duration_min, context.fire.burst_pause_seconds)
	remaining = minf(randf_range(maxf(0.1, duration_min), maxf(maxf(0.1, duration_min), duration_max)), float(basis.valid_until) - context.evidence_elapsed_seconds)
	_shots_remaining = mini(actor.ammo.magazine_rounds, maxi(1, context.fire.burst_shots_remaining(_reason == &"support")))
	target_center = preview.center
	_clear_targets.assign(preview.targets)
	active = true
	super.begin(candidate.duplicate(true), visible)
	context.state = context.State.HOLD_POSITION
	actor.agent.target_position = actor.global_position
	_select_aim_point()
	return true

func on_target_lost() -> void:
	if active or not context.is_arena_active() or context.player.is_dead() or context.player.is_in_dialogue: return
	var candidates := collect_candidates(false)
	if not candidates.is_empty(): begin(candidates[0], false)

func _targets_available() -> bool:
	var preview := _preview(_current_mode(), _evidence)
	if preview.is_empty(): return false
	_clear_targets.assign(preview.targets)
	if _current_mode() == &"visible": aim_point = preview.center
	elif not _point_reachable(aim_point): _select_aim_point()
	return aim_point.is_finite() and _point_reachable(aim_point)

func _select_aim_point() -> void:
	if _current_mode() == &"visible":
		aim_point = context.perception.visible_aim_position(context.sees_player)
		return
	var angle := randf() * TAU
	var radius := sqrt(randf()) * maxf(0.0, target_radius)
	var point := target_center + Vector3(cos(angle), 0.0, sin(angle)) * radius
	aim_point = point if _point_reachable(point) else _clear_targets.pick_random() if not _clear_targets.is_empty() else Vector3.INF

func step(delta: float, visible: bool) -> Vector3:
	if not active: return Vector3.ZERO
	if not is_enabled() or not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading or (mode_visible() != visible) or not _evidence_live(_evidence) or _purpose(_current_mode(), _evidence, _request_id).is_empty() or not _targets_available():
		finish(visible)
		return Vector3.ZERO
	remaining = maxf(0.0, remaining - maxf(delta, 0.0))
	if remaining <= 0.0 or _shots_remaining <= 0 or (not _claim.is_empty() and not context.cooperation_update(_claim, {"position": actor.global_position})): finish(visible)
	return Vector3.ZERO

func mode_visible() -> bool:
	return _current_mode() == &"visible"

func valid(visible: bool) -> bool:
	return _running and active and mode_visible() == visible and _evidence_live(_evidence) and not _purpose(_current_mode(), _evidence, _request_id).is_empty()

func tick(delta: float, visible: bool) -> Dictionary:
	step(delta, visible)
	_running = active
	var fire: Dictionary = {}
	if active:
		fire = {"owner": action_id, "mode": &"visible", "support_intent": true} if mode_visible() else {"owner": action_id, "mode": &"memory", "point": aim_point, "support_intent": _reason == &"support"}
	return motion(Vector3.ZERO, 1.0, aim_point - actor.global_position, fire)

func on_shot_fired() -> void:
	if not active: return
	_shots_remaining -= 1
	if _shots_remaining <= 0: finish(context.sees_player)
	else: _select_aim_point()

func reset() -> void:
	if not _claim.is_empty() and context != null: context.cooperation_release(_claim)
	_claim = {}
	active = false
	_evidence = {}
	_mode = &""
	_reason = &""
	_request_id = 0
	remaining = 0.0
	_shots_remaining = 0
	_clear_targets.clear()

func finish(visible: bool) -> void:
	reset()
	_running = false
	context.resume_after_action(visible, context.last_known_position)

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running: finish(context.sees_player)

func _point_preference(basis: Dictionary) -> float:
	return maxf(0.0, float(context.setting(&"suppression", &"low_cover_point_preference", 1.0))) if basis.get("low_cover_context", false) else 0.0

func preference_credit() -> float:
	return _point_preference(_basis()) if _current_mode() == &"point" else 0.0

func state_label() -> String:
	return "近距压制" if _reason == &"close" else "掩护射击" if _reason == &"support" else "消失点短促压制"
