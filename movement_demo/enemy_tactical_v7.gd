extends CharacterBody3D

enum State { IDLE, APPROACH, INVESTIGATE, SEARCH, DEAD, PATROL, REPOSITION, HOLD_POSITION, TRACK }
enum CombatType { MELEE, RANGED }
enum SearchHintDecayMode {
	NONE,
	LINEAR_TIME,
	EXPONENTIAL_TIME,
	LINEAR_DISTANCE,
	TIME_AND_DISTANCE,
	CUSTOM
}

## 近战沿用接近行为；远程寻找射击位置。本步尚无攻击。
@export var combat_type: CombatType = CombatType.MELEE
## 远程敌人希望保持的距离区间，单位为米。
@export_range(1.0, 20.0, 0.5) var ranged_min_distance: float = 4.0
@export_range(2.0, 25.0, 0.5) var ranged_max_distance: float = 6.0
## 选位有冷却，且有效目标会继续沿用，避免频繁左右换路。
@export_range(0.1, 5.0, 0.05) var ranged_repath_seconds: float = 0.75
## 远程选位时更偏好侧向换位，而不是只沿玩家径向前后移动。
@export_range(0.0, 10.0, 0.1) var ranged_flank_weight: float = 3.0
## 候选射击位附近若有侧墙/后墙，可获得额外战术价值。
@export_range(0.0, 10.0, 0.1) var ranged_wall_support_weight: float = 2.5
## 探测候选射击位附近墙体的距离。
@export_range(0.5, 4.0, 0.1) var ranged_wall_probe_distance: float = 1.5

@export var move_speed: float = 2.0
@export var sight_distance: float = 10.0
@export_range(10.0, 360.0, 5.0) var sight_angle_degrees: float = 120.0

@export_group("Tracking Cheat")
## 是否允许 AI 在失去视野后偶尔读取一次墙后玩家的位置。
## 关闭后不会偷看 player.global_position，只依赖真实目击留下的 last_seen_direction。
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
## TRACK 状态专用视野角。比普通 sight_angle_degrees 更宽，让 NPC 架枪追踪时仍能注意侧面动静。
## 例如 220° 表示前方左右各约 110°；仍保留身后的盲区，不是 360° 透视。
@export_range(10.0, 360.0, 5.0) var track_sight_angle_degrees: float = 220.0
## TRACK 的移动目标至少离 NavigationRegion 边界这么远，避免目标贴在 NavMesh 边缘导致角色顶住边界。
@export_range(0.1, 1.5, 0.05) var track_nav_edge_margin: float = 0.35
## 判断目标是否贴近 NavMesh 边界时，外围探针允许被吸附回网格的最大误差。
@export_range(0.02, 0.5, 0.01) var track_nav_probe_tolerance: float = 0.12
## TRACK 距离安全导航目标小于这个距离时直接视为到达，不要求 NavigationAgent 必须精确走到一点。
@export_range(0.1, 1.0, 0.05) var track_arrival_distance: float = 0.45
@export_group("Search")
## SEARCH 的保险超时。0 = 不按时间结束，而是把系统化搜索路线扫完后才结束。
@export_range(0.0, 120.0, 1.0) var search_seconds: float = 0.0
## 以玩家最后出现/最后已知的位置为圆心，系统搜索到这个最大半径。
@export_range(1.0, 20.0, 0.5) var search_radius: float = 5.0
## 每到一个搜索点后停留观察多久。
@export_range(0.0, 5.0, 0.1) var search_pause_seconds: float = 0.5
## 相邻搜索圆环之间的半径间距。NPC 会从中心开始，一圈一圈向外扩大搜索。
@export_range(0.5, 4.0, 0.25) var search_ring_spacing: float = 1.25
## 同一圆环上相邻搜索点之间期望的弧长间距。越小覆盖越细。
@export_range(0.5, 4.0, 0.25) var search_point_spacing: float = 1.25
## 距离搜索点小于这个值时直接视为到达，不要求 NavigationAgent 精确踩点。
@export_range(0.1, 1.0, 0.05) var search_arrival_distance: float = 0.5
## 原始规则搜索点投影到 NavigationRegion 时，最多允许被吸附这么远；超过就跳过该点。
@export_range(0.1, 2.0, 0.05) var search_nav_snap_tolerance: float = 0.65
## SEARCH 系统化扫区时的移动速度倍率。
@export_range(0.1, 1.0, 0.05) var search_move_speed_multiplier: float = 0.45
## 朝当前搜索目标这么久没有明显靠近时，跳过这个点继续下一个，避免卡死。
@export_range(0.2, 3.0, 0.1) var search_stuck_repath_seconds: float = 0.9
## 要比历史最近距离至少缩短这么多，才算真的在朝当前搜索点推进。
@export_range(0.02, 0.5, 0.01) var search_stuck_min_progress_distance: float = 0.08
## 调试时打印系统化搜索生成了多少点、当前走到第几个点。
@export var debug_systematic_search: bool = false

@export var stopping_distance: float = 1.3
@export var turn_speed_degrees: float = 360.0
@export var max_health: float = 100.0
## 每次巡逻抵达后停留的时间。
@export_range(0.0, 10.0, 0.1) var patrol_pause_seconds: float = 1.5
## 近身警戒不限制方向，但仍检测墙壁遮挡。
@export_range(0.0, 5.0, 0.1) var close_awareness_radius: float = 2.0
## 受击时只知道攻击者附近区域，不持续获取攻击者坐标。
@export_range(0.0, 5.0, 0.1) var attack_position_uncertainty: float = 1.0

var state: State = State.IDLE
var last_known_position: Vector3
## 只由真实目击更新；来弹推测不能覆盖它。
var last_seen_position: Vector3
## 玩家连续可见时估计出的最后移动方向。
var last_seen_direction: Vector3 = Vector3.ZERO
var was_seeing_player: bool = false

## TRACK 实际要走到的安全导航目标；必须位于 NavigationRegion 内且与边界保留余量。
var suspected_position: Vector3
## TRACK 架枪时持续瞄准的“怀疑位置”。它与移动目标分离，允许脚下绕路但不会把枪口带偏。
## 该点也会先吸附到 NavigationRegion，因此不会生成在地图/NavMesh 外。
var suspected_look_position: Vector3
var has_suspected_position: bool = false
var track_timer: float = 0.0
var search_direction: Vector3 = Vector3.ZERO
var search_hint_timer: float = 0.0

## 系统化同心圆搜索路线。点从中心向外逐圈生成，不使用随机数。
var search_sweep_points: Array[Vector3] = []
var search_sweep_index: int = 0
var search_current_target: Vector3 = Vector3.ZERO
var search_current_target_active: bool = false
var search_progress_best_distance: float = INF
var search_stuck_timer: float = 0.0
var search_elapsed_seconds: float = 0.0


## 唯一的“知道玩家”标志。被目击、受击或近身来弹触发后都会设为 true；
## 搜索彻底结束后才恢复为 false。
var is_alerted: bool = false

var search_origin: Vector3
var search_timer: float = 0.0
var search_pause_timer: float = 0.0
var search_is_pausing: bool = false

var health: float = 100.0
var is_dead: bool = false
var player: Node3D
var initial_transform: Transform3D
var initial_body_transform: Transform3D
var death_tween: Tween
var patrol_pause_timer: float = 0.0
var ranged_repath_timer: float = 0.0
var ranged_has_destination: bool = false

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var arena_zone: Area3D = $"../CombatZone"
@onready var navigation_region: NavigationRegion3D = $"../NavigationRegion3D"
@onready var cover = get_node_or_null("Cover")


func _ready() -> void:
	initial_transform = transform
	initial_body_transform = $Body.transform
	player = get_tree().get_first_node_in_group("player")
	reset_target()


## 给其他脚本查询：敌人当前是否已经知道玩家并处于战斗激活状态。
func is_active() -> bool:
	return is_alerted and not is_dead


func reset_target() -> void:
	if death_tween != null and death_tween.is_valid():
		death_tween.kill()

	transform = initial_transform
	$Body.transform = initial_body_transform
	$FrontMarker.show()
	$CollisionShape3D.set_deferred("disabled", false)
	add_to_group("combat_target")

	health = max_health
	is_dead = false
	state = State.IDLE
	velocity = Vector3.ZERO

	is_alerted = false
	last_known_position = global_position
	last_seen_position = global_position
	last_seen_direction = Vector3.ZERO
	was_seeing_player = false
	suspected_position = global_position
	suspected_look_position = global_position
	has_suspected_position = false
	track_timer = 0.0
	search_direction = Vector3.ZERO
	search_hint_timer = 0.0
	search_sweep_points.clear()
	search_sweep_index = 0
	search_current_target = global_position
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	search_elapsed_seconds = 0.0
	if cover != null:
		cover.reset()

	search_origin = global_position
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false

	patrol_pause_timer = patrol_pause_seconds
	ranged_repath_timer = 0.0
	ranged_has_destination = false
	agent.target_position = global_position
	_update_label()


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# 地图同步完成前不能请求路径。
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return

	var sees_player: bool = can_see_player()
	var lost_player_this_frame: bool = was_seeing_player and not sees_player

	# 只用“连续两帧都真正看见玩家”来估计移动方向。
	# 这样不需要额外的“是否曾目击玩家”状态，也不会把第一次看见时的长距离差误当成移动。
	if sees_player:
		var new_seen_position := player.global_position
		if was_seeing_player:
			var seen_motion := new_seen_position - last_seen_position
			seen_motion.y = 0.0
			if seen_motion.length() > 0.05:
				last_seen_direction = seen_motion.normalized()
		last_seen_position = new_seen_position

	# 躲藏循环优先处理。躲在墙后时“看不见玩家”是主动行为，不在这里触发丢失目标判定；
	# 如果探头后仍未重新发现玩家，由 Cover 自己进入 TRACK/SEARCH。
	if cover != null and cover.is_active():
		if sees_player:
			is_alerted = true
			last_known_position = last_seen_position
			has_suspected_position = false
			search_hint_timer = 0.0
		var cover_direction: Vector3 = cover.step(delta, sees_player)
		if cover.phase == cover.Phase.RUN_TO_COVER and cover.covering_retreat:
			# 掩护撤退：脚仍沿导航路径去掩体，但身体/武器方向保持朝向玩家或最后已知威胁位置。
			_face_direction(cover.look_position - global_position, delta)
		elif cover.phase == cover.Phase.RUN_TO_COVER and not cover_direction.is_zero_approx():
			# 普通跑掩体：直接朝移动方向转身冲过去。
			_face_direction(cover_direction, delta)
		else:
			_face_direction(cover.look_position - global_position, delta)
		_move_character(cover_direction, delta, cover.movement_multiplier())
		was_seeing_player = sees_player
		_update_label()
		return

	was_seeing_player = sees_player

	# 只要真正看到玩家，就进入唯一的“知道玩家”状态，并持续刷新最后已知位置。
	if sees_player:
		is_alerted = true
		last_known_position = player.global_position
		has_suspected_position = false
		track_timer = 0.0
		search_hint_timer = 0.0

		if combat_type == CombatType.RANGED:
			if state != State.REPOSITION and state != State.HOLD_POSITION:
				state = State.REPOSITION
				ranged_repath_timer = 0.0
				ranged_has_destination = false
		else:
			if state != State.APPROACH or agent.target_position.distance_to(last_known_position) > 0.25:
				agent.target_position = last_known_position
			state = State.APPROACH
		search_timer = 0.0
		search_pause_timer = 0.0
		search_is_pausing = false

	# 真正从“看见”切到“看不见”时，只掷一次方向线索。
	elif lost_player_this_frame:
		_begin_tracking_or_search(true)

	# 没有可用方向信息时，旧的近战调查仍可走到最后目击位置再搜索。
	elif state == State.APPROACH:
		state = State.INVESTIGATE
		agent.target_position = last_known_position

	var direction := Vector3.ZERO

	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)
		if patrol_pause_timer <= 0.0:
			_start_random_patrol()

	elif state == State.APPROACH or state == State.INVESTIGATE or state == State.PATROL:
		# 每个物理帧更新导航路径；只沿导航点移动，不直冲障碍物。
		var next_position: Vector3 = agent.get_next_path_position()
		var close_to_player: bool = (
			state == State.APPROACH
			and sees_player
			and _horizontal_distance(last_known_position) <= stopping_distance
		)

		if not close_to_player and not agent.is_navigation_finished():
			direction = next_position - global_position
			direction.y = 0.0
			if not direction.is_zero_approx():
				direction = direction.normalized()

		elif state == State.INVESTIGATE:
			_begin_tracking_or_search(false)

		elif state == State.PATROL:
			state = State.IDLE
			patrol_pause_timer = patrol_pause_seconds

		if close_to_player:
			_face_direction(last_known_position - global_position, delta)

	elif state == State.TRACK:
		direction = _process_track(delta)

	elif state == State.SEARCH:
		direction = _process_search(delta)

	elif state == State.REPOSITION or state == State.HOLD_POSITION:
		direction = _process_ranged_position(delta, sees_player)

	# 远程走位和 TRACK 允许侧移/后退，同时把武器方向保持在威胁方向。
	if state == State.REPOSITION or state == State.HOLD_POSITION:
		_face_direction(last_known_position - global_position, delta)
	elif state == State.TRACK and has_suspected_position:
		# TRACK 是“重点关注怀疑方向”，而不是把身体永久锁死。
		# 实际朝向在怀疑方向和导航移动方向之间混合：权重越高越偏向怀疑区域。
		var attention_direction: Vector3 = suspected_look_position - global_position
		attention_direction.y = 0.0
		var movement_direction: Vector3 = direction
		movement_direction.y = 0.0

		var track_facing_direction: Vector3 = attention_direction
		if not attention_direction.is_zero_approx() and not movement_direction.is_zero_approx():
			track_facing_direction = movement_direction.normalized().lerp(
				attention_direction.normalized(),
				clampf(track_attention_weight, 0.0, 1.0)
			)
			if track_facing_direction.is_zero_approx():
				track_facing_direction = attention_direction
		elif attention_direction.is_zero_approx():
			track_facing_direction = movement_direction

		if not track_facing_direction.is_zero_approx():
			_face_direction(track_facing_direction, delta)
	elif state == State.SEARCH:
		# SEARCH 在移动时身体朝实际移动方向，避免脚向左走但身体还一直朝另一边。
		# 停下来观察时才重新朝向最可疑方向。
		if not direction.is_zero_approx():
			_face_direction(direction, delta)
		elif not search_direction.is_zero_approx():
			_face_direction(search_direction, delta)
	elif not direction.is_zero_approx():
		_face_direction(direction, delta)

	var movement_speed_multiplier: float = 1.0
	if state == State.TRACK:
		movement_speed_multiplier = track_move_speed_multiplier
	elif state == State.SEARCH:
		movement_speed_multiplier = search_move_speed_multiplier

	_move_character(direction, delta, movement_speed_multiplier)
	_update_label()


func _move_character(direction: Vector3, delta: float, speed_multiplier: float = 1.0) -> void:
	velocity.x = direction.x * move_speed * speed_multiplier
	velocity.z = direction.z * move_speed * speed_multiplier
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()


func _process_ranged_position(delta: float, sees_player: bool) -> Vector3:
	var band := _ranged_distance_band()
	var distance := _horizontal_distance(last_known_position)
	var in_band := sees_player and distance >= band.x and distance <= band.y

	# HOLD 只表示“已经到达一个认可的射击位”。玩家明显改变距离或 LOS 后才重新选位。
	if state == State.HOLD_POSITION:
		if in_band and _has_clear_ray_to_known_position(global_position):
			return Vector3.ZERO
		state = State.REPOSITION
		ranged_has_destination = false
		ranged_repath_timer = 0.0

	ranged_repath_timer = maxf(0.0, ranged_repath_timer - delta)
	if ranged_repath_timer <= 0.0:
		ranged_repath_timer = maxf(0.1, ranged_repath_seconds)
		var destination := agent.target_position
		var target_distance := _horizontal_distance_between(destination, last_known_position)
		var valid_destination := (
			ranged_has_destination
			and target_distance >= band.x and target_distance <= band.y
			and _ranged_point_is_free(destination)
			and _has_clear_ray_to_known_position(destination)
		)

		# 玩家太近时，退路不能从玩家身边擦过去。
		if valid_destination and distance < band.x:
			var path := NavigationServer3D.map_get_path(
				agent.get_navigation_map(), global_position, destination, true, agent.navigation_layers)
			valid_destination = not path.is_empty() and _retreat_path_is_safe(path, distance)

		if not valid_destination:
			ranged_has_destination = _choose_ranged_position(band, distance)
			if not ranged_has_destination:
				if not sees_player:
					_begin_tracking_or_search(true)
					return Vector3.ZERO
				if distance > band.y:
					# 没采到合适战术点时，至少先接近到有效射程。
					agent.target_position = last_known_position
					ranged_has_destination = true
				elif in_band:
					# 当前已经能打，但没有更好的点，留在原地而不是无意义乱跑。
					state = State.HOLD_POSITION
					agent.target_position = global_position
					return Vector3.ZERO
				else:
					agent.target_position = global_position
					return Vector3.ZERO

	if not ranged_has_destination:
		return Vector3.ZERO

	var next_position := agent.get_next_path_position()
	if agent.is_navigation_finished():
		ranged_has_destination = false
		if sees_player:
			state = State.HOLD_POSITION
			agent.target_position = global_position
		else:
			_begin_tracking_or_search(true)
		return Vector3.ZERO

	var direction := next_position - global_position
	direction.y = 0.0
	return direction.normalized()


func _ranged_distance_band() -> Vector2:
	var minimum := maxf(1.0, ranged_min_distance)
	return Vector2(minimum, maxf(minimum + 1.0, ranged_max_distance))


func _choose_ranged_position(band: Vector2, current_distance: float) -> bool:
	var preferred_distance := (band.x + band.y) * 0.5
	var best_score := INF
	var best_position := Vector3.ZERO

	var current_radial := global_position - last_known_position
	current_radial.y = 0.0
	if current_radial.is_zero_approx():
		current_radial = Vector3.BACK
	else:
		current_radial = current_radial.normalized()

	var start_angle := atan2(current_radial.z, current_radial.x)

	# 在两个距离环上采样。候选点必须能射到“最后已知位置”，但评分不再只看距离。
	for radius in [preferred_distance, band.y - 0.25]:
		for index in range(16):
			var angle := start_angle + TAU * float(index) / 16.0
			var candidate: Vector3 = last_known_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var nav_point := NavigationServer3D.region_get_closest_point(navigation_region.get_rid(), candidate)
			if _horizontal_distance_between(candidate, nav_point) > 0.75:
				continue

			var destination := Vector3(nav_point.x, global_position.y, nav_point.z)
			var distance := _horizontal_distance_between(destination, last_known_position)
			if distance < band.x or distance > band.y:
				continue
			if not _ranged_point_is_free(destination) or not _has_clear_ray_to_known_position(destination):
				continue

			var path := NavigationServer3D.map_get_path(
				agent.get_navigation_map(), global_position, nav_point, true, agent.navigation_layers)
			if path.is_empty() or path[path.size() - 1].distance_to(nav_point) > 0.5:
				continue
			if current_distance < band.x and not _retreat_path_is_safe(path, current_distance):
				continue

			var path_length := 0.0
			for step in range(1, path.size()):
				path_length += path[step - 1].distance_to(path[step])

			var candidate_radial := destination - last_known_position
			candidate_radial.y = 0.0
			if candidate_radial.is_zero_approx():
				continue
			candidate_radial = candidate_radial.normalized()

			# 与当前径向越不同，越像主动侧移/换角度，而不是只前后保持距离。
			var flank_amount := 1.0 - absf(current_radial.dot(candidate_radial))
			# 有 LOS 的前提下，附近存在侧墙/后墙意味着更容易重新断线或撤回。
			var wall_support := _ranged_wall_support(destination)

			var score := path_length + absf(distance - preferred_distance) * 2.0
			score -= flank_amount * ranged_flank_weight
			score -= wall_support * ranged_wall_support_weight
			# 几乎原地不动的候选点略微惩罚，避免“看起来只是站着保持距离”。
			if path_length < 0.75:
				score += 2.0

			if score < best_score:
				best_score = score
				best_position = destination

	if is_inf(best_score):
		return false
	agent.target_position = best_position
	return true


func _ranged_wall_support(point: Vector3) -> float:
	var threat_direction := last_known_position - point
	threat_direction.y = 0.0
	if threat_direction.is_zero_approx():
		return 0.0
	threat_direction = threat_direction.normalized()

	var side := threat_direction.cross(Vector3.UP).normalized()
	var away := -threat_direction
	var directions: Array[Vector3] = [side, -side, away]
	var hits := 0.0

	for probe_direction in directions:
		var from: Vector3 = point + Vector3.UP * 0.8
		var to: Vector3 = from + probe_direction * ranged_wall_probe_distance
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
		if is_instance_valid(player) and player is CollisionObject3D:
			query.exclude = [get_rid(), player.get_rid()]
		var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is StaticBody3D:
			hits += 1.0

	return hits / 3.0


func _retreat_path_is_safe(path: PackedVector3Array, current_distance: float) -> bool:
	var threat := Vector2(last_known_position.x, last_known_position.z)
	var previous := Vector2(global_position.x, global_position.z)
	for point in path:
		var next := Vector2(point.x, point.z)
		var closest := Geometry2D.get_closest_point_to_segment(threat, previous, next)
		if closest.distance_to(threat) < maxf(0.1, current_distance - 0.2):
			return false
		previous = next
	return true


func _ranged_point_is_free(point: Vector3) -> bool:
	var collision: CollisionShape3D = $CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	# 略高于地面，避免把正常接触地板误判成被墙堵住。
	query.transform = Transform3D(Basis.IDENTITY, point + collision.position + Vector3.UP * 0.05)
	query.collision_mask = collision_mask
	query.exclude = [get_rid()]
	# 候选点评估只检查障碍，不能借碰撞查询感知墙后玩家的位置。
	if is_instance_valid(player) and player is CollisionObject3D:
		query.exclude = [get_rid(), player.get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _has_clear_ray_to_known_position(from: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 0.8, last_known_position + Vector3.UP * 0.8, 1, [get_rid()])
	# 检查的是已知位置与墙的关系；隐藏玩家的实体不能改变候选点评分。
	if is_instance_valid(player) and player is CollisionObject3D:
		query.exclude = [get_rid(), player.get_rid()]
	query.hit_from_inside = true
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _start_random_patrol() -> void:
	# 激活期间不允许随机巡逻。正常情况下 SEARCH 结束时才会解除警戒。
	if is_alerted:
		return

	# 只从本竞技场的导航区域选点，避免走进连接通道或其他场地。
	for attempt in range(12):
		var destination := NavigationServer3D.region_get_random_point(
			navigation_region.get_rid(),
			agent.navigation_layers,
			true
		)

		if _horizontal_distance(destination) < 2.0:
			continue

		var path := NavigationServer3D.map_get_path(
			agent.get_navigation_map(),
			global_position,
			destination,
			true,
			agent.navigation_layers
		)

		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 0.5:
			continue

		# 烘焙网格高于脚底；目标也需换成角色脚底高度才能正确判定抵达。
		destination.y -= agent.path_height_offset
		agent.target_position = destination
		state = State.PATROL
		return

	# 没有合适的点时稍后重试，避免每一帧重复查找。
	patrol_pause_timer = maxf(patrol_pause_seconds, 0.5)


func _begin_tracking_or_search(allow_hint: bool = true) -> void:
	is_alerted = true
	ranged_has_destination = false
	ranged_repath_timer = 0.0
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	search_hint_timer = 0.0

	# 第一优先：如果允许“小外挂”，只在这个时刻掷一次骰子。
	if allow_hint and _try_tracking_cheat_hint(lost_target_hint_chance):
		_start_track_to_suspected()
		return

	# 第二优先：不用作弊，只根据玩家最后真正被看到时的移动方向进行推断。
	if not last_seen_direction.is_zero_approx():
		search_direction = last_seen_direction.normalized()
		var raw_target: Vector3 = last_seen_position + search_direction * track_distance
		if _set_suspected_position_from_raw(raw_target, 2.0):
			_start_track_to_suspected()
			return

	# 连最后移动方向都没有，就在最后已知位置进入警戒搜索。
	has_suspected_position = false
	_begin_search(last_known_position)


## SEARCH 当前实际使用的“外挂”概率。
## 这是留给外部调试/UI/后续扩展的统一接口；丢失视野瞬间的 lost_target_hint_chance 不走这里。
func get_current_search_hint_chance() -> float:
	if search_hint_chance <= 0.0:
		return 0.0

	var elapsed: float = maxf(0.0, search_elapsed_seconds)
	var player_displacement: float = 0.0
	if is_instance_valid(player):
		player_displacement = _horizontal_distance_between(search_origin, player.global_position)

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
	# 默认示例：时间越久、玩家离搜索中心越远，倍率越低。
	# 当前返回 1.0，保持 CUSTOM 为“接口占位”，方便你之后直接替换公式。
	return 1.0


## “小外挂”：按概率读取一次隐藏玩家的大概位置。
## 成功后只保存 suspected_position；后续 TRACK 不会持续跟踪隐藏玩家。
func _try_tracking_cheat_hint(chance: float) -> bool:
	if debug_tracking_cheat:
		print("[TrackingCheat] 尝试提示 chance=", snappedf(chance, 0.001))

	if not tracking_cheat_enabled:
		if debug_tracking_cheat:
			print("[TrackingCheat] 失败：tracking_cheat_enabled=false")
		return false
	if chance <= 0.0:
		if debug_tracking_cheat:
			print("[TrackingCheat] 失败：当前实际概率<=0")
		return false
	if randf() > chance:
		if debug_tracking_cheat:
			print("[TrackingCheat] 失败：概率未命中")
		return false
	if not is_alerted or not is_instance_valid(player):
		if debug_tracking_cheat:
			print("[TrackingCheat] 失败：AI未激活或player无效")
		return false
	if not arena_zone.overlaps_body(player):
		if debug_tracking_cheat:
			print("[TrackingCheat] 失败：player不在CombatZone")
		return false

	var player_distance: float = _horizontal_distance_between(global_position, player.global_position)
	if player_distance > tracking_cheat_max_distance:
		if debug_tracking_cheat:
			print(
				"[TrackingCheat] 失败：距离超限 distance=",
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
		var raw_target: Vector3 = player.global_position

		if tracking_hint_error_radius > 0.0:
			var error_angle: float = randf_range(0.0, TAU)
			var error_radius: float = sqrt(randf()) * tracking_hint_error_radius
			raw_target += Vector3(cos(error_angle), 0.0, sin(error_angle)) * error_radius

		if _set_suspected_position_from_raw(raw_target, max_snap_distance):
			var hint_direction: Vector3 = suspected_look_position - global_position
			hint_direction.y = 0.0
			if not hint_direction.is_zero_approx():
				search_direction = hint_direction.normalized()
			if debug_tracking_cheat:
				print(
					"[TrackingCheat] 成功：误差采样 ",
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
	if _set_suspected_position_relaxed(player.global_position):
		var fallback_direction: Vector3 = suspected_look_position - global_position
		fallback_direction.y = 0.0
		if not fallback_direction.is_zero_approx():
			search_direction = fallback_direction.normalized()
		if debug_tracking_cheat:
			print(
				"[TrackingCheat] 成功：使用真实位置的宽松Nav回退 suspected=",
				suspected_position,
				" look=",
				suspected_look_position
			)
		return true

	if debug_tracking_cheat:
		print("[TrackingCheat] 失败：概率已命中，但玩家附近与通往该区域的导航路径都不可用")
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
			navigation_region.get_rid(),
			probe
		)
		if _horizontal_distance_between(probe, snapped) > tolerance:
			return false
	return true


## TRACK 的候选终点只要求：导航可达，而且角色碰撞体在终点能站下。
## 不再对整条导航路径做“一票否决”的碰撞采样；那会把很多实际可走的拐角误判掉。
func _track_nav_point_is_reachable(nav_point: Vector3) -> bool:
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(),
		global_position,
		nav_point,
		true,
		agent.navigation_layers
	)
	if path.is_empty() or path[path.size() - 1].distance_to(nav_point) > 0.5:
		return false

	var destination := Vector3(nav_point.x, global_position.y, nav_point.z)
	return _ranged_point_is_free(destination)


## 将推测位置限制在本竞技场 NavigationRegion3D。
## suspected_look_position 保存吸附后的怀疑方向；suspected_position 则进一步向网格内部收缩，专门作为安全移动终点。
func _set_suspected_position_from_raw(raw_target: Vector3, max_snap_distance: float) -> bool:
	var closest_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		navigation_region.get_rid(),
		raw_target
	)
	if _horizontal_distance_between(raw_target, closest_nav_point) > max_snap_distance:
		return false

	# 瞄准点本身也只允许落在 NavigationRegion 上，不保留地图外的原始点。
	var look_destination: Vector3 = Vector3(
		closest_nav_point.x,
		global_position.y,
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
			navigation_region.get_rid(),
			global_position
		)
		var inward: Vector3 = current_nav_point - closest_nav_point
		inward.y = 0.0
		if not inward.is_zero_approx():
			inward = inward.normalized()
			var step_distance: float = maxf(0.1, track_nav_edge_margin * 0.5)
			for step_index in range(1, 9):
				var inward_probe: Vector3 = closest_nav_point + inward * step_distance * float(step_index)
				var candidate: Vector3 = NavigationServer3D.region_get_closest_point(
					navigation_region.get_rid(),
					inward_probe
				)
				if _horizontal_distance_between(inward_probe, candidate) > maxf(0.25, track_nav_probe_tolerance * 2.0):
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
	suspected_position = Vector3(safe_nav_point.x, global_position.y, safe_nav_point.z)
	has_suspected_position = true
	return true


## 外挂概率已经命中时使用的宽松位置转换。
## 它不要求目标拥有 TRACK 的完整边界余量；如果玩家附近终点站不下，
## 就沿“当前NPC -> 玩家附近Nav点”的导航路径从后往前找最后一个可站立点。
## 这样“知道大概在哪”与“是否能精确走到那个点”不会再混成一件事。
func _set_suspected_position_relaxed(raw_target: Vector3) -> bool:
	var closest_nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		navigation_region.get_rid(),
		raw_target
	)

	# 玩家提示的注意力方向仍然只指向NavigationRegion内的最近合法位置。
	var look_destination: Vector3 = Vector3(
		closest_nav_point.x,
		global_position.y,
		closest_nav_point.z
	)

	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(),
		global_position,
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
			global_position.y,
			path_point.z
		)
		if not _ranged_point_is_free(destination):
			continue

		suspected_look_position = look_destination
		suspected_position = destination
		has_suspected_position = true
		return true

	return false


func _start_track_to_suspected() -> void:
	if not has_suspected_position:
		return

	var direction: Vector3 = suspected_look_position - global_position
	direction.y = 0.0
	if not direction.is_zero_approx():
		search_direction = direction.normalized()

	track_timer = track_seconds
	state = State.TRACK
	agent.target_position = suspected_position


func _process_track(delta: float) -> Vector3:
	track_timer = maxf(0.0, track_timer - delta)

	var reached_track_target: bool = (
		has_suspected_position
		and _horizontal_distance(suspected_position) <= track_arrival_distance
	)

	# TRACK 只负责去怀疑位置。
	# 到达、超时，或 NavigationAgent 已经结束当前路径时，就进入 SEARCH。
	# SEARCH 的圆心始终回到玩家最后真正出现/最后已知的位置，
	# 不把 TRACK 的预测终点当成新的搜索中心。
	if track_timer <= 0.0 or reached_track_target or agent.is_navigation_finished():
		_begin_search(last_known_position)
		return Vector3.ZERO

	var next_position: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized()

func _begin_search(center: Vector3 = Vector3.INF) -> void:
	state = State.SEARCH
	is_alerted = true

	# 这里的 center 就是本轮“最后知道玩家在那里”的位置：
	# 正常丢失视野时通常是 last_known_position；
	# 如果先经过 TRACK，也可能是那次模糊提示的 suspected_position。
	search_origin = center if center.is_finite() else last_known_position
	search_origin.y = global_position.y

	# SEARCH 主方向优先使用玩家最后真实移动方向。
	# 没有移动方向时，再使用已有的怀疑方向；还没有就从 NPC 朝搜索中心；最后才使用当前朝向。
	var forward: Vector3 = last_seen_direction
	forward.y = 0.0

	if forward.is_zero_approx():
		forward = search_direction
		forward.y = 0.0

	if forward.is_zero_approx():
		forward = search_origin - global_position
		forward.y = 0.0

	if forward.is_zero_approx():
		forward = -global_basis.z
		forward.y = 0.0

	if forward.is_zero_approx():
		forward = Vector3.FORWARD

	search_direction = forward.normalized()

	# 0 = 没有时间限制，直到固定路线扫完。
	search_timer = search_seconds if search_seconds > 0.0 else INF
	search_elapsed_seconds = 0.0
	search_hint_timer = maxf(0.25, search_hint_interval_seconds)
	search_pause_timer = maxf(0.0, search_pause_seconds)
	search_is_pausing = true

	search_sweep_index = 0
	search_current_target = global_position
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0

	_build_systematic_radial_search()

	# 先停一下观察，然后按固定路线开始。
	agent.target_position = global_position

	if debug_systematic_search:
		print(
			"[SearchSweep] 开始同心圆系统搜索 center=",
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
				print("[SearchSweep] 达到搜索保险超时")
			_end_search()
			return Vector3.ZERO

	# SEARCH 的外挂提示仍然保留，但路线本身完全不随机。
	if search_hint_timer <= 0.0:
		search_hint_timer = maxf(0.25, search_hint_interval_seconds)
		if _try_tracking_cheat_hint(get_current_search_hint_chance()):
			_start_track_to_suspected()
			return Vector3.ZERO

	# 每到一个固定搜索点，短暂停留观察，再去路线里的下一个点。
	if search_is_pausing:
		search_stuck_timer = 0.0
		search_progress_best_distance = INF
		search_pause_timer = maxf(0.0, search_pause_timer - delta)

		if search_pause_timer <= 0.0:
			search_is_pausing = false

			if not _advance_systematic_search_target():
				if debug_systematic_search:
					print("[SearchSweep] 同心圆区域已按路线搜索完毕")
				_end_search()
				return Vector3.ZERO

		return Vector3.ZERO

	# 当前没有有效目标时，直接拿下一个固定搜索点。
	if not search_current_target_active:
		if not _advance_systematic_search_target():
			_end_search()
		return Vector3.ZERO

	var distance_to_target: float = _horizontal_distance(search_current_target)

	# 不要求 Agent 精确踩点。
	if distance_to_target <= search_arrival_distance:
		_finish_current_search_point()
		return Vector3.ZERO

	# Agent 提前认为路径结束，但距离目标仍较远：这个点跳过，继续固定路线中的下一个。
	if agent.is_navigation_finished():
		if debug_systematic_search:
			print(
				"[SearchSweep] 路径提前结束，跳过 point ",
				search_sweep_index,
				" target=",
				search_current_target
			)
		_skip_current_search_point()
		return Vector3.ZERO

	# 监测的是“是否真的越来越靠近当前固定搜索点”，不是任意位移。
	if is_inf(search_progress_best_distance):
		search_progress_best_distance = distance_to_target
		search_stuck_timer = 0.0
	elif distance_to_target <= search_progress_best_distance - search_stuck_min_progress_distance:
		search_progress_best_distance = distance_to_target
		search_stuck_timer = 0.0
	else:
		search_stuck_timer += delta

	if search_stuck_timer >= search_stuck_repath_seconds:
		if debug_systematic_search:
			print(
				"[SearchSweep] 当前点无法继续靠近，跳过 target=",
				search_current_target
			)
		_skip_current_search_point()
		return Vector3.ZERO

	var next_position: Vector3 = agent.get_next_path_position()
	var direction: Vector3 = next_position - global_position
	direction.y = 0.0

	if direction.is_zero_approx():
		# 不原地死等，让 stuck timer 继续累计，超时后自动跳到路线下一个点。
		return Vector3.ZERO

	return direction.normalized()


## 生成固定的“同心圆逐圈外扩搜索路线”。
##
## search_origin = 玩家最后出现/最后已知的位置
## search_direction = 用来决定每一圈从哪个方向开始；不会限制搜索范围
##
## 路线顺序：
##   中心点
##   第1圈（顺时针）
##   第2圈（逆时针）
##   第3圈（顺时针）
##   ...
## 一直扩展到 search_radius。
##
## 相邻圆环交替旋转方向，这样上一圈结束后可以直接向外接到下一圈，
## 不需要每一圈都横穿整个搜索区域。整个路线不使用随机数。
func _build_systematic_radial_search() -> void:
	search_sweep_points.clear()

	var radius: float = maxf(1.0, search_radius)
	var ring_spacing: float = maxf(0.5, search_ring_spacing)
	var point_spacing: float = maxf(0.5, search_point_spacing)

	# 每一圈都从“最后移动/最可疑方向”附近开始。
	# 即使这个方向不存在，也固定使用世界前方，因此路线仍然完全确定。
	var anchor: Vector3 = search_direction
	anchor.y = 0.0
	if anchor.is_zero_approx():
		anchor = Vector3.FORWARD
	anchor = anchor.normalized()
	var anchor_angle: float = atan2(anchor.z, anchor.x)

	# 先检查最后出现的位置本身。
	_try_append_systematic_search_point(search_origin)

	var ring_index: int = 1
	var ring_radius: float = ring_spacing
	var generated_outer_ring: bool = false

	while ring_radius <= radius + 0.001:
		_append_systematic_search_ring(
			ring_radius,
			point_spacing,
			anchor_angle,
			ring_index % 2 == 1
		)

		if absf(ring_radius - radius) <= 0.001:
			generated_outer_ring = true

		ring_index += 1
		ring_radius += ring_spacing

	# search_radius 不一定刚好是 ring_spacing 的整数倍。
	# 无论如何都补一条最外圈，保证搜索范围真的扩展到最大半径。
	if not generated_outer_ring:
		_append_systematic_search_ring(
			radius,
			point_spacing,
			anchor_angle,
			ring_index % 2 == 1
		)

	if debug_systematic_search:
		print(
			"[SearchSweep] 生成同心圆路线 points=",
			search_sweep_points.size(),
			" radius=",
			radius,
			" ring=",
			ring_spacing,
			" point=",
			point_spacing
		)


## 生成一条固定半径的搜索圆环。
## clockwise=true 时按顺时针顺序加入，下一圈则反向，形成有规律的往复环扫。
func _append_systematic_search_ring(
	ring_radius: float,
	point_spacing: float,
	anchor_angle: float,
	clockwise: bool
) -> void:
	var circumference: float = TAU * ring_radius
	# 至少 6 个点，避免小圆环退化成多边形跨度过大。
	var point_count: int = maxi(6, int(ceil(circumference / point_spacing)))
	var direction_sign: float = -1.0 if clockwise else 1.0

	for point_index in range(point_count):
		var t: float = float(point_index) / float(point_count)
		var angle: float = anchor_angle + direction_sign * TAU * t
		var raw_point: Vector3 = search_origin + Vector3(
			cos(angle),
			0.0,
			sin(angle)
		) * ring_radius
		_try_append_systematic_search_point(raw_point)


## 把一个规则生成的点转换成当前 NavigationRegion 内的合法搜索点。
## 返回 false 只代表这个格子不可搜索，不会改变其他格子的固定顺序。
func _try_append_systematic_search_point(raw_point: Vector3) -> bool:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		navigation_region.get_rid(),
		raw_point
	)

	if _horizontal_distance_between(raw_point, nav_point) > search_nav_snap_tolerance:
		return false

	var destination: Vector3 = Vector3(
		nav_point.x,
		global_position.y,
		nav_point.z
	)

	# 投影后也必须仍处于本次圆形搜索范围中。
	var offset: Vector3 = destination - search_origin
	offset.y = 0.0

	if offset.length() > search_radius + search_nav_snap_tolerance:
		return false

	if not _ranged_point_is_free(destination):
		return false

	# 避免多个规则点被 NavMesh 吸到几乎同一个地方。
	for existing: Vector3 in search_sweep_points:
		if _horizontal_distance_between(existing, destination) < maxf(0.35, search_point_spacing * 0.35):
			return false

	search_sweep_points.append(destination)
	return true


## 按固定索引顺序寻找下一个“从当前位置真实可达”的搜索点。
## 不可达点直接跳过，不随机改方向。
func _advance_systematic_search_target() -> bool:
	while search_sweep_index < search_sweep_points.size():
		var destination: Vector3 = search_sweep_points[search_sweep_index]
		search_sweep_index += 1

		if _horizontal_distance(destination) <= search_arrival_distance:
			continue

		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			agent.get_navigation_map(),
			global_position,
			destination,
			true,
			agent.navigation_layers
		)

		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 0.5:
			if debug_systematic_search:
				print(
					"[SearchSweep] 跳过不可达点 ",
					search_sweep_index,
					"/",
					search_sweep_points.size(),
					" target=",
					destination
				)
			continue

		search_current_target = destination
		search_current_target_active = true
		search_progress_best_distance = _horizontal_distance(destination)
		search_stuck_timer = 0.0
		agent.target_position = destination

		if debug_systematic_search:
			print(
				"[SearchSweep] 前往 ",
				search_sweep_index,
				"/",
				search_sweep_points.size(),
				" target=",
				destination
			)

		return true

	search_current_target_active = false
	agent.target_position = global_position
	return false


func _finish_current_search_point() -> void:
	# 到达圆环上的点后，停下来时朝“从圆心向外”的方向观察。
	# 这样每一圈看起来是在扩大警戒范围，而不是始终盯着同一个方向。
	var outward: Vector3 = search_current_target - search_origin
	outward.y = 0.0
	if not outward.is_zero_approx():
		search_direction = outward.normalized()

	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	agent.target_position = global_position
	search_is_pausing = true
	search_pause_timer = maxf(0.0, search_pause_seconds)


func _skip_current_search_point() -> void:
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	agent.target_position = global_position
	search_is_pausing = true
	# 卡住点只做很短的停顿，然后继续固定路线。
	search_pause_timer = minf(maxf(0.05, search_pause_seconds * 0.35), 0.25)


func _end_search() -> void:
	# 搜索完整结束后，才退出“知道玩家”状态并恢复正常巡逻。
	is_alerted = false
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	track_timer = 0.0
	search_hint_timer = 0.0
	search_sweep_points.clear()
	search_sweep_index = 0
	search_current_target = global_position
	search_current_target_active = false
	search_progress_best_distance = INF
	search_stuck_timer = 0.0
	search_elapsed_seconds = 0.0
	has_suspected_position = false
	suspected_look_position = global_position
	search_direction = Vector3.ZERO
	last_seen_direction = Vector3.ZERO
	was_seeing_player = false

	state = State.IDLE
	patrol_pause_timer = patrol_pause_seconds
	agent.target_position = global_position


func can_see_player() -> bool:
	if not is_instance_valid(player) or not arena_zone.overlaps_body(player):
		return false

	var offset: Vector3 = player.global_position - global_position

	if offset.length() > maxf(sight_distance, close_awareness_radius):
		return false

	offset.y = 0.0

	if offset.length() > close_awareness_radius and not offset.is_zero_approx():
		var current_sight_angle: float = sight_angle_degrees
		if state == State.TRACK:
			# 架枪追踪时注意力更集中，但不是视野更窄：保留更宽的周边警觉，
			# 玩家从侧面接近时仍有机会进入真实视觉检测。
			current_sight_angle = maxf(current_sight_angle, track_sight_angle_degrees)

		var alignment: float = (-global_basis.z).dot(offset.normalized())
		if alignment < cos(deg_to_rad(current_sight_angle * 0.5)):
			return false

	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP * 0.8,
		player.global_position + Vector3.UP * 0.8,
		1,
		[get_rid()]
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _horizontal_distance_between(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _face_direction(direction: Vector3, delta: float) -> void:
	if Vector2(direction.x, direction.z).is_zero_approx():
		return

	rotation.y = rotate_toward(
		rotation.y,
		atan2(-direction.x, -direction.z),
		deg_to_rad(turn_speed_degrees) * delta
	)


func receive_hit(damage: float, attacker_position: Vector3 = Vector3.INF) -> void:
	if is_dead:
		return

	health = maxf(0.0, health - maxf(damage, 0.0))

	if health <= 0.0:
		is_dead = true
		if cover != null:
			cover.reset()
		is_alerted = false
		state = State.DEAD
		velocity = Vector3.ZERO
		remove_from_group("combat_target")
		$CollisionShape3D.set_deferred("disabled", true)
		$FrontMarker.hide()

		death_tween = create_tween().set_parallel(true)
		death_tween.tween_property($Body, "rotation:x", PI / 2.0, 0.3)
		death_tween.tween_property($Body, "position:y", 0.35, 0.3)

	elif damage > 0.0:
		if attacker_position.is_finite():
			_investigate_attack(attacker_position)

		# 掩护转移期间每次真正受伤都重新判定是否放弃慢速掩护撤退、改为全速冲刺。
		# 这一步也会把 _investigate_attack() 临时改写的导航目标重新锁回 Hide。
		if cover != null:
			cover.on_damage_during_transfer()

	_update_label()


func _investigate_attack(attacker_position: Vector3) -> void:
	# 受击或近身来弹直接进入唯一的“知道玩家”状态。
	# attacker_position 仍可带误差，但不再区分“只警觉、尚未目击”这种记忆状态。
	is_alerted = true

	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(0.25, 1.0) * attack_position_uncertainty

	last_known_position = attacker_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	last_known_position.y = global_position.y

	state = State.REPOSITION if combat_type == CombatType.RANGED else State.INVESTIGATE
	ranged_repath_timer = 0.0
	ranged_has_destination = false
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	search_hint_timer = 0.0
	agent.target_position = last_known_position


func _update_label() -> void:
	var names := ["巡逻停留", "看见玩家", "前往最后位置", "警戒搜索", "已死亡", "随机巡逻", "寻找射击位置", "保持射击位置", "架枪追踪"]
	if state == State.REPOSITION and _horizontal_distance(last_known_position) < _ranged_distance_band().x:
		names[State.REPOSITION] = "寻找后退路线"
	var knowledge_text := "知道玩家" if is_alerted else "未激活"

	var state_text: String = cover.state_label() if cover != null and cover.is_active() else names[state]
	var type_text := "近战" if combat_type == CombatType.MELEE else "远程"
	$Label.text = "%s敌人：%s\n生命 %d / %d\n%s" % [
		type_text,
		state_text,
		ceili(health),
		ceili(max_health),
		knowledge_text
	]
