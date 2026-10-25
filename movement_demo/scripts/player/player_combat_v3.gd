extends Node

const ImpactEffects = preload("res://scripts/systems/effects/impact_effects.gd")
const ShotgunBallistics = preload("res://scripts/weapons/shotgun_ballistics.gd")
var _shotgun_rng := RandomNumberGenerator.new()

@onready var debug_settings = get_node("/root/DebugSettings")

const Ammo = preload("res://scripts/weapons/weapon_ammo.gd")
## 奔跑中开始的慢速换弹进度倍率；整次固定，0.5表示耗时翻倍。
@export_range(0.1, 1.0, 0.05) var sprint_reload_speed_multiplier: float = 0.5
var ammo = Ammo.new()
var _reload_started_sprinting: bool = false
enum AimMode { PROBABILITY, SPREAD_CONE }
## 选择本节点的射击算法；两种模式共用锁定、碰撞和伤害结算。
@export_enum("旧概率模式:0", "新散布锥模式:1") var aim_mode: int = AimMode.SPREAD_CONE

@export_group("目标跟枪精度")
## 目标沿瞄准连线靠近／远离时的免罚半角（度），前后对称；默认两侧各15°，合计30°。
## 超出后按有效横向位移逐渐增加惩罚；0使用纯横向投影。只影响玩家，三种瞄准分支共用。
@export_range(0.0, 45.0, 0.5, "suffix:°") var tracking_parallel_tolerance_degrees: float = 15.0

@export_group("蹲姿精度")
## 仅玩家完成蹲伏时增加的0～1稳定度；0关闭，不改写武器或基础精度。
@export_range(0.0, 1.0, 0.01) var crouch_accuracy_bonus: float = 0.25
var crouch_bonus_blocked_until_recovery: bool = false

@export_group("受击反应倍率")
## 受到攻击武器命中精度损失的倍率，射击与附带近战共用；0免除此项、0.5减半、1正常、2加倍。
## 例如武器损失20%、本值0.5，实际扣10个百分点，精度80%变70%；不改变伤害或擦过影响。
@export_range(0.0, 10.0, 0.05, "suffix:×") var hit_accuracy_loss_multiplier: float = 1.0
## 受到敌方弹道擦过时的精度损失倍率；0关闭该损失、0.5减半、1正常。范围仍由攻击武器决定，不改变命中影响。
@export_range(0.0, 10.0, 0.05, "suffix:×") var suppression_accuracy_loss_multiplier: float = 1.0
## 命中速度损失倍率，射击与附带近战共用；武器减速30%×0.5=减速15%、保留85%速度。
## 0免除减速，1正常，2加倍；只缩放损失，不缩放持续时间、击退或重力，擦过不会减速。
@export_range(0.0, 10.0, 0.05, "suffix:×") var hit_speed_loss_multiplier: float = 1.0

signal weapon_changed(data: WeaponData)
signal shot_fired(hit: bool, stability: float)
signal melee_started
signal melee_struck(target: Node3D)
signal melee_finished

@export_group("近战表现")
## 纯表现剑光；留空关闭特效，近战判定仍正常执行。
@export var melee_effect_scene: PackedScene = preload("res://scenes/effects/melee_slash.tscn")

enum MeleePhase { READY, WINDUP, RECOVERY }
var melee_phase: MeleePhase = MeleePhase.READY
var melee_cooldown: float = 0.0
var melee_elapsed: float = 0.0
var melee_direction: Vector3 = Vector3.FORWARD
var melee_count: int = 0
var last_melee_target: Node3D
var _melee_settings: Dictionary = {}
var _melee_struck: bool = false
var _melee_effect: Node3D
var _melee_region: WeakRef
var _hit_accuracy_frame: int = -1
var _pending_melee_weapon: WeaponData
var _locked_aim_point: Vector3 = Vector3.INF

## 由 Equipment 装备的运行时引用；武器资源只在槽位中配置。
var weapon: WeaponData

var is_aiming: bool = false
var locked_target: Node3D = null
var accuracy: float = 0.5
var shot_cooldown: float = 0.0
var shot_count: int = 0
var last_shot_collider: Object = null
var shot_requested: bool = false
var fire_held: bool = false
var last_result: String = ""
var accuracy_recovery_timer: float = 0.0
var last_target_position: Vector3 = Vector3.ZERO
var has_last_target_position: bool = false
# 每帧移动前记录位置；不把转向、顶墙或跨帧传送当作行走距离。
var player_position_before_move: Vector3 = Vector3.ZERO

@onready var player = get_parent()
@onready var status: Label = $HUD/Panel/Status


func _ready() -> void:
	debug_settings.changed.connect(_apply_debug_mode)
	player.get_node("Health").died.connect(cancel_melee)
	add_to_group("shot_listener")
	equip_weapon(weapon)
	_apply_debug_mode(debug_settings.enabled)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED or what == NOTIFICATION_UNPAUSED:
		_reset_target_movement_tracking()


func _apply_debug_mode(enabled: bool) -> void:
	$HUD/Panel.visible = enabled and not player.is_in_dialogue


## 装备组件调用此接口；切槽传 true 保留上一枪冷却，避免快速切枪绕过射速。
## Resource 只保存配置，不保存运行中的稳定度。
## ammo_state 保留该枪的半程，resume_slow_reload 恢复该槽原有的快慢方式。
func equip_weapon(data: WeaponData, preserve_cooldown: bool = false, ammo_state = null, resume_slow_reload: bool = false) -> void:
	if data != null and data.fire_mode == WeaponData.FireMode.MELEE:
		push_warning("玩家只能装备枪械；专用近战武器仅供近战兵使用。")
		return
	cancel_melee()
	interrupt_reload()
	weapon = data
	ammo = ammo_state if ammo_state != null else Ammo.new(data)
	_reload_started_sprinting = resume_slow_reload
	accuracy = weapon.get_aim_settings(is_using_spread_cone()).initial if weapon != null else 0.0
	accuracy_recovery_timer = 0.0
	crouch_bonus_blocked_until_recovery = false
	cancel_aim()
	if not preserve_cooldown:
		shot_cooldown = 0.0
	last_result = ""
	_resume_reload_if_ready()
	weapon_changed.emit(weapon)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo():
		return
	if event.is_action_pressed("melee"):
		request_melee()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_released("fire"):
		fire_held = false
		return
	if event.is_action_pressed("reload"):
		request_reload()
		get_viewport().set_input_as_handled()
		return
	if is_melee_active() or is_waiting_for_melee_stand() or player.is_vaulting():
		return
	if ammo.is_reloading and ammo.reloads_one_shell_at_a_time() and not player.is_dead() and not player.is_in_dialogue and not get_tree().paused:
		# 只响应新按下的瞄准键；按住右键再按 R 仍可装填。射击中断需已有余弹。
		var aimed_trigger: bool = event.is_action_pressed("fire") and Input.is_action_pressed("aim") and ammo.magazine_rounds > 0 and can_combat()
		if event.is_action_pressed("aim") or aimed_trigger:
			cancel_reload()
	if ammo.is_reloading or ammo.reload_checkpoint > 0.0: return
	if player.is_in_dialogue or weapon == null or not can_combat():
		return
	if event.is_action_pressed("fire") and Input.is_action_pressed("aim"):
		shot_requested = true
		fire_held = true
		get_viewport().set_input_as_handled()


## R主动请求，不要求瞄准或进入战斗区；枪械状态自己检查弹量和备弹。
func request_reload() -> bool:
	if is_melee_active() or is_waiting_for_melee_stand() or player.is_vaulting() or weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE or player.is_dead() or player.is_in_dialogue or get_tree().paused:
		return false
	var resuming: bool = ammo.reload_checkpoint > 0.0
	if resuming and player.is_sprinting and not _reload_started_sprinting:
		return false
	if not ammo.start_reload():
		return false
	_hold_reload_accuracy()
	if not resuming: _reload_started_sprinting = player.is_sprinting
	shot_requested = false
	fire_held = false
	return true


func cancel_reload() -> void:
	ammo.cancel_reload()
	_reload_started_sprinting = false

## 整匣换弹保留已完成的半程；逐发装填仅保留已入匣弹药，取消未完成的本发。
func interrupt_reload() -> void:
	if not ammo.is_reloading: return
	if ammo.reloads_one_shell_at_a_time():
		cancel_reload() # 已装好的弹药保留，未完成的本发不保留半程，也不强制续换。
	else:
		var committed: bool = ammo.reload_checkpoint > 0.0 or ammo.reload_progress >= 0.5 or is_equal_approx(ammo.reload_progress, 0.5)
		ammo.suspend_reload(0.5 if committed else 0.0)
	shot_requested = false
	fire_held = false

func _resume_reload_if_ready() -> void:
	if ammo.reload_checkpoint > 0.0 and not ammo.is_reloading:
		request_reload()

func is_slow_reload() -> bool:
	return _reload_started_sprinting

func _hold_reload_accuracy() -> void:
	accuracy = 0.0
	crouch_bonus_blocked_until_recovery = true
	accuracy_recovery_timer = maxf(0.0, weapon.get_aim_settings(is_using_spread_cone()).delay) if weapon != null else 0.0

## 攻击基础值来自攻击者快照；无来源扣血不调用此入口，也不回退旧角色常量。
func apply_weapon_hit(effects: Dictionary) -> void:
	var loss := _scaled_loss(float(effects.get("hit_accuracy_loss", 0.0)), hit_accuracy_loss_multiplier)
	var melee: bool = effects.get("melee", false)
	_apply_accuracy_loss(loss, melee)
	if melee and loss > 0.0:
		player.get_node("Equipment").apply_stowed_accuracy_loss(loss)
	player.apply_hit_slowdown(_scaled_loss(float(effects.get("hit_speed_loss", 0.0)), hit_speed_loss_multiplier),
		float(effects.get("hit_speed_loss_seconds", 0.0)))

func _scaled_loss(base: float, multiplier: float) -> float:
	if not is_finite(base) or not is_finite(multiplier): return 0.0
	return clampf(maxf(0.0, base) * maxf(0.0, multiplier), 0.0, 1.0)

func _apply_accuracy_loss(loss: float, block_crouch: bool = false) -> void:
	if weapon == null or player.is_dead() or not is_finite(loss) or loss <= 0.0: return
	accuracy = clampf(accuracy - loss, 0.0, 1.0)
	accuracy_recovery_timer = maxf(accuracy_recovery_timer, weapon.get_aim_settings(is_using_spread_cone()).delay)
	if block_crouch:
		_hit_accuracy_frame = Engine.get_physics_frames()
		crouch_bonus_blocked_until_recovery = true

func notice_shot(origin: Vector3, endpoint: Vector3, effects: Dictionary) -> void:
	if weapon == null or player.is_dead() or player.is_in_dialogue or get_tree().paused: return
	var radius: float = effects.get("near_miss_radius", 0.0)
	if not is_finite(radius) or radius <= 0.0: return
	var chest: Vector3 = player.get_torso_position()
	var closest := Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
	if chest.distance_to(closest) > radius: return
	if chest.distance_squared_to(closest) > 0.000001:
		var query := PhysicsRayQueryParameters3D.create(chest, closest, 1, [player.get_rid()])
		query.hit_from_inside = true
		if not player.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return
	_apply_accuracy_loss(_scaled_loss(float(effects.get("suppression_accuracy_loss", 0.0)), suppression_accuracy_loss_multiplier))


func cancel_aim() -> void:
	is_aiming = false
	clear_target_lock()
	shot_requested = false
	fire_held = false
	# 松开再按瞄准不能消除刚刚累积的射击惩罚。
	accuracy = minf(accuracy, weapon.get_aim_settings(is_using_spread_cone()).initial) if weapon != null else 0.0
	$HUD/Reticle.hide()


## 翻越、姿态变化只解除旧目标牵引，不能借取消瞄准改写精度或扳机。
func clear_target_lock() -> void:
	locked_target = null
	_locked_aim_point = Vector3.INF
	_reset_target_movement_tracking()


func begin_vault() -> void:
	_pending_melee_weapon = null
	clear_target_lock()
	shot_requested = false
	interrupt_reload()


func get_locked_aim_point() -> Vector3:
	if _locked_aim_point.is_finite(): return _locked_aim_point
	if is_instance_valid(locked_target):
		return locked_target.get_torso_position() if locked_target.has_method("get_torso_position") else locked_target.global_position + Vector3.UP * 0.8
	return Vector3.INF


func can_combat() -> bool:
	if player.is_dead():
		return false
	# 查询实际重叠区域；支持多个区域重叠，不需要全局开关。
	for area in get_tree().get_nodes_in_group("combat_zone"):
		if area is Area3D and area.monitoring and area.overlaps_body(player):
			return true
	return false


# Player 在移动前调用：检查锁定，再由 Player 应用朝向。
func begin_frame(delta: float, aim_pressed: bool) -> void:
	if get_tree().paused: return
	if weapon != null and weapon.fire_mode == WeaponData.FireMode.MELEE:
		equip_weapon(null) # 共享资源运行时被改成近战时，玩家也不能继续使用。
	_advance_melee(delta)
	player_position_before_move = player.global_position
	shot_cooldown = maxf(0.0, shot_cooldown - delta)
	# 0.2秒按60Hz扣减会留下浮点尾差，不能因此让连发额外等待一帧。
	if is_zero_approx(shot_cooldown):
		shot_cooldown = 0.0
	if is_melee_active() or weapon == null or player.is_in_dialogue or not aim_pressed or not can_combat():
		cancel_aim()
		return
	is_aiming = true
	if player.is_vaulting():
		clear_target_lock()
		return
	if is_instance_valid(locked_target) and not _target_visible(locked_target):
		clear_target_lock()
	if not is_instance_valid(locked_target):
		var new_target: Node3D = _find_target()
		if is_instance_valid(new_target):
			locked_target = new_target
			_locked_aim_point = _visible_target_point(new_target)
			_start_target_movement_tracking(new_target)
			# 锁定只改变瞄准目标，不重置当前稳定度。
			# 因此无锁定持续瞄准积累的稳定度会自然带入锁定状态。
	if is_instance_valid(locked_target):
		var direction: Vector3 = locked_target.global_position - player.global_position
		if Vector2(direction.x, direction.z).length_squared() > 0.0001:
			player.visual.global_rotation.y = atan2(-direction.x, -direction.z)


# Player 移动后调用，以实际位移判断移动惩罚，射击使用本帧的视线。
func end_frame(delta: float, moving: bool) -> void:
	if get_tree().paused: return
	var was_reloading: bool = ammo.is_reloading or ammo.reload_checkpoint > 0.0
	if player.is_dead() or player.is_in_dialogue:
		cancel_reload()
	elif not get_tree().paused and not is_melee_active() and not is_waiting_for_melee_stand() and not player.is_vaulting():
		if player.is_sprinting and not _reload_started_sprinting:
			interrupt_reload()
		else:
			_resume_reload_if_ready()
		was_reloading = was_reloading or ammo.is_reloading or ammo.reload_checkpoint > 0.0
		var reload_speed: float = sprint_reload_speed_multiplier if _reload_started_sprinting else 1.0
		ammo.advance_reload(delta, reload_speed)
	if not can_combat() or player.is_in_dialogue:
		cancel_melee()
		cancel_aim()
	if is_instance_valid(locked_target) and not _target_visible(locked_target):
		clear_target_lock()
	if weapon != null:
		# 只有有效的横向跟枪影响才限制恢复；前后移动／免罚范围内仍可逐渐瞄准到最准。
		var tracking_limited: bool = _apply_target_movement_accuracy_penalty(delta)

		var settings: Dictionary = weapon.get_aim_settings(is_using_spread_cone())
		var recovery: float = settings.recovery
		if was_reloading:
			# 完成的这一帧也保持最低，下一帧才开始原恢复等待，避免大delta提前恢复。
			_hold_reload_accuracy()
		elif _hit_accuracy_frame == Engine.get_physics_frames():
			pass # 近战命中的同一物理帧不能立即恢复准度。
		elif moving:
			var displacement: Vector3 = player.global_position - player_position_before_move
			var distance: float = Vector2(displacement.x, displacement.z).length()
			# 两种模式都逐米累积；移动惩罚不能覆盖其他来源造成的更低稳定度。
			if accuracy > settings.moving_cap:
				accuracy = maxf(settings.moving_cap, accuracy - distance * settings.player_move_loss)
				accuracy_recovery_timer = settings.delay
			else:
				# 受击等造成的额外损失允许边走边恢复；走路不能每帧续期这段等待。
				var movement_limit: float = minf(settings.moving_cap, 1.0 if is_aiming else settings.initial)
				if tracking_limited:
					movement_limit = minf(movement_limit, _get_target_move_accuracy_floor())
				if accuracy < movement_limit:
					_recover_accuracy(delta, recovery, movement_limit)
				else:
					accuracy_recovery_timer = settings.delay
		elif tracking_limited:
			# 目标有效横向移动时，若当前稳定度已经低于“移动目标最低稳定度”，
			# 仍允许按正常稳定速度恢复，但最多只恢复到这个下限。
			# 若当前稳定度已经达到/高于该下限，则只承受目标移动惩罚，不再额外恢复，
			# 避免移动惩罚被稳定恢复抵消。
			var movement_floor: float = _get_target_move_accuracy_floor()
			if accuracy < movement_floor:
				_recover_accuracy(delta, recovery, movement_floor)
		else:
			# 瞄准可恢复到100%；未瞄准只恢复到初始值，避免帧尾越过初始散布。
			_recover_accuracy(delta, recovery, 1.0 if is_aiming else settings.initial)
	# 只有未被 UI 消费的按下事件才能启动连发；释放事件即使被 UI 消费也能停火。
	if not was_reloading and _hit_accuracy_frame != Engine.get_physics_frames() and accuracy_recovery_timer <= 0.0:
		crouch_bonus_blocked_until_recovery = false
	if not Input.is_action_pressed("fire"):
		fire_held = false
	var automatic_fire: bool = weapon != null and weapon.fire_mode == WeaponData.FireMode.AUTOMATIC and fire_held
	if shot_requested or automatic_fire:
		shot_requested = false
		shoot()
	_update_status()


func _recover_accuracy(delta: float, recovery: float, limit: float) -> void:
	# 只计入延迟结束后剩余的时间，避免低帧率改变恢复速度。
	var recovery_delta: float = maxf(0.0, delta - accuracy_recovery_timer)
	accuracy_recovery_timer = maxf(0.0, accuracy_recovery_timer - delta)
	accuracy = minf(limit, accuracy + recovery * recovery_delta)


func _start_target_movement_tracking(target: Node3D) -> void:
	if not is_instance_valid(target):
		_reset_target_movement_tracking()
		return
	last_target_position = target.global_position
	has_last_target_position = true


func _reset_target_movement_tracking() -> void:
	has_last_target_position = false
	last_target_position = Vector3.ZERO


func _apply_target_movement_accuracy_penalty(delta: float) -> bool:
	if weapon == null or not is_instance_valid(locked_target):
		_reset_target_movement_tracking()
		return false

	var current_position: Vector3 = locked_target.global_position
	if not current_position.is_finite():
		_reset_target_movement_tracking()
		return false
	var previous_position := last_target_position
	last_target_position = current_position
	if not has_last_target_position:
		has_last_target_position = true
		return false
	if get_tree().paused or not is_finite(delta) or delta <= 0.0: return false

	# 地面位移相对玩家→目标中点投影；玩家自身移动仍由原独立分支处理。
	var offset := current_position - previous_position
	var displacement := Vector2(offset.x, offset.z)
	var moved_distance := displacement.length()
	var relative_midpoint: Vector3 = (previous_position + current_position) * 0.5 - player.global_position
	var axis := Vector2(relative_midpoint.x, relative_midpoint.z)
	if moved_distance <= 0.000001 or not axis.is_finite() or axis.length_squared() <= 0.000001: return false
	var lateral_ratio := clampf(absf(displacement.cross(axis.normalized())) / moved_distance, 0.0, 1.0)
	var tolerance := sin(deg_to_rad(clampf(tracking_parallel_tolerance_degrees, 0.0, 45.0)))
	var lateral_weight := clampf((lateral_ratio - tolerance) / (1.0 - tolerance), 0.0, 1.0)
	var tracking_distance := moved_distance * lateral_weight
	if tracking_distance <= 0.000001: return false

	var settings: Dictionary = weapon.get_aim_settings(is_using_spread_cone())
	var target_speed: float = tracking_distance / delta
	var speed_factor: float = clampf(target_speed / maxf(settings.fast_speed, 0.01), 0.0, 1.0)
	var loss_per_meter: float = lerpf(
		settings.slow,
		settings.fast,
		speed_factor
	)
	var movement_penalty: float = tracking_distance * loss_per_meter
	# 关闭跟枪损失也必须解除恢复限制；更低的精度仍由原有来源／下限控制。
	if movement_penalty <= 0.0: return false

	# “目标移动”只允许把稳定度压到自己的下限；它不会覆盖其他来源已经造成的更低稳定度。
	var movement_floor: float = _get_target_move_accuracy_floor()
	if accuracy > movement_floor:
		accuracy = maxf(movement_floor, accuracy - movement_penalty)
	# 如果稳定度已经被射击/玩家移动等其他因素压到 movement_floor 以下，
	# 目标移动不会反过来提高稳定度，也不会继续额外降低它。
	return true


func _get_target_move_accuracy_floor() -> float:
	if weapon == null:
		return 0.0
	return weapon.get_aim_settings(is_using_spread_cone()).target_floor


func _find_target() -> Node3D:
	var best: Node3D = null
	var best_dot: float = cos(deg_to_rad(weapon.cone_angle_degrees * 0.5))
	var forward: Vector3 = -player.visual.global_basis.z
	for candidate in get_tree().get_nodes_in_group("combat_target"):
		var direction: Vector3 = candidate.global_position - player.global_position
		direction.y = 0.0
		if direction.is_zero_approx():
			continue
		var alignment: float = forward.dot(direction.normalized())
		if alignment >= best_dot and _target_visible(candidate):
			best = candidate
			best_dot = alignment
	return best


func _target_visible(target: Node3D) -> bool:
	var point := _visible_target_point(target)
	if target == locked_target: _locked_aim_point = point
	return point.is_finite()


func _visible_target_point(target: Node3D) -> Vector3:
	if not target.is_inside_tree() or not target.is_in_group("combat_target"):
		return Vector3.INF
	if not preload("res://scripts/systems/combat_view.gd").contains_actor(target):
		return Vector3.INF
	var offset: Vector3 = target.global_position - player.global_position
	if offset.length() > weapon.aim_range:
		return Vector3.INF
	var points: Array[Vector3] = []
	if target.has_method("get_visibility_points"):
		points.assign(target.get_visibility_points())
	else:
		points.append(target.global_position + Vector3.UP * 0.8)
	for point in points:
		var hit := _ray_to(point, player.get_eye_position())
		if not hit.is_empty() and (hit.collider == target or target.is_ancestor_of(hit.collider)):
			return point
	return Vector3.INF


func _ray_to(endpoint: Vector3, origin: Vector3 = Vector3.INF) -> Dictionary:
	if not origin.is_finite(): origin = player.get_muzzle_position()
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, [player.get_rid()])
	query.hit_from_inside = true
	return player.get_world_3d().direct_space_state.intersect_ray(query)


func shoot() -> void:
	if is_melee_active() or is_waiting_for_melee_stand() or player.is_vaulting() or not is_aiming or player.is_in_dialogue or weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE or shot_cooldown > 0.0 or not can_combat():
		return
	if get_tree().paused or not ammo.consume_round():
		return
	# 再检查一次，防止输入与物理更新之间出现遮挡。
	if is_instance_valid(locked_target) and not _target_visible(locked_target):
		clear_target_lock()
	shot_count += 1
	var attack_effects := weapon.get_attack_effects()
	if weapon.shot_noise != null:
		weapon.shot_noise.emit_from(player, weapon.shot_noise_radius)
	shot_cooldown = weapon.shot_interval
	var stability: float = get_effective_accuracy()
	var origin: Vector3 = player.get_muzzle_position()
	var direction: Vector3 = -player.visual.global_basis.z
	var has_lock: bool = is_instance_valid(locked_target)
	if has_lock:
		direction = (get_locked_aim_point() - origin).normalized()

	if weapon.fire_mode == WeaponData.FireMode.SHOTGUN:
		_shoot_shotgun(origin, direction, stability, attack_effects)
		return
	if is_using_spread_cone():
		# 有无锁定都在整个三维锥内取样，稳定度只控制锥的半角。
		direction = _random_direction_in_spread_cone(direction, get_spread_half_angle_degrees())
	elif randf() >= stability:
		# 旧模式保留“直射中心概率 + 8～20度三维偏转”，便于对比手感。
		direction = _random_direction_in_miss_cone(direction, 8.0, 20.0)
	var endpoint: Vector3 = origin + direction * weapon.fire_range
	var hit: Dictionary = _ray_to(endpoint)
	var effects := ImpactEffects.find_for(player)
	var impact = effects.capture_hit(hit, direction, player) if effects != null else null
	last_shot_collider = hit.get("collider")
	var target_hit: bool = false
	if not hit.is_empty():
		endpoint = hit.position
		if hit.collider.is_in_group("combat_target"):
			if hit.collider.has_method("receive_weapon_hit"):
				hit.collider.receive_weapon_hit(weapon.damage, player.global_position, attack_effects)
			else:
				hit.collider.receive_hit(weapon.damage, player.global_position)
			target_hit = true
			if locked_target == hit.collider and not hit.collider.is_in_group("combat_target"):
				clear_target_lock()
				$HUD/Reticle.hide()
	# 使用实际命中点截断后的线段检测近处来弹；墙后的延长线不会触发。
	for listener in get_tree().get_nodes_in_group("shot_listener"):
		if listener.get_parent() != player and listener.get_parent() != last_shot_collider and not listener.get_parent().is_in_group("player"):
			listener.notice_shot(origin, endpoint, attack_effects)
	var settings: Dictionary = weapon.get_aim_settings(is_using_spread_cone())
	accuracy = maxf(minf(accuracy, settings.shot_floor), accuracy - settings.shot_penalty)
	accuracy_recovery_timer = settings.delay
	last_result = "命中" if target_hit else "未命中"
	_draw_shot(origin, endpoint, target_hit)
	if effects != null: effects.dispatch_impact(impact)
	shot_fired.emit(target_hit, stability)
	_update_status()


func _shoot_shotgun(origin: Vector3, direction: Vector3, stability: float, attack_effects: Dictionary) -> void:
	var shotgun := weapon.get_shotgun_settings()
	var pellet_damage := maxf(0.0, shotgun.pellet_damage)
	var pellets := ShotgunBallistics.trace(player, weapon, origin, direction, stability, _shotgun_rng)
	var hits := ShotgunBallistics.count_hits(pellets, &"combat_target")
	var effects := ImpactEffects.find_for(player)
	last_shot_collider = hits.keys()[0] if not hits.is_empty() else pellets[0].collider
	for target in hits:
		if not is_instance_valid(target): continue
		var total_damage: float = pellet_damage * hits[target]
		if target.has_method("receive_weapon_hit"):
			target.receive_weapon_hit(total_damage, player.global_position, attack_effects)
		elif target.has_method("receive_hit"):
			target.receive_hit(total_damage, player.global_position)
	if locked_target != null and (not is_instance_valid(locked_target) or not locked_target.is_in_group("combat_target")):
		clear_target_lock()
		$HUD/Reticle.hide()
	for listener in get_tree().get_nodes_in_group("shot_listener"):
		var receiver := listener.get_parent()
		if not receiver is Node3D or receiver == player or receiver.is_in_group("player") or hits.has(receiver): continue
		var endpoint := ShotgunBallistics.near_miss_endpoint(receiver, origin, pellets, attack_effects.near_miss_radius)
		if endpoint.is_finite(): listener.notice_shot(origin, endpoint, attack_effects)
	var settings := shotgun.get_aim_settings(is_using_spread_cone())
	accuracy = maxf(minf(accuracy, settings.shot_floor), accuracy - settings.shot_penalty)
	accuracy_recovery_timer = settings.delay
	last_result = "命中" if not hits.is_empty() else "未命中"
	for pellet in pellets:
		_draw_shot(origin, pellet.endpoint, hits.has(pellet.collider))
		if effects != null: effects.dispatch_impact(pellet.impact)
	shot_fired.emit(not hits.is_empty(), stability)
	_update_status()


## Combat 检查器选择算法；不重置锁定、稳定度或冷却。
func is_using_spread_cone() -> bool:
	return aim_mode == AimMode.SPREAD_CONE


# 返回围绕 forward 的随机锥形偏移方向。
# min_angle_degrees / max_angle_degrees 控制偏离瞄准中心的最小和最大夹角。
func _random_direction_in_miss_cone(
	forward: Vector3,
	min_angle_degrees: float,
	max_angle_degrees: float
) -> Vector3:
	var cone_axis: Vector3 = forward.normalized()

	# 构造一个与瞄准方向垂直的局部二维平面。
	# 当瞄准方向接近竖直时改用 RIGHT，避免叉乘退化。
	var reference_axis: Vector3 = Vector3.UP
	if absf(cone_axis.dot(reference_axis)) > 0.999:
		reference_axis = Vector3.RIGHT

	var cone_right: Vector3 = cone_axis.cross(reference_axis).normalized()
	var cone_up: Vector3 = cone_right.cross(cone_axis).normalized()

	# phi 决定锥体圆周上的方向，因此上下左右和斜方向都有可能出现。
	var phi: float = randf_range(0.0, TAU)
	var theta: float = deg_to_rad(randf_range(min_angle_degrees, max_angle_degrees))
	var radial: Vector3 = cone_right * cos(phi) + cone_up * sin(phi)

	return (cone_axis * cos(theta) + radial * sin(theta)).normalized()


## 姿态只影响当前有效精度，不改写原惩罚与恢复状态。
func get_effective_accuracy() -> float:
	var base := clampf(accuracy, 0.0, 1.0)
	if crouch_bonus_blocked_until_recovery or ammo.is_reloading or ammo.reload_checkpoint > 0.0:
		return base
	if player != null and player.has_method("is_crouching") and player.is_crouching() and not player.is_vaulting():
		return clampf(base + crouch_accuracy_bonus, 0.0, 1.0)
	return base


## 当前实际弹道半角；准星保留原圆形样式，仅用稳定度表现收拢。
func get_spread_half_angle_degrees() -> float:
	if weapon == null:
		return 0.0
	if weapon.fire_mode == WeaponData.FireMode.SHOTGUN:
		var shotgun := weapon.get_shotgun_settings()
		var extent := 0.0
		for point in shotgun.get_pattern_points(): extent = maxf(extent, point.length())
		return extent * shotgun.pattern_angle_degrees + shotgun.get_jitter_degrees(get_effective_accuracy())
	var minimum: float = clampf(weapon.min_spread_angle_degrees, 0.0, 45.0)
	var maximum: float = clampf(weapon.max_spread_angle_degrees, minimum, 45.0)
	return lerpf(maximum, minimum, get_effective_accuracy())


# 在整个锥内按立体角均匀取样，不再先判定是否直射中心。
func _random_direction_in_spread_cone(forward: Vector3, half_angle_degrees: float) -> Vector3:
	var cone_axis: Vector3 = forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD
	var angle: float = deg_to_rad(clampf(half_angle_degrees, 0.0, 45.0))
	if is_zero_approx(angle):
		return cone_axis
	# 接近竖直方向时换参考轴，避免叉乘退化。
	var reference_axis: Vector3 = Vector3.UP if absf(cone_axis.y) < 0.999 else Vector3.RIGHT
	var cone_right: Vector3 = cone_axis.cross(reference_axis).normalized()
	var cone_up: Vector3 = cone_right.cross(cone_axis).normalized()
	var phi: float = randf_range(0.0, TAU)
	# 均匀取 cos(theta)，避免直接均匀取角度导致弹道过度集中在中心。
	var cosine: float = lerpf(1.0, cos(angle), randf())
	var sine: float = sqrt(maxf(0.0, 1.0 - cosine * cosine))
	var radial: Vector3 = cone_right * cos(phi) + cone_up * sin(phi)
	return (cone_axis * cosine + radial * sine).normalized()


func _draw_shot(origin: Vector3, endpoint: Vector3, hit: bool) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(origin)
	mesh.surface_add_vertex(endpoint)
	mesh.surface_end()
	var line := MeshInstance3D.new()
	line.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.GREEN_YELLOW if hit else Color.ORANGE
	line.material_override = material
	get_tree().current_scene.add_child(line)
	get_tree().create_timer(0.12).timeout.connect(line.queue_free)


## 玩家近战独立函数区；执行保留在现有 Combat，不供敌人调用。
func is_melee_active() -> bool:
	return melee_phase != MeleePhase.READY


func is_waiting_for_melee_stand() -> bool:
	return _pending_melee_weapon != null


func get_melee_progress() -> float:
	if not is_melee_active(): return 0.0
	return clampf(melee_elapsed / maxf(0.001, _melee_settings.windup + _melee_settings.recovery), 0.0, 1.0)


func request_melee() -> bool:
	if weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE or not weapon.melee_enabled or is_melee_active() or is_waiting_for_melee_stand() or player.is_vaulting() or melee_cooldown > 0.0:
		return false
	if not can_combat() or player.is_in_dialogue or get_tree().paused: return false
	if not is_finite(weapon.melee_stamina_cost) or weapon.melee_stamina_cost < 0.0 or player.stamina < weapon.melee_stamina_cost: return false
	if player.crouch_amount > 0.0001:
		if not player.can_stand(): return false
		_pending_melee_weapon = weapon
		_bind_melee_region()
		return true
	# 通过全部攻击资格后才扣体力；失败请求不会打断换弹或消耗冷却。
	if not player.try_consume_stamina(weapon.melee_stamina_cost): return false
	# 一次挥击固定配置；资源调参、切槽或动画长度都不能改变已开始的命中。
	_melee_settings = {
		"damage": maxf(0.0, weapon.melee_damage), "range": maxf(0.1, weapon.melee_range),
		"angle": clampf(weapon.melee_angle_degrees, 1.0, 180.0),
		"height": maxf(0.0, weapon.melee_height_tolerance),
		"windup": maxf(0.0, weapon.melee_windup_seconds),
		"recovery": maxf(0.0, weapon.melee_recovery_seconds),
		"distance": maxf(0.0, weapon.melee_knockback_distance),
		"duration": maxf(0.05, weapon.melee_knockback_seconds),
		"effects": weapon.get_attack_effects(true),
	}
	melee_direction = -player.global_basis.z
	melee_direction.y = 0.0
	melee_direction = melee_direction.normalized()
	if melee_direction.is_zero_approx(): melee_direction = Vector3.FORWARD
	melee_cooldown = maxf(weapon.melee_interval, _melee_settings.windup + _melee_settings.recovery)
	melee_elapsed = 0.0
	_melee_struck = false
	last_melee_target = null
	melee_phase = MeleePhase.WINDUP
	interrupt_reload()
	cancel_aim()
	player.is_sprinting = false
	player.current_speed = minf(player.current_speed, player.move_speed)
	_bind_melee_region()
	melee_count += 1
	melee_started.emit()
	return true


func _bind_melee_region() -> void:
	_melee_region = null
	# 只绑定本次所在区域；其他靶场复位不会取消这次攻击。
	for zone in get_tree().get_nodes_in_group("combat_zone"):
		if zone is Area3D and zone.monitoring and zone.overlaps_body(player):
			var region: Node = zone.get_parent()
			if region.has_signal("presentation_reset"):
				_melee_region = weakref(region)
				if not region.presentation_reset.is_connected(_on_melee_region_reset):
					region.presentation_reset.connect(_on_melee_region_reset)
				break


func _advance_melee(delta: float) -> void:
	if get_tree().paused: return
	var elapsed := maxf(0.0, delta)
	melee_cooldown = maxf(0.0, melee_cooldown - elapsed)
	if is_zero_approx(melee_cooldown): melee_cooldown = 0.0
	if is_waiting_for_melee_stand():
		if weapon != _pending_melee_weapon or not can_combat() or player.is_in_dialogue or player.is_vaulting() or not player.can_stand() or player.stamina < weapon.melee_stamina_cost:
			_pending_melee_weapon = null
			return
		if player.crouch_amount > 0.0001: return
		_pending_melee_weapon = null
		request_melee()
	if not is_melee_active(): return
	if not can_combat() or player.is_in_dialogue or weapon == null or weapon.fire_mode == WeaponData.FireMode.MELEE:
		cancel_melee()
		return
	melee_elapsed += elapsed
	if not _melee_struck and melee_elapsed + 0.000001 >= float(_melee_settings.windup):
		_melee_struck = true
		melee_phase = MeleePhase.RECOVERY
		_execute_player_melee()
		# 受击回调可能触发场景复位并取消本次动作。
		if not is_melee_active(): return
	if melee_elapsed + 0.000001 >= float(_melee_settings.windup + _melee_settings.recovery):
		melee_phase = MeleePhase.READY
		_melee_settings.clear()
		melee_finished.emit()


func cancel_melee() -> void:
	_pending_melee_weapon = null
	var was_active := is_melee_active()
	melee_phase = MeleePhase.READY
	melee_elapsed = 0.0
	_melee_settings.clear()
	_melee_struck = false
	_melee_region = null
	if is_instance_valid(_melee_effect): _melee_effect.queue_free()
	_melee_effect = null
	if was_active: melee_finished.emit()
	# 取消、换枪不能清除已经消耗的冷却；新场景实例自然从零开始。


func _on_melee_region_reset(region: Node) -> void:
	if _melee_region != null and _melee_region.get_ref() == region: cancel_melee()


func _find_melee_target() -> Node3D:
	var closest: Node3D
	var nearest := INF
	var origin: Vector3 = player.get_torso_position()
	var threshold: float = cos(deg_to_rad(_melee_settings.angle * 0.5))
	for target in get_tree().get_nodes_in_group("combat_target"):
		if not target is Node3D or not target.has_method("receive_hit") or target.is_queued_for_deletion(): continue
		var offset: Vector3 = target.global_position - player.global_position
		if absf(offset.y) > float(_melee_settings.height): continue
		offset.y = 0.0
		var distance := offset.length()
		if distance > float(_melee_settings.range) or distance >= nearest: continue
		if distance > 0.00001 and melee_direction.dot(offset / distance) < threshold: continue
		var endpoint: Vector3 = target.get_torso_position() if target.has_method("get_torso_position") else target.global_position + Vector3.UP * 0.8
		var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, [player.get_rid()])
		query.hit_from_inside = true
		var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or (hit.collider != target and not target.is_ancestor_of(hit.collider)): continue
		closest = target
		nearest = distance
	return closest


func _execute_player_melee() -> void:
	var target := _find_melee_target()
	last_melee_target = target
	_show_melee_slash()
	if is_instance_valid(target):
		if target.has_method("receive_melee_hit"):
			target.receive_melee_hit(_melee_settings.damage, player.global_position,
				_melee_settings.distance, _melee_settings.duration, melee_direction,
				_melee_settings.effects)
		else:
			# 固定训练靶沿用自身计数与生命规则，不改成可移动角色。
			target.receive_hit(_melee_settings.damage, player.global_position)
	melee_struck.emit(target if is_instance_valid(target) else null)


func _show_melee_slash() -> void:
	if melee_effect_scene == null: return
	if is_instance_valid(_melee_effect): _melee_effect.queue_free()
	var effect := melee_effect_scene.instantiate()
	if not effect is Node3D or not effect.has_method("start"):
		effect.free()
		return
	_melee_effect = effect
	add_child(effect)
	effect.add_to_group("player_melee_effect")
	# 子节点随 Combat 卸载，世界变换固定在实际出手位置。
	effect.start(player.get_torso_position(), melee_direction,
		float(_melee_settings.range), float(_melee_settings.angle))


func _update_status() -> void:
	_apply_debug_mode(debug_settings.enabled)
	var title: String = weapon.display_name if weapon != null else "未装备"
	var target_name: String = str(locked_target.name) if is_instance_valid(locked_target) else "无"
	var precision: String = "%d%%" % roundi(get_effective_accuracy() * 100.0)
	var fire_hint: String = "按住左键连发" if weapon != null and weapon.fire_mode == WeaponData.FireMode.AUTOMATIC else "左键单发"
	var hint: String = "右键瞄准 / " + fire_hint if can_combat() else "非战斗区域：请进入靶场"
	var accuracy_label: String = "稳定度" if is_using_spread_cone() else "中心概率"
	status.text = "%s　%s\n锁定：%s　%s：%s\n%s" % [title, hint, target_name, accuracy_label, precision, last_result]
