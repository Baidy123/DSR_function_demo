extends CharacterBody3D

@onready var debug_settings = get_node("/root/DebugSettings")

const BodyMotion = preload("res://scripts/enemy/services/enemy_body_motion.gd")
var body_motion = BodyMotion.new()
@export_group("Posture")
const standing_height := 1.75
@export var crouching_height := 1.0
@export var standing_eye_height := 1.55
@export var crouching_eye_height := 0.88
@export var standing_muzzle_height := 1.30
@export var crouching_muzzle_height := 0.72
@export var posture_seconds := 0.20
@export var crouching_speed_multiplier := 0.5

const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
const ImpactEffects = preload("res://scripts/systems/effects/impact_effects.gd")
var ammo = Ammo.new()
## 身体执行层不读取玩家位置，也不决定追踪、搜索或掩体策略。
signal hit_received(damage: float, attacker_position: Vector3)
signal reset_completed
signal shot_fired
signal died
signal vault_landed
signal melee_started
signal melee_struck(target: Node3D, settings: Dictionary, direction: Vector3)
signal melee_finished(cancelled: bool)

# 冷却只由身体物理更新推进；阶段与参数快照属于敌人的近战控制器。
var melee_active := false
var melee_cooldown := 0.0
var melee_count := 0
var _melee_hit_used := false

## 基础移动速度（米/秒）；AI 可给当前行动提供速度倍率。
@export var move_speed: float = 2.0
## 身体每秒最多转动的角度（度/秒）。
@export var turn_speed_degrees: float = 360.0
## 出生、离场刷新和重新开始时恢复的生命值。
@export var max_health: float = 100.0

@export_group("移动声音")
## 实际水平移动时发声，0关闭；敌人听觉会忽略自己及队友的声音。
@export_range(0.0, 100.0, 0.5) var movement_noise_radius: float = 3.0
## 执行移动的速度倍率大于 1 时使用，普通移动和慢走使用普通半径。
var _legacy_fast_radius := -1.0
var _fast_multiplier_explicit := false
@export_storage var fast_movement_noise_radius: float = -1.0:
	get: return _legacy_fast_radius if _legacy_fast_radius >= 0.0 else movement_noise_radius * fast_noise_multiplier
	set(value):
		if not is_finite(value): return
		if is_node_ready(): _fast_multiplier_explicit = false
		elif _fast_multiplier_explicit: return
		_legacy_fast_radius = maxf(0.0, value)
		if is_node_ready(): _normalize_legacy_noise_radius()
## 隔墙衰减与预留音频，留空关闭移动声。
@export_range(0.0, 4.0, 0.05) var crouching_noise_multiplier := 0.5
@export_range(0.0, 4.0, 0.05) var fast_noise_multiplier := 2.0:
	set(value):
		fast_noise_multiplier = maxf(0.0, value) if is_finite(value) else 0.0
		_fast_multiplier_explicit = true
		_legacy_fast_radius = -1.0
@export var movement_noise: NoiseData = preload("res://resources/noise/movement_noise.tres")
## 持续移动时的发声间隔（秒）；刚开始移动立即发声。
@export_range(0.05, 2.0, 0.05) var movement_noise_interval: float = 0.4
var _movement_noise_timer: float = 0.0
var _status_text: String = ""

@export_group("Shooting")
## 是否允许执行射击；可暂时关闭以单独观察移动和掩体行为。
@export var shooting_enabled: bool = true
## 武器类型及攻击参数；近战武器不启用射击，远程武器使用原中心概率模式。
## 运行时换枪调用 equip_weapon；反应时间与连射节奏仍由 AI/Tactics 决定。
@export var weapon: WeaponData
## 枪口瞄准方向的最大跟随角速度（度/秒），独立于身体转速。
@export_range(1.0, 720.0, 1.0) var aim_turn_speed_degrees: float = 90.0
## 输出每枪结果到 Godot 输出面板；玩家受伤/无敌日志不受此开关影响。
@export var debug_shooting: bool = false

# 首次追上才可开火；持续目击后的转向允许留下误差，不要求每枪重新锁准。
const AIM_ACQUIRE_ANGLE: float = deg_to_rad(3.0)
const MAX_GUN_BODY_ANGLE: float = deg_to_rad(30.0)
var aim_direction: Vector3 = Vector3.FORWARD
var has_aim: bool = false
var aim_acquired: bool = false
var shot_cooldown: float = 0.0
var shot_count: int = 0
var last_shot_collider: Object
var last_shot_direction: Vector3 = Vector3.ZERO
# weapon_stability保留旧内部名称，当前含义为中心概率；每个持枪者独立保存。
var weapon_stability: float = 1.0
var weapon_recovery_timer: float = 0.0
var _weapon_move_distance: float = 0.0
var _last_visible_point: Vector3 = Vector3.INF
# 射击取样不消耗全局随机序列，避免改变巡逻/搜索/掩体的随机选择。
var _shot_rng := RandomNumberGenerator.new()

var health: float = 100.0
var is_dead: bool = false
var initial_transform: Transform3D
var initial_body_transform: Transform3D
var death_tween: Tween
var _hit_push_velocity: Vector3 = Vector3.ZERO
var _hit_push_remaining: float = 0.0
var _hit_push_duration: float = 0.0
var _last_move_physics_frame: int = -1
var _melee_accuracy_frame: int = -1

@onready var agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	# AI 先提交正常移动；身体最后只补上尚未被推进的受击移动。
	process_physics_priority = 100
	debug_settings.changed.connect(_apply_debug_mode)
	_apply_debug_mode(debug_settings.enabled)
	_shot_rng.randomize()
	initial_transform = transform
	initial_body_transform = $Body.transform
	_normalize_legacy_noise_radius()
	body_motion.setup(self)
	reset_target()


func _physics_process(delta: float) -> void:
	if weapon != null and not can_equip_weapon(weapon):
		push_warning("当前兵种不能装备专用近战武器，已取消攻击并卸下武器。")
		equip_weapon(null)
	body_motion.update_posture(delta)
	if body_motion.active() and _last_move_physics_frame != Engine.get_physics_frames():
		_last_move_physics_frame = Engine.get_physics_frames()
		body_motion.advance(delta)
	melee_cooldown = maxf(0.0, melee_cooldown - maxf(0.0, delta))
	if is_zero_approx(melee_cooldown): melee_cooldown = 0.0
	# 未激活或暂停 AI 时仍能承受物理击退；正常移动过的帧不会重复移动。
	if not is_dead and _hit_push_remaining > 0.0 and _last_move_physics_frame != Engine.get_physics_frames():
		move_character(Vector3.ZERO, delta)


## 执行方向与速度；调用者负责决定目的地。
func move_character(direction: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	if get_tree().paused: return
	if body_motion.active():
		if _last_move_physics_frame == Engine.get_physics_frames(): return
		_last_move_physics_frame = Engine.get_physics_frames()
		body_motion.advance(delta)
		return
	if is_dead: return
	# 自主移动与受击外力分开：任何行为都不能绕过前摇限制。
	if not can_move(): direction = Vector3.ZERO
	speed_multiplier = get_effective_movement_multiplier(speed_multiplier)
	velocity.x = direction.x * move_speed * speed_multiplier
	velocity.z = direction.z * move_speed * speed_multiplier
	velocity += _advance_hit_push(delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	var before: Vector3 = global_position
	_last_move_physics_frame = Engine.get_physics_frames()
	move_and_slide()
	_weapon_move_distance += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_update_movement_noise(delta, before, speed_multiplier > 1.0)


## 条件查询与实际执行共用；不读取 AI、行为 ID 或控制器阶段。
func can_move() -> bool:
	return not is_dead and not is_vaulting() and not get_tree().paused and (not melee_active or _melee_hit_used)


func can_turn() -> bool:
	return not is_dead and not is_vaulting() and not get_tree().paused and not melee_active


## 换弹可走可转，但快速移动最多按普通速度执行；慢走保持原倍率。
## 行动层估算移动时限时也使用同一限制。
func get_effective_movement_multiplier(requested: float) -> float:
	var effective := minf(requested, 1.0) if ammo.is_reloading or melee_active else requested
	return effective * lerpf(1.0, crouching_speed_multiplier, body_motion.amount)


func _update_movement_noise(delta: float, before_move: Vector3, fast_movement: bool = false) -> void:
	var distance := Vector2(global_position.x - before_move.x, global_position.z - before_move.z).length()
	if is_dead or distance <= 0.0001:
		_movement_noise_timer = 0.0
		return
	_movement_noise_timer = maxf(0.0, _movement_noise_timer - delta)
	if _movement_noise_timer <= 0.0:
		if movement_noise != null:
			movement_noise.emit_from(self, get_movement_noise_radius(fast_movement))
		_movement_noise_timer = maxf(0.05, movement_noise_interval)



func face_direction(direction: Vector3, delta: float) -> void:
	if not can_turn():
		return
	if Vector2(direction.x, direction.z).is_zero_approx():
		return

	rotation.y = rotate_toward(
		rotation.y,
		atan2(-direction.x, -direction.z),
		deg_to_rad(turn_speed_degrees) * delta
	)



func receive_hit(damage: float, attacker_position: Vector3 = Vector3.INF) -> void:
	if is_dead:
		return
	health = maxf(0.0, health - maxf(damage, 0.0))
	if health <= 0.0:
		is_dead = true
		cancel_melee()
		_clear_hit_push()
		cancel_reload()
		clear_aim()
		velocity = Vector3.ZERO
		remove_from_group("combat_target")
		if is_vaulting(): body_motion.interrupt()
		else: $CollisionShape3D.set_deferred("disabled", true)
		$FrontMarker.hide()
		var presentation := get_node_or_null("Presentation")
		if presentation == null or not presentation.has_method("has_model") or not presentation.has_model():
			death_tween = create_tween().set_parallel(true)
			death_tween.tween_property($Body, "rotation:x", PI / 2.0, 0.3)
			death_tween.tween_property($Body, "position:y", 0.35, 0.3)
		died.emit()
	_update_health_label()
	hit_received.emit(damage, attacker_position)


## 敌人自身的近战受击入口。只接收结果，不读取玩家或选择战术。
func receive_melee_hit(damage: float, attacker_position: Vector3, distance: float,
		duration: float, fallback_direction: Vector3 = Vector3.FORWARD) -> void:
	if is_dead or get_tree().paused: return
	receive_hit(damage, attacker_position)
	weapon_stability = 0.0
	weapon_recovery_timer = maxf(0.0, weapon.get_aim_settings(false).delay) if weapon != null else 0.0
	_melee_accuracy_frame = Engine.get_physics_frames()
	if is_dead: return
	if is_vaulting(): body_motion.interrupt()
	var direction := global_position - attacker_position
	direction.y = 0.0
	if direction.is_zero_approx():
		direction = Vector3(fallback_direction.x, 0.0, fallback_direction.z)
	_hit_push_duration = maxf(0.05, duration)
	_hit_push_remaining = _hit_push_duration if distance > 0.0 else 0.0
	_hit_push_velocity = direction.normalized() * (2.0 * maxf(0.0, distance) / _hit_push_duration)


func _advance_hit_push(delta: float) -> Vector3:
	if _hit_push_remaining <= 0.0 or delta <= 0.0: return Vector3.ZERO
	# 积分线性衰减速度，以本帧平均速度交给 move_and_slide；尾帧不多推一步。
	var elapsed := minf(delta, _hit_push_remaining)
	var before := _hit_push_remaining / _hit_push_duration
	_hit_push_remaining = maxf(0.0, _hit_push_remaining - elapsed)
	var after := _hit_push_remaining / _hit_push_duration
	return _hit_push_velocity * (before + after) * 0.5 * elapsed / delta


func _clear_hit_push() -> void:
	_hit_push_velocity = Vector3.ZERO
	_hit_push_remaining = 0.0
	_hit_push_duration = 0.0


func reset_target() -> void:
	body_motion.reset()
	cancel_melee()
	melee_cooldown = 0.0
	melee_count = 0
	_clear_hit_push()
	_melee_accuracy_frame = -1
	_last_move_physics_frame = -1
	_movement_noise_timer = 0.0
	if death_tween != null and death_tween.is_valid():
		death_tween.kill()
	transform = initial_transform
	$Body.transform = initial_body_transform
	$FrontMarker.show()
	$CollisionShape3D.set_deferred("disabled", false)
	add_to_group("combat_target")
	health = max_health
	equip_weapon(weapon)
	clear_aim()
	shot_cooldown = 0.0
	shot_count = 0
	last_shot_collider = null
	last_shot_direction = Vector3.ZERO
	is_dead = false
	velocity = Vector3.ZERO
	agent.target_position = global_position
	_update_health_label()
	reset_completed.emit()


func _apply_debug_mode(_enabled: bool) -> void:
	_refresh_status_label()


## AI 的动作文字仅 Debug 显示，真实换弹进度在普通游戏中也显示。
func set_status_text(text: String) -> void:
	_status_text = text
	_refresh_status_label()

func _refresh_status_label() -> void:
	if not is_instance_valid(debug_settings): return
	var reload_text := ""
	# 换弹属于武器状态，与当前战术动作并行；动作改名不能隐藏真实进度。
	if weapon != null and ammo.is_reloading:
		var remaining: float = maxf(0.1, weapon.reload_seconds) * (1.0 - ammo.reload_progress)
		reload_text = "换弹 %d%% · 剩余 %.1f 秒" % [floori(ammo.reload_progress * 100.0), remaining]
	$Label.visible = debug_settings.enabled or not reload_text.is_empty()
	$Label.text = _status_text + ("\n" + reload_text if not reload_text.is_empty() else "") if debug_settings.enabled else reload_text


func _update_health_label() -> void:
	set_status_text("敌人：%s\n生命 %d / %d" % [
		"已死亡" if is_dead else "待命", ceili(health), ceili(max_health)
	])



## 由决策层每帧调用一次；INF 表示没有可见瞄准点，冷却仍继续计时。
func update_weapon(delta: float, visible_point: Vector3 = Vector3.INF) -> void:
	var elapsed: float = maxf(delta, 0.0)
	shot_cooldown = maxf(0.0, shot_cooldown - elapsed)
	if not can_use_firearms():
		cancel_reload()
	var was_reloading: bool = ammo.is_reloading
	if not is_vaulting(): ammo.advance_reload(elapsed)
	_refresh_status_label()
	var can_aim: bool = not is_vaulting() and can_use_firearms() and visible_point.is_finite()
	if was_reloading:
		_hold_reload_accuracy()
		_weapon_move_distance = 0.0
		_last_visible_point = visible_point if can_aim else Vector3.INF
	else:
		_update_weapon_stability(elapsed, visible_point if can_aim else Vector3.INF)
	if not can_aim:
		clear_aim()
		return
	var desired: Vector3 = visible_point - get_shot_origin()
	if desired.is_zero_approx():
		clear_aim()
		return
	desired = desired.normalized()
	if not has_aim:
		aim_direction = -global_basis.z.normalized()
		has_aim = true
	var angle: float = aim_direction.angle_to(desired)
	var step: float = deg_to_rad(maxf(0.0, aim_turn_speed_degrees)) * maxf(delta, 0.0)
	if angle <= step:
		aim_direction = desired
	elif step > 0.0:
		var axis: Vector3 = aim_direction.cross(desired)
		# 正好相反时叉积为零，选稳定的垂直轴完成转向。
		if axis.is_zero_approx():
			axis = aim_direction.cross(Vector3.UP if absf(aim_direction.y) < 0.999 else Vector3.RIGHT)
		aim_direction = aim_direction.rotated(axis.normalized(), step).normalized()
	if aim_direction.angle_to(desired) <= AIM_ACQUIRE_ANGLE:
		aim_acquired = true


func clear_aim() -> void:
	has_aim = false
	aim_acquired = false
	_last_visible_point = Vector3.INF
	if weapon != null:
		weapon_stability = minf(weapon_stability, weapon.get_aim_settings(false).initial)


## 不修改共享资源，也不通过换枪清掉尚未结束的开火冷却。
func equip_weapon(data: WeaponData) -> void:
	if not can_equip_weapon(data):
		push_warning("专用近战武器只允许具备近战装备资格的兵种使用。")
		if can_equip_weapon(weapon): return # 运行时拒绝错误请求，保留原有效武器。
		data = null # 出生场景误配的武器不能成为有效装备。
	cancel_melee()
	cancel_reload()
	weapon = data
	ammo = Ammo.new(data, {}, true)
	weapon_stability = weapon.get_aim_settings(false).initial if weapon != null else 0.0
	weapon_recovery_timer = 0.0
	_weapon_move_distance = 0.0
	clear_aim()


func can_equip_weapon(data: WeaponData) -> bool:
	if data == null or data.fire_mode != WeaponData.FireMode.MELEE: return true
	var unit = get_node_or_null("UnitType")
	return unit != null and unit.supports_melee_weapons()


## 查询身体／武器执行条件，不决定换弹时机。敌人备弹无限、弹匣有限。
func can_reload() -> bool:
	return not is_vaulting() and not melee_active and can_use_firearms() and not get_tree().paused and ammo.can_reload()


func request_reload() -> bool:
	if not can_reload():
		return false
	if not ammo.start_reload(): return false
	_hold_reload_accuracy()
	_refresh_status_label()
	return true

func _hold_reload_accuracy() -> void:
	weapon_stability = 0.0
	weapon_recovery_timer = maxf(0.0, weapon.get_aim_settings(false).delay) if weapon != null else 0.0

## 身体只执行精度损失；惩罚参数由公共射击服务从本敌人的训练快照读取。
func apply_aim_penalty(amount: float) -> void:
	if not can_use_firearms() or not is_finite(amount) or amount <= 0.0: return
	weapon_stability = clampf(weapon_stability - amount, 0.0, 1.0)
	weapon_recovery_timer = maxf(weapon_recovery_timer, weapon.get_aim_settings(false).delay)


func cancel_reload() -> void:
	ammo.cancel_reload()
	_refresh_status_label()


func get_center_probability() -> float:
	return clampf(weapon_stability, 0.0, 1.0) if weapon != null else 0.0


func get_max_shot_deviation_degrees() -> float:
	return 20.0


func _update_weapon_stability(delta: float, visible_point: Vector3) -> void:
	var distance: float = _weapon_move_distance
	_weapon_move_distance = 0.0
	if _melee_accuracy_frame == Engine.get_physics_frames():
		_last_visible_point = visible_point
		return
	if weapon == null or is_dead:
		return
	var settings: Dictionary = weapon.get_aim_settings(false)
	var target_moving := false
	if visible_point.is_finite() and _last_visible_point.is_finite():
		var target_distance: float = visible_point.distance_to(_last_visible_point)
		target_moving = target_distance > 0.0001
		if target_moving and weapon_stability > settings.target_floor:
			var speed: float = target_distance / maxf(delta, 0.0001)
			var loss: float = lerpf(settings.slow, settings.fast, clampf(speed / maxf(settings.fast_speed, 0.01), 0.0, 1.0))
			weapon_stability = maxf(settings.target_floor, weapon_stability - target_distance * loss)
	_last_visible_point = visible_point
	if distance > 0.0001:
		if weapon_stability > settings.moving_cap:
			weapon_stability = maxf(settings.moving_cap, weapon_stability - distance * settings.player_move_loss)
		weapon_recovery_timer = settings.delay
	elif not target_moving or weapon_stability < settings.target_floor:
		# 与玩家一致：目标仍移动时，只允许更差的精度恢复到跟枪惩罚下限。
		var recovery_delta: float = maxf(0.0, delta - weapon_recovery_timer)
		weapon_recovery_timer = maxf(0.0, weapon_recovery_timer - delta)
		weapon_stability = minf(settings.target_floor if target_moving else 1.0, weapon_stability + settings.recovery * recovery_delta)


func get_shot_origin() -> Vector3:
	return get_muzzle_position()


## AI选择与基础执行共用枪械资格；不依赖AI、Training或战术动作清单。
## 缺少兵种时不启用枪械，移动、转向等公共身体操作不受影响。
func can_use_firearms() -> bool:
	if is_dead or not shooting_enabled or weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE:
		return false
	var unit = get_node_or_null("UnitType")
	return unit != null and unit.supports_firearms()


## 纯查询执行条件；让评分只在枪械确实能发射时积累主动等待时间。
func can_fire() -> bool:
	if is_vaulting(): return false
	if get_tree().paused or melee_active or not can_use_firearms() or not ammo.can_fire():
		return false
	if not has_aim or not aim_acquired or shot_cooldown > 0.0:
		return false
	# 不从身体背后开枪；只检查水平夹角，保留上下瞄准。
	var horizontal_aim := Vector3(aim_direction.x, 0.0, aim_direction.z)
	var body_forward := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	if not horizontal_aim.is_zero_approx() and body_forward.angle_to(horizontal_aim) > MAX_GUN_BODY_ANGLE:
		return false
	return true


## 敌人基础近战能力，不查找玩家、读取 AI 或决定何时使用。
func can_melee() -> bool:
	if is_vaulting() or body_motion.amount > 0.0001: return false
	return not is_dead and not get_tree().paused and weapon != null and can_equip_weapon(weapon) and weapon.melee_enabled and not melee_active and melee_cooldown <= 0.0


func begin_melee(interval: float) -> bool:
	if not can_melee(): return false
	cancel_reload()
	clear_aim()
	melee_active = true
	_melee_hit_used = false
	melee_cooldown = maxf(0.0, interval)
	melee_count += 1
	melee_started.emit()
	return true


func cancel_melee(cancelled: bool = true) -> void:
	var active := melee_active
	melee_active = false
	_melee_hit_used = false
	if active: melee_finished.emit(cancelled)


## 纯几何查询；目标由调用者传入，不从隐藏目标获取决策信息。
func melee_target_reachable(target: Node3D, settings: Dictionary, direction: Vector3) -> bool:
	if not is_instance_valid(target) or not target.is_inside_tree() or target.is_queued_for_deletion(): return false
	var offset := target.global_position - global_position
	if absf(offset.y) > float(settings.height): return false
	offset.y = 0.0
	if offset.length() > float(settings.range): return false
	if not offset.is_zero_approx() and direction.dot(offset.normalized()) < cos(deg_to_rad(float(settings.angle) * 0.5)): return false
	var query := PhysicsRayQueryParameters3D.create(get_torso_position(), target.get_torso_position() if target.has_method("get_torso_position") else target.global_position + Vector3.UP * 0.8, 1, [get_rid()])
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and (hit.collider == target or target.is_ancestor_of(hit.collider))


func execute_melee(target: Node3D, settings: Dictionary, direction: Vector3) -> bool:
	if is_dead or get_tree().paused or not melee_active or _melee_hit_used or weapon == null or not can_equip_weapon(weapon): return false
	_melee_hit_used = true
	var hit := melee_target_reachable(target, settings, direction) and target.has_method("receive_melee_hit")
	if hit:
		target.receive_melee_hit(settings.damage, global_position, settings.distance, settings.duration, direction)
	# 受击可能导致世界暂停或死亡取消，表现层仍以当前身体状态为准。
	melee_struck.emit(target if hit else null, settings, direction)
	return hit


## 只执行请求，不寻找玩家或决定行为；实际射线围绕当前枪口方向取样。
func try_fire() -> bool:
	if not can_fire():
		return false
	ammo.consume_round()
	var probability: float = get_center_probability()
	last_shot_direction = _random_shot_direction(aim_direction, probability)
	var origin: Vector3 = get_shot_origin()
	var endpoint: Vector3 = origin + last_shot_direction * maxf(0.0, weapon.fire_range)
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, [get_rid()])
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	var effects := ImpactEffects.find_for(self)
	var impact = effects.capture_hit(hit, last_shot_direction, self) if effects != null else null
	last_shot_collider = hit.get("collider")
	shot_count += 1
	if weapon.shot_noise != null:
		weapon.shot_noise.emit_from(self, weapon.shot_noise_radius)
	shot_cooldown = maxf(0.05, weapon.shot_interval)
	var settings: Dictionary = weapon.get_aim_settings(false)
	if weapon_stability > settings.shot_floor:
		weapon_stability = maxf(settings.shot_floor, weapon_stability - settings.shot_penalty)
	weapon_recovery_timer = settings.delay
	var hit_player := false
	if not hit.is_empty():
		endpoint = hit.position
		if hit.collider.is_in_group("player"):
			hit.collider.receive_hit(weapon.damage)
			hit_player = true
	# 只通知对方阵营，实际命中不再叠加近弹；线段已在第一处碰撞截断。
	for listener in get_tree().get_nodes_in_group("shot_listener"):
		var receiver: Node = listener.get_parent()
		if receiver.is_in_group("player") and receiver != last_shot_collider:
			listener.notice_shot(origin, endpoint)
	if debug_shooting:
		print("[敌人][开火] ", "命中玩家" if hit_player else ("被物体挡住" if not hit.is_empty() else "未命中"), "；中心概率=", roundi(probability * 100.0), "%")
	_draw_shot(origin, endpoint, hit_player)
	if effects != null: effects.dispatch_impact(impact)
	shot_fired.emit()
	return true


# 与玩家旧模式相同：抽中时直射中心，否则在8～20度范围随机三维偏射。
func _random_shot_direction(forward: Vector3, probability: float) -> Vector3:
	var axis := forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD
	if _shot_rng.randf() < clampf(probability, 0.0, 1.0):
		return axis
	var reference := Vector3.UP if absf(axis.y) < 0.999 else Vector3.RIGHT
	var right := axis.cross(reference).normalized()
	var up := right.cross(axis).normalized()
	var phi := _shot_rng.randf_range(0.0, TAU)
	var angle := deg_to_rad(_shot_rng.randf_range(8.0, get_max_shot_deviation_degrees()))
	return (axis * cos(angle) + (right * cos(phi) + up * sin(phi)) * sin(angle)).normalized()


func _draw_shot(origin: Vector3, endpoint: Vector3, hit_player: bool) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(origin)
	mesh.surface_add_vertex(endpoint)
	mesh.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.2, 0.15) if hit_player else Color(1.0, 0.55, 0.2)
	line.material_override = material
	get_tree().current_scene.add_child(line)
	get_tree().create_timer(0.12, false).timeout.connect(line.queue_free)


func request_crouch(value: bool) -> void:
	body_motion.request_crouch(value)

func begin_vault(plan: Dictionary) -> bool:
	return body_motion.begin(plan)

func is_vaulting() -> bool:
	return body_motion.active()

func get_posture_presentation_state() -> Dictionary:
	return body_motion.presentation_state()

func is_crouching() -> bool:
	return not is_vaulting() and body_motion.amount >= 0.9999

func get_body_height() -> float:
	return body_motion.height()

func get_posture_eye_position(crouched: bool, feet: Vector3 = Vector3.INF) -> Vector3:
	return (global_position if not feet.is_finite() else feet) + Vector3.UP * (crouching_eye_height if crouched else standing_eye_height)

func get_posture_muzzle_position(crouched: bool, feet: Vector3 = Vector3.INF) -> Vector3:
	return (global_position if not feet.is_finite() else feet) + Vector3.UP * (crouching_muzzle_height if crouched else standing_muzzle_height)

func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * lerpf(standing_eye_height, crouching_eye_height, body_motion.amount)

func get_muzzle_position() -> Vector3:
	return global_position + Vector3.UP * lerpf(standing_muzzle_height, crouching_muzzle_height, body_motion.amount)

func get_torso_position() -> Vector3:
	return global_position + Vector3.UP * get_body_height() * 0.6

func get_visibility_points() -> PackedVector3Array:
	var shoulder := get_eye_position() - Vector3.UP * 0.12
	return PackedVector3Array([get_eye_position(), shoulder + global_basis.x * 0.22, shoulder - global_basis.x * 0.22, get_torso_position()])

func get_movement_noise_radius(fast: bool = false) -> float:
	if is_crouching(): return movement_noise_radius * crouching_noise_multiplier
	# Explicit legacy radii remain valid; the default radius follows the new multiplier.
	if fast: return fast_movement_noise_radius
	return movement_noise_radius

func get_posture_body_height(crouched: bool) -> float:
	return maxf(crouching_height, $CollisionShape3D.shape.radius * 2.0) if crouched else standing_height

func _normalize_legacy_noise_radius() -> void:
	if _legacy_fast_radius < 0.0: return
	if movement_noise_radius > 0.0:
		fast_noise_multiplier = _legacy_fast_radius / movement_noise_radius
	elif is_zero_approx(_legacy_fast_radius): fast_noise_multiplier = 0.0

func _validate_property(property: Dictionary) -> void:
	if property.name == "fast_movement_noise_radius" and _legacy_fast_radius < 0.0:
		property.usage &= ~PROPERTY_USAGE_STORAGE
