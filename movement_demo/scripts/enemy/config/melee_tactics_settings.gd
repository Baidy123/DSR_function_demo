@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"melee_tactics"

## 掩体落点至少缩短多少米的已知目标距离；不反复选择原地躲藏。
@export_range(0.1, 3.0, 0.1) var cover_minimum_progress: float = 0.6:
	set(value):
		cover_minimum_progress = value
		mark_override(&"cover_minimum_progress")
## 最后目击允许新掩体推进的期限；已开始的绕出／观察按原路段时限结束，不刷新目击记忆。
@export_range(0.5, 10.0, 0.5) var cover_memory_seconds: float = 5.0:
	set(value):
		cover_memory_seconds = value
		mark_override(&"cover_memory_seconds")
## 绕出掩体及重新目击后的接敌奔跑倍率；普通掩体探头速度仍由 Cover 单独控制。
@export_range(0.1, 3.0, 0.1) var cover_exit_speed_multiplier: float = 2.0:
	set(value):
		cover_exit_speed_multiplier = value
		mark_override(&"cover_exit_speed_multiplier")
## 绕出重新发现玩家后最多继续奔跑多久；贴脸、失视或受阻时提前交回共同决策。
@export_range(0.0, 4.0, 0.1) var cover_charge_seconds: float = 2.0:
	set(value):
		cover_charge_seconds = value
		mark_override(&"cover_charge_seconds")
## 两出口的接敌时间及共同代价相近时，允许为换侧多花的时间；不是强制绕远。
@export_range(0.0, 1.0, 0.05) var cover_exit_side_tolerance_seconds: float = 0.25:
	set(value):
		cover_exit_side_tolerance_seconds = value
		mark_override(&"cover_exit_side_tolerance_seconds")
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
