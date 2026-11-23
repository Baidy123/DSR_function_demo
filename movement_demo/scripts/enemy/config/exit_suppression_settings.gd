@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"exit_suppression"

## 【旧资源兼容】只保留序列化值；当前个人与协调器均不以此调节动作。
## Retired settings: preserve serialized values, expose no active tuning controls.
@export_storage var duration_min: float = 3.0:
	set(value):
		duration_min = value
		mark_override(&"duration_min")
## 【旧资源兼容】只保留序列化值；当前个人与协调器均不以此调节动作。
## 最长秒数，每次在最短与最长之间抽取；至少等于最短值。
@export_storage var duration_max: float = 5.0:
	set(value):
		duration_max = value
		mark_override(&"duration_max")
## 【旧资源兼容】只保留序列化值；当前个人与协调器均不以此调节动作。
## 每侧随机连续打出的枪数范围；仅实际开火才计数，冷却和连射停顿不换边。
@export_storage var shots_per_exit_min: int = 2:
	set(value):
		shots_per_exit_min = value
		mark_override(&"shots_per_exit_min")

## 【旧资源兼容】只保留序列化值；当前个人与协调器均不以此调节动作。
@export_storage var shots_per_exit_max: int = 5:
	set(value):
		shots_per_exit_max = value
		mark_override(&"shots_per_exit_max")
