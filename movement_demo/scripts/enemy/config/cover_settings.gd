@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"cover"

## 敌人胸部到实际弹道线段的警戒半径（米）；墙挡住来弹时不会隔墙触发。
@export_range(0.1, 5.0, 0.1) var shot_radius: float = 1.5:
	set(value):
		shot_radius = value
		mark_override(&"shot_radius")
## 抵达 Peek 后最多观察多少秒；看见玩家会提前结束，否则转入追踪或搜索。
@export_range(0.1, 10.0, 0.1) var watch_seconds: float = 2.0:
	set(value):
		watch_seconds = value
		mark_override(&"watch_seconds")
## 转身跑向掩体时相对于敌人 Move Speed 的速度倍率。
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier: float = 2.0:
	set(value):
		run_speed_multiplier = value
		mark_override(&"run_speed_multiplier")
## 从躲藏位置移向 Peek 点时相对于敌人 Move Speed 的速度倍率。
@export_range(0.1, 1.0, 0.1) var peek_speed_multiplier: float = 0.5:
	set(value):
		peek_speed_multiplier = value
		mark_override(&"peek_speed_multiplier")
## 掩护撤退时的移动速度倍率；通常比直接冲向掩体慢。
@export_range(0.1, 1.5, 0.1) var covering_retreat_speed_multiplier: float = 0.8:
	set(value):
		covering_retreat_speed_multiplier = value
		mark_override(&"covering_retreat_speed_multiplier")
## 跑向掩体时，连续这么多秒未朝下一个寻路拐点有效推进，就尝试临时绕行。
@export_range(0.2, 3.0, 0.1) var cover_stuck_repath_seconds: float = 0.8:
	set(value):
		cover_stuck_repath_seconds = value
		mark_override(&"cover_stuck_repath_seconds")
## 在上面的时间窗口内，至少要朝 NavigationAgent 当前的下一个路径点靠近这么远，才算确实有进展。
## 贴墙左右抖动、原地滑动不会再误判成正常前进。
@export_range(0.02, 0.5, 0.01) var cover_stuck_min_progress_distance: float = 0.08:
	set(value):
		cover_stuck_min_progress_distance = value
		mark_override(&"cover_stuck_min_progress_distance")
## 同一次跑向掩体最多尝试多少次临时绕行；全部失败后退出本次掩体行为，避免永久卡住。
@export_range(1, 8, 1) var cover_max_detour_retries: int = 4:
	set(value):
		cover_max_detour_retries = value
		mark_override(&"cover_max_detour_retries")
## 卡住时，临时绕行点离当前位置的大致距离。
@export_range(0.5, 4.0, 0.25) var cover_detour_distance: float = 1.5:
	set(value):
		cover_detour_distance = value
		mark_override(&"cover_detour_distance")
## 卡住时优先向当前“去掩体方向”的左右多少度寻找临时绕行点。
@export_range(20.0, 120.0, 5.0) var cover_detour_angle_degrees: float = 65.0:
	set(value):
		cover_detour_angle_degrees = value
		mark_override(&"cover_detour_angle_degrees")
## 距离临时绕行点小于这个值时，认为绕行完成并重新追原 Hide。
@export_range(0.1, 1.0, 0.05) var cover_detour_arrival_distance: float = 0.45:
	set(value):
		cover_detour_arrival_distance = value
		mark_override(&"cover_detour_arrival_distance")
