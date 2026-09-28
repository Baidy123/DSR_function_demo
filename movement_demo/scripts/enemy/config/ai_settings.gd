@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"ai"

## 每次巡逻抵达后停留的时间。
@export_range(0.0, 10.0, 0.1) var patrol_pause_seconds: float = 1.5:
	set(value):
		patrol_pause_seconds = value
		mark_override(&"patrol_pause_seconds")
## 受击时只知道攻击者附近区域，不持续获取攻击者坐标。
@export_range(0.0, 5.0, 0.1) var attack_position_uncertainty: float = 1.0:
	set(value):
		attack_position_uncertainty = value
		mark_override(&"attack_position_uncertainty")
