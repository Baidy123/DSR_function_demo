extends CharacterBody3D

## 基础行走速度（米/秒）；奔跑和锁定慢走均以此值乘各自倍率。
@export_range(0.1, 10.0, 0.1) var move_speed: float = 3.0
## 每秒转过的角度；720 表示转 90 度约需 0.125 秒。
@export_range(30.0, 1080.0, 10.0) var turn_speed_degrees: float = 720.0
## 奔跑速度是行走速度的多少倍。
@export_range(1.0, 5.0, 0.1) var sprint_speed_multiplier: float = 2.0
## 满耐力可以连续奔跑的秒数。
@export_range(0.1, 30.0, 0.1) var sprint_duration: float = 5.0
## 耐力从空恢复到满需要的秒数。
@export_range(0.1, 30.0, 0.1) var stamina_recovery_duration: float = 3.0
## 停止奔跑或近战扣除体力后，等待多少秒才恢复耐力。
@export_range(0.0, 5.0, 0.1) var stamina_recovery_delay: float = 0.5
## 从静止加速到走路速度需要的时间。
@export_range(0.01, 2.0, 0.01) var acceleration_time: float = 0.3
## 从走路速度减速到停止需要的时间。
@export_range(0.01, 2.0, 0.01) var deceleration_time: float = 0.2

@export_group("移动声音")
## 普通移动声无遮挡半径（米）；0关闭。奔跑使用下面的独立半径。
@export_range(0.0, 100.0, 0.5) var movement_noise_radius: float = 3.0
## 当帧处于奔跑状态时的移动声音半径，仍需实际发生位移。
@export_range(0.0, 100.0, 0.5) var sprint_noise_radius: float = 6.0
## 逻辑声源配置；留空关闭移动声。第一版走路与奔跑共用此资源。
@export var movement_noise: NoiseData = preload("res://resources/noise/movement_noise.tres")
## 实际水平移动时每隔多少秒产生一次声源；刚开始移动立即产生。
@export_range(0.05, 2.0, 0.05) var movement_noise_interval: float = 0.4
var _movement_noise_timer: float = 0.0

const MAX_STAMINA: float = 100.0
var stamina: float = MAX_STAMINA
var stamina_exhausted: bool = false
var is_sprinting: bool = false
var stamina_recovery_timer: float = 0.0
var is_facing_npc: bool = false
var npc_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var is_in_dialogue: bool = false
var _melee_push_velocity := Vector3.ZERO
var _melee_push_remaining := 0.0
var _melee_push_duration := 0.0

@onready var visual: Node3D = $"."
@onready var combat = get_node_or_null("Combat")
@onready var health = get_node_or_null("Health")

func _physics_process(delta: float) -> void:
	if is_dead():
		return
	if combat != null:
		combat.begin_frame(delta, Input.is_action_pressed("aim"))
	var input_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var direction: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y)
	if combat != null and combat.is_melee_active() and not is_in_dialogue:
		visual.global_rotation.y = atan2(-combat.melee_direction.x, -combat.melee_direction.z)
		_move_while_locked(delta, direction, true)
		return

	if combat != null and is_instance_valid(combat.locked_target) and not is_in_dialogue:
		_move_while_locked(delta, direction)
		return

	# 对话时忽略方向键，仍允许下面的 NPC 转身。
	if is_in_dialogue:
		direction = Vector3.ZERO

	# 本帧完成 NPC 转向后，也不立即恢复移动。
	var facing_npc_this_frame: bool = is_facing_npc
	if facing_npc_this_frame:
		direction = npc_direction

	# 松键或尚未转好时，目标速度为零，逐渐减速。
	var target_speed: float = 0.0
	is_sprinting = false

	if not direction.is_zero_approx():
		var target_angle: float = atan2(-direction.x, -direction.z)
		visual.rotation.y = rotate_toward(
			visual.rotation.y, target_angle, deg_to_rad(turn_speed_degrees) * delta
		)
		var remaining_angle: float = angle_difference(visual.rotation.y, target_angle)

		if absf(remaining_angle) <= 0.0001:
			if facing_npc_this_frame:
				is_facing_npc = false
			else:
				is_sprinting = Input.is_action_pressed("sprint") and not stamina_exhausted
				target_speed = move_speed
				if is_sprinting:
					target_speed *= sprint_speed_multiplier
	if facing_npc_this_frame or is_in_dialogue:
		# 对话期间清掉移动惯性。
		current_speed = 0.0
	else:
		var acceleration: float = move_speed / acceleration_time
		var deceleration: float = move_speed / deceleration_time
		var speed_change: float = acceleration
		if target_speed < current_speed:
			speed_change = deceleration
		current_speed = move_toward(current_speed, target_speed, speed_change * delta)

	# 剩余速度跟随当前朝向，形成弧线；松键后不再转身。
	var forward: Vector3 = -visual.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed

	_update_stamina(delta)

	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	var before_move: Vector3 = global_position
	var own_horizontal := Vector2(velocity.x, velocity.z)
	var push := _advance_melee_push(delta)
	velocity += push
	move_and_slide()
	_update_movement_noise(delta, before_move)
	if combat != null:
		combat.end_frame(delta, Vector2(get_real_velocity().x, get_real_velocity().z).length() > 0.01)
	# 下一帧可能进入锁定移动；只把主动移动惯性留给该分支。
	if not push.is_zero_approx():
		velocity.x = own_horizontal.x
		velocity.z = own_horizontal.y


# 锁定和近战时朝向交给 Combat；移动方向独立于角色朝向。
func _move_while_locked(delta: float, direction: Vector3, melee: bool = false) -> void:
	is_sprinting = false
	var speed: float = move_speed if melee else move_speed * combat.weapon.locked_move_multiplier
	var desired: Vector3 = direction * speed
	# 进入锁定时也限制惯性，不能带着奔跑速度横移。
	var horizontal := Vector3(velocity.x, 0.0, velocity.z).limit_length(speed)
	var change: float = move_speed / (deceleration_time if direction.is_zero_approx() else acceleration_time)
	horizontal = horizontal.move_toward(desired, change * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z
	current_speed = horizontal.length()
	_update_stamina(delta)
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	var before_move: Vector3 = global_position
	var push := _advance_melee_push(delta)
	velocity += push
	move_and_slide()
	_update_movement_noise(delta, before_move)
	combat.end_frame(delta, Vector2(get_real_velocity().x, get_real_velocity().z).length() > 0.01)
	# 锁定移动下一帧以自己的惯性加速，不能把外力再次当作主动速度累积。
	if not push.is_zero_approx():
		velocity.x = horizontal.x
		velocity.z = horizontal.z


## 一次性体力开销由玩家自身处理；不足不扣除，0消耗不打断恢复。
func try_consume_stamina(amount: float) -> bool:
	if not is_finite(amount) or amount < 0.0 or stamina < amount:
		return false
	if amount == 0.0:
		return true
	stamina -= amount
	stamina_recovery_timer = stamina_recovery_delay
	if is_zero_approx(stamina):
		stamina = 0.0
		stamina_exhausted = true
		is_sprinting = false
	return true


func _update_stamina(delta: float) -> void:
	if is_sprinting:
		stamina_recovery_timer = stamina_recovery_delay
		stamina = move_toward(stamina, 0.0, MAX_STAMINA / sprint_duration * delta)
		
		# 消除连续小数运算的微小误差，确保在约定时间耗尽。
		if is_zero_approx(stamina):
			stamina = 0.0
			stamina_exhausted = true
	else:
		if stamina_recovery_timer > 0:
			stamina_recovery_timer = move_toward(stamina_recovery_timer, 0, delta)
			return
		stamina = move_toward(
			stamina, MAX_STAMINA, MAX_STAMINA / stamina_recovery_duration * delta)
			
		# 耗尽后必须回满才解除锁定；一直按 Shift 会在下一帧自动跑。
		if is_equal_approx(stamina, MAX_STAMINA):
			stamina = MAX_STAMINA
			stamina_exhausted = false
		
func set_dialogue_active(active: bool) -> void:
	is_in_dialogue = active
	if active:
		_clear_melee_push()
		if combat != null:
			combat.cancel_melee()
			combat.cancel_aim()
			combat.cancel_reload()
		current_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		is_sprinting = false


func face_npc(npc_position: Vector3) -> void:
	npc_direction = npc_position - global_position
	npc_direction.y = 0.0
	if not npc_direction.is_zero_approx():
		is_facing_npc = true


## 统一受伤入口，后续敌人命中玩家时调用；当前不使用攻击者位置。
func receive_hit(damage: float = 25.0, _attacker_position: Vector3 = Vector3.ZERO) -> void:
	if health != null:
		health.receive_hit(damage)
		if health.is_dead: _clear_melee_push()


## 玩家自己的近战受击入口；与敌人受击实现分开，外力由原移动入口推进。
func receive_melee_hit(damage: float, attacker_position: Vector3, distance: float,
		duration: float, fallback_direction: Vector3 = Vector3.FORWARD) -> void:
	if is_dead() or is_in_dialogue or get_tree().paused: return
	receive_hit(damage, attacker_position)
	if combat != null: combat.apply_melee_disruption()
	if is_dead(): return
	var direction := global_position - attacker_position
	direction.y = 0.0
	if direction.is_zero_approx(): direction = Vector3(fallback_direction.x, 0.0, fallback_direction.z)
	_melee_push_duration = maxf(0.05, duration)
	_melee_push_remaining = _melee_push_duration if distance > 0.0 else 0.0
	_melee_push_velocity = direction.normalized() * (2.0 * maxf(0.0, distance) / _melee_push_duration)


func _advance_melee_push(delta: float) -> Vector3:
	if _melee_push_remaining <= 0.0 or delta <= 0.0: return Vector3.ZERO
	var elapsed := minf(delta, _melee_push_remaining)
	var before := _melee_push_remaining / _melee_push_duration
	_melee_push_remaining = maxf(0.0, _melee_push_remaining - elapsed)
	var after := _melee_push_remaining / _melee_push_duration
	return _melee_push_velocity * (before + after) * 0.5 * elapsed / delta


func _clear_melee_push() -> void:
	_melee_push_velocity = Vector3.ZERO
	_melee_push_remaining = 0.0
	_melee_push_duration = 0.0


func is_dead() -> bool:
	return health != null and health.is_dead


func _update_movement_noise(delta: float, before_move: Vector3) -> void:
	var distance := Vector2(global_position.x - before_move.x, global_position.z - before_move.z).length()
	if is_dead() or is_in_dialogue or distance <= 0.0001:
		_movement_noise_timer = 0.0
		return
	_movement_noise_timer = maxf(0.0, _movement_noise_timer - delta)
	if _movement_noise_timer <= 0.0:
		if movement_noise != null:
			movement_noise.emit_from(self, sprint_noise_radius if is_sprinting else movement_noise_radius)
		_movement_noise_timer = maxf(0.05, movement_noise_interval)
