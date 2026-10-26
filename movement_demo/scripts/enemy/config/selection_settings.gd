@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"selection"

## 【个人与协调器共用】个人和团队均给合法翻越方案加偏好，折算倍率不同，见下文。
## 已通过完整路径与身体预检的翻越方案的基础偏好；0关闭。
## 个人 Utility 按1.5倍扣除总代价（默认3分），团队协调器按原值（默认2分）。
## 不改变实际耗时、暴露或安全检查，其他更有利的方案仍可胜出。
@export_range(0.0, 20.0, 0.25) var vault_preference: float = 2.0:
	set(value):
		vault_preference = maxf(0.0, value)
		mark_override(&"vault_preference")

## 【个人与协调器共用】共用的压制/掩体线索推断；仍受动作权限和真实遮挡检查限制。
## 最后目击位置到掩体表面的最大推断距离；两种压制共用，不依赖出口压制是否解锁。
@export_range(0.1, 4.0, 0.05) var cover_inference_distance: float = 1.75:
	set(value):
		cover_inference_distance = value
		mark_override(&"cover_inference_distance")

## 【个人与协调器共用】已训练攻击占位的共用几何查询，团队候选准备也使用。
## 优质攻击区域至少遮住的身体投影比例；枪口安全仍单独检查。
@export_range(0.05, 0.5, 0.05) var attack_minimum_protection: float = 0.2:
	set(value):
		attack_minimum_protection = value
		mark_override(&"attack_minimum_protection")
## 【个人与协调器共用】已训练攻击占位的共用几何查询，团队候选准备也使用。
## 过多遮挡属于躲藏区；攻击区优先保留约四分之一至半身的遮挡。
@export_range(0.3, 0.9, 0.05) var attack_maximum_protection: float = 0.65:
	set(value):
		attack_maximum_protection = value
		mark_override(&"attack_maximum_protection")
## 【个人与协调器共用】已训练攻击占位的共用几何查询，团队候选准备也使用。
## 在玩家到墙角的遮挡边界附近细分区域；查询仍由空间服务分帧执行。
@export_range(0, 2, 1) var attack_refinement_levels: int = 1:
	set(value):
		attack_refinement_levels = value
		mark_override(&"attack_refinement_levels")

## 【仅个人 Utility】个人掩体质量评估/转移；团队防御岗位另用实际遮蔽检查。
## 开启时额外使用所属掩体的质量门槛和评分；关闭时要求身体中心及两侧被静态墙遮挡。
## 两种模式都必须先位于威胁对侧，且中心射线被当前掩体挡住；不再手动指定 Cover Body。
@export var require_assigned_cover: bool = true:
	set(value):
		require_assigned_cover = value
		mark_override(&"require_assigned_cover")
## 【仅个人 Utility】个人掩体质量评估/转移；团队防御岗位另用实际遮蔽检查。
## 模拟威胁左右移动的距离（米）；仅在要求指定掩体时参与质量门槛和评分，0 表示不做横向模拟。
@export_range(0.0, 2.0, 0.1) var cover_lateral_test_distance: float = 0.5:
	set(value):
		cover_lateral_test_distance = value
		mark_override(&"cover_lateral_test_distance")
## 【仅个人 Utility】个人掩体质量评估/转移；团队防御岗位另用实际遮蔽检查。
## 要求指定掩体时，采样射线中被该墙挡住的最低比例（0～1）；中心射线还必须单独通过检查。
@export_range(0.0, 1.0, 0.05) var minimum_cover_quality: float = 0.20:
	set(value):
		minimum_cover_quality = value
		mark_override(&"minimum_cover_quality")
## 【个人与协调器共用】控制共用候选/动作内部已有的调试打印；不是协调器总日志开关。
## 调试时打印区域候选数量、合格数量及最终选择的掩体和位置。
@export var debug_cover_selection: bool = true:
	set(value):
		debug_cover_selection = value
		mark_override(&"debug_cover_selection")
## 【个人与协调器共用】独立攻击区域预览，两种模式均可诊断；不参与个人或团队评分。
## 高开销旧区域预览，仅专项诊断手动启用；Debug 总开关不自动开启。
@export var debug_attack_points: bool = false:
	set(value):
		debug_attack_points = value
		mark_override(&"debug_attack_points")
