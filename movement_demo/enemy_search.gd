extends Node

# 搜寻：丢失目标后的预测追踪、调查和区域搜索。由 AI 统一调用。
enum SearchHintDecayMode {
	NONE,
	LINEAR_TIME,
	EXPONENTIAL_TIME,
	LINEAR_DISTANCE,
	TIME_AND_DISTANCE,
	CUSTOM
}

@export_group("Tracking Hints")
## 是否允许 AI 在失去视野后偶尔读取一次墙后玩家的位置。
## 关闭后不再用隐藏位置生成追踪目标，仍保留真实目击方向和来弹推测。
## 距离衰减概率的查询仍会计算玩家距离，但不会据此生成位置提示。
@export var tracking_cheat_enabled: bool = true
## 刚刚丢失玩家时，立即获得一次“玩家大概位置”提示的概率。
@export_range(0.0, 1.0, 0.05) var lost_target_hint_chance: float = 0.5
## 进入 SEARCH 后，每次检查重新获得“大概位置”提示的概率。
@export_range(0.0, 1.0, 0.05) var search_hint_chance: float = 0.35
## SEARCH 中多久进行一次提示概率检查；不是每帧偷看。
@export_range(0.25, 5.0, 0.25) var search_hint_interval_seconds: float = 1.5
## SEARCH 期间的外挂概率如何随调查持续时间/玩家离开搜索中心的距离递减。
@export var search_hint_decay_mode: SearchHintDecayMode = SearchHintDecayMode.TIME_AND_DISTANCE
## 递减后的最低倍率。0=最终可降到 0；0.1=最低保留基础概率的 10%。
@export_range(0.0, 1.0, 0.05) var search_hint_min_multiplier: float = 0.05
## LINEAR_TIME：经过这么多秒后降到最低倍率。
@export_range(0.5, 30.0, 0.5) var search_hint_linear_decay_seconds: float = 8.0
## EXPONENTIAL_TIME / TIME_AND_DISTANCE：每经过这么多秒，时间部分概率约减半。
@export_range(0.5, 30.0, 0.5) var search_hint_half_life_seconds: float = 4.0
## LINEAR_DISTANCE / TIME_AND_DISTANCE：玩家离开本轮搜索中心这么远后，距离部分降到最低倍率。
@export_range(0.5, 30.0, 0.5) var search_hint_distance_falloff: float = 6.0
## “外挂”得到的位置误差半径。0 表示几乎知道精确位置，数值越大越模糊。
@export_range(0.0, 5.0, 0.25) var tracking_hint_error_radius: float = 1.25
## 概率已经命中后，如果误差点刚好落进墙/导航边缘，最多重新采样几次位置。
## 这里只重采样“位置误差”，不会重新掷外挂概率。
@export_range(1, 8, 1) var tracking_hint_position_attempts: int = 4
## 超过这个距离就不给位置提示，避免跨整个场景透视。
@export_range(1.0, 30.0, 0.5) var tracking_cheat_max_distance: float = 12.0
## 打印外挂提示为什么成功/失败，以及 SEARCH 当前实际使用的递减后概率。
@export var debug_tracking_cheat: bool = false
@export_group("Tracking Movement")
## 没拿到位置外挂时，仍可沿玩家最后真实移动方向推进这么远。
@export_range(1.0, 10.0, 0.5) var track_distance: float = 4.0
## TRACK 最长持续时间；到达怀疑位置或超时后进入警戒搜索。
@export_range(0.5, 10.0, 0.5) var track_seconds: float = 5.0
## 架枪追踪时的移动速度倍率。
@export_range(0.1, 1.0, 0.05) var track_move_speed_multiplier: float = 0.55
## TRACK 时身体朝向对“怀疑方向”的关注权重。1=完全锁定怀疑方向，0=完全朝实际移动方向。
## 推荐 0.65~0.85：明显注意怀疑区域，但绕路时身体也会自然跟随一些移动方向。
@export_range(0.0, 1.0, 0.05) var track_attention_weight: float = 0.75
## TRACK 状态的水平总视野角（度）；实际取它与普通 Sight Angle Degrees 的较大值。
## 例如 220° 表示前方左右各约 110°；仍保留身后的盲区，不是 360° 透视。
@export_range(10.0, 360.0, 5.0) var track_sight_angle_degrees: float = 220.0
## TRACK 的移动目标至少离 NavigationRegion 边界这么远，避免目标贴在 NavMesh 边缘导致角色顶住边界。
@export_range(0.1, 1.5, 0.05) var track_nav_edge_margin: float = 0.35
## 判断目标是否贴近 NavMesh 边界时，外围探针允许被吸附回网格的最大误差。
@export_range(0.02, 0.5, 0.01) var track_nav_probe_tolerance: float = 0.12
## TRACK 距离安全导航目标小于这个距离时直接视为到达，不要求 NavigationAgent 必须精确走到一点。
@export_range(0.1, 1.0, 0.05) var track_arrival_distance: float = 0.45
@export_group("Area Search")
## 小圆的假想覆盖半径；仅用于搜索进度，不改变真实视野，也不考虑墙壁遮挡。
@export_range(0.5, 6.0, 0.25) var search_coverage_radius: float = 2.0
## 达到这个可达区域覆盖比例后结束本轮搜索。
@export_range(0.8, 1.0, 0.01) var search_coverage_goal: float = 0.95
## SEARCH 的可选保险超时。0 = 按覆盖比例结束，当前场景使用 0。
@export_range(0.0, 120.0, 1.0) var search_seconds: float = 0.0
## 以玩家最后目击位置为圆心的搜索半径；未目击过才采用来弹推测。
@export_range(1.0, 20.0, 0.5) var search_radius: float = 5.0
## 每到一个搜索点后停留观察多久。
@export_range(0.0, 5.0, 0.1) var search_pause_seconds: float = 0.5
## 距离搜索点小于这个值时直接视为到达，不要求 NavigationAgent 精确踩点。
@export_range(0.1, 1.0, 0.05) var search_arrival_distance: float = 0.5
## 原始规则搜索点投影到 NavigationRegion 时，最多允许被吸附这么远；超过就跳过该点。
@export_range(0.1, 2.0, 0.05) var search_nav_snap_tolerance: float = 0.65
## SEARCH 搜索期间的移动速度倍率。
@export_range(0.1, 1.0, 0.05) var search_move_speed_multiplier: float = 0.45
## 朝下一个寻路拐点连续这么多秒没有明显推进，就放弃当前搜寻目标，避免卡死。
@export_range(0.2, 3.0, 0.1) var search_stuck_repath_seconds: float = 0.9
## 到下一个寻路拐点的距离至少缩短这么多米，才算有进展；沿途换拐点会重新计量。
@export_range(0.02, 0.5, 0.01) var search_stuck_min_progress_distance: float = 0.08
## 调试时打印系统化搜索生成了多少点、当前走到第几个点。
@export var debug_systematic_search: bool = false
## TRACK 实际要走到的安全导航目标；必须位于 NavigationRegion 内且与边界保留余量。
var suspected_position: Vector3
## TRACK 架枪时持续瞄准的“怀疑位置”。它与移动目标分离，允许脚下绕路但不会把枪口带偏。
## 该点也会先吸附到 NavigationRegion，因此不会生成在地图/NavMesh 外。
var suspected_look_position: Vector3
var has_suspected_position: bool = false
var track_timer: float = 0.0
var search_direction: Vector3 = Vector3.ZERO
var search_hint_timer: float = 0.0
## 尚未尝试、且未被已抵达目标的小圆覆盖的搜寻候选点。
var search_sweep_points: Array[Vector3] = []
# 均匀采样近似面积；只有抵达搜寻目标才删去小圆内的样本，寻路拐点不计入。
var search_uncovered_points: Array[Vector3] = []
var search_sample_count: int = 0
var search_progress_waypoint: Vector3 = Vector3.INF
var search_target_timer: float = 0.0
var search_sweep_index: int = 0
var search_current_target: Vector3 = Vector3.ZERO
var search_current_target_active: bool = false
var search_progress_best_distance: float = INF
var search_stuck_timer: float = 0.0
var search_elapsed_seconds: float = 0.0
var search_origin: Vector3
var search_timer: float = 0.0
var search_pause_timer: float = 0.0
var search_is_pausing: bool = false

const Actor = preload("res://enemy_actor.gd")
@onready var ai = get_parent()
@onready var actor: Actor = get_parent().get_parent()
@onready var agent: NavigationAgent3D = actor.get_node("NavigationAgent3D")


func begin_tracking_or_search(allow_hint: bool = true) -> void:
	ai.is_alerted = true
	ai.tactics.ranged_has_destination = false
	ai.tactics.ranged_repath_timer = 0.0
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	search_hint_timer = 0.0

	# 第一优先：如果允许“小外挂”，只在这个时刻掷一次骰子。
	if allow_hint and _try_tracking_cheat_hint(lost_target_hint_chance):
		_start_track_to_suspected()
		return

	# 第二优先：不用作弊，只根据玩家最后真正被看到时的移动方向进行推断。
	if not ai.last_seen_direction.is_zero_approx():
		search_direction = ai.last_seen_direction.normalized()
		var raw_target: Vector3 = ai.last_seen_position + search_direction * track_distance
		if _set_suspected_position_from_raw(raw_target, 2.0):
			_start_track_to_suspected()
			return

	# 连最后移动方向都没有，就在最后已知位置进入警戒搜索。
	has_suspected_position = false
	begin_search(ai.last_known_position)


## SEARCH 当前实际使用的“外挂”概率。
## 这是留给外部调试/UI/后续扩展的统一接口；丢失视野瞬间的 lost_target_hint_chance 不走这里。


func get_current_search_hint_chance() -> float:
	if search_hint_chance <= 0.0:
		return 0.0

	var elapsed: float = maxf(0.0, search_elapsed_seconds)
	var player_displacement: float = 0.0
	if is_instance_valid(ai.player):
		player_displacement = ai._horizontal_distance_between(search_origin, ai.player.global_position)

	var minimum: float = clampf(search_hint_min_multiplier, 0.0, 1.0)
	var multiplier: float = 1.0

	match search_hint_decay_mode:
		SearchHintDecayMode.NONE:
			multiplier = 1.0

		SearchHintDecayMode.LINEAR_TIME:
			var t: float = clampf(elapsed / maxf(0.01, search_hint_linear_decay_seconds), 0.0, 1.0)
			multiplier = lerpf(1.0, minimum, t)

		SearchHintDecayMode.EXPONENTIAL_TIME:
			multiplier = pow(0.5, elapsed / maxf(0.01, search_hint_half_life_seconds))

		SearchHintDecayMode.LINEAR_DISTANCE:
			var distance_ratio: float = clampf(player_displacement / maxf(0.01, search_hint_distance_falloff), 0.0, 1.0)
			multiplier = lerpf(1.0, minimum, distance_ratio)

		SearchHintDecayMode.TIME_AND_DISTANCE:
			var time_multiplier: float = pow(0.5, elapsed / maxf(0.01, search_hint_half_life_seconds))
			var combined_distance_ratio: float = clampf(player_displacement / maxf(0.01, search_hint_distance_falloff), 0.0, 1.0)
			var distance_multiplier: float = lerpf(1.0, minimum, combined_distance_ratio)
			multiplier = time_multiplier * distance_multiplier

		SearchHintDecayMode.CUSTOM:
			multiplier = _custom_search_hint_decay_multiplier(elapsed, player_displacement)

	multiplier = clampf(multiplier, minimum, 1.0)
	return clampf(search_hint_chance * multiplier, 0.0, 1.0)


## CUSTOM 模式的扩展接口。
## 想自己写递减公式时，只改/覆写这里并返回 0~1 倍率即可。


func _custom_search_hint_decay_multiplier(
	elapsed_seconds: float,
	player_displacement: float
) -> float:
	# 当前自定义接口返回 1.0，即不递减；需要自定义公式时再使用传入的时间和距离。
	return 1.0


## “小外挂”：按概率读取一次隐藏玩家的大概位置。
## 成功后只保存 suspected_position；后续 TRACK 不会持续跟踪隐藏玩家。


func _try_tracking_cheat_hint(chance: float) -> bool:
	if debug_tracking_cheat:
		print("[AI][追踪提示] 尝试提示 chance=", snappedf(chance, 0.001))

	if not tracking_cheat_enabled:
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：tracking_cheat_enabled=false")
		return false
	if chance <= 0.0:
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：当前实际概率<=0")
		return false
	if randf() > chance:
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：概率未命中")
		return false
	if not ai.is_alerted or not is_instance_valid(ai.player):
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：AI未激活或player无效")
		return false
	if not ai.arena_zone.overlaps_body(ai.player):
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：player不在CombatZone")
		return false

	var player_distance: float = ai._horizontal_distance_between(actor.global_position, ai.player.global_position)
	if player_distance > tracking_cheat_max_distance:
		if debug_tracking_cheat:
			print(
				"[AI][追踪提示] 失败：距离超限 distance=",
				snappedf(player_distance, 0.01),
				" max=",
				tracking_cheat_max_distance
			)
		return false

	# 到这里说明“外挂概率”已经真正命中。
	# 后面的工作只是把这次提示转换成一个可用的导航目标，不能再因为一次误差点不合法就把提示吞掉。
	var max_snap_distance: float = maxf(1.5, tracking_hint_error_radius + 0.75)
	var attempts: int = maxi(1, tracking_hint_position_attempts)

	for attempt_index in range(attempts):
		var raw_target: Vector3 = ai.player.global_position

		if tracking_hint_error_radius > 0.0:
			var error_angle: float = randf_range(0.0, TAU)
			var error_radius: float = sqrt(randf()) * tracking_hint_error_radius
			raw_target += Vector3(cos(error_angle), 0.0, sin(error_angle)) * error_radius

		if _set_suspected_position_from_raw(raw_target, max_snap_distance):
			var hint_direction: Vector3 = suspected_look_position - actor.global_position
			hint_direction.y = 0.0
			if not hint_direction.is_zero_approx():
				search_direction = hint_direction.normalized()
			if debug_tracking_cheat:
				print(
					"[AI][追踪提示] 成功：误差采样 ",
					attempt_index + 1,
					"/",
					attempts,
					" suspected=",
					suspected_position
				)
			return true

	# 带误差的候选都不适合 TRACK 时，不再把已经命中的外挂作废。
	# 退回玩家真实位置，并使用更宽松的导航目标转换：
	# 瞄准/注意力仍指向玩家附近，但移动终点取路径上最后一个角色真正站得下的位置。
	if _set_suspected_position_relaxed(ai.player.global_position):
		var fallback_direction: Vector3 = suspected_look_position - actor.global_position
		fallback_direction.y = 0.0
		if not fallback_direction.is_zero_approx():
			search_direction = fallback_direction.normalized()
		if debug_tracking_cheat:
			print(
				"[AI][追踪提示] 成功：使用真实位置的宽松Nav回退 suspected=",
				suspected_position,
				" look=",
				suspected_look_position
			)
		return true

	if debug_tracking_cheat:
		print("[AI][追踪提示] 失败：概率已命中，但玩家附近与通往该区域的导航路径都不可用")
	return false


## 检查一个 NavigationRegion 点周围是否仍有足够导航空间。
## 如果外围探针被明显吸回 NavMesh，说明该点太靠近地图边缘/障碍切边，不适合当 TRACK 终点。


func _track_nav_point_has_margin(nav_point: Vector3) -> bool:
	var margin: float = maxf(0.05, track_nav_edge_margin)
	var tolerance: float = maxf(0.01, track_nav_probe_tolerance)
	for index in range(8):
		var angle: float = TAU * float(index) / 8.0
		var probe: Vector3 = nav_point + Vector3(cos(angle), 0.0, sin(angle)) * margin
		var snapped: Vector3 = NavigationServer3D.region_get_closest_point(
			ai.navigation_region.get_rid(),
			probe
		)
		if ai._horizontal_distance_between(probe, snapped) > tolerance:
			return false
	return true


## TRACK 的候选终点只要求：导航可达，而且角色碰撞体在终点能站下。
## 不再对整条导航路径做“一票否决”的碰撞采样；那会把很多实际可走的拐角误判掉。


func _track_nav_point_is_reachable(nav_point: Vector3) -> bool:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(),
		actor.global_position,
		nav_point,
		true,
		agent.navigation_layers
	)
	if path.is_empty() or path[path.size() - 1].distance_to(nav_point) > 0.5:
		return false

	var destination = Vector3(nav_point.x, actor.global_position.y, nav_point.z)
	return ai.is_position_free(destination)


## 将推测位置限制在本竞技场 NavigationRegion3D。
## suspected_look_position 保存吸附后的怀疑方向；suspected_position 则进一步向网格内部收缩，专门作为安全移动终点。


func _set_suspected_position_from_raw(raw_target: Vector3, max_snap_distance: float) -> bool:
	var closest_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		ai.navigation_region.get_rid(),
		raw_target
	)
	if ai._horizontal_distance_between(raw_target, closest_nav_point) > max_snap_distance:
		return false

	# 瞄准点本身也只允许落在 NavigationRegion 上，不保留地图外的原始点。
	var look_destination: Vector3 = Vector3(
		closest_nav_point.x,
		actor.global_position.y,
		closest_nav_point.z
	)

	var safe_nav_point: Vector3 = closest_nav_point
	var found_safe_point: bool = (
		_track_nav_point_has_margin(safe_nav_point)
		and _track_nav_point_is_reachable(safe_nav_point)
	)

	# 最接近怀疑位置的点经常正好落在 NavMesh 边界。
	# 这种情况沿“边界点 -> NPC 当前导航位置”的方向逐步往网格内部退，直到找到有边界余量且可达的点。
	if not found_safe_point:
		var current_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
			ai.navigation_region.get_rid(),
			actor.global_position
		)
		var inward: Vector3 = current_nav_point - closest_nav_point
		inward.y = 0.0
		if not inward.is_zero_approx():
			inward = inward.normalized()
			var step_distance: float = maxf(0.1, track_nav_edge_margin * 0.5)
			for step_index in range(1, 9):
				var inward_probe: Vector3 = closest_nav_point + inward * step_distance * float(step_index)
				var candidate: Vector3 = NavigationServer3D.region_get_closest_point(
					ai.navigation_region.get_rid(),
					inward_probe
				)
				if ai._horizontal_distance_between(inward_probe, candidate) > maxf(0.25, track_nav_probe_tolerance * 2.0):
					continue
				if not _track_nav_point_has_margin(candidate):
					continue
				if not _track_nav_point_is_reachable(candidate):
					continue
				safe_nav_point = candidate
				found_safe_point = true
				break

	if not found_safe_point:
		return false

	suspected_look_position = look_destination
	suspected_position = Vector3(safe_nav_point.x, actor.global_position.y, safe_nav_point.z)
	has_suspected_position = true
	return true


## 外挂概率已经命中时使用的宽松位置转换。
## 它不要求目标拥有 TRACK 的完整边界余量；如果玩家附近终点站不下，
## 就沿“当前NPC -> 玩家附近Nav点”的导航路径从后往前找最后一个可站立点。
## 这样“知道大概在哪”与“是否能精确走到那个点”不会再混成一件事。


func _set_suspected_position_relaxed(raw_target: Vector3) -> bool:
	var closest_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		ai.navigation_region.get_rid(),
		raw_target
	)

	# 玩家提示的注意力方向仍然只指向NavigationRegion内的最近合法位置。
	var look_destination: Vector3 = Vector3(
		closest_nav_point.x,
		actor.global_position.y,
		closest_nav_point.z
	)

	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(),
		actor.global_position,
		closest_nav_point,
		true,
		agent.navigation_layers
	)
	if path.is_empty():
		return false

	# 从玩家附近往回找，优先选择尽可能靠近提示位置、同时角色碰撞体能站下的位置。
	for reverse_index in range(path.size() - 1, -1, -1):
		var path_point: Vector3 = path[reverse_index]
		var destination: Vector3 = Vector3(
			path_point.x,
			actor.global_position.y,
			path_point.z
		)
		if not ai.is_position_free(destination):
			continue

		suspected_look_position = look_destination
		suspected_position = destination
		has_suspected_position = true
		return true

	return false


func _start_track_to_suspected() -> void:
	if not has_suspected_position:
		return

	var direction: Vector3 = suspected_look_position - actor.global_position
	direction.y = 0.0
	if not direction.is_zero_approx():
		search_direction = direction.normalized()

	track_timer = track_seconds
	ai.state = ai.State.TRACK
	agent.target_position = suspected_position


func _process_track(delta: float) -> Vector3:
	track_timer = maxf(0.0, track_timer - delta)

	var reached_track_target: bool = (
		has_suspected_position
		and ai._horizontal_distance(suspected_position) <= track_arrival_distance
	)

	# TRACK 只负责去怀疑位置。
	# 到达、超时，或 NavigationAgent 已经结束当前路径时，就进入 SEARCH。
	# SEARCH 的圆心始终回到玩家最后真正出现/最后已知的位置，
	# 不把 TRACK 的预测终点当成新的搜索中心。
	if track_timer <= 0.0 or reached_track_target or agent.is_navigation_finished():
		begin_search(ai.last_known_position)
		return Vector3.ZERO

	var next_position: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_position - actor.global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized()


func begin_search(center: Vector3 = Vector3.INF) -> void:
	ai.state = ai.State.SEARCH
	ai.is_alerted = true

	# 真正见过玩家时固定使用最后目击位置；来弹推测和 TRACK 预测不挪动圆心。
	# 从未见过玩家而仅被枪声激活时，才使用传入位置或最后已知位置。
	search_origin = ai.last_seen_position if ai.has_visual_memory else (center if center.is_finite() else ai.last_known_position)
	search_origin.y = actor.global_position.y

	# SEARCH 主方向优先使用玩家最后真实移动方向。
	# 没有移动方向时，再使用已有的怀疑方向；还没有就从 NPC 朝搜索中心；最后才使用当前朝向。
	var forward: Vector3 = ai.last_seen_direction
	forward.y = 0.0

	if forward.is_zero_approx():
		forward = search_direction
		forward.y = 0.0

	if forward.is_zero_approx():
		forward = search_origin - actor.global_position
		forward.y = 0.0

	if forward.is_zero_approx():
		forward = -actor.global_basis.z
		forward.y = 0.0

	if forward.is_zero_approx():
		forward = Vector3.FORWARD

	search_direction = forward.normalized()

	# 0 = 没有时间限制，直到小圆大约覆盖完可达区域。
	search_timer = search_seconds if search_seconds > 0.0 else INF
	search_elapsed_seconds = 0.0
	search_hint_timer = maxf(0.25, search_hint_interval_seconds)
	search_pause_timer = maxf(0.0, search_pause_seconds)
	search_is_pausing = true

	search_sweep_index = 0
	search_current_target = actor.global_position
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0

	_build_systematic_area_search()

	# 先停一下观察，然后选择第一个随机搜寻目标。
	agent.target_position = actor.global_position

	if debug_systematic_search:
		print(
			"[AI][搜索] 开始区域覆盖搜索 center=",
			search_origin,
			" forward=",
			search_direction,
			" points=",
			search_sweep_points.size()
		)


func _process_search(delta: float) -> Vector3:
	search_elapsed_seconds += delta
	search_hint_timer = maxf(0.0, search_hint_timer - delta)

	if search_seconds > 0.0:
		search_timer = maxf(0.0, search_timer - delta)
		if search_timer <= 0.0:
			if debug_systematic_search:
				print("[AI][搜索] 达到搜索保险超时")
			_end_search()
			return Vector3.ZERO

	# 保留现有追踪提示；真正重新发现玩家时仍由主状态机打断搜索。
	if search_hint_timer <= 0.0:
		search_hint_timer = maxf(0.25, search_hint_interval_seconds)
		if _try_tracking_cheat_hint(get_current_search_hint_chance()):
			_start_track_to_suspected()
			return Vector3.ZERO

	# 每到一个搜寻目标，短暂停留观察，再从尚未覆盖的区域随机选点。
	if search_is_pausing:
		search_stuck_timer = 0.0
		search_progress_best_distance = INF
		search_pause_timer = maxf(0.0, search_pause_timer - delta)

		if search_pause_timer <= 0.0:
			search_is_pausing = false

			if not _advance_systematic_search_target():
				if debug_systematic_search:
					print("[AI][搜索] 本轮搜索结束，覆盖比例=", get_search_coverage())
				_end_search()
				return Vector3.ZERO

		return Vector3.ZERO

	# 当前没有有效目标时，直接拿下一个规划搜索点。
	if not search_current_target_active:
		if not _advance_systematic_search_target():
			_end_search()
		return Vector3.ZERO

	var distance_to_target: float = ai._horizontal_distance(search_current_target)

	# 不要求 Agent 精确踩点。
	if distance_to_target <= search_arrival_distance:
		_finish_current_search_point()
		return Vector3.ZERO

	# Agent 提前认为路径结束，但距离目标仍较远：这个点跳过，继续固定路线中的下一个。
	if agent.is_navigation_finished():
		if debug_systematic_search:
			print(
				"[AI][搜索] 路径提前结束，跳过 point ",
				search_sweep_index,
				" target=",
				search_current_target
			)
		_skip_current_search_point()
		return Vector3.ZERO

	# 绕墙时可能暂时远离最终搜寻目标，所以按下一个寻路拐点监测进展。
	var next_position: Vector3 = agent.get_next_path_position()
	var distance_to_waypoint: float = ai._horizontal_distance(next_position)
	if not search_progress_waypoint.is_finite() or ai._horizontal_distance_between(search_progress_waypoint, next_position) > 0.25:
		search_progress_waypoint = next_position
		search_progress_best_distance = distance_to_waypoint
		search_stuck_timer = 0.0
	elif distance_to_waypoint <= search_progress_best_distance - search_stuck_min_progress_distance:
		search_progress_best_distance = distance_to_waypoint
		search_stuck_timer = 0.0
	else:
		search_stuck_timer += delta
	search_target_timer = maxf(0.0, search_target_timer - delta)
	if search_stuck_timer >= search_stuck_repath_seconds or search_target_timer <= 0.0:
		_skip_current_search_point()
		return Vector3.ZERO

	var direction: Vector3 = next_position - actor.global_position
	direction.y = 0.0

	if direction.is_zero_approx():
		# 不原地死等，让 stuck timer 继续累计，超时后自动跳到路线下一个点。
		return Vector3.ZERO

	return direction.normalized()


## 生成固定的“圆形区域覆盖搜索路线”。
##
## 用均匀地面样本估算可达面积，每次从未覆盖部分随机挑选搜寻目标。


func _build_systematic_area_search() -> void:
	search_sweep_points.clear()
	search_uncovered_points.clear()
	search_sample_count = 0
	var radius: float = maxf(1.0, search_radius)
	# 均匀采样近似面积；每轮随机转动采样网，避免目标坐标固定。
	var spacing: float = maxf(0.5, maxf(search_coverage_radius * 0.5, radius / 18.0))
	var angle: float = randf() * TAU
	var extent: int = int(ceil(radius / spacing))
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			var offset = Vector3(x * spacing, 0, z * spacing)
			if offset.length() > radius:
				continue
			_try_append_systematic_search_point(search_origin + offset.rotated(Vector3.UP, angle))
	search_uncovered_points.assign(search_sweep_points)
	search_sample_count = search_uncovered_points.size()

## 将面积采样点转换成可达地面上的候选点。


func _try_append_systematic_search_point(raw_point: Vector3) -> bool:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		ai.navigation_region.get_rid(), raw_point
	)
	if ai._horizontal_distance_between(raw_point, nav_point) > search_nav_snap_tolerance:
		return false
	var destination = Vector3(nav_point.x, actor.global_position.y, nav_point.z)
	if ai._horizontal_distance_between(destination, search_origin) > search_radius:
		return false
	if not ai.is_position_free(destination):
		return false
	# 只统计本轮起点所在连通区域内可达的地面。
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
	)
	if path.is_empty() or ai._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
		return false
	for existing: Vector3 in search_sweep_points:
		if ai._horizontal_distance_between(existing, destination) < 0.3:
			return false
	search_sweep_points.append(destination)
	return true


func get_search_coverage() -> float:
	if search_sample_count == 0:
		return 1.0
	return 1.0 - float(search_uncovered_points.size()) / float(search_sample_count)


func _mark_search_coverage(point: Vector3) -> void:
	# 目标点的假想小圆，与真实视野分开，按用户规则不检测墙壁遮挡。
	for index in range(search_uncovered_points.size() - 1, -1, -1):
		if ai._horizontal_distance_between(point, search_uncovered_points[index]) <= search_coverage_radius:
			search_uncovered_points.remove_at(index)
	for index in range(search_sweep_points.size() - 1, -1, -1):
		if ai._horizontal_distance_between(point, search_sweep_points[index]) <= search_coverage_radius:
			search_sweep_points.remove_at(index)

## 从未覆盖区域随机选择真实可达的搜寻目标。


func _advance_systematic_search_target() -> bool:
	if get_search_coverage() >= search_coverage_goal:
		return false
	# 从未覆盖候选里抽几个，再选较近的一个，减少横穿整个搜索区。
	while not search_sweep_points.is_empty():
		var chosen_index: int = randi_range(0, search_sweep_points.size() - 1)
		for attempt in range(3):
			var candidate_index: int = randi_range(0, search_sweep_points.size() - 1)
			if ai._horizontal_distance(search_sweep_points[candidate_index]) < ai._horizontal_distance(search_sweep_points[chosen_index]):
				chosen_index = candidate_index
		var destination: Vector3 = search_sweep_points[chosen_index]
		search_sweep_points.remove_at(chosen_index)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
		)
		if path.is_empty() or ai._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
			continue
		search_sweep_index += 1
		search_current_target = destination
		search_current_target_active = true
		var planned_direction: Vector3 = destination - actor.global_position
		planned_direction.y = 0.0
		if not planned_direction.is_zero_approx():
			search_direction = planned_direction.normalized()
		search_progress_best_distance = INF
		search_progress_waypoint = Vector3.INF
		search_stuck_timer = 0.0
		var path_length: float = 0.0
		for index in range(1, path.size()):
			path_length += path[index - 1].distance_to(path[index])
		search_target_timer = path_length / maxf(0.1, actor.move_speed * search_move_speed_multiplier) + 3.0
		agent.target_position = destination
		if debug_systematic_search:
			print("[AI][搜索] 随机目标=", destination, " 已覆盖=", snappedf(get_search_coverage() * 100.0, 0.1), "%")
		return true
	# 动态障碍使所有剩余目标失败时退出，不把失败点当作已覆盖。
	search_current_target_active = false
	agent.target_position = actor.global_position
	if debug_systematic_search:
		print("[AI][搜索] 无剩余可用目标，实际覆盖=", get_search_coverage())
	return false


func _finish_current_search_point() -> void:
	_mark_search_coverage(search_current_target)
	# 到达搜寻目标才记录覆盖并停留；普通寻路拐点不会调用这里。
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	agent.target_position = actor.global_position
	search_is_pausing = true
	search_pause_timer = maxf(0.0, search_pause_seconds)


func _skip_current_search_point() -> void:
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	agent.target_position = actor.global_position
	search_is_pausing = true
	# 卡住点只做很短的停顿，然后继续规划路线。
	search_pause_timer = minf(maxf(0.05, search_pause_seconds * 0.35), 0.25)


func _end_search() -> void:
	# 搜索完整结束后，才退出“知道玩家”状态并恢复正常巡逻。
	ai.is_alerted = false
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	track_timer = 0.0
	search_hint_timer = 0.0
	search_sweep_points.clear()
	search_uncovered_points.clear()
	search_sample_count = 0
	search_sweep_index = 0
	search_current_target = actor.global_position
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	search_elapsed_seconds = 0.0
	has_suspected_position = false
	suspected_look_position = actor.global_position
	search_direction = Vector3.ZERO
	ai.last_seen_direction = Vector3.ZERO
	ai.was_seeing_player = false
	ai.has_visual_memory = false

	ai.state = ai.State.IDLE
	ai.patrol_pause_timer = ai.patrol_pause_seconds
	agent.target_position = actor.global_position


func reset() -> void:
	has_suspected_position = false
	suspected_position = actor.global_position
	suspected_look_position = actor.global_position
	track_timer = 0.0
	search_direction = Vector3.ZERO
	search_hint_timer = 0.0
	search_sweep_points.clear()
	search_uncovered_points.clear()
	search_sample_count = 0
	search_sweep_index = 0
	search_current_target = actor.global_position
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	search_elapsed_seconds = 0.0
	search_origin = actor.global_position
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	search_progress_waypoint = Vector3.INF
	search_target_timer = 0.0


func step(delta: float) -> Vector3:
	if ai.state == ai.State.TRACK:
		return _process_track(delta)
	if ai.state == ai.State.SEARCH:
		return _process_search(delta)
	var next_position: Vector3 = agent.get_next_path_position()
	if agent.is_navigation_finished():
		begin_tracking_or_search(false)
		return Vector3.ZERO
	var direction: Vector3 = next_position - actor.global_position
	direction.y = 0.0
	return direction.normalized()


func movement_multiplier() -> float:
	if ai.state == ai.State.TRACK:
		return track_move_speed_multiplier
	if ai.state == ai.State.SEARCH:
		return search_move_speed_multiplier
	return 1.0


func facing_direction(direction: Vector3) -> Vector3:
	if ai.state == ai.State.TRACK and has_suspected_position:
		var attention: Vector3 = suspected_look_position - actor.global_position
		attention.y = 0.0
		if attention.is_zero_approx():
			return direction
		if direction.is_zero_approx():
			return attention
		var facing := direction.normalized().lerp(attention.normalized(), clampf(track_attention_weight, 0.0, 1.0))
		return attention if facing.is_zero_approx() else facing
	if ai.state == ai.State.SEARCH and direction.is_zero_approx():
		return search_direction
	return direction
