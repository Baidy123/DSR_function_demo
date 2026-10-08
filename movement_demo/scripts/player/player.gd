extends CharacterBody3D

const CharacterGeometry = preload("res://scripts/systems/character_geometry.gd")
const LowCoverGeometry = preload("res://scripts/world/low_cover_geometry.gd")
const PostureCapsule = preload("res://resources/models/crouch_capsule.tres")
const STANDING_HEIGHT: float = 1.75

signal vault_landed

@export_group("姿态与翻越")
@export_range(0.7, 1.5, 0.01) var crouch_height: float = 1.0
@export_range(0.05, 1.0, 0.01) var posture_transition_seconds: float = 0.2
@export_range(0.1, 1.0, 0.05) var crouch_move_multiplier: float = 0.5
@export_range(0.7, 1.75, 0.01) var standing_eye_height: float = 1.55
@export_range(0.1, 1.5, 0.01) var crouching_eye_height: float = 0.88
@export_range(0.7, 1.75, 0.01) var standing_muzzle_height: float = 1.30
@export_range(0.1, 1.5, 0.01) var crouching_muzzle_height: float = 0.72
@export_range(0.3, 2.0, 0.05) var vault_duration: float = 0.8
@export_range(0.5, 2.5, 0.05) var cover_interaction_distance: float = 1.5
var manual_crouch: bool = false
var crouch_amount: float = 0.0
var _posture_presentation_transition: StringName = &""
var _posture_wants_crouch: bool = false
var _aim_cover: Dictionary = {}
var _body_shape: CapsuleShape3D
var _body_mesh: CapsuleMesh
var _vault_plan: Dictionary = {}
var _vault_elapsed: float = 0.0
var _vault_falling: bool = false
var _vault_progress: float = 0.0
var _vault_region: WeakRef
var _camera_ground_height: float = 0.0

@export_group("移动")

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
var _legacy_sprint_radius: float = -1.0
var _sprint_multiplier_explicit: bool = false
## 普通移动声无遮挡半径（米）；纯倍率配置下0关闭全部移动声。
@export_range(0.0, 100.0, 0.5) var movement_noise_radius: float = 3.0
## 奔跑相对于普通移动的听觉半径倍率，不改变枪声。
@export_range(0.0, 10.0, 0.05) var sprint_noise_multiplier: float = 2.0:
	set(value):
		sprint_noise_multiplier = maxf(0.0, value) if is_finite(value) else 0.0
		_sprint_multiplier_explicit = true
		_legacy_sprint_radius = -1.0
## 蹲行相对于普通移动的听觉半径倍率，不改变发声间隔。
@export_range(0.0, 10.0, 0.05) var crouch_noise_multiplier: float = 0.5
## 旧场景及脚本的半径兼容入口；检查器统一使用倍率。
@export_storage var sprint_noise_radius: float = -1.0:
	get:
		return _legacy_sprint_radius if _legacy_sprint_radius >= 0.0 else movement_noise_radius * sprint_noise_multiplier
	set(value):
		if not is_finite(value): return
		if value < 0.0:
			_legacy_sprint_radius = -1.0
			return
		if is_node_ready():
			_sprint_multiplier_explicit = false
		elif _sprint_multiplier_explicit:
			return
		_legacy_sprint_radius = maxf(0.0, value)
		if is_node_ready(): _normalize_legacy_noise_radius()
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


func _ready() -> void:
	_normalize_legacy_noise_radius()
	_camera_ground_height = global_position.y
	var collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is CapsuleShape3D:
		_body_shape = collision.shape.duplicate() as CapsuleShape3D
		collision.shape = _body_shape
	var body := get_node_or_null("Visual/Body") as MeshInstance3D
	if body != null and body.mesh is CapsuleMesh:
		var original := body.mesh as CapsuleMesh
		_body_mesh = PostureCapsule.duplicate() as CapsuleMesh
		_body_mesh.radius = original.radius
		_body_mesh.material = original.material
		body.mesh = _body_mesh
	_apply_body_posture()
	if health != null: health.died.connect(_on_posture_death)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_echo() or is_dead() or is_in_dialogue or get_tree().paused: return
	if event.is_action_pressed("crouch"):
		request_crouch(not manual_crouch)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vault"):
		var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		var direction := Vector3(input_direction.x, 0.0, input_direction.y)
		request_vault(direction if not direction.is_zero_approx() else -global_basis.z)
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if is_dead() or get_tree().paused:
		return
	if combat != null:
		combat.begin_frame(delta, Input.is_action_pressed("aim"))
	if is_vaulting():
		var before_vault := global_position
		_advance_vault(delta)
		_update_stamina(delta)
		if combat != null:
			combat.end_frame(delta, Vector2(global_position.x - before_vault.x, global_position.z - before_vault.z).length() > 0.0001)
		return
	_update_posture(delta)
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
				is_sprinting = Input.is_action_pressed("sprint") and not stamina_exhausted and crouch_amount <= 0.0001
				target_speed = move_speed * get_posture_move_multiplier()
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
		if crouch_amount > 0.0001:
			current_speed = minf(current_speed, move_speed * get_posture_move_multiplier())

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
	if is_on_floor(): _camera_ground_height = global_position.y
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
	speed *= get_posture_move_multiplier()
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
	if is_on_floor(): _camera_ground_height = global_position.y
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
		_begin_vault_fall()
		_aim_cover.clear()
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
	_begin_vault_fall()
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
			movement_noise.emit_from(self, get_movement_noise_radius())
		_movement_noise_timer = maxf(0.05, movement_noise_interval)


func _normalize_legacy_noise_radius() -> void:
	if _legacy_sprint_radius < 0.0: return
	if movement_noise_radius > 0.0:
		var multiplier := _legacy_sprint_radius / movement_noise_radius
		sprint_noise_multiplier = multiplier
	elif is_zero_approx(_legacy_sprint_radius):
		sprint_noise_multiplier = 0.0
	# 普通0、快速非0是旧独立半径的有效配置，保留到用户明确设置倍率。


func _validate_property(property: Dictionary) -> void:
	# 旧字段仍能读取，但纯倍率配置不再序列化推导半径，防止产生第二事实来源。
	if property.name == "sprint_noise_radius" and _legacy_sprint_radius < 0.0:
		property.usage = int(property.usage) & ~PROPERTY_USAGE_STORAGE


func get_movement_noise_radius() -> float:
	if is_sprinting and crouch_amount <= 0.0001: return sprint_noise_radius
	return maxf(0.0, movement_noise_radius) * lerpf(1.0, maxf(0.0, crouch_noise_multiplier), crouch_amount)


func request_crouch(crouched: bool) -> bool:
	if is_dead() or is_in_dialogue or get_tree().paused: return false
	manual_crouch = crouched
	if not crouched: _aim_cover.clear()
	return true


func is_crouching() -> bool:
	return not is_vaulting() and crouch_amount >= 0.9999


func is_vaulting() -> bool:
	return not _vault_plan.is_empty()


func get_vault_progress() -> float:
	return _vault_progress if is_vaulting() else 0.0


## 独立只读快照；表现不得通过它改变碰撞、姿态请求或翻越进度。
func get_posture_presentation_state() -> Dictionary:
	return {
		"amount": crouch_amount,
		"transition": _posture_presentation_transition,
		"vaulting": is_vaulting(),
		"vault_progress": get_vault_progress(),
		"vault_falling": is_vaulting() and _vault_falling,
	}


func get_posture_move_multiplier() -> float:
	return lerpf(1.0, crouch_move_multiplier, crouch_amount)


func get_body_height() -> float:
	if is_vaulting(): return maxf(float(_vault_plan.get("height", 1.0)), _body_radius() * 2.0)
	return lerpf(STANDING_HEIGHT, get_posture_body_height(true), crouch_amount)


func get_posture_body_height(crouched: bool) -> float:
	return maxf(crouch_height, _body_radius() * 2.0) if crouched else STANDING_HEIGHT


func get_posture_eye_position(crouched: bool, feet: Vector3 = Vector3.INF) -> Vector3:
	return (global_position if not feet.is_finite() else feet) + Vector3.UP * (crouching_eye_height if crouched else standing_eye_height)


func get_posture_muzzle_position(crouched: bool, feet: Vector3 = Vector3.INF) -> Vector3:
	return (global_position if not feet.is_finite() else feet) + Vector3.UP * (crouching_muzzle_height if crouched else standing_muzzle_height)


func get_eye_position() -> Vector3:
	return global_position + Vector3.UP * lerpf(standing_eye_height, crouching_eye_height, crouch_amount)


func get_muzzle_position() -> Vector3:
	return global_position + Vector3.UP * lerpf(standing_muzzle_height, crouching_muzzle_height, crouch_amount)


func get_torso_position() -> Vector3:
	return global_position + Vector3.UP * (get_body_height() * 0.55)


func get_visibility_points() -> Array[Vector3]:
	var height := get_body_height()
	var shoulder := global_position + Vector3.UP * (height - 0.25)
	var side := global_basis.x.normalized() * (_body_radius() * 0.5)
	return [get_torso_position(), global_position + Vector3.UP * (height - 0.06), shoulder - side, shoulder + side]


func get_camera_ground_height() -> float:
	return _camera_ground_height


func _body_radius() -> float:
	return _body_shape.radius if _body_shape != null else 0.35


func can_stand() -> bool:
	return not is_vaulting() and CharacterGeometry.can_occupy(self, global_position, STANDING_HEIGHT, _body_radius())


func _update_posture(delta: float) -> void:
	if is_in_dialogue or is_dead(): return
	_posture_wants_crouch = manual_crouch
	_aim_cover.clear()
	if combat != null:
		if combat.is_melee_active() or combat.is_waiting_for_melee_stand():
			_posture_wants_crouch = false
		elif manual_crouch and combat.is_aiming:
			_aim_cover = LowCoverGeometry.aim_cover(self, -global_basis.z, cover_interaction_distance)
			if not _aim_cover.is_empty(): _posture_wants_crouch = false
	var next := move_toward(crouch_amount, 1.0 if _posture_wants_crouch else 0.0, maxf(0.0, delta) / maxf(0.001, posture_transition_seconds))
	if next < crouch_amount:
		if not CharacterGeometry.can_occupy(self, global_position, STANDING_HEIGHT, _body_radius()): return
	# 只有真实高度改变才切换方向；中途顶阻时保留原方向和进度。
	if next > crouch_amount: _posture_presentation_transition = &"crouch_enter"
	elif next < crouch_amount: _posture_presentation_transition = &"crouch_exit"
	if next <= 0.0 or next >= 1.0: _posture_presentation_transition = &""
	crouch_amount = next
	_apply_body_posture()


func _apply_body_posture() -> void:
	var height := get_body_height()
	if _body_shape != null:
		_body_shape.height = height
		$CollisionShape3D.position.y = height * 0.5
	if _body_mesh != null:
		_body_mesh.height = height
		$Visual/Body.position.y = height * 0.5
	var marker := get_node_or_null("Visual/FrontMarker") as Node3D
	if marker != null: marker.position.y = height - 0.25


func request_vault(direction: Vector3) -> bool:
	if is_dead() or is_in_dialogue or get_tree().paused or is_vaulting() or not is_on_floor(): return false
	if combat != null and combat.is_melee_active(): return false
	var plan: Dictionary = LowCoverGeometry.query_vault(self, direction, cover_interaction_distance, vault_duration)
	if not plan.get("valid", false): return false
	_vault_plan = plan
	_vault_elapsed = 0.0
	_vault_progress = 0.0
	_vault_falling = false
	_camera_ground_height = global_position.y
	_aim_cover.clear()
	is_sprinting = false
	current_speed = 0.0
	velocity = Vector3.ZERO
	crouch_amount = 1.0
	_posture_presentation_transition = &""
	_apply_body_posture()
	var heading: Vector3 = plan.exit - plan.entry
	heading.y = 0.0
	if not heading.is_zero_approx(): global_rotation.y = atan2(-heading.x, -heading.z)
	if combat != null: combat.begin_vault()
	_vault_region = null
	for zone in get_tree().get_nodes_in_group("combat_zone"):
		if zone is Area3D and zone.monitoring and zone.overlaps_body(self):
			var region: Node = zone.get_parent()
			if region.has_signal("presentation_reset"):
				_vault_region = weakref(region)
				if not region.presentation_reset.is_connected(_on_vault_region_reset):
					region.presentation_reset.connect(_on_vault_region_reset)
				break
	return true


func _advance_vault(delta: float) -> void:
	is_sprinting = false
	current_speed = 0.0
	if _vault_falling:
		_advance_vault_fall(delta)
		return
	if not is_instance_valid(_vault_plan.get("cover")):
		_begin_vault_fall()
		_advance_vault_fall(delta)
		return
	_vault_elapsed += maxf(0.0, delta)
	_vault_progress = clampf(_vault_elapsed / maxf(0.01, float(_vault_plan.duration)), 0.0, 1.0)
	var destination := LowCoverGeometry.sample_vault(_vault_plan, _vault_progress)
	var motion := destination - global_position
	velocity = motion / maxf(delta, 0.0001)
	var collision := move_and_collide(motion, false, 0.001)
	if collision != null or _vault_progress >= 1.0:
		_begin_vault_fall()
		_advance_vault_fall(delta)


func _begin_vault_fall() -> void:
	if not is_vaulting() or _vault_falling: return
	_vault_falling = true
	# 轨迹的帧位移不是物理冲量；交回重力前清掉合成速度。
	# 重复中断保留已积累的下落速度，真实近战推力仍由独立外力推进。
	velocity = Vector3.ZERO


func _advance_vault_fall(delta: float) -> void:
	var ground_height: float = maxf(_vault_plan.entry.y, _vault_plan.exit.y)
	var own := Vector3.ZERO
	# 临时停在墙顶不算落地；沿最近合法端点走出后继续重力收尾。
	if is_on_floor() and global_position.y > ground_height + 0.2:
		var entry: Vector3 = _vault_plan.entry
		var finish: Vector3 = _vault_plan.exit
		var destination := entry if global_position.distance_squared_to(entry) < global_position.distance_squared_to(finish) else finish
		own = destination - global_position
		own.y = 0.0
		own = own.normalized() * move_speed
	velocity.x = own.x
	velocity.z = own.z
	velocity += get_gravity() * delta
	velocity += _advance_melee_push(delta)
	move_and_slide()
	if is_on_floor() and global_position.y <= ground_height + 0.2:
		_finish_vault()


func _finish_vault() -> void:
	var was_vaulting := is_vaulting()
	_vault_plan.clear()
	_vault_elapsed = 0.0
	_vault_falling = false
	_vault_progress = 0.0
	_vault_region = null
	_camera_ground_height = global_position.y
	velocity = Vector3.ZERO
	_aim_cover.clear()
	# 保留手动选择，下一物理帧按落地方向重新评估辅助起身。
	if combat != null: combat.clear_target_lock()
	if was_vaulting and not is_dead(): vault_landed.emit()


func _on_vault_region_reset(region: Node) -> void:
	if _vault_region != null and _vault_region.get_ref() == region:
		_begin_vault_fall()
		if combat != null: combat.clear_target_lock()


func _on_posture_death() -> void:
	_vault_plan.clear()
	_posture_presentation_transition = &""
	_vault_region = null
	_aim_cover.clear()
	_clear_melee_push()
