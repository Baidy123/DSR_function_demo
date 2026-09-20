extends CharacterBody3D

## 身体执行层不读取玩家位置，也不决定追踪、搜索或掩体策略。
signal hit_received(damage: float, attacker_position: Vector3)
signal reset_completed

## 基础移动速度（米/秒）；AI 可给当前行动提供速度倍率。
@export var move_speed: float = 2.0
## 身体每秒最多转动的角度（度/秒）。
@export var turn_speed_degrees: float = 360.0
## 出生、离场刷新和重新开始时恢复的生命值。
@export var max_health: float = 100.0

@export_group("Shooting")
## 是否允许执行射击；可暂时关闭以单独观察移动和掩体行为。
@export var shooting_enabled: bool = true
## 每次真实命中玩家造成的伤害；玩家无敌时仍走受伤日志入口。
@export_range(0.0, 1000.0, 1.0) var shot_damage: float = 10.0
## 射线最大长度（米）；墙体和第一个碰撞物会截断弹道。
@export_range(0.1, 100.0, 0.5) var shot_range: float = 12.0
## 两枪之间的最短间隔（秒）；冷却结束不会补发积压子弹。
@export_range(0.05, 10.0, 0.05) var shot_interval: float = 0.8
## 枪口瞄准方向的最大跟随角速度（度/秒），独立于身体转速。
@export_range(1.0, 720.0, 1.0) var aim_turn_speed_degrees: float = 90.0
## 站立时三维散布锥的半角（度），与跟枪误差分别计算。
@export_range(0.0, 45.0, 0.1) var standing_spread_degrees: float = 4.0
## 移动时三维散布半角（度）；是否允许移动射击由 AI 决定。
@export_range(0.0, 45.0, 0.1) var moving_spread_degrees: float = 8.0
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
# 射击取样不消耗全局随机序列，避免改变巡逻/搜索/掩体的随机选择。
var _shot_rng := RandomNumberGenerator.new()

var health: float = 100.0
var is_dead: bool = false
var initial_transform: Transform3D
var initial_body_transform: Transform3D
var death_tween: Tween

@onready var agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
	_shot_rng.randomize()
	initial_transform = transform
	initial_body_transform = $Body.transform
	reset_target()


## 执行方向与速度；调用者负责决定目的地。
func move_character(direction: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	if is_dead:
		return
	velocity.x = direction.x * move_speed * speed_multiplier
	velocity.z = direction.z * move_speed * speed_multiplier
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()



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
	if death_tween != null and death_tween.is_valid():
		death_tween.kill()
	transform = initial_transform
	$Body.transform = initial_body_transform
	$FrontMarker.show()
	$CollisionShape3D.set_deferred("disabled", false)
	add_to_group("combat_target")
	health = max_health
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


## AI 可以补充状态文字；没有 AI 时仍显示生命。
func set_status_text(text: String) -> void:
	$Label.text = text


func _update_health_label() -> void:
	set_status_text("敌人：%s\n生命 %d / %d" % [
		"已死亡" if is_dead else "待命", ceili(health), ceili(max_health)
	])



## 由决策层每帧调用一次；INF 表示没有可见瞄准点，冷却仍继续计时。
func update_weapon(delta: float, visible_point: Vector3 = Vector3.INF) -> void:
	shot_cooldown = maxf(0.0, shot_cooldown - maxf(delta, 0.0))
	if is_dead or not shooting_enabled or not visible_point.is_finite():
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


func get_shot_origin() -> Vector3:
	return global_position + Vector3.UP * 0.8


## 只执行请求，不寻找玩家或决定行为；实际射线围绕当前枪口方向取样。
func try_fire(moving: bool = false) -> bool:
	if is_dead or not shooting_enabled or not has_aim or not aim_acquired or shot_cooldown > 0.0:
		return false
	# 不从身体背后开枪；只检查水平夹角，保留上下瞄准。
	var horizontal_aim := Vector3(aim_direction.x, 0.0, aim_direction.z)
	var body_forward := Vector3(-global_basis.z.x, 0.0, -global_basis.z.z)
	if not horizontal_aim.is_zero_approx() and body_forward.angle_to(horizontal_aim) > MAX_GUN_BODY_ANGLE:
		return false
	var spread: float = moving_spread_degrees if moving else standing_spread_degrees
	last_shot_direction = _random_direction_in_spread_cone(aim_direction, spread)
	var origin: Vector3 = get_shot_origin()
	var endpoint: Vector3 = origin + last_shot_direction * maxf(0.0, shot_range)
	var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, [get_rid()])
	query.hit_from_inside = true
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	last_shot_collider = hit.get("collider")
	shot_count += 1
	shot_cooldown = maxf(0.05, shot_interval)
	var hit_player := false
	if not hit.is_empty():
		endpoint = hit.position
		if hit.collider.is_in_group("player"):
			hit.collider.receive_hit(shot_damage)
			hit_player = true
	if debug_shooting:
		print("[敌人][开火] ", "命中玩家" if hit_player else ("被物体挡住" if not hit.is_empty() else "未命中"), "；散布半角=", spread)
	_draw_shot(origin, endpoint, hit_player)
	return true


# 与玩家相同：在完整三维锥内按立体角均匀取样。
func _random_direction_in_spread_cone(forward: Vector3, half_angle_degrees: float) -> Vector3:
	var cone_axis: Vector3 = forward.normalized() if not forward.is_zero_approx() else Vector3.FORWARD
	var angle: float = deg_to_rad(clampf(half_angle_degrees, 0.0, 45.0))
	if is_zero_approx(angle):
		return cone_axis
	# 接近竖直方向时换参考轴，避免叉乘退化。
	var reference_axis: Vector3 = Vector3.UP if absf(cone_axis.y) < 0.999 else Vector3.RIGHT
	var cone_right: Vector3 = cone_axis.cross(reference_axis).normalized()
	var cone_up: Vector3 = cone_right.cross(cone_axis).normalized()
	var phi: float = _shot_rng.randf_range(0.0, TAU)
	# 均匀取 cos(theta)，避免直接均匀取角度导致弹道过度集中在中心。
	var cosine: float = lerpf(1.0, cos(angle), _shot_rng.randf())
	var sine: float = sqrt(maxf(0.0, 1.0 - cosine * cosine))
	var radial: Vector3 = cone_right * cos(phi) + cone_up * sin(phi)
	return (cone_axis * cosine + radial * sine).normalized()


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
