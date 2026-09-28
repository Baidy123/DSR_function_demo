extends StaticBody3D

enum TargetKind { TRAINING, TEST }

## 训练靶只计数；测试靶作为静止敌人原型，会受伤和死亡。
@export var target_kind: TargetKind = TargetKind.TRAINING
## 测试靶出生和离场刷新时恢复的生命值；训练靶只统计命中，不按此值扣血。
@export_range(1.0, 10000.0, 1.0) var max_health: float = 100.0

var hit_count: int = 0
var health: float = 100.0
var is_dead: bool = false
var death_tween: Tween
var initial_transform: Transform3D
var initial_body_transform: Transform3D


func _ready() -> void:
	initial_transform = transform
	initial_body_transform = $Body.transform
	reset_target()


func reset_target() -> void:
	# 离场可能发生在倒下动画尚未结束时，先停止动画再恢复姿态。
	if death_tween != null and death_tween.is_valid():
		death_tween.kill()
	transform = initial_transform
	$Body.transform = initial_body_transform
	is_dead = false
	hit_count = 0
	health = max_health
	add_to_group("combat_target")
	$CollisionShape3D.set_deferred("disabled", false)
	_update_label()


func receive_hit(damage: float, _attacker_position: Vector3 = Vector3.INF) -> void:
	if is_dead:
		return
	hit_count += 1
	if target_kind == TargetKind.TEST:
		health = maxf(0.0, health - maxf(damage, 0.0))
		if health <= 0.0:
			_die()
	_update_label()


func _die() -> void:
	is_dead = true
	remove_from_group("combat_target")
	# 倒下后不再阻挡玩家或射线，避免留下看不见的直立碰撞体。
	$CollisionShape3D.set_deferred("disabled", true)
	death_tween = create_tween().set_parallel(true)
	death_tween.tween_property($Body, "rotation:x", PI / 2.0, 0.3)
	death_tween.tween_property($Body, "position:y", 0.35, 0.3)


func _update_label() -> void:
	if target_kind == TargetKind.TRAINING:
		$Label.text = "训练靶\n命中 %d 次" % hit_count
	elif is_dead:
		$Label.text = "测试靶\n已死亡"
	else:
		$Label.text = "测试靶\n生命 %d / %d" % [ceili(health), ceili(max_health)]
