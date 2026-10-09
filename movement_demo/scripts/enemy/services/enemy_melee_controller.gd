extends RefCounted

## 仅执行已选动作提交的近战意图；不选择目标或战术，不使用玩家近战代码。
enum Phase { READY, WINDUP, RECOVERY }
var context
var phase := Phase.READY
var elapsed := 0.0
var owner: StringName = &""
var settings: Dictionary = {}
var direction := Vector3.FORWARD
var _weapon: WeaponData
var _target: Node3D


func setup(shared_context) -> void:
	context = shared_context


func detach() -> void:
	cancel()
	context = null


func weapon_settings() -> Dictionary:
	var weapon: WeaponData = context.actor.weapon
	if weapon == null: return {}
	return {"damage": maxf(0.0, weapon.melee_damage), "range": maxf(0.1, weapon.melee_range),
		"angle": clampf(weapon.melee_angle_degrees, 1.0, 180.0), "height": maxf(0.0, weapon.melee_height_tolerance),
		"windup": maxf(0.0, weapon.melee_windup_seconds), "recovery": maxf(0.0, weapon.melee_recovery_seconds),
		"interval": maxf(0.0, weapon.melee_interval), "distance": maxf(0.0, weapon.melee_knockback_distance),
		"duration": maxf(0.05, weapon.melee_knockback_seconds),
		"slow_multiplier": weapon.melee_slow_multiplier, "slow_seconds": weapon.melee_slow_seconds}


func can_request(visible: bool) -> bool:
	if not visible or not _environment_valid() or not context.actor.can_melee(): return false
	return context.actor.melee_target_reachable(context.player, weapon_settings(), _forward())


func is_active_for(action_id: StringName) -> bool:
	return context != null and phase != Phase.READY and owner == action_id and context.actor.melee_active


## 行为只查询执行许可；阶段如何划分由控制器和身体内部维护。
func allows_movement(action_id: StringName) -> bool:
	return is_active_for(action_id) and context.actor.can_move()


## 表现读取独立快照，不参与执行许可判断，也不能修改控制器进度。
func presentation_state() -> Dictionary:
	var active := is_active_for(owner)
	return {"active": active, "phase": phase if active else Phase.READY, "progress": progress() if active else 0.0}


func progress() -> float:
	if phase == Phase.READY: return 0.0
	return clampf(elapsed / maxf(0.001, settings.windup + settings.recovery), 0.0, 1.0)


func update(delta: float, visible: bool, intent: Dictionary) -> void:
	if context.get_tree().paused: return
	var requested: StringName = intent.get("owner", &"")
	var authorized: bool = not requested.is_empty() and context.can_use_action(requested) and context.utility_current.get("id", &"") == requested
	if not authorized or not _environment_valid():
		cancel()
		return
	if phase != Phase.READY and (owner != requested or not context.actor.melee_active or context.actor.weapon != _weapon):
		cancel()
		return
	if phase == Phase.READY:
		if not can_request(visible): return
		owner = requested
		settings = weapon_settings()
		_weapon = context.actor.weapon
		_target = context.player
		direction = _forward()
		elapsed = 0.0
		phase = Phase.WINDUP
		if not context.actor.begin_melee(maxf(settings.interval, settings.windup + settings.recovery)):
			cancel()
			return
	# 正常失视取消；离开距离但仍可见则允许挥空，命中以出手时几何为准。
	if not visible or not context.perception.can_see_player():
		cancel()
		return
	elapsed += maxf(0.0, delta)
	if phase == Phase.WINDUP and elapsed + 0.000001 >= float(settings.windup):
		phase = Phase.RECOVERY
		context.actor.execute_melee(_target, settings, direction)
		if phase == Phase.READY: return # 受击回调可能取消或卸载动作。
	if elapsed + 0.000001 >= float(settings.windup + settings.recovery):
		cancel(false)


func cancel(cancelled: bool = true) -> void:
	phase = Phase.READY
	elapsed = 0.0
	owner = &""
	settings = {}
	_weapon = null
	_target = null
	if context != null: context.actor.cancel_melee(cancelled)


func _environment_valid() -> bool:
	return context != null and not context.actor.is_dead and context.is_arena_active() and context.arena_zone.monitoring and not context.player.is_dead() and not context.player.is_in_dialogue


func _forward() -> Vector3:
	var facing: Vector3 = -context.actor.global_basis.z
	facing.y = 0.0
	return facing.normalized()
