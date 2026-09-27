extends CharacterBody3D

@onready var debug_settings = get_node("/root/DebugSettings")

const Ammo = preload("res://weapon_ammo.gd")
var ammo = Ammo.new()
## 身体执行层不读取玩家位置，也不决定追踪、搜索或掩体策略。
signal hit_received(damage: float, attacker_position: Vector3)
signal reset_completed

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
@export_range(0.0, 100.0, 0.5) var fast_movement_noise_radius: float = 6.0
## 隔墙衰减与预留音频，留空关闭移动声。
@export var movement_noise: NoiseData = preload("res://movement_noise.tres")
## 持续移动时的发声间隔（秒）；刚开始移动立即发声。
@export_range(0.05, 2.0, 0.05) var movement_noise_interval: float = 0.4
var _movement_noise_timer: float = 0.0

@export_group("Shooting")
## 是否允许执行射击；可暂时关闭以单独观察移动和掩体行为。
@export var shooting_enabled: bool = true
## 枪械伤害、射程、射速与中心概率参数；敌人使用玩家旧概率模式，空资源表示没有枪。
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

@onready var agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	debug_settings.changed.connect(_apply_debug_mode)
	_apply_debug_mode(debug_settings.enabled)
	_shot_rng.randomize()
	initial_transform = transform
	initial_body_transform = $Body.transform
	reset_target()


## 执行方向与速度；调用者负责决定目的地。
func move_character(direction: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	if is_dead:
		return
	speed_multiplier = get_effective_movement_multiplier(speed_multiplier)
	velocity.x = direction.x * move_speed * speed_multiplier
	velocity.z = direction.z * move_speed * speed_multiplier
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	var before: Vector3 = global_position
	move_and_slide()
	_weapon_move_distance += Vector2(global_position.x - before.x, global_position.z - before.z).length()
	_update_movement_noise(delta, before, speed_multiplier > 1.0)


## 换弹可走可转，但快速移动最多按普通速度执行；慢走保持原倍率。
## 行动层估算移动时限时也使用同一限制。
func get_effective_movement_multiplier(requested: float) -> float:
	return minf(requested, 1.0) if ammo.is_reloading else requested


func _update_movement_noise(delta: float, before_move: Vector3, fast_movement: bool = false) -> void:
	var distance := Vector2(global_position.x - before_move.x, global_position.z - before_move.z).length()
	if is_dead or distance <= 0.0001:
		_movement_noise_timer = 0.0
		return
	_movement_noise_timer = maxf(0.0, _movement_noise_timer - delta)
	if _movement_noise_timer <= 0.0:
		if movement_noise != null:
			movement_noise.emit_from(self, fast_movement_noise_radius if fast_movement else movement_noise_radius)
		_movement_noise_timer = maxf(0.05, movement_noise_interval)



func face_direction(direction: Vector3, delta: float) -> void:
	if is_dead:
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
		cancel_reload()
		clear_aim()
		velocity = Vector3.ZERO
		remove_from_group("combat_target")
		$CollisionShape3D.set_deferred("disabled", true)
		$FrontMarker.hide()
		death_tween = create_tween().set_parallel(true)
		death_tween.tween_property($Body, "rotation:x", PI / 2.0, 0.3)
		death_tween.tween_property($Body, "position:y", 0.35, 0.3)
	_update_health_label()
	hit_received.emit(damage, attacker_position)


func reset_target() -> void:
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


func _apply_debug_mode(enabled: bool) -> void:
	$Label.visible = enabled


## AI 可以补充状态文字；仅 Debug 模式显示，没有 AI 时显示生命。
func set_status_text(text: String) -> void:
	$Label.text = text


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
	ammo.advance_reload(elapsed)
	var can_aim: bool = can_use_firearms() and visible_point.is_finite()
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
	cancel_reload()
	weapon = data
	ammo = Ammo.new(data, {}, true)
	weapon_stability = weapon.get_aim_settings(false).initial if weapon != null else 0.0
	weapon_recovery_timer = 0.0
	_weapon_move_distance = 0.0
	clear_aim()


## 只执行请求；打空后是否开始换弹由AI决定。敌人备弹无限、弹匣有限。
func request_reload() -> bool:
	if not can_use_firearms() or get_tree().paused:
		return false
	return ammo.start_reload()


func cancel_reload() -> void:
	ammo.cancel_reload()


func get_center_probability() -> float:
	return clampf(weapon_stability, 0.0, 1.0) if weapon != null else 0.0


func get_max_shot_deviation_degrees() -> float:
	return 20.0


func _update_weapon_stability(delta: float, visible_point: Vector3) -> void:
	var distance: float = _weapon_move_distance
	_weapon_move_distance = 0.0
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
	return global_position + Vector3.UP * 0.8


## AI选择与基础执行共用枪械资格；不依赖AI、Training或战术动作清单。
## 缺少兵种时不启用枪械，移动、转向等公共身体操作不受影响。
func can_use_firearms() -> bool:
	if is_dead or not shooting_enabled or weapon == null:
		return false
	var unit = get_node_or_null("UnitType")
	return unit != null and unit.supports_firearms()


## 纯查询执行条件；让评分只在枪械确实能发射时积累主动等待时间。
func can_fire() -> bool:
	if not can_use_firearms() or not ammo.can_fire():
		return false
	if not has_aim or not aim_acquired or shot_cooldown > 0.0:
		return false
	# 不从身体背后开枪；只检查水平夹角，保留上下瞄准。
	var horizontal_aim := Vector3(aim_direction.x, 0.0, aim_direction.z)
	var body_forward := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	if not horizontal_aim.is_zero_approx() and body_forward.angle_to(horizontal_aim) > MAX_GUN_BODY_ANGLE:
		return false
	return true


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
	if debug_shooting:
		print("[敌人][开火] ", "命中玩家" if hit_player else ("被物体挡住" if not hit.is_empty() else "未命中"), "；中心概率=", roundi(probability * 100.0), "%")
	_draw_shot(origin, endpoint, hit_player)
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
