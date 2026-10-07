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

## 连续看见玩家换弹多久后形成机会判断；失视打断尚未完成的观察。
@export_range(0.0, 2.0, 0.05) var reload_observation_seconds: float = 0.15:
	set(value):
		reload_observation_seconds = value
		mark_override(&"reload_observation_seconds")
## 最后一次观察到换弹后保留多久的机会证据；不读取墙后的换弹进度。
@export_range(0.0, 3.0, 0.05) var reload_memory_seconds: float = 0.8:
	set(value):
		reload_memory_seconds = value
		mark_override(&"reload_memory_seconds")
