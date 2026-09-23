extends Node

const ActionDefinition = preload("res://enemy_action_definition.gd")

# 只保存权限和训练参数，不启动、更新或停止动作。
enum SearchHintDecayMode { NONE, LINEAR_TIME, EXPONENTIAL_TIME, LINEAR_DISTANCE, TIME_AND_DISTANCE, CUSTOM }

## 拖入训练允许使用的动作资源；按动作ID匹配，仍须兵种提供并满足现场条件。
@export var allowed_actions: Array[ActionDefinition] = [
	preload("res://enemy_actions/patrol.tres"),
	preload("res://enemy_actions/search.tres"),
	preload("res://enemy_actions/engage.tres"),
	preload("res://enemy_actions/cover.tres"),
	preload("res://enemy_actions/attack_position.tres"),
	preload("res://enemy_actions/suppression.tres"),
	preload("res://enemy_actions/exit_suppression.tres"),
	preload("res://enemy_actions/covering_retreat.tres"),
]

@export_group("通用训练", "ai_")
## 每次巡逻抵达后停留的时间。
@export_range(0.0, 10.0, 0.1) var ai_patrol_pause_seconds: float = 1.5
## 受击时只知道攻击者附近区域，不持续获取攻击者坐标。
@export_range(0.0, 5.0, 0.1) var ai_attack_position_uncertainty: float = 1.0

@export_group("接敌与射击", "tactics_")
## 是否掌握面向威胁的撤退射击；关闭时概率再高也不会使用。
## 此处直接决定训练权限；默认开启，保留现有敌人的表现。
@export var tactics_can_covering_retreat: bool = true
## 是否掌握主动选择墙角攻击位置；优先保证散布射界，不强制身体被遮挡。
## 默认开启供试玩；不影响普通换位或躲藏能力。
@export var tactics_can_use_attack_positions: bool = true
## 是否掌握失视后朝最后目击区域压制的能力；具体持续时间和范围在SuppressionAction。
@export var tactics_can_suppress_fire: bool = true
## 高训练专属动作的临时能力接口，默认关闭；还需最后目击邻近掩体且两端可射击。
## 该开关控制当前训练权限；开启不自动代表某个正式训练等级。
@export var tactics_can_suppress_exits: bool = false
## 首次／重新真实目击玩家，或真正受伤且有攻击者位置时，尝试攻击占位的概率。
## 持续可见不重抽；攻击占位或掩体动作中不重选。0=不触发，1=每次满足条件都尝试。
## 两种触发共用此概率；0.5是可调试玩初值。
@export_range(0.0, 1.0, 0.05) var tactics_attack_position_chance: float = 0.5
## 接敌侧移/后退和掩护撤退时允许开火；关闭后只在停稳时射击，转身冲刺仍停火。
@export var tactics_fire_while_moving: bool = true
## 首次发现或重新取得有效视线后，至少观察多久才允许射击（秒）；0可关闭。
@export_range(0.0, 5.0, 0.05) var tactics_fire_reaction_seconds: float = 0.3
## 普通交火（含接敌跑打）希望达到的中心概率；0.7表示70%，不是最终命中率。
## 用作FireDecision评分的精度偏好，低于目标也可选择射击；掩护撤退不等待稳枪。
@export_range(0.0, 1.0, 0.05) var tactics_fire_stability_target: float = 0.7
## 每轮实际打出几枪后暂停；只统计执行成功的射击，不按命中次数计数。
@export_range(1, 20, 1) var tactics_burst_shot_count: int = 3
## 每轮最后一枪后的停火时间（秒）；与枪械冷却并行，必须都结束才能再开火。
@export_range(0.0, 10.0, 0.05) var tactics_burst_pause_seconds: float = 1.0
## 远程敌人希望保持的距离区间，单位为米。
@export_range(1.0, 20.0, 0.5) var tactics_ranged_min_distance: float = 4.0
## 远程期望距离上限（米）；与下限共同决定射击候选点的采样范围。
@export_range(2.0, 25.0, 0.5) var tactics_ranged_max_distance: float = 6.0
## 选位有冷却，且有效目标会继续沿用，避免频繁左右换路。
@export_range(0.1, 5.0, 0.05) var tactics_ranged_repath_seconds: float = 0.75
## 远程选位时更偏好侧向换位，而不是只沿玩家径向前后移动。
@export_range(0.0, 10.0, 0.1) var tactics_ranged_flank_weight: float = 3.0
## 候选射击位附近若有侧墙/后墙，可获得额外战术价值。
@export_range(0.0, 10.0, 0.1) var tactics_ranged_wall_support_weight: float = 2.5
## 探测候选射击位附近墙体的距离。
@export_range(0.5, 4.0, 0.1) var tactics_ranged_wall_probe_distance: float = 1.5
## 近战接近时的停止距离（米）；远程保持距离由 Ranged Min/Max Distance 控制。
@export var tactics_stopping_distance: float = 1.3

@export_group("追踪与搜索", "search_")
## 是否允许 AI 在失去视野后偶尔读取一次墙后玩家的位置。
## 关闭后不再用隐藏位置生成追踪目标，仍保留真实目击方向和来弹推测。
## 距离衰减概率的查询仍会计算玩家距离，但不会据此生成位置提示。
@export var search_tracking_cheat_enabled: bool = true
## 刚刚丢失玩家时，立即获得一次“玩家大概位置”提示的概率。
@export_range(0.0, 1.0, 0.05) var search_lost_target_hint_chance: float = 0.5
## 进入 SEARCH 后，每次检查重新获得“大概位置”提示的概率。
@export_range(0.0, 1.0, 0.05) var search_search_hint_chance: float = 0.35
## SEARCH 中多久进行一次提示概率检查；不是每帧偷看。
@export_range(0.25, 5.0, 0.25) var search_search_hint_interval_seconds: float = 1.5
## SEARCH 期间的外挂概率如何随调查持续时间/玩家离开搜索中心的距离递减。
@export var search_search_hint_decay_mode: SearchHintDecayMode = SearchHintDecayMode.TIME_AND_DISTANCE
## 递减后的最低倍率。0=最终可降到 0；0.1=最低保留基础概率的 10%。
@export_range(0.0, 1.0, 0.05) var search_search_hint_min_multiplier: float = 0.05
## LINEAR_TIME：经过这么多秒后降到最低倍率。
@export_range(0.5, 30.0, 0.5) var search_search_hint_linear_decay_seconds: float = 8.0
## EXPONENTIAL_TIME / TIME_AND_DISTANCE：每经过这么多秒，时间部分概率约减半。
@export_range(0.5, 30.0, 0.5) var search_search_hint_half_life_seconds: float = 4.0
## LINEAR_DISTANCE / TIME_AND_DISTANCE：玩家离开本轮搜索中心这么远后，距离部分降到最低倍率。
@export_range(0.5, 30.0, 0.5) var search_search_hint_distance_falloff: float = 6.0
## “外挂”得到的位置误差半径。0 表示几乎知道精确位置，数值越大越模糊。
@export_range(0.0, 5.0, 0.25) var search_tracking_hint_error_radius: float = 1.25
## 概率已经命中后，如果误差点刚好落进墙/导航边缘，最多重新采样几次位置。
## 这里只重采样“位置误差”，不会重新掷外挂概率。
@export_range(1, 8, 1) var search_tracking_hint_position_attempts: int = 4
## 超过这个距离就不给位置提示，避免跨整个场景透视。
@export_range(1.0, 30.0, 0.5) var search_tracking_cheat_max_distance: float = 12.0
## 打印外挂提示为什么成功/失败，以及 SEARCH 当前实际使用的递减后概率。
@export var search_debug_tracking_cheat: bool = false
## 没拿到位置外挂时，仍可沿玩家最后真实移动方向推进这么远。
@export_range(1.0, 10.0, 0.5) var search_track_distance: float = 4.0
## TRACK 最长持续时间；到达怀疑位置或超时后进入警戒搜索。
@export_range(0.5, 10.0, 0.5) var search_track_seconds: float = 5.0
## 架枪追踪时的移动速度倍率。
@export_range(0.1, 1.0, 0.05) var search_track_move_speed_multiplier: float = 0.55
## TRACK 时身体朝向对“怀疑方向”的关注权重。1=完全锁定怀疑方向，0=完全朝实际移动方向。
## 推荐 0.65~0.85：明显注意怀疑区域，但绕路时身体也会自然跟随一些移动方向。
@export_range(0.0, 1.0, 0.05) var search_track_attention_weight: float = 0.75
## TRACK 状态的水平总视野角（度）；实际取它与普通 Sight Angle Degrees 的较大值。
## 例如 220° 表示前方左右各约 110°；仍保留身后的盲区，不是 360° 透视。
@export_range(10.0, 360.0, 5.0) var search_track_sight_angle_degrees: float = 220.0
## TRACK 的移动目标至少离 NavigationRegion 边界这么远，避免目标贴在 NavMesh 边缘导致角色顶住边界。
@export_range(0.1, 1.5, 0.05) var search_track_nav_edge_margin: float = 0.35
## 判断目标是否贴近 NavMesh 边界时，外围探针允许被吸附回网格的最大误差。
@export_range(0.02, 0.5, 0.01) var search_track_nav_probe_tolerance: float = 0.12
## TRACK 距离安全导航目标小于这个距离时直接视为到达，不要求 NavigationAgent 必须精确走到一点。
@export_range(0.1, 1.0, 0.05) var search_track_arrival_distance: float = 0.45
## 小圆的假想覆盖半径；仅用于搜索进度，不改变真实视野，也不考虑墙壁遮挡。
@export_range(0.5, 6.0, 0.25) var search_search_coverage_radius: float = 2.0
## 达到这个可达区域覆盖比例后结束本轮搜索。
@export_range(0.8, 1.0, 0.01) var search_search_coverage_goal: float = 0.95
## SEARCH 的可选保险超时。0 = 按覆盖比例结束，当前场景使用 0。
@export_range(0.0, 120.0, 1.0) var search_search_seconds: float = 0.0
## 以玩家最后目击位置为圆心的搜索半径；未目击过才采用来弹推测。
@export_range(1.0, 20.0, 0.5) var search_search_radius: float = 5.0
## 每到一个搜索点后停留观察多久。
@export_range(0.0, 5.0, 0.1) var search_search_pause_seconds: float = 0.5
## 距离搜索点小于这个值时直接视为到达，不要求 NavigationAgent 精确踩点。
@export_range(0.1, 1.0, 0.05) var search_search_arrival_distance: float = 0.5
## 原始规则搜索点投影到 NavigationRegion 时，最多允许被吸附这么远；超过就跳过该点。
@export_range(0.1, 2.0, 0.05) var search_search_nav_snap_tolerance: float = 0.65
## SEARCH 搜索期间的移动速度倍率。
@export_range(0.1, 1.0, 0.05) var search_search_move_speed_multiplier: float = 0.45
## 朝下一个寻路拐点连续这么多秒没有明显推进，就放弃当前搜寻目标，避免卡死。
@export_range(0.2, 3.0, 0.1) var search_search_stuck_repath_seconds: float = 0.9
## 到下一个寻路拐点的距离至少缩短这么多米，才算有进展；沿途换拐点会重新计量。
@export_range(0.02, 0.5, 0.01) var search_search_stuck_min_progress_distance: float = 0.08
## 调试时打印系统化搜索生成了多少点、当前走到第几个点。
@export var search_debug_systematic_search: bool = false

@export_group("掩体动作", "cover_")
## 敌人胸部到实际弹道线段的警戒半径（米）；墙挡住来弹时不会隔墙触发。
@export_range(0.1, 5.0, 0.1) var cover_shot_radius: float = 1.5
## 每次新的有效近身来弹触发“寻找掩体”的概率。0=从不找掩体，1=每次都找。
## 已经处于跑向掩体/躲藏/探头流程时不会重新掷骰子，避免连续来弹让行为反复取消。
@export_range(0.0, 1.0, 0.05) var cover_take_cover_chance: float = 1.0
## 到达有效躲藏位置后等待探头的秒数；新来弹可重新计时，真正看见玩家则立即结束躲藏。
@export_range(0.1, 10.0, 0.1) var cover_hide_seconds: float = 3.0
## 抵达 Peek 后最多观察多少秒；看见玩家会提前结束，否则转入追踪或搜索。
@export_range(0.1, 10.0, 0.1) var cover_watch_seconds: float = 2.0
## 转身跑向掩体时相对于敌人 Move Speed 的速度倍率。
@export_range(1.0, 3.0, 0.1) var cover_run_speed_multiplier: float = 2.0
## 从躲藏位置移向 Peek 点时相对于敌人 Move Speed 的速度倍率。
@export_range(0.1, 1.0, 0.1) var cover_peek_speed_multiplier: float = 0.5
## 跑向掩体时改为“面向威胁撤退”的概率。0=永远转身跑，1=每次都掩护撤退。
@export_range(0.0, 1.0, 0.05) var cover_covering_retreat_chance: float = 0.4
## 掩护撤退时的移动速度倍率；通常比直接冲向掩体慢。
@export_range(0.1, 1.5, 0.1) var cover_covering_retreat_speed_multiplier: float = 0.8
## RUN_TO_COVER 期间每次真正受到伤害时，放弃掩护撤退并改为全速冲刺的概率。
## 每次受伤都会重新判定；0=中弹也继续掩护撤退，1=一中弹就立刻冲刺。
@export_range(0.0, 1.0, 0.05) var cover_damage_force_sprint_chance: float = 0.5
## 跑向掩体时，连续这么多秒未朝下一个寻路拐点有效推进，就尝试临时绕行。
@export_range(0.2, 3.0, 0.1) var cover_cover_stuck_repath_seconds: float = 0.8
## 在上面的时间窗口内，至少要朝 NavigationAgent 当前的下一个路径点靠近这么远，才算确实有进展。
## 贴墙左右抖动、原地滑动不会再误判成正常前进。
@export_range(0.02, 0.5, 0.01) var cover_cover_stuck_min_progress_distance: float = 0.08
## 同一次跑向掩体最多尝试多少次临时绕行；全部失败后退出本次掩体行为，避免永久卡住。
@export_range(1, 8, 1) var cover_cover_max_detour_retries: int = 4
## 卡住时，临时绕行点离当前位置的大致距离。
@export_range(0.5, 4.0, 0.25) var cover_cover_detour_distance: float = 1.5
## 卡住时优先向当前“去掩体方向”的左右多少度寻找临时绕行点。
@export_range(20.0, 120.0, 5.0) var cover_cover_detour_angle_degrees: float = 65.0
## 距离临时绕行点小于这个值时，认为绕行完成并重新追原 Hide。
@export_range(0.1, 1.0, 0.05) var cover_cover_detour_arrival_distance: float = 0.45

@export_group("普通压制", "suppression_")
## 朝最后目击位置附近压制的最短秒数；当前未接弹匣。
@export_range(0.1, 10.0, 0.1) var suppression_duration_min: float = 3.0
## 最长秒数，每次在最短与最长之间抽取；至少等于最短值。
@export_range(0.1, 10.0, 0.1) var suppression_duration_max: float = 5.0
## 瞄准点在最后目击位置周围的水平采样半径；实际子弹继续使用枪械散布。
@export_range(0.0, 3.0, 0.05) var suppression_target_radius: float = 0.75

@export_group("出口压制", "exit_suppression_")
## 朝最后目击位置附近压制的最短秒数；当前未接弹匣。
@export_range(0.1, 10.0, 0.1) var exit_suppression_duration_min: float = 3.0
## 最长秒数，每次在最短与最长之间抽取；至少等于最短值。
@export_range(0.1, 10.0, 0.1) var exit_suppression_duration_max: float = 5.0
## 瞄准点在最后目击位置周围的水平采样半径；实际子弹继续使用枪械散布。
@export_range(0.0, 3.0, 0.05) var exit_suppression_target_radius: float = 0.75
## 最后目击位置离掩体实体表面的最大水平距离；只推测邻近掩体，不追踪墙后玩家。
@export_range(0.1, 4.0, 0.05) var exit_suppression_cover_inference_distance: float = 1.75
## 每侧随机连续打出的枪数范围；仅实际开火才计数，冷却和连射停顿不换边。
@export_range(1, 20, 1) var exit_suppression_shots_per_exit_min: int = 2

@export_range(1, 20, 1) var exit_suppression_shots_per_exit_max: int = 5

@export_group("开火判断", "fire_decision_")
## 稳定度正在提高时，继续稳枪可获得多少额外分数。
@export_range(0.0, 2.0, 0.05) var fire_decision_recovery_gain_weight: float = 0.35
## 敌人被逼近到最小交战距离以内时，增加多少开火分数。
@export_range(0.0, 2.0, 0.05) var fire_decision_close_range_weight: float = 0.35
## 已具备射击条件却选择等待时，每秒增加多少开火分数；避免永远等不到目标精度。
@export_range(0.05, 2.0, 0.05) var fire_decision_wait_pressure_per_second: float = 0.45

@export_group("感知", "perception_")
## 是否接收玩家移动和开枪的声源；调查仍受UnitType/Training的search权限限制。
@export var perception_hearing_enabled: bool = true
## 普通视觉感知的最大距离（米）；仍受视角、墙壁和竞技场范围限制。
@export var perception_sight_distance: float = 10.0
## 普通视野的水平总角度（度）；左右各占一半，近身警戒不受此角度限制。
@export_range(10.0, 360.0, 5.0) var perception_sight_angle_degrees: float = 120.0
## 近身警戒不限制方向，但仍检测墙壁遮挡。
@export_range(0.0, 5.0, 0.1) var perception_close_awareness_radius: float = 2.0

@export_group("掩体评估", "selection_")
## 掩体选位：朝远离威胁方向移动会得到奖励，朝威胁方向冲会被强烈惩罚。
@export_range(0.0, 10.0, 0.1) var selection_away_from_threat_weight: float = 4.0
## 路径或掩体位置比当前位置更靠近威胁时的惩罚。
@export_range(0.0, 10.0, 0.1) var selection_closer_to_threat_weight: float = 5.0
## 开启时额外使用所属掩体的质量门槛和评分；关闭时要求身体中心及两侧被静态墙遮挡。
## 两种模式都必须先位于威胁对侧，且中心射线被当前掩体挡住；不再手动指定 Cover Body。
@export var selection_require_assigned_cover: bool = true
## 模拟威胁左右移动的距离（米）；仅在要求指定掩体时参与质量门槛和评分，0 表示不做横向模拟。
@export_range(0.0, 2.0, 0.1) var selection_cover_lateral_test_distance: float = 0.5
## 要求指定掩体时，采样射线中被该墙挡住的最低比例（0～1）；中心射线还必须单独通过检查。
@export_range(0.0, 1.0, 0.05) var selection_minimum_cover_quality: float = 0.20
## 掩护质量越高，越优先选择。
@export_range(0.0, 10.0, 0.1) var selection_cover_quality_weight: float = 3.0
## 调试时打印区域候选数量、合格数量及最终选择的掩体和位置。
@export var selection_debug_cover_selection: bool = true
## Debug运行时显示攻击候选评估：绿=可用，红=淘汰；只按最后目击位置查询，不控制AI动作。
@export var selection_debug_attack_points: bool = true

func allows_action(id: StringName) -> bool:
	var permitted := false
	for definition in allowed_actions:
		if definition != null and definition.action_id == id:
			permitted = true
			break
	if not permitted:
		return false
	match id:
		&"attack_position": return tactics_can_use_attack_positions
		&"suppression": return tactics_can_suppress_fire
		&"exit_suppression": return tactics_can_suppress_fire and tactics_can_suppress_exits
		&"covering_retreat": return tactics_can_covering_retreat
	return true
