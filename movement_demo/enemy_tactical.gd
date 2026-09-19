extends CharacterBody3D

enum State { IDLE, APPROACH, INVESTIGATE, SEARCH, DEAD, PATROL, REPOSITION, HOLD_POSITION, TRACK }
enum CombatType { MELEE, RANGED }

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

## 真正确认过玩家后，最长搜索时间。
@export var search_seconds: float = 10.0
## 只因受击而警觉、但还没亲眼见到玩家时的搜索时间。
@export var uncertain_search_seconds: float = 4.0
## 围绕最后已知位置搜索的半径。
@export_range(0.5, 20.0, 0.5) var search_radius: float = 4.0
## 到达每个搜索点后原地观察多久。
@export_range(0.1, 5.0, 0.1) var search_pause_seconds: float = 0.7
## 刚丢失真正目击目标时，有一次机会得到“玩家大概往哪边去了”的模糊提示。
@export_range(0.0, 1.0, 0.05) var lost_target_hint_chance: float = 0.5
## 模糊方向会加入随机角度误差，避免形成精确透视。
@export_range(0.0, 90.0, 1.0) var lost_target_hint_error_degrees: float = 25.0
## 得到方向线索后，先沿该方向谨慎推进的距离。
@export_range(1.0, 10.0, 0.5) var track_distance: float = 4.0
## TRACK 最长持续时间，超时后转为区域搜索。
@export_range(0.5, 10.0, 0.5) var track_seconds: float = 4.0
## SEARCH 主要在怀疑方向前方的锥形区域选点。
@export_range(15.0, 120.0, 5.0) var search_cone_degrees: float = 55.0
## 少量概率跳出前方锥形范围，避免永远只搜一个方向。
@export_range(0.0, 1.0, 0.05) var search_wide_sample_chance: float = 0.2

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
## 上一次真实目击位置，用于估计玩家最后移动方向。
var previous_seen_position: Vector3
var last_seen_direction: Vector3 = Vector3.ZERO
var was_seeing_player: bool = false

## 丢失目标后推测出的方向点；只在丢失瞬间计算一次，不持续读取隐藏玩家坐标。
var suspected_position: Vector3
var has_suspected_position: bool = false
var track_timer: float = 0.0
var search_direction: Vector3 = Vector3.ZERO

## 敌人是否已经意识到玩家/攻击者的存在。
var is_alerted: bool = false
## 敌人是否曾经亲眼确认过玩家。
var has_seen_player: bool = false

var search_origin: Vector3
var search_timer: float = 0.0
var search_pause_timer: float = 0.0
var search_start_angle: float = 0.0
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


## 给其他脚本查询：敌人当前是否处于激活/警戒状态。
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
	has_seen_player = false
	last_known_position = global_position
	last_seen_position = global_position
	previous_seen_position = global_position
	last_seen_direction = Vector3.ZERO
	was_seeing_player = false
	suspected_position = global_position
	has_suspected_position = false
	track_timer = 0.0
	search_direction = Vector3.ZERO
	if cover != null:
		cover.reset()

	search_origin = global_position
	search_timer = 0.0
	search_pause_timer = 0.0
	search_start_angle = rotation.y
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

	# 只在真正目击时记录运动方向；第一次看见不会把“出生点→玩家”误当成移动方向。
	if sees_player:
		var new_seen_position := player.global_position
		if has_seen_player:
			var seen_motion := new_seen_position - last_seen_position
			seen_motion.y = 0.0
			if seen_motion.length() > 0.05:
				last_seen_direction = seen_motion.normalized()
		previous_seen_position = last_seen_position
		last_seen_position = new_seen_position

	# 躲藏循环优先处理。躲在墙后时“看不见玩家”是主动行为，不在这里触发丢失目标判定；
	# 如果探头后仍未重新发现玩家，由 Cover 自己进入 TRACK/SEARCH。
	if cover != null and cover.is_active():
		if sees_player:
			is_alerted = true
			has_seen_player = true
			last_known_position = last_seen_position
			has_suspected_position = false
		var cover_direction: Vector3 = cover.step(delta, sees_player)
		if cover.phase == cover.Phase.RUN_TO_COVER and not cover_direction.is_zero_approx():
			_face_direction(cover_direction, delta)
		else:
			_face_direction(cover.look_position - global_position, delta)
		_move_character(cover_direction, delta, cover.movement_multiplier())
		was_seeing_player = sees_player
		_update_label()
		return

	was_seeing_player = sees_player

	# 只要真正看到玩家，就进入激活状态，并持续刷新最后目击位置。
	if sees_player:
		is_alerted = true
		has_seen_player = true
		last_known_position = player.global_position
		has_suspected_position = false
		track_timer = 0.0

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
	elif lost_player_this_frame and has_seen_player:
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
		_face_direction(suspected_position - global_position, delta)
	elif state == State.SEARCH and search_is_pausing and not search_direction.is_zero_approx():
		_face_direction(search_direction, delta)
	elif not direction.is_zero_approx():
		_face_direction(direction, delta)

	_move_character(direction, delta)
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

	var direction := Vector3.ZERO

	# “小外挂”只在丢失目标的这一刻读取一次隐藏玩家方向，并加入明显误差。
	if (
		allow_hint
		and has_seen_player
		and is_instance_valid(player)
		and randf() <= lost_target_hint_chance
	):
		direction = player.global_position - last_seen_position
		direction.y = 0.0
		if not direction.is_zero_approx():
			direction = direction.normalized()
			var error := deg_to_rad(randf_range(
				-lost_target_hint_error_degrees,
				lost_target_hint_error_degrees
			))
			direction = direction.rotated(Vector3.UP, error)

	# 没拿到“直觉”时仍可使用真实目击期间记录到的最后移动方向，这不算透视。
	if direction.is_zero_approx() and not last_seen_direction.is_zero_approx():
		direction = last_seen_direction

	if direction.is_zero_approx():
		has_suspected_position = false
		_begin_search(last_known_position)
		return

	direction = direction.normalized()
	search_direction = direction
	var raw_target := last_seen_position + direction * track_distance
	var nav_point := NavigationServer3D.region_get_closest_point(navigation_region.get_rid(), raw_target)

	# 如果推测方向指向完全不可达区域，就不要硬吸到很远的另一块 NavMesh。
	if _horizontal_distance_between(raw_target, nav_point) > 2.0:
		raw_target = last_seen_position + direction * (track_distance * 0.5)
		nav_point = NavigationServer3D.region_get_closest_point(navigation_region.get_rid(), raw_target)
		if _horizontal_distance_between(raw_target, nav_point) > 2.0:
			has_suspected_position = false
			_begin_search(last_known_position)
			return

	suspected_position = Vector3(nav_point.x, global_position.y, nav_point.z)
	has_suspected_position = true
	track_timer = track_seconds
	state = State.TRACK
	agent.target_position = suspected_position


func _process_track(delta: float) -> Vector3:
	track_timer = maxf(0.0, track_timer - delta)

	if track_timer <= 0.0 or agent.is_navigation_finished():
		var search_center := suspected_position if has_suspected_position else last_known_position
		_begin_search(search_center)
		return Vector3.ZERO

	var next_position := agent.get_next_path_position()
	var direction := next_position - global_position
	direction.y = 0.0
	if direction.is_zero_approx():
		return Vector3.ZERO
	return direction.normalized()


func _begin_search(center: Vector3 = Vector3.INF) -> void:
	state = State.SEARCH
	is_alerted = true
	search_origin = center if center.is_finite() else last_known_position

	if has_seen_player:
		search_timer = search_seconds
	else:
		search_timer = uncertain_search_seconds

	# 搜索不再大幅左右甩头；保持朝最可疑的方向警戒，只在该方向附近换搜索点。
	if search_direction.is_zero_approx():
		if has_suspected_position:
			search_direction = suspected_position - last_seen_position
		elif not last_seen_direction.is_zero_approx():
			search_direction = last_seen_direction
		else:
			search_direction = search_origin - global_position
		search_direction.y = 0.0
		if not search_direction.is_zero_approx():
			search_direction = search_direction.normalized()

	search_pause_timer = minf(search_pause_seconds, search_timer)
	search_is_pausing = true
	agent.target_position = global_position


func _process_search(delta: float) -> Vector3:
	search_timer = maxf(0.0, search_timer - delta)

	if search_timer <= 0.0:
		_end_search()
		return Vector3.ZERO

	# 到点后短暂停顿、保持架住可疑方向；不再做 ±60° 的机械摇头。
	if search_is_pausing:
		search_pause_timer = maxf(0.0, search_pause_timer - delta)
		if search_pause_timer <= 0.0:
			search_is_pausing = false
			if not _choose_search_point():
				search_is_pausing = true
				search_pause_timer = minf(0.4, search_timer)
		return Vector3.ZERO

	var next_position: Vector3 = agent.get_next_path_position()
	if not agent.is_navigation_finished():
		var direction := next_position - global_position
		direction.y = 0.0
		if not direction.is_zero_approx():
			return direction.normalized()
		return Vector3.ZERO

	search_is_pausing = true
	search_pause_timer = minf(search_pause_seconds, search_timer)
	return Vector3.ZERO


func _choose_search_point() -> bool:
	var has_direction := not search_direction.is_zero_approx()
	var base_angle := 0.0
	if has_direction:
		base_angle = atan2(search_direction.z, search_direction.x)

	for attempt in range(20):
		var angle: float
		if not has_direction or randf() < search_wide_sample_chance:
			angle = randf_range(0.0, TAU)
		else:
			angle = base_angle + deg_to_rad(randf_range(-search_cone_degrees, search_cone_degrees))

		var radius := randf_range(search_radius * 0.35, search_radius)
		var candidate := search_origin + Vector3(cos(angle), 0.0, sin(angle)) * radius
		var destination := NavigationServer3D.region_get_closest_point(
			navigation_region.get_rid(), candidate)

		if _horizontal_distance_between(candidate, destination) > 1.5:
			continue
		if _horizontal_distance(destination) < 1.0:
			continue
		if _horizontal_distance_between(search_origin, destination) > search_radius + 1.0:
			continue

		var path := NavigationServer3D.map_get_path(
			agent.get_navigation_map(), global_position, destination, true, agent.navigation_layers)
		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 0.5:
			continue

		destination.y -= agent.path_height_offset
		agent.target_position = destination
		return true

	return false


func _end_search() -> void:
	# 搜索完整结束后，才认为暂时失去玩家并恢复正常巡逻。
	is_alerted = false
	has_seen_player = false
	search_timer = 0.0
	search_pause_timer = 0.0
	search_is_pausing = false
	track_timer = 0.0
	has_suspected_position = false
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
		var alignment: float = (-global_basis.z).dot(offset.normalized())
		if alignment < cos(deg_to_rad(sight_angle_degrees * 0.5)):
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

	elif damage > 0.0 and attacker_position.is_finite():
		_investigate_attack(attacker_position)

	_update_label()


func _investigate_attack(attacker_position: Vector3) -> void:
	# 受击意味着敌人已经知道附近存在威胁，但不代表亲眼看到了玩家。
	# 如果之前已经见过玩家，则保留 has_seen_player = true，不会因为再次受击而失忆。
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
	agent.target_position = last_known_position


func _update_label() -> void:
	var names := ["巡逻停留", "看见玩家", "前往最后位置", "搜索", "已死亡", "随机巡逻", "寻找射击位置", "保持射击位置", "沿可疑方向追踪"]
	if state == State.REPOSITION and _horizontal_distance(last_known_position) < _ranged_distance_band().x:
		names[State.REPOSITION] = "寻找后退路线"
	var alert_text := "已激活" if is_alerted else "未激活"
	var memory_text := "见过玩家" if has_seen_player else "未确认玩家"

	var state_text: String = cover.state_label() if cover != null and cover.is_active() else names[state]
	var type_text := "近战" if combat_type == CombatType.MELEE else "远程"
	$Label.text = "%s敌人：%s\n生命 %d / %d\n%s / %s" % [
		type_text,
		state_text,
		ceili(health),
		ceili(max_health),
		alert_text,
		memory_text
	]
