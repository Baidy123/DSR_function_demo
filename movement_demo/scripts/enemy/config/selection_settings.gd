@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"selection"

## 优质攻击区域至少遮住的身体投影比例；枪口安全仍单独检查。
@export_range(0.05, 0.5, 0.05) var attack_minimum_protection: float = 0.2:
	set(value):
		attack_minimum_protection = value
		mark_override(&"attack_minimum_protection")
## 过多遮挡属于躲藏区；攻击区优先保留约四分之一至半身的遮挡。
@export_range(0.3, 0.9, 0.05) var attack_maximum_protection: float = 0.65:
	set(value):
		attack_maximum_protection = value
		mark_override(&"attack_maximum_protection")
## 在玩家到墙角的遮挡边界附近细分区域；查询仍由空间服务分帧执行。
@export_range(0, 2, 1) var attack_refinement_levels: int = 1:
	set(value):
		attack_refinement_levels = value
		mark_override(&"attack_refinement_levels")

## 掩体选位：朝远离威胁方向移动会得到奖励，朝威胁方向冲会被强烈惩罚。
@export_range(0.0, 10.0, 0.1) var away_from_threat_weight: float = 4.0:
	set(value):
		away_from_threat_weight = value
		mark_override(&"away_from_threat_weight")
## 路径或掩体位置比当前位置更靠近威胁时的惩罚。
@export_range(0.0, 10.0, 0.1) var closer_to_threat_weight: float = 5.0:
	set(value):
		closer_to_threat_weight = value
		mark_override(&"closer_to_threat_weight")
## 开启时额外使用所属掩体的质量门槛和评分；关闭时要求身体中心及两侧被静态墙遮挡。
## 两种模式都必须先位于威胁对侧，且中心射线被当前掩体挡住；不再手动指定 Cover Body。
@export var require_assigned_cover: bool = true:
	set(value):
		require_assigned_cover = value
		mark_override(&"require_assigned_cover")
## 模拟威胁左右移动的距离（米）；仅在要求指定掩体时参与质量门槛和评分，0 表示不做横向模拟。
@export_range(0.0, 2.0, 0.1) var cover_lateral_test_distance: float = 0.5:
	set(value):
		cover_lateral_test_distance = value
		mark_override(&"cover_lateral_test_distance")
## 要求指定掩体时，采样射线中被该墙挡住的最低比例（0～1）；中心射线还必须单独通过检查。
@export_range(0.0, 1.0, 0.05) var minimum_cover_quality: float = 0.20:
	set(value):
		minimum_cover_quality = value
		mark_override(&"minimum_cover_quality")
## 掩护质量越高，越优先选择。
@export_range(0.0, 10.0, 0.1) var cover_quality_weight: float = 3.0:
	set(value):
		cover_quality_weight = value
		mark_override(&"cover_quality_weight")
## 调试时打印区域候选数量、合格数量及最终选择的掩体和位置。
@export var debug_cover_selection: bool = true:
	set(value):
		debug_cover_selection = value
		mark_override(&"debug_cover_selection")
## Debug运行时显示攻击区域：绿=可用，橙=未通过，暗红=内圈禁用；只用目击记忆。
@export var debug_attack_points: bool = true:
	set(value):
		debug_attack_points = value
		mark_override(&"debug_attack_points")
