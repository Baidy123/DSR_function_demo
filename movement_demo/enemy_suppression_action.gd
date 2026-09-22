extends "res://enemy_action.gd"

## 朝最后目击位置附近压制的最短秒数；当前未接弹匣。
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



func is_active() -> bool:
	return active


func reset() -> void:
	active = false
	remaining = 0.0


# 只在真实目击从有到无时调用；持续看不见不会每帧重启。
func on_target_lost() -> void:
	if not is_enabled():
		return
	if active or not tactics.can_suppress_fire or tactics.cover.is_active():
		return
	if actor.is_dead or not actor.shooting_enabled or actor.weapon == null or not ai.is_arena_active():
		return
	if ai.combat_type != ai.CombatType.RANGED or not ai.has_visual_memory or ai.player.is_dead() or ai.player.is_in_dialogue:
		return
	var center: Vector3 = ai.last_seen_position + Vector3.UP * 0.8
	if actor.get_shot_origin().distance_to(center) > actor.weapon.fire_range:
		return
	if not _prepare_targets(center):
		return
	ai.cancel_action(&"attack_position")
	tactics.ranged_has_destination = false
	target_center = center
	remaining = randf_range(maxf(0.1, duration_min), maxf(maxf(0.1, duration_min), duration_max))
	active = true
	ai.state = ai.State.HOLD_POSITION
	actor.agent.target_position = actor.global_position
	_select_aim_point()
	if ai.cover_selection.debug_cover_selection:
		print("[AI][压制] ", state_label(), "开始，最后目击区域=", target_center, "，持续=", snappedf(remaining, 0.01), "秒")


func step(delta: float, sees_player: bool) -> Vector3:
	if not active:
		return Vector3.ZERO
	if sees_player:
		finish(true)
		return Vector3.ZERO
	if not is_enabled() or not tactics.can_suppress_fire or actor.weapon == null or not actor.shooting_enabled or ai.combat_type != ai.CombatType.RANGED or not _targets_available():
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
func _prepare_targets(_center: Vector3) -> bool:
	return true


func _targets_available() -> bool:
	return true


func state_label() -> String:
	return "火力压制"


func _select_aim_point() -> void:
	var angle := randf() * TAU
	var radius := sqrt(randf()) * maxf(0.0, target_radius)
	aim_point = target_center + Vector3(cos(angle), 0.0, sin(angle)) * radius
	# 中心已在启动时核实射程。边缘采样越界则回退中心，避免永远等不到一枪。
	if actor.weapon != null and actor.get_shot_origin().distance_to(aim_point) > actor.weapon.fire_range:
		aim_point = target_center


func finish(sees_player: bool) -> void:
	reset()
	tactics.ranged_has_destination = false
	tactics.ranged_repath_timer = 0.0
	actor.agent.target_position = actor.global_position
	if sees_player:
		ai.state = ai.State.REPOSITION
	else:
		ai.search.begin_tracking_or_search(true)
	if ai.cover_selection.debug_cover_selection:
		print("[AI][压制] 结束，", "重新目击并恢复交战" if sees_player else "回到追踪／搜索")
