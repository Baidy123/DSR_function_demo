@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"perception"

## 是否接收玩家移动和开枪的声源；调查仍受UnitType/Training的search权限限制。
@export var hearing_enabled: bool = true:
	set(value):
		hearing_enabled = value
		mark_override(&"hearing_enabled")
## 普通视觉感知的最大距离（米）；仍受视角、墙壁和竞技场范围限制。
@export var sight_distance: float = 10.0:
	set(value):
		sight_distance = value
		mark_override(&"sight_distance")
## 普通视野的水平总角度（度）；左右各占一半，近身警戒不受此角度限制。
@export_range(10.0, 360.0, 5.0) var sight_angle_degrees: float = 120.0:
	set(value):
		sight_angle_degrees = value
		mark_override(&"sight_angle_degrees")
## 近身警戒不限制方向，但仍检测墙壁遮挡。
@export_range(0.0, 5.0, 0.1) var close_awareness_radius: float = 2.0:
	set(value):
		close_awareness_radius = value
		mark_override(&"close_awareness_radius")
