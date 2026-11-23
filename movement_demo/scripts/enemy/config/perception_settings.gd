@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"perception"

## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 是否接收玩家移动和开枪的声源；调查仍受UnitType/Training的search权限限制。
@export var hearing_enabled: bool = true:
	set(value):
		hearing_enabled = value
		mark_override(&"hearing_enabled")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 远程敌人开启后使用自身武器 Aim Range 加额外感知距离；近战／无武器仍使用 Sight Distance。
@export var use_weapon_sight_range: bool = true:
	set(value):
		use_weapon_sight_range = value
		mark_override(&"use_weapon_sight_range")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 远程武器锁定距离之外额外看多远（米）；只扩展感知，屏幕外射击概率另由敌人根节点 Offscreen Fire Chance 控制。
@export_range(0.0, 20.0, 0.5, "suffix:m") var weapon_sight_extra_distance: float = 2.0:
	set(value):
		weapon_sight_extra_distance = value
		mark_override(&"weapon_sight_extra_distance")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 近战／无武器或关闭武器联动时的视距（米）；仍受视角、墙壁和竞技场范围限制。
@export var sight_distance: float = 10.0:
	set(value):
		sight_distance = value
		mark_override(&"sight_distance")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 普通视野的水平总角度（度）；左右各占一半，近身警戒不受此角度限制。
@export_range(10.0, 360.0, 5.0) var sight_angle_degrees: float = 120.0:
	set(value):
		sight_angle_degrees = value
		mark_override(&"sight_angle_degrees")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 近身警戒不限制方向，但仍检测墙壁遮挡。
@export_range(0.0, 5.0, 0.1) var close_awareness_radius: float = 2.0:
	set(value):
		close_awareness_radius = value
		mark_override(&"close_awareness_radius")

## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 连续看见玩家换弹多久后形成机会判断；失视打断尚未完成的观察。
@export_range(0.0, 2.0, 0.05) var reload_observation_seconds: float = 0.15:
	set(value):
		reload_observation_seconds = value
		mark_override(&"reload_observation_seconds")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## 最后一次观察到换弹后保留多久的机会证据；不读取墙后的换弹进度。
@export_range(0.0, 3.0, 0.05) var reload_memory_seconds: float = 0.8:
	set(value):
		reload_memory_seconds = value
		mark_override(&"reload_memory_seconds")

## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
## Optional non-visual exact clue, separately authorized for finite suppression.
@export var close_cover_intelligence_enabled := true:
	set(value):
		close_cover_intelligence_enabled = value
		mark_override(&"close_cover_intelligence_enabled")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
@export_range(0.5, 5.0, 0.1) var close_cover_intelligence_distance := 2.0:
	set(value):
		close_cover_intelligence_distance = value
		mark_override(&"close_cover_intelligence_distance")
## 【个人与协调器共用】成员的共用感知/证据查询；协调器指挥也遵守，具体动作仍须另行满足权限。
@export_range(0.5, 20.0, 0.5) var close_cover_intelligence_cooldown := 4.0:
	set(value):
		close_cover_intelligence_cooldown = value
		mark_override(&"close_cover_intelligence_cooldown")
