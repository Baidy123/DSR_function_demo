@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"suppression"

## 朝最后目击位置附近压制的最短秒数；当前未接弹匣。
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
