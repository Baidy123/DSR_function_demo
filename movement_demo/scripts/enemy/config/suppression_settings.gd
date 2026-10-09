@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"suppression"

## 点压制的最短秒数；空匣时交回统一换弹调度。
@export_range(0.1, 10.0, 0.1) var duration_min: float = 3.0:
	set(value):
		duration_min = value
		mark_override(&"duration_min")
## 最长秒数，每次在最短与最长之间抽取；至少等于最短值。
@export_range(0.1, 10.0, 0.1) var duration_max: float = 5.0:
	set(value):
		duration_max = value
		mark_override(&"duration_max")
## 瞄准点在最后目击位置周围的水平采样半径；实际子弹继续使用枪械散布。
@export_range(0.0, 3.0, 0.05) var target_radius: float = 0.75:
	set(value):
		target_radius = value
		mark_override(&"target_radius")

## Transparent Utility credit for directly suppressing a frozen low-cover disappearance/clue point.
@export_range(0.0, 5.0, 0.1) var low_cover_point_preference: float = 1.0:
	set(value):
		low_cover_point_preference = value
		mark_override(&"low_cover_point_preference")

@export_group("出口方案")
@export_range(0.1, 10.0, 0.1) var exit_duration_min: float = 3.0:
	set(value):
		exit_duration_min = value
		mark_override(&"exit_duration_min")
@export_range(0.1, 10.0, 0.1) var exit_duration_max: float = 5.0:
	set(value):
		exit_duration_max = value
		mark_override(&"exit_duration_max")
## 每侧实际射击次数，冷却和连射停顿不计入。
@export_range(1, 20, 1) var shots_per_exit_min: int = 2:
	set(value):
		shots_per_exit_min = value
		mark_override(&"shots_per_exit_min")
@export_range(1, 20, 1) var shots_per_exit_max: int = 5:
	set(value):
		shots_per_exit_max = value
		mark_override(&"shots_per_exit_max")
