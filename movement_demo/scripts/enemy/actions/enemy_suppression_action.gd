extends "res://scripts/enemy/actions/enemy_action.gd"


## 朝最后目击位置附近压制的最短秒数；换弹不会延长本次压制时长。
var duration_min: float:
	get: return _setting(&"duration_min", 3.0)
	set(value): _set_setting(&"duration_min", value)
## 最长秒数，每次在最短与最长之间抽取；至少等于最短值。
var duration_max: float:
	get: return _setting(&"duration_max", 5.0)
	set(value): _set_setting(&"duration_max", value)
## 瞄准点在最后目击位置周围的水平采样半径；实际子弹继续使用枪械散布。
var target_radius: float:
	get: return _setting(&"target_radius", 0.75)
	set(value): _set_setting(&"target_radius", value)

var active: bool = false
var remaining: float = 0.0
var target_center: Vector3
var aim_point: Vector3
var _clear_targets: Array[Vector3] = []
var _preview_information_retention: float = 0.0



func is_active() -> bool:
	return active


## 无副作用候选检查；出口压制在临时动作对象中查询目标，避免改动执行中的连射状态。
func utility_available() -> bool:
	if not is_enabled() or not actor.can_use_firearms():
		return false
	if not context.has_visual_memory or actor.ammo.magazine_rounds <= 0 or actor.ammo.is_reloading:
		return false
	var center: Vector3 = context.last_seen_position + Vector3.UP * 0.8
	# 范围由实际射击样本判断：记忆中心超距时，近侧出口仍可能在射程内。
	var preview = get_script().new()
	preview.action_id = action_id
	preview.definition = definition
	preview.setup(context, config_section)
	var available: bool = preview._prepare_targets(center)
	_preview_information_retention = preview.information_retention() if available else 0.0
	return available

## 近侧出口明显更近、或另一端身体无法通过时，集中压制记忆区域更有效。
func information_retention() -> float:
	var geometry: Dictionary = context.cover_selection.suppression_geometry(context.last_seen_position,
		float(context.setting(&"exit_suppression", &"cover_inference_distance", 1.75)))
	if geometry.is_empty(): return 0.0
	var focus := maxf(1.0 - float(geometry.balance), 1.0 - float(geometry.open_sides) * 0.5)
	var freshness := pow(0.5, context.utility_unseen_seconds / maxf(0.5, context.utility_threat_half_life_seconds))
	return 0.65 * float(geometry.confidence) * focus * freshness


## 执行会把全部射击分配到可射样本，不能再按未被使用的遮挡样本扣除射击时间。
func utility_fire_fraction() -> float:
	var center: Vector3 = context.last_seen_position + Vector3.UP * 0.8
	for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var target: Vector3 = center + offset * target_radius
		if _can_reach_target(target):
			return 1.0
	return 0.0


func reset() -> void:
	active = false
	remaining = 0.0
	_clear_targets.clear()


# 只在真实目击从有到无时调用；持续看不见不会每帧重启。
func on_target_lost() -> void:
	if not is_enabled():
		return
	if active:
		return
	if not actor.can_use_firearms() or not context.is_arena_active():
		return
	if not context.has_visual_memory or context.player.is_dead() or context.player.is_in_dialogue:
		return
	var center: Vector3 = context.last_seen_position + Vector3.UP * 0.8
	if not _prepare_targets(center):
		return
	target_center = center
	remaining = randf_range(maxf(0.1, duration_min), maxf(maxf(0.1, duration_min), duration_max))
	active = true
	context.state = context.State.HOLD_POSITION
	actor.agent.target_position = actor.global_position
	_select_aim_point()
	if context.cover_selection.debug_cover_selection:
		print("[AI][压制] ", state_label(), "开始，最后目击区域=", target_center, "，持续=", snappedf(remaining, 0.01), "秒")


func step(delta: float, sees_player: bool) -> Vector3:
	if not active:
		return Vector3.ZERO
	if sees_player:
		finish(true)
		return Vector3.ZERO
	if not is_enabled() or not actor.can_use_firearms() or not _targets_available():
		finish(false)
		return Vector3.ZERO
	remaining = maxf(0.0, remaining - maxf(delta, 0.0))
	if remaining <= 0.0:
		finish(false)
	return Vector3.ZERO


func on_shot_fired() -> void:
	# 当前点一直保留到实际打出一枪，避免有限跟枪永远追逐变化目标。
	_select_aim_point()


# 子类只负责目标区域，计时、结束和射击权限继续共用。
func _prepare_targets(center: Vector3) -> bool:
	_clear_targets.clear()
	for offset: Vector3 in [Vector3.ZERO, Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var target: Vector3 = center + offset * maxf(0.0, target_radius)
		if _can_reach_target(target):
			_clear_targets.append(target)
	return not _clear_targets.is_empty()


func _targets_available() -> bool:
	if _can_reach_target(aim_point):
		return true
	# 枪口附近堵住时先换可射样本；全部不可用则结束。
	if not _prepare_targets(target_center):
		return false
	_select_aim_point()
	return true


func _can_reach_target(target: Vector3) -> bool:
	var origin: Vector3 = actor.get_shot_origin()
	return actor.weapon != null and origin.distance_to(target) <= actor.weapon.fire_range and context.fire.has_clear_suppression_lane(origin, target - origin, origin.distance_to(target))


func state_label() -> String:
	return "火力压制"


func _select_aim_point() -> void:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * maxf(0.0, target_radius)
	aim_point = target_center + Vector3(cos(angle), 0.0, sin(angle)) * radius
	# 允许打在远处目标掩体上；只有近处堵枪口才改用核实过的方向。
	if not _can_reach_target(aim_point) and not _clear_targets.is_empty():
		aim_point = _clear_targets.pick_random()


func finish(sees_player: bool) -> void:
	reset()
	_running = false
	context.resume_after_action(sees_player, context.last_known_position)
	if context.cover_selection.debug_cover_selection:
		print("[AI][压制] 结束，", "重新目击并恢复交战" if sees_player else "回到追踪／搜索")


func collect_candidates(visible: bool) -> Array[Dictionary]:
	if visible or context.is_executing_cover_plan() or (not active and not context.utility_suppression_pending) or not utility_available():
		return []
	var duration: float = remaining if active else maxf(0.1, duration_min)
	var horizon: float = context.utility_horizon_seconds
	var available: float = maxf(0.0, minf(horizon, duration) - context.spatial._ammo_wait(context)) * utility_fire_fraction()
	var threat: Vector3 = context._known_reload_threat()
	var information := minf(horizon, duration) * (1.0 - _preview_information_retention)
	return [option({}, horizon - available, context.spatial._exposure(context, actor.global_position, threat) * horizon, information)]

func validate(_candidate: Dictionary, visible: bool) -> bool:
	return not visible and is_enabled() and utility_available()

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	context.utility_suppression_pending = false
	on_target_lost()
	_running = active
	return active

func valid(visible: bool) -> bool:
	return _running and active and not visible and actor.can_use_firearms()

func tick(delta: float, visible: bool) -> Dictionary:
	step(delta, visible)
	_running = active
	return motion(Vector3.ZERO, 1.0, aim_point - actor.global_position, {"owner": action_id, "mode": &"memory", "point": aim_point} if active else {})

func on_event(event: StringName, _data: Dictionary) -> void:
	if event == &"damage" and _running:
		reset()
		_running = false
