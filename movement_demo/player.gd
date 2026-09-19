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
## 停止奔跑后，等待多少秒才恢复耐力。
@export_range(0.0, 5.0, 0.1) var stamina_recovery_delay: float = 0.5
## 从静止加速到走路速度需要的时间。
@export_range(0.01, 2.0, 0.01) var acceleration_time: float = 0.3
## 从走路速度减速到停止需要的时间。
@export_range(0.01, 2.0, 0.01) var deceleration_time: float = 0.2

#DEBUG
var last_printed_stamina: int = 100

const MAX_STAMINA: float = 100.0
var stamina: float = MAX_STAMINA
var stamina_exhausted: bool = false
var is_sprinting: bool = false
var stamina_recovery_timer: float = 0.0
var is_facing_npc: bool = false
var npc_direction: Vector3 = Vector3.ZERO
var current_speed: float = 0.0
var is_in_dialogue: bool = false

@onready var visual: Node3D = $"."
@onready var combat = get_node_or_null("Combat")

func _physics_process(delta: float) -> void:
	if combat != null:
		combat.begin_frame(delta, Input.is_action_pressed("aim"))
	var input_direction: Vector2 = Input.get_vector(
		"move_left", "move_right", "move_up", "move_down"
	)
	var direction: Vector3 = Vector3(input_direction.x, 0.0, input_direction.y)

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
	move_and_slide()
	if combat != null:
		combat.end_frame(delta, Vector2(get_real_velocity().x, get_real_velocity().z).length() > 0.01)


# 锁定时朝向交给 Combat；移动方向独立于角色朝向。
func _move_while_locked(delta: float, direction: Vector3) -> void:
	is_sprinting = false
	var speed: float = move_speed * combat.weapon.locked_move_multiplier
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
	move_and_slide()
	combat.end_frame(delta, Vector2(get_real_velocity().x, get_real_velocity().z).length() > 0.01)


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
#	DEBUG
	var current_stamina: int = int(stamina)
	if current_stamina != last_printed_stamina:
		print("当前耐力：", current_stamina)
		last_printed_stamina = current_stamina
		
func set_dialogue_active(active: bool) -> void:
	is_in_dialogue = active
	if active:
		if combat != null:
			combat.cancel_aim()
		current_speed = 0.0
		velocity.x = 0.0
		velocity.z = 0.0
		is_sprinting = false


func face_npc(npc_position: Vector3) -> void:
	npc_direction = npc_position - global_position
	npc_direction.y = 0.0
	if not npc_direction.is_zero_approx():
		is_facing_npc = true
