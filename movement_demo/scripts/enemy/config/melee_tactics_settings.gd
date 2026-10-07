@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"melee_tactics"

## 掩体落点至少缩短多少米的已知目标距离；不反复选择原地躲藏。
@export_range(0.1, 3.0, 0.1) var cover_minimum_progress: float = 0.6:
	set(value):
		cover_minimum_progress = value
		mark_override(&"cover_minimum_progress")
## 掩体推进只沿用这么久的最后目击信息，之后交回原搜索。
@export_range(0.5, 10.0, 0.5) var cover_memory_seconds: float = 5.0:
	set(value):
		cover_memory_seconds = value
		mark_override(&"cover_memory_seconds")
## 没有换弹证据时，可突然突进的最大目标距离；有证据时仍受持续时间约束。
@export_range(0.5, 8.0, 0.1) var rush_distance: float = 3.5:
	set(value):
		rush_distance = value
		mark_override(&"rush_distance")
@export_range(1.1, 4.0, 0.1) var rush_speed_multiplier: float = 2.5:
	set(value):
		rush_speed_multiplier = value
		mark_override(&"rush_speed_multiplier")
## 单次快速接近的最长时间；到达出手距离会提前交回基础接敌。
@export_range(0.1, 3.0, 0.05) var rush_seconds: float = 1.0:
	set(value):
		rush_seconds = value
		mark_override(&"rush_seconds")
## 从本次突进预定结束时刻起计算冷却；普通切换与提前取消不返还。
@export_range(0.0, 10.0, 0.1) var rush_cooldown_seconds: float = 4.0:
	set(value):
		rush_cooldown_seconds = value
		mark_override(&"rush_cooldown_seconds")
