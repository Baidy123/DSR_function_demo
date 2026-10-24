extends "res://scripts/enemy/actions/enemy_action.gd"

## Bounded fire for a personal disappearance, close threat or assigned team support.
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
var _close_available_at := 0.0
var _generation := -1

func default_mode() -> StringName:
	return &"point"

func _current_mode() -> StringName:
	return default_mode() if _mode.is_empty() else _mode

func _sync_generation() -> void:
	if _generation == context.memory_generation: return
	_generation = context.memory_generation
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

func _purpose(mode: StringName, basis: Dictionary) -> Dictionary:
	if not _evidence_live(basis) or not _basis_aim(basis).is_finite(): return {}
	# A committed wave keeps its original reason and beneficiary. A different
	# opportunity may enter a new Utility decision only after this wave ends.
	if active:
		if _reason == &"personal_loss": return {"reason": &"personal_loss"} if mode == &"point" else {}
		if _reason == &"close": return {"reason": &"close"} if mode == &"visible" and context.fire.close_suppression_pressure() > 0.0 else {}
		return {}
	if mode == &"point":
		if not basis.get("shared", false) and basis.get("source") == &"visual_loss" and context.utility_suppression_pending and context.suppression_available(basis):
			return {"reason": &"personal_loss"}
	elif mode == &"visible":
		if context.fire.close_suppression_pressure() > 0.0 and context.evidence_elapsed_seconds >= _close_available_at:
			return {"reason": &"close"}
	else: return {}
	return {}

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

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_enabled() or not actor.can_use_firearms() or context.is_executing_cover_plan(): return result
	_sync_generation()
	var mode: StringName = _current_mode() if active else &"visible" if visible else &"point"
	if (mode == &"visible") != visible: return result
	var basis: Dictionary = _basis() if active or not visible else context.cooperation_target_evidence()
	if _purpose(mode, basis).is_empty(): return result
	var candidate := preview_candidate(mode, basis)
	if not candidate.is_empty(): result.append(candidate)
	return result

## Diagnostic fallback never authorizes execution of a legacy foot-only fixture.
func preview_candidate(mode: StringName, basis: Dictionary = {}, duration: float = -1.0) -> Dictionary:
	if basis.is_empty(): basis = _basis()
	var preview := _preview(mode, basis, true)
	if preview.is_empty(): return {}
	if duration < 0.0: duration = remaining if active else maxf(0.1, duration_min)
	duration = minf(duration, maxf(0.0, float(basis.valid_until) - context.evidence_elapsed_seconds))
	var purpose := _purpose(mode, basis)
	var prediction := _support_prediction(mode, preview, duration, false)
	var horizon: float = context.utility_horizon_seconds
	var available: float = float(prediction.support_seconds)
	var candidate := option({}, horizon - available, context.spatial._exposure(context, actor.global_position, context._known_reload_threat()) * horizon, 0.0 if mode == &"visible" else minf(horizon, duration), mode)
	candidate.suppression_evidence = basis.duplicate(true)
	candidate.target_id = context.cooperation_target_id()
	candidate.outcome.preference_credit = _point_preference(basis) if mode == &"point" else 0.0
	candidate.suppression_reason = purpose.get("reason", &"")
	if mode == &"visible": candidate.support_intent = true
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	if not is_enabled() or candidate.get("target_id", context.cooperation_target_id()) != context.cooperation_target_id(): return false
	var mode: StringName = candidate.get("plan", default_mode())
	var basis: Dictionary = candidate.get("suppression_evidence", _basis())
	if (mode == &"visible") != visible or _preview(mode, basis).is_empty(): return false
	var purpose := _purpose(mode, basis)
	return not purpose.is_empty() and purpose.get("reason") == candidate.get("suppression_reason", purpose.get("reason"))

func begin(candidate: Dictionary, visible: bool) -> bool:
	if not validate(candidate, visible): return false
	var mode: StringName = candidate.get("plan", default_mode())
	var basis: Dictionary = candidate.get("suppression_evidence", _basis())
	if active:
		if mode != _current_mode() or basis != _evidence: return false
		super.begin(candidate.duplicate(true), visible)
		return true
	var purpose := _purpose(mode, basis)
	var preview := _preview(mode, basis)
	reset()
	_mode = mode
	_reason = purpose.reason
	_evidence = basis.duplicate(true)
	if _reason == &"personal_loss": context.consume_suppression(basis)
	if _reason == &"close": _close_available_at = context.evidence_elapsed_seconds + maxf(duration_min, context.fire.burst_pause_seconds)
	remaining = minf(randf_range(maxf(0.1, duration_min), maxf(maxf(0.1, duration_min), duration_max)), float(basis.valid_until) - context.evidence_elapsed_seconds)
	_shots_remaining = mini(actor.ammo.magazine_rounds, maxi(1, context.fire.burst_shots_remaining(false)))
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
	if not is_enabled() or not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading or (mode_visible() != visible) or not _evidence_live(_evidence) or _purpose(_current_mode(), _evidence).is_empty() or not _targets_available():
		finish(visible)
		return Vector3.ZERO
	remaining = maxf(0.0, remaining - maxf(delta, 0.0))
	if remaining <= 0.0 or _shots_remaining <= 0: finish(visible)
	return Vector3.ZERO

func mode_visible() -> bool:
	return _current_mode() == &"visible"

func valid(visible: bool) -> bool:
	return _running and active and mode_visible() == visible and _evidence_live(_evidence) and not _purpose(_current_mode(), _evidence).is_empty()

func tick(delta: float, visible: bool) -> Dictionary:
	step(delta, visible)
	_running = active
	var fire: Dictionary = {}
	if active:
		fire = {"owner": action_id, "mode": &"visible", "support_intent": true} if mode_visible() else {"owner": action_id, "mode": &"memory", "point": aim_point, "support_intent": false}
	return motion(Vector3.ZERO, 1.0, aim_point - actor.global_position, fire)

func on_shot_fired() -> void:
	if not active: return
	_shots_remaining -= 1
	if _shots_remaining <= 0: finish(context.sees_player)
	else: _select_aim_point()

func reset() -> void:
	active = false
	_evidence = {}
	_mode = &""
	_reason = &""
	remaining = 0.0
	_shots_remaining = 0
	_clear_targets.clear()

func finish(visible: bool) -> void:
	reset()
	if context.commanded() and not command.is_empty():
		context.report_command(command, &"complete", {"reason": &"fire_window_finished"})
		return
	_running = false
	context.resume_after_action(visible, context.last_known_position)

func on_event(event: StringName, _data: Dictionary) -> void:
	# Personal suppression keeps its original damage interruption.
	if event == &"damage" and _running: finish(context.sees_player)

func _point_preference(basis: Dictionary) -> float:
	return maxf(0.0, float(_setting(&"low_cover_point_preference", 1.0))) if basis.get("low_cover_context", false) else 0.0

func preference_credit() -> float:
	return _point_preference(_basis()) if _current_mode() == &"point" else 0.0

func state_label() -> String:
	if context.commanded() and command.get("fire_mode") == &"support": return "掩护射击"
	return "近距压制" if _reason == &"close" else "掩护射击" if _reason == &"support" else "消失点短促压制"

func command_roles() -> Array[StringName]:
	return [&"support", &"engage"] if actor.can_use_firearms() else []

func command_runtime_state() -> Dictionary:
	_sync_generation()
	return {"active": active, "remaining": remaining, "shots_remaining": _shots_remaining}

func freeze_command_capability() -> Dictionary:
	var result := super.freeze_command_capability()
	result.attack_modes.append(&"frozen_personal_evidence")
	return result

func command_site_offer(query: Dictionary, site: Dictionary) -> Dictionary:
	if site.role != &"support": return {}
	var offer := super.command_site_offer(query, site)
	if not offer.is_empty() and not offer.get("retry_detour", false) and not offer.get("route_pending", false): offer.fire_mode = &"support"
	return offer

func prepare_command_offers(query: Dictionary, cursor: Dictionary, deadline_usec: int) -> Dictionary:
	var batch := super.prepare_command_offers(query, cursor, deadline_usec)
	var next: Dictionary = batch.get("next_cursor", {}).duplicate(true)
	if not next.get("personal_checked", false) and Time.get_ticks_usec() < deadline_usec:
		next.personal_checked = true
		var mode: StringName = _current_mode() if active else (&"visible" if query.body.visible else &"point")
		var basis: Dictionary = _evidence if active else (context.cooperation_target_evidence() if query.body.visible else context.suppression_basis())
		var purpose := _purpose(mode, basis)
		var preview := _preview(mode, basis) if not purpose.is_empty() else {}
		if not preview.is_empty() and ((mode == &"visible") == query.body.visible):
			var duration: float = remaining if active else minf(duration_min, float(basis.valid_until) - context.evidence_elapsed_seconds)
			var prediction := _support_prediction(mode, preview, duration)
			if float(prediction.support_seconds) > 0.0:
				var offer := {"action": action_id, "role": &"engage", "position": query.body.position,
					"route": PackedVector3Array([query.body.position]), "look_position": basis.position,
					"site_key": "fire-window:%s:%s" % [basis.get("id", 0), mode], "objective_id": query.objective.objective_id,
					"target_id": context.cooperation_target_id(), "fire_mode": mode, "fire_evidence": basis.duplicate(true), "fire_reason": purpose.reason,
					"attack": &"frozen_personal_evidence" if mode == &"point" else &"personal_sight",
					"fire_radius": target_radius, "plan_key": [action_id, context.memory_generation, basis.get("id", 0), mode],
					"allowed_phases": [&"contact", &"search"], "travel_seconds": 0.0,
					"estimate": maxf(0.0, context.utility_horizon_seconds - float(prediction.support_seconds) - (_point_preference(basis) if mode == &"point" else 0.0)),
					"tactical": {"sustainable_fire": true, "travel": 0.0}}
				batch.offers.append(offer)
	batch.next_cursor = next
	batch.done = batch.done and next.get("personal_checked", false)
	return batch

func validate_command_offer(query: Dictionary, offer: Dictionary) -> Dictionary:
	var result := super.validate_command_offer(query, offer)
	if offer.get("fire_mode", &"support") == &"support": return result
	var basis: Dictionary = offer.get("fire_evidence", {})
	var mode: StringName = offer.get("fire_mode", &"")
	result.valid = result.valid and ((mode == &"visible") == query.body.visible) and not _preview(mode, basis).is_empty()
	if result.valid:
		var purpose := _purpose(mode, basis)
		result.valid = purpose.get("reason", &"") == offer.get("fire_reason") and not purpose.is_empty()
		if mode == &"point":
			result.valid = result.valid and int(basis.get("id", 0)) > 0 and basis.get("source") == &"visual_loss" and not basis.get("shared", false)
			result.valid = result.valid and basis == context.suppression_evidence
			result.valid = result.valid and (active and _evidence.get("id") == basis.id or context.utility_suppression_pending and context.suppression_available(basis))
	return result

func begin_command(task: Dictionary) -> bool:
	if task.get("fire_mode", &"support") != &"support":
		var candidate := {"plan": task.fire_mode, "target_id": task.target_id,
			"suppression_evidence": task.fire_evidence, "suppression_reason": task.fire_reason}
		if not begin(candidate, context.sees_player): return false
	return super.begin_command(task)

func command_work(delta: float, visible: bool, _arrived: bool) -> Dictionary:
	if command.get("fire_mode", &"support") == &"support":
		return {"fire": {"owner": action_id, "mode": &"visible", "support_intent": true}} if visible and actor.can_use_firearms() else {}
	step(delta, visible)
	if not active: return {}
	var fire := {"owner": action_id, "mode": &"visible", "support_intent": true} if mode_visible() else {"owner": action_id, "mode": &"memory", "point": aim_point, "evidence_id": _evidence.id, "support_intent": false}
	return {"facing": aim_point - actor.global_position, "fire": fire}
