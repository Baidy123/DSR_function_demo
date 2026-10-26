@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"search"

## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## 是否允许 AI 在失去视野后偶尔读取一次墙后玩家的位置。
## 关闭后不再用隐藏位置生成追踪目标，仍保留真实目击方向和来弹推测。
## 距离衰减概率的查询仍会计算玩家距离，但不会据此生成位置提示。
@export var tracking_cheat_enabled: bool = true:
	set(value):
		tracking_cheat_enabled = value
		mark_override(&"tracking_cheat_enabled")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## 刚刚丢失玩家时，立即获得一次“玩家大概位置”提示的概率。
@export_range(0.0, 1.0, 0.05) var lost_target_hint_chance: float = 0.5:
	set(value):
		lost_target_hint_chance = value
		mark_override(&"lost_target_hint_chance")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## 进入 SEARCH 后，每次检查重新获得“大概位置”提示的概率。
@export_range(0.0, 1.0, 0.05) var search_hint_chance: float = 0.35:
	set(value):
		search_hint_chance = value
		mark_override(&"search_hint_chance")
## 【个人与协调器共用】团队采用首个具备搜索能力成员的冻结值，作为全小队提示检查间隔。
## SEARCH 中多久进行一次提示概率检查；不是每帧偷看。
@export_range(0.25, 5.0, 0.25) var search_hint_interval_seconds: float = 1.5:
	set(value):
		search_hint_interval_seconds = value
		mark_override(&"search_hint_interval_seconds")
## 【个人与协调器共用】两套流程分别调用自己的自定义公式；只改个人搜索的扩展函数不会改变团队公式。
## SEARCH 期间的外挂概率如何随调查持续时间/玩家离开搜索中心的距离递减。
## 只影响搜索期间的提示概率，不影响刚失视时的 Lost Target Hint Chance。
## 自定义模式分别调用个人搜索动作/团队搜索服务的扩展公式；默认均返回1，尚未定制时等同不递减。
@export_enum("不递减:0", "按时间线性递减:1", "按时间指数递减:2", "按距离线性递减:3", "时间与距离共同递减:4", "自定义公式:5") var search_hint_decay_mode: int = 4:
	set(value):
		search_hint_decay_mode = value
		mark_override(&"search_hint_decay_mode")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## 递减后的最低倍率。0=最终可降到 0；0.1=最低保留基础概率的 10%。
@export_range(0.0, 1.0, 0.05) var search_hint_min_multiplier: float = 0.05:
	set(value):
		search_hint_min_multiplier = value
		mark_override(&"search_hint_min_multiplier")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## LINEAR_TIME：经过这么多秒后降到最低倍率。
@export_range(0.5, 30.0, 0.5) var search_hint_linear_decay_seconds: float = 8.0:
	set(value):
		search_hint_linear_decay_seconds = value
		mark_override(&"search_hint_linear_decay_seconds")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## EXPONENTIAL_TIME / TIME_AND_DISTANCE：每经过这么多秒，时间部分概率约减半。
@export_range(0.5, 30.0, 0.5) var search_hint_half_life_seconds: float = 4.0:
	set(value):
		search_hint_half_life_seconds = value
		mark_override(&"search_hint_half_life_seconds")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## LINEAR_DISTANCE / TIME_AND_DISTANCE：玩家离开本轮搜索中心这么远后，距离部分降到最低倍率。
@export_range(0.5, 30.0, 0.5) var search_hint_distance_falloff: float = 6.0:
	set(value):
		search_hint_distance_falloff = value
		mark_override(&"search_hint_distance_falloff")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## “外挂”得到的位置误差半径。0 表示几乎知道精确位置，数值越大越模糊。
@export_range(0.0, 5.0, 0.25) var tracking_hint_error_radius: float = 1.25:
	set(value):
		tracking_hint_error_radius = value
		mark_override(&"tracking_hint_error_radius")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## 概率已经命中后，如果误差点刚好落进墙/导航边缘，最多重新采样几次位置。
## 这里只重采样“位置误差”，不会重新掷外挂概率。
@export_range(1, 8, 1) var tracking_hint_position_attempts: int = 4:
	set(value):
		tracking_hint_position_attempts = value
		mark_override(&"tracking_hint_position_attempts")
## 【个人与协调器共用】团队按合格搜索成员的本场冻结配置抽取提示；每次小队机会只抽一次。
## 超过这个距离就不给位置提示，避免跨整个场景透视。
@export_range(1.0, 30.0, 0.5) var tracking_cheat_max_distance: float = 12.0:
	set(value):
		tracking_cheat_max_distance = value
		mark_override(&"tracking_cheat_max_distance")
## 【仅个人 Utility】只控制个人搜索的诊断输出，不控制协调器诊断。
## 打印外挂提示为什么成功/失败，以及 SEARCH 当前实际使用的递减后概率。
@export var debug_tracking_cheat: bool = false:
	set(value):
		debug_tracking_cheat = value
		mark_override(&"debug_tracking_cheat")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## 没拿到位置外挂时，仍可沿玩家最后真实移动方向推进这么远。
@export_range(1.0, 10.0, 0.5) var track_distance: float = 4.0:
	set(value):
		track_distance = value
		mark_override(&"track_distance")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## TRACK 最长持续时间；到达怀疑位置或超时后进入警戒搜索。
@export_range(0.5, 10.0, 0.5) var track_seconds: float = 5.0:
	set(value):
		track_seconds = value
		mark_override(&"track_seconds")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## 普通调查的移动倍率；近期视觉交战可在短路段内使用下方的快速／重点追查速度。
@export_range(0.1, 1.0, 0.05) var track_move_speed_multiplier: float = 0.55:
	set(value):
		track_move_speed_multiplier = value
		mark_override(&"track_move_speed_multiplier")
## 【个人与协调器共用】团队搜索也按最后合法目击的年龄决定是否加速，不由位置提示续期。
## 近期真实目击允许快速追查的时窗；0关闭加速，提示和到点不刷新目击时间。
@export_range(0.0, 8.0, 0.5) var combat_pursuit_seconds: float = 4.0:
	set(value):
		combat_pursuit_seconds = value
		mark_override(&"combat_pursuit_seconds")
## 【个人与协调器共用】团队搜索也按最后合法目击的年龄决定是否加速，不由位置提示续期。
## 快速追查倍率；只用于已有视觉交战记忆，普通声音调查仍用原速度。
@export_range(1.0, 3.0, 0.1) var combat_pursuit_speed_multiplier: float = 1.8:
	set(value):
		combat_pursuit_speed_multiplier = value
		mark_override(&"combat_pursuit_speed_multiplier")
## 【仅个人 Utility】个人新鲜线索阶段的时窗/短停留；不控制团队搜索阶段。
## 优先检查轨迹和掩体出口的总时窗，从最后真实目击开始计算。
@export_range(0.0, 20.0, 0.5) var focused_search_seconds: float = 8.0:
	set(value):
		focused_search_seconds = value
		mark_override(&"focused_search_seconds")
## 【个人与协调器共用】个人用于重点搜索阶段；协调器将其作为搜索任务基础速度，不受 Focused Search Seconds 限制。
## 重点查找移动倍率；已承诺路段结束后才降到原调查／区域搜索速度。
@export_range(0.1, 2.0, 0.1) var focused_search_speed_multiplier: float = 1.0:
	set(value):
		focused_search_speed_multiplier = value
		mark_override(&"focused_search_speed_multiplier")
## 【仅个人 Utility】个人新鲜线索阶段的时窗/短停留；不控制团队搜索阶段。
## 新鲜线索阶段到点观察时长上限，不延长原来的短停留设置。
@export_range(0.0, 1.0, 0.05) var focused_search_pause_seconds: float = 0.25:
	set(value):
		focused_search_pause_seconds = value
		mark_override(&"focused_search_pause_seconds")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## TRACK 时身体朝向对“怀疑方向”的关注权重。1=完全锁定怀疑方向，0=完全朝实际移动方向。
## 推荐 0.65~0.85：明显注意怀疑区域，但绕路时身体也会自然跟随一些移动方向。
@export_range(0.0, 1.0, 0.05) var track_attention_weight: float = 0.75:
	set(value):
		track_attention_weight = value
		mark_override(&"track_attention_weight")
## 【仅个人 Utility】感知服务仅在个人 TRACK 状态扩展视角；团队搜索不进入该状态。
## TRACK 状态的水平总视野角（度）；实际取它与普通 Sight Angle Degrees 的较大值。
## 例如 220° 表示前方左右各约 110°；仍保留身后的盲区，不是 360° 透视。
@export_range(10.0, 360.0, 5.0) var track_sight_angle_degrees: float = 220.0:
	set(value):
		track_sight_angle_degrees = value
		mark_override(&"track_sight_angle_degrees")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## TRACK 的移动目标至少离 NavigationRegion 边界这么远，避免目标贴在 NavMesh 边缘导致角色顶住边界。
@export_range(0.1, 1.5, 0.05) var track_nav_edge_margin: float = 0.35:
	set(value):
		track_nav_edge_margin = value
		mark_override(&"track_nav_edge_margin")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## 判断目标是否贴近 NavMesh 边界时，外围探针允许被吸附回网格的最大误差。
@export_range(0.02, 0.5, 0.01) var track_nav_probe_tolerance: float = 0.12:
	set(value):
		track_nav_probe_tolerance = value
		mark_override(&"track_nav_probe_tolerance")
## 【仅个人 Utility】个人 TRACK 调查流程；团队搜索按协调器任务执行。
## TRACK 距离安全导航目标小于这个距离时直接视为到达，不要求 NavigationAgent 必须精确走到一点。
@export_range(0.1, 1.0, 0.05) var track_arrival_distance: float = 0.45:
	set(value):
		track_arrival_distance = value
		mark_override(&"track_arrival_distance")
## 【仅个人 Utility】个人覆盖/结束规则；团队维护自己的持续区域搜索目标，不使用这些结束条件。
## 到达调查点后记录覆盖的半径；只有实际视角、距离及遮挡允许观察的样本才计入，不扩大真实视野。
@export_range(0.5, 6.0, 0.25) var search_coverage_radius: float = 2.0:
	set(value):
		search_coverage_radius = value
		mark_override(&"search_coverage_radius")
## 【仅个人 Utility】个人覆盖/结束规则；团队维护自己的持续区域搜索目标，不使用这些结束条件。
## 达到这个可达区域覆盖比例后结束本轮搜索；视觉接敌后继续下一轮，不解除警戒。
@export_range(0.8, 1.0, 0.01) var search_coverage_goal: float = 0.95:
	set(value):
		search_coverage_goal = value
		mark_override(&"search_coverage_goal")
## 【仅个人 Utility】个人覆盖/结束规则；团队维护自己的持续区域搜索目标，不使用这些结束条件。
## 未目击玩家的普通调查可选超时；0 = 按覆盖比例结束。视觉接敌后忽略此时限，持续警戒搜索。
@export_range(0.0, 120.0, 1.0) var search_seconds: float = 0.0:
	set(value):
		search_seconds = value
		mark_override(&"search_seconds")
## 【个人与协调器共用】个人用作范围边界；团队取首个搜索成员的冻结值参与选点排序，不限制整区搜索边界。
## 以玩家最后目击位置为圆心的搜索半径；未目击过才采用来弹推测。
## 普通/强配合中参与围绕线索的候选排序，不裁剪本战斗区地图；个人搜索仍以此为范围边界。
@export_range(1.0, 20.0, 0.5) var search_radius: float = 5.0:
	set(value):
		search_radius = value
		mark_override(&"search_radius")
## 【个人与协调器共用】个人到点停留；团队按成员冻结值累计有效观察，最少0.25秒。
## 有效观察时长；团队任务可以边走边累计，关键检查点仍须真实就位。
@export_range(0.0, 5.0, 0.1) var search_pause_seconds: float = 0.5:
	set(value):
		search_pause_seconds = value
		mark_override(&"search_pause_seconds")
## 【仅个人 Utility】个人区域搜索的移动/选点参数；团队使用任务路线与到达规则。
## 距离搜索点小于这个值时直接视为到达，不要求 NavigationAgent 精确踩点。
@export_range(0.1, 1.0, 0.05) var search_arrival_distance: float = 0.5:
	set(value):
		search_arrival_distance = value
		mark_override(&"search_arrival_distance")
## 【仅个人 Utility】个人区域搜索的移动/选点参数；团队使用任务路线与到达规则。
## 原始规则搜索点投影到 NavigationRegion 时，最多允许被吸附这么远；超过就跳过该点。
@export_range(0.1, 2.0, 0.05) var search_nav_snap_tolerance: float = 0.65:
	set(value):
		search_nav_snap_tolerance = value
		mark_override(&"search_nav_snap_tolerance")
## 【仅个人 Utility】个人区域搜索的移动/选点参数；团队使用任务路线与到达规则。
## 线索变旧后的区域搜索移动倍率；声音调查沿用此值，近期视觉交战另有重点搜索速度。
@export_range(0.1, 1.0, 0.05) var search_move_speed_multiplier: float = 0.45:
	set(value):
		search_move_speed_multiplier = value
		mark_override(&"search_move_speed_multiplier")
## 【仅个人 Utility】个人区域搜索的移动/选点参数；团队使用任务路线与到达规则。
## 朝下一个寻路拐点连续这么多秒没有明显推进，就放弃当前搜寻目标，避免卡死。
@export_range(0.2, 3.0, 0.1) var search_stuck_repath_seconds: float = 0.9:
	set(value):
		search_stuck_repath_seconds = value
		mark_override(&"search_stuck_repath_seconds")
## 【仅个人 Utility】个人区域搜索的移动/选点参数；团队使用任务路线与到达规则。
## 到下一个寻路拐点的距离至少缩短这么多米，才算有进展；沿途换拐点会重新计量。
@export_range(0.02, 0.5, 0.01) var search_stuck_min_progress_distance: float = 0.08:
	set(value):
		search_stuck_min_progress_distance = value
		mark_override(&"search_stuck_min_progress_distance")
## 【仅个人 Utility】只控制个人搜索的诊断输出，不控制协调器诊断。
## 调试时打印系统化搜索生成了多少点、当前走到第几个点。
@export var debug_systematic_search: bool = false:
	set(value):
		debug_systematic_search = value
		mark_override(&"debug_systematic_search")
