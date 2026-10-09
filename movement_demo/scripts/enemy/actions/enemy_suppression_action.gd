extends "res://scripts/enemy/actions/enemy_action.gd"

## Point fire, visible support and validated cover exits share one action instance.
var duration_min: float:
	get: return _setting(&"duration_min", 3.0)
	set(value): _set_setting(&"duration_min", value)
var duration_max: float:
	get: return _setting(&"duration_max", 5.0)
	set(value): _set_setting(&"duration_max", value)
var target_radius: float:
	get: return _setting(&"target_radius", 0.75)
	set(value): _set_setting(&"target_radius", value)
var shots_per_exit_min: int:
	get: return _setting(&"shots_per_exit_min", 2)
	set(value): _set_setting(&"shots_per_exit_min", value)
var shots_per_exit_max: int:
	get: return _setting(&"shots_per_exit_max", 5)
	set(value): _set_setting(&"shots_per_exit_max", value)

var active := false
var remaining := 0.0
var target_center := Vector3.INF
var aim_point := Vector3.INF
var target_cover: StaticBody3D
var first_exit: Array[Vector3] = []
var second_exit: Array[Vector3] = []
var _clear_targets: Array[Vector3] = []
var _preview_information_retention := 0.0
var _evidence: Dictionary = {}
var _exit_geometry: Dictionary = {}
var _exit_memory := Vector3.INF
var _inference_confidence := 0.0
var _next_exit := 0
var _shots_remaining := 0
var _mode: StringName = &""
var _claim: Dictionary = {}
var _shared_consumed_id := -1
var _shared_generation := -1

func default_mode() -> StringName:
	return &"point"

func _current_mode() -> StringName:
	return default_mode() if _mode.is_empty() else _mode

func _is_exit(mode: StringName) -> bool:
	return mode in [&"exit_left", &"exit_right", &"exit_sweep"]

func _duration(mode: StringName, maximum: bool = false) -> float:
	if _is_exit(mode) and config_section != &"exit_suppression":
		return float(_setting(&"exit_duration_max" if maximum else &"exit_duration_min", 5.0 if maximum else 3.0))
	return duration_max if maximum else duration_min

func _fresh_basis() -> Dictionary:
	if _shared_generation != context.memory_generation:
		_shared_generation = context.memory_generation
		_shared_consumed_id = -1
	var personal: Dictionary = context.suppression_basis()
	if context.utility_suppression_pending and context.suppression_available(personal): return personal
	var shared: Dictionary = context.cooperation_target_evidence()
	if shared.get("shared", false) and _evidence_live(shared) and int(shared.get("id", -1)) != _shared_consumed_id:
		return shared
	# Read-only geometry inspection remains possible without creating a new event.
	return personal

func _basis() -> Dictionary:
	return _evidence if active and not _evidence.is_empty() else _fresh_basis()

func _evidence_live(basis: Dictionary) -> bool:
	return not basis.is_empty() and basis.get("position", Vector3.INF).is_finite() and context.evidence_elapsed_seconds < float(basis.get("valid_until", -INF))

func _available_evidence(basis: Dictionary) -> bool:
	if not _evidence_live(basis): return false
	if basis.get("shared", false): return int(basis.get("id", -1)) != _shared_consumed_id
	return context.suppression_available(basis)

func _evidence_position() -> Vector3:
	return _basis().get("position", Vector3.INF)

func _freshness(basis: Dictionary = {}) -> float:
	if basis.is_empty(): basis = _basis()
	var age: float = maxf(0.0, context.evidence_elapsed_seconds - float(basis.get("captured_at", 0.0)))
	return pow(0.5, age / maxf(0.5, context.utility_threat_half_life_seconds)) * clampf(float(basis.get("confidence", 1.0)), 0.0, 1.0)

func is_active() -> bool:
	return active

## Preview never changes execution aim, shot count, claim or duration.
func _preview(mode: StringName, basis: Dictionary) -> Dictionary:
	if not _evidence_live(basis) or not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading: return {}
	var center: Vector3 = basis.position + Vector3.UP * 0.8
	if mode == &"visible":
		var point: Vector3 = context.perception.visible_aim_position(context.sees_player)
		if not point.is_finite() or not _point_reachable(point, true): return {}
		return {"targets": [point], "information": 1.0, "geometry": {}}
	var geometry: Dictionary = context.cover_selection.suppression_geometry(basis.position)
	var targets: Array = []
	if _is_exit(mode):
		if geometry.is_empty(): return {}
		if mode != &"exit_right": targets.append_array(geometry.first)
		if mode != &"exit_left": targets.append_array(geometry.second)
	else:
		for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			var point := center + offset * maxf(0.0, target_radius)
			if _point_reachable(point, false): targets.append(point)
	if targets.is_empty(): return {}
	return {"targets": targets, "information": _retention(mode, basis, geometry), "geometry": geometry}

func _retention(mode: StringName, basis: Dictionary, geometry: Dictionary) -> float:
	if geometry.is_empty(): return 0.0
	var balance: float = geometry.get("balance", 0.0)
	var open_fraction := float(geometry.get("open_sides", 0)) * 0.5
	var confidence: float = geometry.get("confidence", 0.0)
	if not _is_exit(mode): return 0.65 * confidence * maxf(1.0 - balance, 1.0 - open_fraction) * _freshness(basis)
	var covered := 0.0
	if mode != &"exit_right" and not geometry.first.is_empty(): covered += 0.5
	if mode != &"exit_left" and not geometry.second.is_empty(): covered += 0.5
	return 0.65 * confidence * covered * _freshness(basis) * balance * open_fraction

func utility_available() -> bool:
	if not is_enabled(): return false
	var preview := _preview(_current_mode(), _basis())
	_preview_information_retention = float(preview.get("information", 0.0))
	return not preview.is_empty()

func information_retention() -> float:
	return _retention(_current_mode(), _basis(), context.cover_selection.suppression_geometry(_evidence_position()))

func utility_fire_fraction() -> float:
	return 0.0 if _preview(_current_mode(), _basis()).is_empty() else 1.0

func reset() -> void:
	if not _claim.is_empty() and context != null: context.cooperation_release(_claim)
	_claim = {}
	active = false
	_evidence = {}
	remaining = 0.0
	_mode = &""
	_clear_targets.clear()
	target_cover = null
	first_exit.clear()
	second_exit.clear()
	_exit_geometry.clear()
	_next_exit = 0
	_shots_remaining = 0
	_inference_confidence = 0.0

## Compatibility entry; normal execution starts the plan selected by Utility.
func on_target_lost() -> void:
	if active or not is_enabled() or not context.is_arena_active(): return
	if context.player.is_dead() or context.player.is_in_dialogue: return
	_start(default_mode(), _fresh_basis(), {})

func _start(mode: StringName, basis: Dictionary, cooperation: Dictionary) -> bool:
	if mode != &"visible" and not _available_evidence(basis): return false
	var preview := _preview(mode, basis)
	if preview.is_empty(): return false
	var claim: Dictionary = {}
	if not cooperation.is_empty():
		var task := cooperation.duplicate(true)
		task.owner_action = action_id
		task.duration = minf(_duration(mode, true), maxf(0.1, float(basis.valid_until) - context.evidence_elapsed_seconds))
		claim = context.cooperation_claim(task)
		if claim.is_empty(): return false
	reset()
	_claim = claim
	_mode = mode
	_evidence = basis.duplicate(true)
	target_center = basis.position + Vector3.UP * 0.8
	_apply_preview(preview, basis)
	remaining = randf_range(maxf(0.1, _duration(mode)), maxf(maxf(0.1, _duration(mode)), _duration(mode, true)))
	if mode != &"visible": remaining = minf(remaining, float(basis.valid_until) - context.evidence_elapsed_seconds)
	if basis.get("shared", false): _shared_consumed_id = int(basis.id)
	elif mode != &"visible": context.consume_suppression(basis)
	active = true
	_running = true
	context.state = context.State.HOLD_POSITION
	actor.agent.target_position = actor.global_position
	_select_aim_point()
	return true

func step(delta: float, sees_player: bool) -> Vector3:
	if not active: return Vector3.ZERO
	if not is_enabled() or not actor.can_use_firearms() or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading:
		finish(sees_player)
		return Vector3.ZERO
	if (_current_mode() == &"visible" and not sees_player) or (_current_mode() != &"visible" and (sees_player or not _evidence_live(_evidence))) or not _targets_available():
		finish(sees_player)
		return Vector3.ZERO
	remaining = maxf(0.0, remaining - maxf(delta, 0.0))
	if not _claim.is_empty() and not context.cooperation_update(_claim, {"remaining": remaining, "position": actor.global_position, "aim_position": aim_point}):
		finish(sees_player)
	elif remaining <= 0.0: finish(sees_player)
	return Vector3.ZERO

func _apply_preview(preview: Dictionary, basis: Dictionary) -> void:
	_clear_targets.assign(preview.targets)
	_exit_geometry = preview.geometry
	first_exit.clear()
	second_exit.clear()
	if _is_exit(_current_mode()):
		_exit_memory = basis.position
		target_cover = _exit_geometry.body
		_inference_confidence = _exit_geometry.confidence
		first_exit.assign(_exit_geometry.first)
		second_exit.assign(_exit_geometry.second)

func _prepare_targets(center: Vector3) -> bool:
	var basis := _basis().duplicate()
	basis.position = center - Vector3.UP * 0.8
	var preview := _preview(_current_mode(), basis)
	if preview.is_empty():
		first_exit.clear()
		second_exit.clear()
		_clear_targets.clear()
		return false
	_apply_preview(preview, basis)
	return true

func _prepare_cover_exits() -> void:
	_exit_geometry = context.cover_selection._suppression_cover_geometry(target_cover, _exit_memory)
	first_exit.assign(_exit_geometry.get("first", []))
	second_exit.assign(_exit_geometry.get("second", []))

func _targets_available() -> bool:
	if _current_mode() == &"visible":
		var point: Vector3 = context.perception.visible_aim_position(context.sees_player)
		if not point.is_finite() or not _point_reachable(point, true): return false
		aim_point = point
		return true
	if _is_exit(_current_mode()):
		if not is_instance_valid(target_cover) or context.cover_selection.confirmed_suppression_cover(_exit_memory) != target_cover: return false
		_prepare_cover_exits()
		if _current_mode() == &"exit_left" and first_exit.is_empty(): return false
		if _current_mode() == &"exit_right" and second_exit.is_empty(): return false
		if first_exit.is_empty() and second_exit.is_empty(): return false
		var points: Array = first_exit if _current_mode() == &"exit_left" else second_exit if _current_mode() == &"exit_right" else first_exit + second_exit
		if not points.has(aim_point): _select_aim_point()
		return true
	if _point_reachable(aim_point, false): return true
	if not _prepare_targets(target_center): return false
	_select_aim_point()
	return true

func _point_reachable(target: Vector3, full_line: bool) -> bool:
	var origin: Vector3 = actor.get_shot_origin()
	return target.is_finite() and actor.weapon != null and origin.distance_to(target) <= actor.weapon.fire_range and context.fire.has_clear_suppression_lane(origin, target - origin, origin.distance_to(target)) and (not full_line or context.cover_selection.has_clear_line(origin, target))

func _can_reach_target(target: Vector3) -> bool:
	return _point_reachable(target, _is_exit(_current_mode()))

func _select_aim_point() -> void:
	if _current_mode() == &"visible":
		aim_point = context.perception.visible_aim_position(context.sees_player)
		return
	if _is_exit(_current_mode()):
		if first_exit.is_empty() and second_exit.is_empty(): return
		if _current_mode() == &"exit_left": _next_exit = 0
		elif _current_mode() == &"exit_right": _next_exit = 1
		elif first_exit.is_empty(): _next_exit = 1
		elif second_exit.is_empty(): _next_exit = 0
		if _shots_remaining <= 0:
			var minimum := maxi(1, mini(shots_per_exit_min, shots_per_exit_max))
			_shots_remaining = randi_range(minimum, maxi(minimum, maxi(shots_per_exit_min, shots_per_exit_max)))
		var points: Array[Vector3] = first_exit if _next_exit == 0 else second_exit
		if not points.is_empty(): aim_point = points.pick_random()
		return
	var angle := randf() * TAU
	var radius := sqrt(randf()) * maxf(0.0, target_radius)
	aim_point = target_center + Vector3(cos(angle), 0.0, sin(angle)) * radius
	if not _clear_targets.is_empty() and (randf() < 0.5 or not _point_reachable(aim_point, false)): aim_point = _clear_targets.pick_random()

func on_shot_fired() -> void:
	if _is_exit(_current_mode()):
		_shots_remaining -= 1
		if _shots_remaining <= 0 and _current_mode() == &"exit_sweep": _next_exit = 1 - _next_exit
	_select_aim_point()

func _allies(snapshot: Dictionary) -> Array:
	return snapshot.get("members", []).filter(func(member): return member.get("id", 0) != actor.get_instance_id() and member.get("can_cooperate", false))

func _exit_lane(mode: StringName, preview: Dictionary) -> String:
	var box: CollisionShape3D = preview.geometry.body.get_node("CollisionShape3D")
	var half: Vector3 = box.shape.size * 0.5
	var observer: Vector3 = box.to_local(actor.global_position)
	var along_x := absf(observer.z) / half.z >= absf(observer.x) / half.x
	var point: Vector3 = box.to_local(preview.targets[0])
	return "exit:%d:%s:%d" % [preview.geometry.body.get_instance_id(), "x" if along_x else "z", int(signf(point.x if along_x else point.z))] if mode != &"exit_sweep" else "exit:%d:sweep" % preview.geometry.body.get_instance_id()

func _cooperation(mode: StringName, preview: Dictionary, _duration: float) -> Dictionary:
	if not context.cooperation_enabled(): return {}
	var target_id: int = context.cooperation_target_id()
	var snapshot: Dictionary = context.cooperation_snapshot(target_id)
	if _allies(snapshot).is_empty(): return {}
	var request: Dictionary = {}
	for item: Dictionary in snapshot.get("requests", []):
		if item.get("target_id", 0) == target_id and item.get("beneficiary_id", item.get("owner_id", 0)) != actor.get_instance_id():
			request = item
			break
	if request.is_empty() and not _is_exit(mode): return {}
	var point: Vector3 = preview.targets[0]
	if mode == &"point" and not _point_reachable(point, true): return {}
	var task := {"target_id": target_id, "kind": &"support", "lane_id": _exit_lane(mode, preview) if _is_exit(mode) else "target", "position": actor.global_position,
		"beneficiary_id": request.get("beneficiary_id", request.get("owner_id", 0)), "request_id": request.get("id", 0),
		"quality": 1.0}
	if _is_exit(mode):
		task.coverage_kind = &"exit"
		task.cover_id = preview.geometry.body.get_instance_id()
		task.coverage_lanes = [task.lane_id]
	return task

func _support_prediction(mode: StringName, preview: Dictionary, duration: float) -> Dictionary:
	# Refresh only the estimate. The active evidence, aim, burst and lease stay frozen.
	var point: Vector3 = aim_point if active and mode == _current_mode() and mode != &"visible" and aim_point.is_finite() else preview.targets[0]
	var desired: Vector3 = point - actor.get_shot_origin()
	var turning: float = 0.0 if desired.is_zero_approx() else maxf(0.0, actor.aim_direction.angle_to(desired) - actor.AIM_ACQUIRE_ANGLE) / maxf(0.01, deg_to_rad(actor.aim_turn_speed_degrees))
	var ready_delay: float = maxf(turning, maxf(actor.shot_cooldown, float(context.fire.fire_pause_remaining)))
	if mode == &"visible":
		ready_delay = maxf(ready_delay, maxf(0.0, context.fire.fire_reaction_seconds - context.fire.fire_reaction_elapsed))
		# Steady waiting accumulates only after the mechanical/reaction gates open.
		ready_delay += context.fire.estimated_steady_wait(true)
	var burst_left: int = maxi(0, context.fire.burst_shot_count - context.fire.fire_burst_shots)
	var ammunition_window: float = mini(actor.ammo.magazine_rounds, burst_left) * maxf(0.05, actor.weapon.shot_interval)
	if actor.ammo.is_reloading: ammunition_window = 0.0
	return {"support_seconds": minf(ammunition_window, maxf(0.0, minf(context.utility_horizon_seconds, duration) - ready_delay)), "estimated_start_seconds": ready_delay}

func _slot_available(task: Dictionary) -> bool:
	if task.is_empty(): return true
	for claim: Dictionary in context.cooperation_snapshot(task.get("target_id", 0)).get("claims", []):
		if claim.get("owner_id", 0) != actor.get_instance_id() and claim.get("kind", &"") == task.get("kind", &"") and String(claim.get("lane_id", "")) == String(task.get("lane_id", "")):
			return false
	return true

func collect_candidates(visible: bool) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_enabled() or not actor.can_use_firearms() or context.is_executing_cover_plan(): return result
	var basis := _basis()
	var modes: Array[StringName] = [&"point", &"exit_sweep", &"exit_left", &"exit_right"]
	if default_mode() != &"point": modes.assign([default_mode()])
	if active: modes.assign([_current_mode()])
	elif visible:
		if not context.cooperation_enabled(): return result
		basis = context.cooperation_target_evidence()
		modes.assign([&"visible"])
	elif (not context.utility_suppression_pending and not basis.get("shared", false)) or not _available_evidence(basis): return result
	if not _evidence_live(basis): return result
	var teamed: bool = context.cooperation_enabled() and not _allies(context.cooperation_snapshot()).is_empty()
	if not active and not visible and default_mode() == &"point":
		modes.assign([&"point", &"exit_left", &"exit_right"] if teamed else [&"point", &"exit_sweep"])
	for mode in modes:
		if (mode == &"visible") != visible or (not active and teamed and mode == &"exit_sweep"): continue
		var duration: float = remaining if active else maxf(0.1, _duration(mode))
		var candidate := preview_candidate(mode, basis, duration)
		if candidate.is_empty(): continue
		if mode in [&"visible", &"exit_left", &"exit_right"] and candidate.get("cooperation", {}).is_empty(): continue
		if not _slot_available(candidate.get("cooperation", {})): continue
		result.append(candidate)
	return result

## Read-only plan preview is also used by diagnostics; it never consumes evidence.
func preview_candidate(mode: StringName, basis: Dictionary = {}, duration: float = -1.0) -> Dictionary:
	if basis.is_empty(): basis = _basis()
	var preview := _preview(mode, basis)
	if preview.is_empty(): return {}
	if duration < 0.0: duration = remaining if active and mode == _current_mode() else maxf(0.1, _duration(mode))
	var horizon: float = context.utility_horizon_seconds
	var available: float = maxf(0.0, minf(horizon, duration) - context.spatial._ammo_wait(context))
	if mode == &"visible":
		# Finishing the bounded support plan can resume normal visible engagement.
		# Only actual readiness/steady time is unavailable, not the rest of the horizon.
		var fire_wait: float = context.fire.estimated_steady_wait(true) if context.fire.has_method("estimated_steady_wait") else 0.0
		available = maxf(0.0, horizon - fire_wait)
	var information: float = minf(horizon, duration) * (1.0 - float(preview.information))
	var candidate := option({}, horizon - available, context.spatial._exposure(context, actor.global_position, context._known_reload_threat()) * horizon, information, mode)
	candidate.suppression_evidence = basis.duplicate(true)
	candidate.target_id = context.cooperation_target_id()
	candidate.outcome.preference_credit = _point_preference(basis) if mode == &"point" else 0.0
	var cooperation: Dictionary = plan.get("cooperation", {}).duplicate(true) if active and mode == _current_mode() else _cooperation(mode, preview, duration)
	if not cooperation.is_empty():
		var support_duration: float = minf(duration, maxf(0.0, float(basis.valid_until) - context.evidence_elapsed_seconds))
		cooperation.merge(_support_prediction(mode, preview, support_duration), true)
		candidate.cooperation = cooperation
	if mode == &"visible": candidate.support_intent = true
	return candidate

func validate(candidate: Dictionary, visible: bool) -> bool:
	var mode: StringName = candidate.get("plan", default_mode())
	var basis: Dictionary = candidate.get("suppression_evidence", _basis())
	return is_enabled() and (mode == &"visible") == visible and not _preview(mode, basis).is_empty() and _slot_available(candidate.get("cooperation", {})) and (active or mode == &"visible" or _available_evidence(basis))

func begin(candidate: Dictionary, visible: bool) -> bool:
	if not validate(candidate, visible): return false
	var saved_plan := candidate.duplicate(true)
	if active:
		# Adopting an already active compatibility plan must not consume its event
		# twice or restart its finite duration and current burst.
		if candidate.get("plan", default_mode()) != _current_mode() or candidate.get("suppression_evidence", _basis()) != _evidence: return false
		if not _claim.is_empty() and not context.cooperation_update(_claim, {"remaining": remaining}): return false
		super.begin(saved_plan, visible)
		return true
	if not _start(candidate.get("plan", default_mode()), candidate.get("suppression_evidence", _basis()), candidate.get("cooperation", {})): return false
	super.begin(saved_plan, visible)
	return true

func valid(visible: bool) -> bool:
	return _running and active and actor.can_use_firearms() and (_current_mode() == &"visible") == visible and (_current_mode() == &"visible" or _evidence_live(_evidence))

func tick(delta: float, visible: bool) -> Dictionary:
	step(delta, visible)
	_running = active
	var fire: Dictionary = {}
	if active:
		fire = {"owner": action_id, "mode": &"visible", "support_intent": true} if _current_mode() == &"visible" else {"owner": action_id, "mode": &"memory", "point": aim_point}
	return motion(Vector3.ZERO, 1.0, aim_point - actor.global_position, fire)

func finish(sees_player: bool) -> void:
	reset()
	_running = false
	context.resume_after_action(sees_player, context.last_known_position)

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running:
		reset()
		_running = false

func _point_preference(basis: Dictionary) -> float:
	return maxf(0.0, float(context.setting(&"suppression", &"low_cover_point_preference", 1.0))) if basis.get("low_cover_context", false) else 0.0

func preference_credit() -> float:
	return _point_preference(_basis()) if _current_mode() == &"point" else 0.0

func state_label() -> String:
	match _current_mode():
		&"visible": return "掩护射击"
		&"exit_left": return "封锁左出口"
		&"exit_right": return "封锁右出口"
		&"exit_sweep": return "掩体出口压制"
	return "火力压制"
