@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"tactics"

## 实际受伤一次减少的中心命中概率；0.15 表示减少15个百分点，0关闭。
@export_range(0.0, 1.0, 0.01) var damage_accuracy_penalty: float = 0.15:
	set(value):
		damage_accuracy_penalty = value
		mark_override(&"damage_accuracy_penalty")
## 一发未命中的子弹从附近通过时减少的中心概率；0.02表示2个百分点。
@export_range(0.0, 1.0, 0.01) var nearby_shot_accuracy_penalty: float = 0.02:
	set(value):
		nearby_shot_accuracy_penalty = value
		mark_override(&"nearby_shot_accuracy_penalty")

## 接敌侧移/后退和掩护撤退时允许开火；关闭后只在停稳时射击，转身冲刺仍停火。
@export var fire_while_moving: bool = true:
	set(value):
		fire_while_moving = value
		mark_override(&"fire_while_moving")
## 首次发现或重新取得有效视线后，至少观察多久才允许射击（秒）；0可关闭。
@export_range(0.0, 5.0, 0.05) var fire_reaction_seconds: float = 0.3:
	set(value):
		fire_reaction_seconds = value
		mark_override(&"fire_reaction_seconds")
## 普通交火（含接敌跑打）希望达到的中心概率；0.7表示70%，不是最终命中率。
## 用作FireDecision评分的精度偏好，低于目标也可选择射击；掩护撤退不等待稳枪。
@export_range(0.0, 1.0, 0.05) var fire_stability_target: float = 0.7:
	set(value):
		fire_stability_target = value
		mark_override(&"fire_stability_target")
## 每轮实际打出几枪后暂停；只统计执行成功的射击，不按命中次数计数。
@export_range(1, 20, 1) var burst_shot_count: int = 3:
	set(value):
		burst_shot_count = value
		mark_override(&"burst_shot_count")
## 每轮最后一枪后的停火时间（秒）；与枪械冷却并行，必须都结束才能再开火。
@export_range(0.0, 10.0, 0.05) var burst_pause_seconds: float = 1.0:
	set(value):
		burst_pause_seconds = value
		mark_override(&"burst_pause_seconds")
## 远程敌人希望保持的距离区间，单位为米。
@export_range(1.0, 20.0, 0.5) var ranged_min_distance: float = 4.0:
	set(value):
		ranged_min_distance = value
		mark_override(&"ranged_min_distance")
## 远程期望距离上限（米）；与下限共同决定射击候选点的采样范围。
@export_range(2.0, 25.0, 0.5) var ranged_max_distance: float = 6.0:
	set(value):
		ranged_max_distance = value
		mark_override(&"ranged_max_distance")
## 选位有冷却，且有效目标会继续沿用，避免频繁左右换路。
@export_range(0.1, 5.0, 0.05) var ranged_repath_seconds: float = 0.75:
	set(value):
		ranged_repath_seconds = value
		mark_override(&"ranged_repath_seconds")
## 近战接近时的停止距离（米）；远程保持距离由 Ranged Min/Max Distance 控制。
@export var stopping_distance: float = 1.3:
	set(value):
		stopping_distance = value
		mark_override(&"stopping_distance")
