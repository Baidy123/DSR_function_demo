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

var health: float = 100.0
var is_dead: bool = false
var initial_transform: Transform3D
var initial_body_transform: Transform3D
var death_tween: Tween

@onready var agent: NavigationAgent3D = $NavigationAgent3D


func _ready() -> void:
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
