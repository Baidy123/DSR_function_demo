@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"suppression"

## 一次压制允许窗口的随机下界；原连射剩余枪数打完、空匣或射界失效会提前结束。
@export_range(0.1, 10.0, 0.1) var duration_min: float = 3.0:
	set(value):
		duration_min = value
		mark_override(&"duration_min")
## 允许窗口的随机上界；还受证据有效期和真实剩余连射枪数限制。
@export_range(0.1, 10.0, 0.1) var duration_max: float = 5.0:
	set(value):
		duration_max = value
		mark_override(&"duration_max")
## 瞄准点在冻结的真实可射身体点周围采样；完整硬遮挡样本会被剔除。
@export_range(0.0, 3.0, 0.05) var target_radius: float = 0.75:
	set(value):
		target_radius = value
		mark_override(&"target_radius")

## 已经具有真实个人失视或队友掩护理由、且完整枪线可达的低墙消失点偏好。
@export_range(0.0, 5.0, 0.1) var low_cover_point_preference: float = 1.0:
	set(value):
		low_cover_point_preference = value
		mark_override(&"low_cover_point_preference")

## Deprecated storage only: opening an old resource preserves its overrides.
@export_storage var exit_duration_min: float = 3.0:
	set(value):
		exit_duration_min = value
		mark_override(&"exit_duration_min")
@export_storage var exit_duration_max: float = 5.0:
	set(value):
		exit_duration_max = value
		mark_override(&"exit_duration_max")
@export_storage var shots_per_exit_min: int = 2:
	set(value):
		shots_per_exit_min = value
		mark_override(&"shots_per_exit_min")
@export_storage var shots_per_exit_max: int = 5:
	set(value):
		shots_per_exit_max = value
		mark_override(&"shots_per_exit_max")
