@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"exit_suppression"

## 朝可通行掩体出口压制的最短秒数；空匣时交回统一换弹调度。
@export_range(0.1, 10.0, 0.1) var duration_min: float = 3.0:
	set(value):
		duration_min = value
		mark_override(&"duration_min")
## 最长秒数，每次在最短与最长之间抽取；至少等于最短值。
@export_range(0.1, 10.0, 0.1) var duration_max: float = 5.0:
	set(value):
		duration_max = value
		mark_override(&"duration_max")
## 每侧随机连续打出的枪数范围；仅实际开火才计数，冷却和连射停顿不换边。
@export_range(1, 20, 1) var shots_per_exit_min: int = 2:
	set(value):
		shots_per_exit_min = value
		mark_override(&"shots_per_exit_min")

@export_range(1, 20, 1) var shots_per_exit_max: int = 5:
	set(value):
		shots_per_exit_max = value
		mark_override(&"shots_per_exit_max")
