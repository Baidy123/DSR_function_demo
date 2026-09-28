@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"fire_decision"

## 稳定度正在提高时，继续稳枪可获得多少额外分数。
@export_range(0.0, 2.0, 0.05) var recovery_gain_weight: float = 0.35:
	set(value):
		recovery_gain_weight = value
		mark_override(&"recovery_gain_weight")
## 敌人被逼近到最小交战距离以内时，增加多少开火分数。
@export_range(0.0, 2.0, 0.05) var close_range_weight: float = 0.35:
	set(value):
		close_range_weight = value
		mark_override(&"close_range_weight")
## 已具备射击条件却选择等待时，每秒增加多少开火分数；避免永远等不到目标精度。
@export_range(0.05, 2.0, 0.05) var wait_pressure_per_second: float = 0.45:
	set(value):
		wait_pressure_per_second = value
		mark_override(&"wait_pressure_per_second")
