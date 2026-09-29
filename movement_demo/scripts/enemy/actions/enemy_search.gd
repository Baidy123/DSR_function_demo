extends "res://scripts/enemy/actions/enemy_action.gd"

# 只用于本次听觉调查；不覆盖最后真实目击记录。
var noise_search_origin: Vector3:
	get: return context.noise_search_origin if context != null else Vector3.INF
	set(value):
		if context != null: context.noise_search_origin = value

# 搜寻：丢失目标后的预测追踪、调查和区域搜索。由 AI 统一调用。
enum SearchHintDecayMode {
	NONE,
	LINEAR_TIME,
	EXPONENTIAL_TIME,
	LINEAR_DISTANCE,
	TIME_AND_DISTANCE,
	CUSTOM
}

## 是否允许 AI 在失去视野后偶尔读取一次墙后玩家的位置。
## 关闭后不再用隐藏位置生成追踪目标，仍保留真实目击方向和来弹推测。
## 距离衰减概率的查询仍会计算玩家距离，但不会据此生成位置提示。
var tracking_cheat_enabled: bool:
	get: return _setting(&"tracking_cheat_enabled", true)
	set(value): _set_setting(&"tracking_cheat_enabled", value)
## 刚刚丢失玩家时，立即获得一次“玩家大概位置”提示的概率。
var lost_target_hint_chance: float:
	get: return _setting(&"lost_target_hint_chance", 0.5)
	set(value): _set_setting(&"lost_target_hint_chance", value)
## 进入 SEARCH 后，每次检查重新获得“大概位置”提示的概率。
var search_hint_chance: float:
	get: return _setting(&"search_hint_chance", 0.35)
	set(value): _set_setting(&"search_hint_chance", value)
## SEARCH 中多久进行一次提示概率检查；不是每帧偷看。
var search_hint_interval_seconds: float:
	get: return _setting(&"search_hint_interval_seconds", 1.5)
	set(value): _set_setting(&"search_hint_interval_seconds", value)
## SEARCH 期间的外挂概率如何随调查持续时间/玩家离开搜索中心的距离递减。
var search_hint_decay_mode: SearchHintDecayMode:
	get: return _setting(&"search_hint_decay_mode", SearchHintDecayMode.TIME_AND_DISTANCE)
	set(value): _set_setting(&"search_hint_decay_mode", value)
## 递减后的最低倍率。0=最终可降到 0；0.1=最低保留基础概率的 10%。
var search_hint_min_multiplier: float:
	get: return _setting(&"search_hint_min_multiplier", 0.05)
	set(value): _set_setting(&"search_hint_min_multiplier", value)
## LINEAR_TIME：经过这么多秒后降到最低倍率。
var search_hint_linear_decay_seconds: float:
	get: return _setting(&"search_hint_linear_decay_seconds", 8.0)
	set(value): _set_setting(&"search_hint_linear_decay_seconds", value)
## EXPONENTIAL_TIME / TIME_AND_DISTANCE：每经过这么多秒，时间部分概率约减半。
var search_hint_half_life_seconds: float:
	get: return _setting(&"search_hint_half_life_seconds", 4.0)
	set(value): _set_setting(&"search_hint_half_life_seconds", value)
## LINEAR_DISTANCE / TIME_AND_DISTANCE：玩家离开本轮搜索中心这么远后，距离部分降到最低倍率。
var search_hint_distance_falloff: float:
	get: return _setting(&"search_hint_distance_falloff", 6.0)
	set(value): _set_setting(&"search_hint_distance_falloff", value)
## “外挂”得到的位置误差半径。0 表示几乎知道精确位置，数值越大越模糊。
var tracking_hint_error_radius: float:
	get: return _setting(&"tracking_hint_error_radius", 1.25)
	set(value): _set_setting(&"tracking_hint_error_radius", value)
## 概率已经命中后，如果误差点刚好落进墙/导航边缘，最多重新采样几次位置。
## 这里只重采样“位置误差”，不会重新掷外挂概率。
var tracking_hint_position_attempts: int:
	get: return _setting(&"tracking_hint_position_attempts", 4)
	set(value): _set_setting(&"tracking_hint_position_attempts", value)
## 超过这个距离就不给位置提示，避免跨整个场景透视。
var tracking_cheat_max_distance: float:
	get: return _setting(&"tracking_cheat_max_distance", 12.0)
	set(value): _set_setting(&"tracking_cheat_max_distance", value)
## 打印外挂提示为什么成功/失败，以及 SEARCH 当前实际使用的递减后概率。
var debug_tracking_cheat: bool:
	get: return _setting(&"debug_tracking_cheat", false)
	set(value): _set_setting(&"debug_tracking_cheat", value)
## 没拿到位置外挂时，仍可沿玩家最后真实移动方向推进这么远。
var track_distance: float:
	get: return _setting(&"track_distance", 4.0)
	set(value): _set_setting(&"track_distance", value)
## TRACK 最长持续时间；到达怀疑位置或超时后进入警戒搜索。
var track_seconds: float:
	get: return _setting(&"track_seconds", 5.0)
	set(value): _set_setting(&"track_seconds", value)
## 架枪追踪时的移动速度倍率。
var track_move_speed_multiplier: float:
	get: return _setting(&"track_move_speed_multiplier", 0.55)
	set(value): _set_setting(&"track_move_speed_multiplier", value)
## TRACK 时身体朝向对“怀疑方向”的关注权重。1=完全锁定怀疑方向，0=完全朝实际移动方向。
## 推荐 0.65~0.85：明显注意怀疑区域，但绕路时身体也会自然跟随一些移动方向。
var track_attention_weight: float:
	get: return _setting(&"track_attention_weight", 0.75)
	set(value): _set_setting(&"track_attention_weight", value)
## TRACK 状态的水平总视野角（度）；实际取它与普通 Sight Angle Degrees 的较大值。
## 例如 220° 表示前方左右各约 110°；仍保留身后的盲区，不是 360° 透视。
var track_sight_angle_degrees: float:
	get: return _setting(&"track_sight_angle_degrees", 220.0)
	set(value): _set_setting(&"track_sight_angle_degrees", value)
## TRACK 的移动目标至少离 NavigationRegion 边界这么远，避免目标贴在 NavMesh 边缘导致角色顶住边界。
var track_nav_edge_margin: float:
	get: return _setting(&"track_nav_edge_margin", 0.35)
	set(value): _set_setting(&"track_nav_edge_margin", value)
## 判断目标是否贴近 NavMesh 边界时，外围探针允许被吸附回网格的最大误差。
var track_nav_probe_tolerance: float:
	get: return _setting(&"track_nav_probe_tolerance", 0.12)
	set(value): _set_setting(&"track_nav_probe_tolerance", value)
## TRACK 距离安全导航目标小于这个距离时直接视为到达，不要求 NavigationAgent 必须精确走到一点。
var track_arrival_distance: float:
	get: return _setting(&"track_arrival_distance", 0.45)
	set(value): _set_setting(&"track_arrival_distance", value)
## 小圆的假想覆盖半径；仅用于搜索进度，不改变真实视野，也不考虑墙壁遮挡。
var search_coverage_radius: float:
	get: return _setting(&"search_coverage_radius", 2.0)
	set(value): _set_setting(&"search_coverage_radius", value)
## 达到这个可达区域覆盖比例后结束本轮搜索。
var search_coverage_goal: float:
	get: return _setting(&"search_coverage_goal", 0.95)
	set(value): _set_setting(&"search_coverage_goal", value)
## SEARCH 的可选保险超时。0 = 按覆盖比例结束，当前场景使用 0。
var search_seconds: float:
	get: return _setting(&"search_seconds", 0.0)
	set(value): _set_setting(&"search_seconds", value)
## 以玩家最后目击位置为圆心的搜索半径；未目击过才采用来弹推测。
var search_radius: float:
	get: return _setting(&"search_radius", 5.0)
	set(value): _set_setting(&"search_radius", value)
## 每到一个搜索点后停留观察多久。
var search_pause_seconds: float:
	get: return _setting(&"search_pause_seconds", 0.5)
	set(value): _set_setting(&"search_pause_seconds", value)
## 距离搜索点小于这个值时直接视为到达，不要求 NavigationAgent 精确踩点。
var search_arrival_distance: float:
	get: return _setting(&"search_arrival_distance", 0.5)
	set(value): _set_setting(&"search_arrival_distance", value)
## 原始规则搜索点投影到 NavigationRegion 时，最多允许被吸附这么远；超过就跳过该点。
var search_nav_snap_tolerance: float:
	get: return _setting(&"search_nav_snap_tolerance", 0.65)
	set(value): _set_setting(&"search_nav_snap_tolerance", value)
## SEARCH 搜索期间的移动速度倍率。
var search_move_speed_multiplier: float:
	get: return _setting(&"search_move_speed_multiplier", 0.45)
	set(value): _set_setting(&"search_move_speed_multiplier", value)
## 朝下一个寻路拐点连续这么多秒没有明显推进，就放弃当前搜寻目标，避免卡死。
var search_stuck_repath_seconds: float:
	get: return _setting(&"search_stuck_repath_seconds", 0.9)
	set(value): _set_setting(&"search_stuck_repath_seconds", value)
## 到下一个寻路拐点的距离至少缩短这么多米，才算有进展；沿途换拐点会重新计量。
var search_stuck_min_progress_distance: float:
	get: return _setting(&"search_stuck_min_progress_distance", 0.08)
	set(value): _set_setting(&"search_stuck_min_progress_distance", value)
## 调试时打印系统化搜索生成了多少点、当前走到第几个点。
var debug_systematic_search: bool:
	get: return _setting(&"debug_systematic_search", false)
	set(value): _set_setting(&"debug_systematic_search", value)
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

# 只由真实目击更新；失视后的预测绝不读取玩家速度或位置。
var observed_velocity: Vector3:
	get: return context.observed_velocity
	set(value): context.observed_velocity = value
var investigation_phase: int = -1
var _return_to_area_search := false
var _segment_released := false
var _segment_nearby_pressure := 0.0
var _segment_boundary_pending := false
var _track_waypoint := Vector3.INF
var _track_best_distance := INF
var _track_stuck_seconds := 0.0

const Actor = preload("res://scripts/enemy/enemy_actor.gd")


func observe_visual_motion(displacement: Vector3, delta: float, continuous: bool) -> void:
	if not continuous:
		reset()
	context.observe_visual_motion(displacement, delta, continuous)


func predicted_position() -> Vector3:
	var distance := track_distance
	if not observed_velocity.is_zero_approx():
		# 按最后可见速度预测短短一段；原 Track Distance 作为最大距离。
		distance = minf(track_distance, observed_velocity.length() * 1.25)
	return context.last_seen_position + context.last_seen_direction * distance


func _begin_segment() -> void:
	_segment_released = false
	_segment_nearby_pressure = context.nearby_shot_pressure


func release_segment() -> void:
	_segment_released = true


func is_segment_released() -> bool:
	return _segment_released


func investigate_known_threat(position: Vector3) -> void:
	# 新的真实受击线索替代旧调查，不恢复已被旧战术入口改坏的计时或目标。
	investigation_phase = -1
	_return_to_area_search = false
	has_suspected_position = false
	if _set_suspected_position_from_raw(position, 2.0):
		_start_track_to_suspected()
	else:
		begin_search(position)
	release_segment()


func has_committed_segment() -> bool:
	# 单发擦弹不必立即折返；明显新增的连续近弹允许重新判断风险。
	if context.nearby_shot_pressure > _segment_nearby_pressure + 0.25:
		release_segment()
	if _segment_released:
		return false
	if _segment_boundary_pending:
		return false
	if context.state == context.State.TRACK:
		return has_suspected_position and track_timer > 0.0
	return context.state == context.State.SEARCH and (search_current_target_active or (search_is_pausing and search_pause_timer > 0.0))


## 搜寻保留自己的目标；公共NavigationAgent可能正被掩体动作使用。
func is_observing() -> bool:
	return investigation_phase == context.State.SEARCH and search_is_pausing and not search_current_target_active


func recover_unreachable_destination() -> void:
	# 只有统一选择器真正执行搜索后才改进度；评估阶段不选点、不消耗候选。
	if investigation_phase == context.State.SEARCH and search_sample_count > 0:
		_skip_current_search_point()
		search_is_pausing = false
		_segment_boundary_pending = false
		if not _advance_systematic_search_target():
			_end_search()
	elif investigation_phase == context.State.TRACK:
		_finish_tracking(true)
	else:
		begin_search(context.last_known_position)
	context.invalidate_utility()


func utility_destination() -> Vector3:
	if investigation_phase == context.State.TRACK and has_suspected_position:
		return suspected_position
	if investigation_phase == context.State.SEARCH and search_current_target_active:
		return search_current_target
	if investigation_phase == context.State.SEARCH and search_is_pausing:
		return actor.global_position
	return noise_search_origin if noise_search_origin.is_finite() else context.last_known_position


func begin_tracking_or_search(allow_hint: bool = true) -> void:
	if not is_enabled():
		context.state = context.State.IDLE
		agent.target_position = actor.global_position
		return
	context.is_alerted = true
	investigation_phase = -1
	_return_to_area_search = false


	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	search_hint_timer = 0.0

	# 第一优先：如果允许“小外挂”，只在这个时刻掷一次骰子。
	if allow_hint and _try_tracking_cheat_hint(lost_target_hint_chance):
		_start_track_to_suspected()
		return

	# 第二优先：不用作弊，只根据玩家最后真正被看到时的移动方向进行推断。
	if not context.last_seen_direction.is_zero_approx():
		search_direction = context.last_seen_direction.normalized()
		var raw_target: Vector3 = predicted_position()
		if _set_suspected_position_from_raw(raw_target, 2.0):
			_start_track_to_suspected()
			return

	# 连最后移动方向都没有，就在最后已知位置进入警戒搜索。
	has_suspected_position = false
	begin_search(context.last_known_position)


## SEARCH 当前实际使用的“外挂”概率。
## 这是留给外部调试/UI/后续扩展的统一接口；丢失视野瞬间的 lost_target_hint_chance 不走这里。


func get_current_search_hint_chance() -> float:
	if search_hint_chance <= 0.0:
		return 0.0

	var elapsed: float = maxf(0.0, search_elapsed_seconds)
	var player_displacement: float = 0.0
	if is_instance_valid(context.player):
		player_displacement = context._horizontal_distance_between(search_origin, context.player.global_position)

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
	if noise_search_origin.is_finite():
		return false
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
	if not context.is_alerted or not is_instance_valid(context.player):
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：AI未激活或player无效")
		return false
	if not context.arena_zone.overlaps_body(context.player):
		if debug_tracking_cheat:
			print("[AI][追踪提示] 失败：player不在CombatZone")
		return false

	var player_distance: float = context._horizontal_distance_between(actor.global_position, context.player.global_position)
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
	# 只在带误差的样本中寻找可用位置；全部失败就等待下次机会。
	var max_snap_distance: float = maxf(1.5, tracking_hint_error_radius + 0.75)
	var attempts: int = maxi(1, tracking_hint_position_attempts)

	for attempt_index in range(attempts):
		var raw_target: Vector3 = context.player.global_position

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

	if debug_tracking_cheat:
		print("[AI][追踪提示] 失败：带误差的候选不可用，保留原调查")
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
			context.navigation_region.get_rid(),
			probe
		)
		if context._horizontal_distance_between(probe, snapped) > tolerance:
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
	return context.is_position_free(destination)


## 将推测位置限制在本竞技场 NavigationRegion3D。
## suspected_look_position 保存吸附后的怀疑方向；suspected_position 则进一步向网格内部收缩，专门作为安全移动终点。


func _set_suspected_position_from_raw(raw_target: Vector3, max_snap_distance: float) -> bool:
	var closest_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		context.navigation_region.get_rid(),
		raw_target
	)
	if context._horizontal_distance_between(raw_target, closest_nav_point) > max_snap_distance:
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
			context.navigation_region.get_rid(),
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
					context.navigation_region.get_rid(),
					inward_probe
				)
				if context._horizontal_distance_between(inward_probe, candidate) > maxf(0.25, track_nav_probe_tolerance * 2.0):
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


## 已知声源使用的宽松位置转换；概率位置提示不使用这个回退。
## 终点站不下时，沿已知声源的导航路径找最后一个可站立点。


func _set_suspected_position_relaxed(raw_target: Vector3) -> bool:
	var closest_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		context.navigation_region.get_rid(),
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
		if not context.is_position_free(destination):
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
	_return_to_area_search = investigation_phase == context.State.SEARCH and search_sample_count > 0
	investigation_phase = context.State.TRACK
	_begin_segment()
	_segment_boundary_pending = false
	_track_waypoint = Vector3.INF
	_track_best_distance = INF
	_track_stuck_seconds = 0.0
	context.state = context.State.TRACK
	agent.target_position = suspected_position


func _process_track(delta: float) -> Vector3:
	track_timer = maxf(0.0, track_timer - delta)
	if _return_to_area_search:
		search_elapsed_seconds += delta
		if search_seconds > 0.0:
			search_timer = maxf(0.0, search_timer - delta)

	var reached_track_target: bool = (
		has_suspected_position
		and context._horizontal_distance(suspected_position) <= track_arrival_distance
	)

	# TRACK 只负责去怀疑位置。
	# 到达、超时，或 NavigationAgent 已经结束当前路径时，就进入 SEARCH。
	# SEARCH 的圆心始终回到玩家最后真正出现/最后已知的位置，
	# 不把 TRACK 的预测终点当成新的搜索中心。
	if track_timer <= 0.0 or reached_track_target or agent.is_navigation_finished():
		_finish_tracking(not reached_track_target)
		return Vector3.ZERO

	var next_position: Vector3 = agent.get_next_path_position()
	var distance: float = context._horizontal_distance(next_position)
	if not _track_waypoint.is_finite() or _track_waypoint.distance_to(next_position) > 0.25:
		_track_waypoint = next_position
		_track_best_distance = distance
		_track_stuck_seconds = 0.0
	elif distance < _track_best_distance - search_stuck_min_progress_distance:
		_track_best_distance = distance
		_track_stuck_seconds = 0.0
	else:
		_track_stuck_seconds += delta
	if _track_stuck_seconds >= search_stuck_repath_seconds:
		_finish_tracking(true)
		return Vector3.ZERO
	var direction: Vector3 = next_position - actor.global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized()


func _finish_tracking(failed: bool = false) -> void:
	has_suspected_position = false
	if not _return_to_area_search:
		begin_search(context.last_known_position)
		if failed:
			release_segment()
		context.invalidate_utility()
		return
	_return_to_area_search = false
	investigation_phase = context.State.SEARCH
	context.state = context.State.SEARCH
	# 概率提示只是本轮搜索的一次支线，不重抽区域、不恢复已消耗的计时。
	search_current_target_active = false
	search_is_pausing = true
	search_pause_timer = maxf(0.0, search_pause_seconds)
	search_hint_timer = maxf(0.25, search_hint_interval_seconds)
	if failed:
		release_segment()
	agent.target_position = actor.global_position
	context.invalidate_utility()


func begin_search(center: Vector3 = Vector3.INF) -> void:
	if not is_enabled():
		context.state = context.State.IDLE
		return
	context.state = context.State.SEARCH
	investigation_phase = context.State.SEARCH
	_return_to_area_search = false
	_begin_segment()
	_segment_boundary_pending = false
	context.is_alerted = true

	# 普通搜索沿用最后目击圆心；本次由声音触发时，以新的声源位置为圆心。
	search_origin = context.last_seen_position if context.has_visual_memory else (center if center.is_finite() else context.last_known_position)
	if noise_search_origin.is_finite():
		search_origin = noise_search_origin
	search_origin.y = actor.global_position.y

	# SEARCH 主方向优先使用玩家最后真实移动方向。
	# 没有移动方向时，再使用已有的怀疑方向；还没有就从 NPC 朝搜索中心；最后才使用当前朝向。
	var forward: Vector3 = Vector3.ZERO if noise_search_origin.is_finite() else context.last_seen_direction
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

	# 先停一下观察，再按最后目击轨迹选择调查位置。
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

	# 提示检查保留原间隔，但等当前段观察结束才接受；不会途中突然折返。
	if search_is_pausing:
		search_stuck_timer = 0.0
		search_progress_best_distance = INF
		search_pause_timer = maxf(0.0, search_pause_timer - delta)

		if search_pause_timer <= 0.0:
			if not _segment_boundary_pending:
				# Utility 在 step 前运行：显式留一帧，才能在两段之间重新选择。
				_segment_boundary_pending = true
				context.invalidate_utility()
				return Vector3.ZERO
			_segment_boundary_pending = false
			search_is_pausing = false
			if not noise_search_origin.is_finite() and search_hint_timer <= 0.0:
				search_hint_timer = maxf(0.25, search_hint_interval_seconds)
				if _try_tracking_cheat_hint(get_current_search_hint_chance()):
					_start_track_to_suspected()
					return Vector3.ZERO

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

	var distance_to_target: float = context._horizontal_distance(search_current_target)

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
	var distance_to_waypoint: float = context._horizontal_distance(next_position)
	if not search_progress_waypoint.is_finite() or context._horizontal_distance_between(search_progress_waypoint, next_position) > 0.25:
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
## 用均匀地面样本估算可达面积，按轨迹推测给未覆盖位置排序。


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
		context.navigation_region.get_rid(), raw_point
	)
	if context._horizontal_distance_between(raw_point, nav_point) > search_nav_snap_tolerance:
		return false
	var destination = Vector3(nav_point.x, actor.global_position.y, nav_point.z)
	if context._horizontal_distance_between(destination, search_origin) > search_radius:
		return false
	if not context.is_position_free(destination):
		return false
	# 只统计本轮起点所在连通区域内可达的地面。
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
	)
	if path.is_empty() or context._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
		return false
	for existing: Vector3 in search_sweep_points:
		if context._horizontal_distance_between(existing, destination) < 0.3:
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
		if context._horizontal_distance_between(point, search_uncovered_points[index]) <= search_coverage_radius:
			search_uncovered_points.remove_at(index)
	for index in range(search_sweep_points.size() - 1, -1, -1):
		if context._horizontal_distance_between(point, search_sweep_points[index]) <= search_coverage_radius:
			search_sweep_points.remove_at(index)

## 方向判断随失视时间变弱，随后自然扩展到两侧和其他未覆盖区域。
func _search_point_cost(point: Vector3) -> float:
	var origin: Vector3 = search_origin
	var prediction: Vector3 = origin
	var confidence := 0.0
	if context.has_visual_memory and not noise_search_origin.is_finite() and not context.last_seen_direction.is_zero_approx():
		prediction = predicted_position()
		confidence = pow(0.5, context.utility_unseen_seconds / 4.0)
	var offset := point - origin
	offset.y = 0.0
	var backwards := maxf(0.0, -offset.dot(context.last_seen_direction))
	return lerpf(offset.length(), context._horizontal_distance_between(point, prediction) + backwards, confidence) + context._horizontal_distance(point) * 0.25


func _advance_systematic_search_target() -> bool:
	if get_search_coverage() >= search_coverage_goal:
		return false
	# 候选已有空间/路径过滤；这里只做廉价排序，选中后重新核实路径。
	while not search_sweep_points.is_empty():
		var chosen_index := 0
		var best_cost := _search_point_cost(search_sweep_points[0])
		for candidate_index in range(1, search_sweep_points.size()):
			var cost := _search_point_cost(search_sweep_points[candidate_index])
			if cost < best_cost:
				chosen_index = candidate_index
				best_cost = cost
		var destination: Vector3 = search_sweep_points[chosen_index]
		search_sweep_points.remove_at(chosen_index)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
		)
		if path.is_empty() or context._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
			continue
		search_sweep_index += 1
		search_current_target = destination
		search_current_target_active = true
		_begin_segment()
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
			print("[AI][搜索] 轨迹调查目标=", destination, " 已覆盖=", snappedf(get_search_coverage() * 100.0, 0.1), "%")
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
	release_segment()
	context.invalidate_utility()
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	agent.target_position = actor.global_position
	search_is_pausing = true
	# 卡住点只做很短的停顿，然后继续规划路线。
	search_pause_timer = minf(maxf(0.05, search_pause_seconds * 0.35), 0.25)


func _end_search() -> void:
	investigation_phase = -1
	_return_to_area_search = false
	noise_search_origin = Vector3.INF
	# 搜索完整结束后，才退出“知道玩家”状态并恢复正常巡逻。
	context.is_alerted = false
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
	context.last_seen_direction = Vector3.ZERO
	context.was_seeing_player = false
	context.has_visual_memory = false

	context.state = context.State.IDLE
	context.patrol_pause_timer = context.patrol_pause_seconds
	agent.target_position = actor.global_position


func reset() -> void:
	investigation_phase = -1
	_return_to_area_search = false
	_segment_released = false
	_segment_boundary_pending = false
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
	if not is_enabled():
		return Vector3.ZERO
	if context.state == context.State.TRACK:
		return _process_track(delta)
	if context.state == context.State.SEARCH:
		return _process_search(delta)
	var next_position: Vector3 = agent.get_next_path_position()
	if agent.is_navigation_finished():
		begin_tracking_or_search(false)
		return Vector3.ZERO
	var direction: Vector3 = next_position - actor.global_position
	direction.y = 0.0
	return direction.normalized()


func movement_multiplier() -> float:
	if context.state == context.State.TRACK:
		return track_move_speed_multiplier
	if context.state == context.State.SEARCH:
		return search_move_speed_multiplier
	return 1.0


func facing_direction(direction: Vector3) -> Vector3:
	if context.state == context.State.TRACK and has_suspected_position:
		var attention: Vector3 = suspected_look_position - actor.global_position
		attention.y = 0.0
		if attention.is_zero_approx():
			return direction
		if direction.is_zero_approx():
			return attention
		var facing := direction.normalized().lerp(attention.normalized(), clampf(track_attention_weight, 0.0, 1.0))
		return attention if facing.is_zero_approx() else facing
	if context.state == context.State.SEARCH and direction.is_zero_approx():
		return search_direction
	return direction


func investigate_noise(position: Vector3, fresh_evidence: bool = false) -> void:
	if not is_enabled():
		return
	# 同位置连发不无限刷新计时；移动后的新声源才更新调查目的地。
	if not fresh_evidence and noise_search_origin.is_finite() and noise_search_origin.distance_to(position) < 0.35 and context.state in [context.State.TRACK, context.State.SEARCH]:
		return
	reset()
	noise_search_origin = position
	context.last_known_position = position
	context.is_alerted = true


	if _set_suspected_position_from_raw(position, 1.0) or _set_suspected_position_relaxed(position):
		_start_track_to_suspected()
	else:
		# 精确声源不可达时，在附近可达区域搜索，不穿过碰撞墙。
		begin_search(position)


func collect_candidates(visible: bool) -> Array[Dictionary]:
	var threat: Vector3 = context._known_reload_threat()
	if visible or not threat.is_finite():
		return []
	var horizon: float = context.utility_horizon_seconds
	var point := utility_destination()
	var path: PackedVector3Array = PackedVector3Array() if is_observing() else selection._path_to(actor.global_position, point)
	if is_observing() or path.is_empty():
		var candidate := option({}, horizon, context._reload_exposure(actor.global_position, threat) * horizon)
		candidate.accepts_noise = true
		candidate.search_recovery = not is_observing()
		return [candidate]
	var route: Dictionary = context.spatial.assess_route(context, path, threat, movement_multiplier(), context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0)
	var candidate := option({}, horizon, route.exposure + context._reload_exposure(point, threat) * maxf(0.0, horizon - route.seconds))
	candidate.accepts_noise = true
	return [candidate]

func begin(candidate: Dictionary, visible: bool) -> bool:
	candidate.accepts_noise = true
	super.begin(candidate, visible)
	context.utility_suppression_pending = false
	if noise_search_origin.is_finite() and investigation_phase < 0:
		var position := noise_search_origin
		investigate_noise(position)
	elif investigation_phase >= 0:
		context.state = investigation_phase
		agent.target_position = utility_destination()
	else:
		begin_tracking_or_search(context.investigation_hint_allowed)
	context.investigation_hint_allowed = false
	return true

func valid(visible: bool) -> bool:
	return _running and not visible and (context.is_alerted or noise_search_origin.is_finite())

func tick(delta: float, _visible: bool) -> Dictionary:
	if plan.get("search_recovery", false):
		plan.erase("search_recovery")
		if not is_observing() and selection._path_to(actor.global_position, utility_destination()).is_empty():
			recover_unreachable_destination()
	if not context.is_alerted and not noise_search_origin.is_finite():
		_running = false
		return motion(Vector3.ZERO)
	var direction := step(delta)
	_running = context.is_alerted or noise_search_origin.is_finite()
	return motion(direction, movement_multiplier(), facing_direction(direction))

func cancel(reason: StringName = &"switch") -> void:
	# 暂时被其他行动接管时保留搜索覆盖和已承诺的调查段；死亡/复位调用 reset。
	_running = false
	plan = {}
	if reason != &"switch": reset()

func can_interrupt(next: Dictionary, visible: bool) -> bool:
	if visible or next.get("urgent", false): return true
	var committed := has_committed_segment()
	# 搜索段边界允许换方案，但同一份旧威胁不能把调查重新送回躲藏。
	# 新受伤/明显近弹通过 release_segment 解锁撤离，换弹仍可立即接管。
	if next.get("conceals", false) and not _segment_released: return false
	return not committed

func hold_released() -> bool:
	return is_segment_released()

func on_event(event: StringName, data: Dictionary) -> void:
	if event == &"visibility" and data.visible:
		reset()
	elif event == &"damage":
		release_segment()
	elif event == &"threat":
		if _running and is_segment_released():
			investigate_known_threat(data.position)
		elif not _running:
			investigation_phase = -1
	elif event == &"noise":
		if _running: investigate_noise(data.position, true)
		else: investigation_phase = -1
