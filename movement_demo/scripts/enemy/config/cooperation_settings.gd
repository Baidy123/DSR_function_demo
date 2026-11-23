@tool
extends "res://scripts/enemy/config/module_settings.gd"
class_name EnemyCooperationSettings

## 仅由 Squad → Profile 或旧区域显式绑定配置；Training 不再提供此模块。
## 0级个人 Utility 仍读所属小队的情报/间距设置；无绑定时使用各消费点默认值。
enum Level { INTEL_ONLY, TACTICAL, COORDINATED }
const Scoring = preload("res://scripts/enemy/services/squad_scoring.gd")

## 【模式选择】0级由个人 Utility 决策，1/2级由协调器指挥；绑定小队时以 Squad → Profile 为准。
## Levels 1/2 both command the squad; optional actions still require training.
@export_enum("仅视野共享", "战术配合", "强配合") var level: int = Level.INTEL_ONLY:
	set(value):
		level = clampi(value, Level.INTEL_ONLY, Level.COORDINATED)
		mark_override(&"level")

func _init() -> void:
	section = &"cooperation"

## 【个人与协调器共用】共享情报的有效期；配置来自 Squad → Profile，与个人 Training 无关。
## Expiry limits precise shared evidence, never completes a search objective.
@export_range(0.1, 15.0, 0.1) var intel_seconds := 5.0:
	set(value):
		intel_seconds = value
		mark_override(&"intel_seconds")
## 【仅个人 Utility】个人搜索共享已查点的保留时长；团队区域覆盖另行维护。绑定小队时取 Squad → Profile。
@export_range(0.5, 15.0, 0.1) var checked_point_seconds := 3.0:
	set(value):
		checked_point_seconds = value
		mark_override(&"checked_point_seconds")
## 【仅个人 Utility】个人掩体检查记忆；团队搜索拥有持续目标。绑定小队时取 Squad → Profile。
## Personal inspection evidence. Commanded searches own a persistent objective.
@export_range(1.0, 40.0, 0.5) var cover_inspection_seconds := 20.0:
	set(value):
		cover_inspection_seconds = value
		mark_override(&"cover_inspection_seconds")
## 【个人与协调器共用】共用的身体/站位间距；绑定小队时取 Squad → Profile。
@export_range(0.0, 1.0, 0.05) var spacing_margin := 0.45:
	set(value):
		spacing_margin = value
		mark_override(&"spacing_margin")

## 【仅协调器】团队侧翼与赶上队友；绑定小队时取 Squad → Profile，掩体动作速度另读 Cover。
## Commanded flanking and catching up to waiting teammates; frozen per battle.
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier := 2.0:
	set(value):
		run_speed_multiplier = value
		mark_override(&"run_speed_multiplier")

@export_group("团队评分（普通／强配合）")
@export_subgroup("行动与掩体")
## 仅配合等级1/2生效。越大越偏好躲藏、探头和掩护撤退：正代价除以倍率，负偏好分乘倍率。
## 默认1.35，1恢复原评分；不是选择概率，不延长躲藏时间，也不解锁未训练的动作。
## 只比较通过实际遮蔽、路线和身体检查的候选；压力触发阈值仍由成员Training控制。
@export_range(0.1, 5.0, 0.05, "suffix:×") var score_cover_preference := 1.35:
	set(value):
		score_cover_preference = Scoring.sanitize(&"score_cover_preference", value)
		mark_override(&"score_cover_preference")
## 仅配合等级1/2生效。所有动作原候选代价（含转移耗时、暴露等估计）的统一倍率。
## 默认1；增大更看重成员自己的行动成本，相对减轻整队配合项的影响；0只比较整队软代价。
## 不改变真实移速、动作时长和通行限制；各动作内部的估计与训练参数仍沿用原逻辑。
@export_range(0.0, 5.0, 0.05, "suffix:×") var score_action_cost_weight := 1.0:
	set(value):
		score_action_cost_weight = Scoring.sanitize(&"score_action_cost_weight", value)
		mark_override(&"score_action_cost_weight")

@export_subgroup("交战配合")
## 仅配合等级1/2生效。放弃所有攻击岗位、或无人保留当前可持续火力时的代价倍率。
## 默认1；增大更重视有人持续射击，减小更能接受全队暂时停火转移/躲藏；0关闭这两项软代价。
## 不绕过实际目击、射程、屏幕外射击规则和弹药检查。
@export_range(0.0, 5.0, 0.05, "suffix:×") var score_fire_continuity_weight := 1.0:
	set(value):
		score_fire_continuity_weight = Scoring.sanitize(&"score_fire_continuity_weight", value)
		mark_override(&"score_fire_continuity_weight")
## 仅配合等级1/2、全远程交战布局生效。同侧射界重叠的代价倍率，默认1。
## 增大更愿意展开交叉射界，减小更能接受集中站位；0关闭软偏好，身体间距与友军枪线仍必须合法。
@export_range(0.0, 5.0, 0.05, "suffix:×") var score_crossfire_weight := 1.0:
	set(value):
		score_crossfire_weight = Scoring.sanitize(&"score_crossfire_weight", value)
		mark_override(&"score_crossfire_weight")
## 仅配合等级1/2、远近混编交战布局生效。远程后侧位置、远近间距和穿越队友枪线的代价倍率。
## 默认1；增大更重视为近战保留接近空间，减小更看重各自较便宜的站位；0只关闭这些软代价。
## 不改变近战攻击距离、碰撞间距和通行/枪线的硬检查。
@export_range(0.0, 5.0, 0.05, "suffix:×") var score_melee_support_weight := 1.0:
	set(value):
		score_melee_support_weight = Scoring.sanitize(&"score_melee_support_weight", value)
		mark_override(&"score_melee_support_weight")

@export_subgroup("搜索掩护")
## 仅配合等级1/2的搜索布局生效。有可用掩护却未安排、或对同一检查安排重复掩护时的代价倍率。
## 默认1；增大更重视合理分配搜索掩护，减小更看重行动成本；0关闭软代价。
## 掩护仍须关联真实检查任务；没有检查者的孤立掩护、强配合入口同步等硬约束不变。
@export_range(0.0, 5.0, 0.05, "suffix:×") var score_search_support_weight := 1.0:
	set(value):
		score_search_support_weight = Scoring.sanitize(&"score_search_support_weight", value)
		mark_override(&"score_search_support_weight")

@export_group("巡逻（普通／强配合）")
## 每名成员围绕自己的出生点巡逻，不向首个队友集合。只影响未警戒巡逻。
## 小队统一分配有序目的地；导航与身体通行仍需合法，路径额外允许0.5米余量。
@export_range(1.0, 20.0, 0.5, "suffix:m") var patrol_radius := 3.0:
	set(value):
		patrol_radius = clampf(value, 1.0, 20.0) if is_finite(value) else 3.0
		mark_override(&"patrol_radius")
