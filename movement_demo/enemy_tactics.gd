extends "res://enemy_action.gd"

# 战术：交战选位、射击节奏与可用动作。具体武器执行由 Enemy 负责。
## 是否掌握面向威胁的撤退射击；关闭时概率再高也不会使用。
## 后续由训练配置决定；当前默认开启，保留现有敌人的表现。
var can_covering_retreat: bool:
	get: return _setting(&"can_covering_retreat", true)
	set(value): _set_setting(&"can_covering_retreat", value)
## 是否掌握主动选择墙角攻击位置；优先保证散布射界，不强制身体被遮挡。
## 默认开启供试玩，后续可由训练配置赋值；不影响普通换位或躲藏能力。
var can_use_attack_positions: bool:
	get: return _setting(&"can_use_attack_positions", true)
	set(value): _set_setting(&"can_use_attack_positions", value)
## 是否掌握失视后朝最后目击区域压制的能力；具体持续时间和范围在SuppressionAction。
var can_suppress_fire: bool:
	get: return _setting(&"can_suppress_fire", true)
	set(value): _set_setting(&"can_suppress_fire", value)
## 高训练专属动作的临时能力接口，默认关闭；还需最后目击邻近掩体且两端可射击。
## 分类挂载架构尚未实现，当前手动勾选以测试；开启不自动代表某个训练等级。
var can_suppress_exits: bool:
	get: return _setting(&"can_suppress_exits", false)
	set(value): _set_setting(&"can_suppress_exits", value)
## 首次／重新真实目击玩家，或真正受伤且有攻击者位置时，尝试攻击占位的概率。
## 持续可见不重抽；攻击占位或掩体动作中不重选。0=不触发，1=每次满足条件都尝试。
## 两种触发共用此概率；0.5是可调试玩初值。
var attack_position_chance: float:
	get: return _setting(&"attack_position_chance", 0.5)
	set(value): _set_setting(&"attack_position_chance", value)
## 接敌侧移/后退和掩护撤退时允许开火；关闭后只在停稳时射击，转身冲刺仍停火。
var fire_while_moving: bool:
	get: return _setting(&"fire_while_moving", true)
	set(value): _set_setting(&"fire_while_moving", value)
## 首次发现或重新取得有效视线后，至少观察多久才允许射击（秒）；0可关闭。
var fire_reaction_seconds: float:
	get: return _setting(&"fire_reaction_seconds", 0.3)
	set(value): _set_setting(&"fire_reaction_seconds", value)
## 普通交火（含接敌跑打）希望达到的中心概率；0.7表示70%，不是最终命中率。
## 用作FireDecision评分的精度偏好，低于目标也可选择射击；掩护撤退不等待稳枪。
var fire_stability_target: float:
	get: return _setting(&"fire_stability_target", 0.7)
	set(value): _set_setting(&"fire_stability_target", value)
## 每轮实际打出几枪后暂停；只统计执行成功的射击，不按命中次数计数。
var burst_shot_count: int:
	get: return _setting(&"burst_shot_count", 3)
	set(value): _set_setting(&"burst_shot_count", value)
## 每轮最后一枪后的停火时间（秒）；与枪械冷却并行，必须都结束才能再开火。
var burst_pause_seconds: float:
	get: return _setting(&"burst_pause_seconds", 1.0)
	set(value): _set_setting(&"burst_pause_seconds", value)
## 远程敌人希望保持的距离区间，单位为米。
var ranged_min_distance: float:
	get: return _setting(&"ranged_min_distance", 4.0)
	set(value): _set_setting(&"ranged_min_distance", value)
## 远程期望距离上限（米）；与下限共同决定射击候选点的采样范围。
var ranged_max_distance: float:
	get: return _setting(&"ranged_max_distance", 6.0)
	set(value): _set_setting(&"ranged_max_distance", value)
## 选位有冷却，且有效目标会继续沿用，避免频繁左右换路。
var ranged_repath_seconds: float:
	get: return _setting(&"ranged_repath_seconds", 0.75)
	set(value): _set_setting(&"ranged_repath_seconds", value)
## 远程选位时更偏好侧向换位，而不是只沿玩家径向前后移动。
var ranged_flank_weight: float:
	get: return _setting(&"ranged_flank_weight", 3.0)
	set(value): _set_setting(&"ranged_flank_weight", value)
## 候选射击位附近若有侧墙/后墙，可获得额外战术价值。
var ranged_wall_support_weight: float:
	get: return _setting(&"ranged_wall_support_weight", 2.5)
	set(value): _set_setting(&"ranged_wall_support_weight", value)
## 探测候选射击位附近墙体的距离。
var ranged_wall_probe_distance: float:
	get: return _setting(&"ranged_wall_probe_distance", 1.5)
	set(value): _set_setting(&"ranged_wall_probe_distance", value)
## 近战接近时的停止距离（米）；远程保持距离由 Ranged Min/Max Distance 控制。
var stopping_distance: float:
	get: return _setting(&"stopping_distance", 1.3)
	set(value): _set_setting(&"stopping_distance", value)
var fire_reaction_elapsed: float = 0.0
var fire_burst_shots: int = 0
var fire_pause_remaining: float = 0.0
var ranged_repath_timer: float = 0.0
var ranged_has_destination: bool = false

const Actor = preload("res://enemy_actor.gd")


# 只允许一个压制动作运行；AI和射击流程共用当前动作接口。


# 引用从AI取得，动作之间不形成RefCounted强引用环。
var cover:
	get: return ai.cover
var fire_decision:
	get: return ai.fire_decision
var attack_position:
	get: return ai.actions[&"attack_position"]
var area_suppression:
	get: return ai.actions[&"suppression"]
var exit_suppression:
	get: return ai.actions[&"exit_suppression"]
var suppression:
	get: return ai.current_suppression
	set(value): ai.current_suppression = value


# 保留旧调用入口；决定和启动统一在AI。
func try_attack_position(from_hit: bool = false) -> void:
	ai.try_attack_position(from_hit)


func start_suppression() -> void:
	ai.start_suppression()


func update_shooting(delta: float, sees_player: bool, movement_requested: bool) -> void:
	if not is_enabled() and not suppression.is_active() and not (cover.is_active() and cover.covering_retreat):
		actor.update_weapon(delta)
		return
	# 停顿按经过的时间计算；短暂失去视野或进入掩体不清掉已打枪数/剩余停顿。
	var elapsed: float = maxf(0.0, delta)
	fire_pause_remaining = maxf(0.0, fire_pause_remaining - elapsed)
	if suppression.is_active():
		_update_suppression_shooting(delta, movement_requested)
		return
	var visible_target: bool = (
		actor.can_use_firearms() and ai.is_arena_active() and sees_player
		and not ai.player.is_dead() and not ai.player.is_in_dialogue
	)
	# 身体刚移动过，射击前再核实实际视线，避免用移动前的可见结果隔墙射击。
	visible_target = visible_target and ai.perception.can_see_player()
	if not visible_target:
		fire_reaction_elapsed = 0.0
		fire_decision.reset()
		actor.update_weapon(delta)
		return
	var point: Vector3 = ai.player.global_position + Vector3.UP * 0.8
	if actor.get_shot_origin().distance_to(point) > actor.weapon.fire_range:
		fire_reaction_elapsed = 0.0
		fire_decision.reset()
		actor.update_weapon(delta)
		return
	# 反应与停顿期间仍然跟枪；两者只阻止开火，不阻止移动、转身或瞄准。
	var previous_stability: float = _current_firing_stability()
	actor.update_weapon(delta, point)
	var reaction_seconds: float = maxf(0.0, fire_reaction_seconds)
	fire_reaction_elapsed = minf(reaction_seconds, fire_reaction_elapsed + elapsed)
	if fire_reaction_elapsed < reaction_seconds or fire_pause_remaining > 0.0:
		fire_decision.reset()
		return
	# 掩护撤退面向威胁，允许边退边打；转身冲刺、躲藏和有效探头仍停火。
	if cover != null and cover.is_active():
		if not can_covering_retreat or cover.phase != cover.Phase.RUN_TO_COVER or not cover.covering_retreat:
			fire_decision.reset()
			return
	# Cover接管期间主状态可能仍是TRACK/SEARCH，按当前掩体动作授权即可。
	elif ai.state != ai.State.REPOSITION and ai.state != ai.State.HOLD_POSITION:
		fire_decision.reset()
		return
	var moving: bool = movement_requested or Vector2(actor.velocity.x, actor.velocity.z).length() > 0.05
	if moving and not fire_while_moving:
		fire_decision.reset()
		return
	if not actor.can_fire():
		fire_decision.reset()
		return
	# 墙角站位按目标方向选出后，实际枪口仍可能在跟转；等它转出墙面再开火。
	if attack_position.phase == attack_position.Phase.HOLD and not ai.cover_selection.has_clear_shot_cone(actor.get_shot_origin(), actor.aim_direction, actor.get_max_shot_deviation_degrees(), actor.get_shot_origin().distance_to(point), attack_position.active_cover):
		fire_decision.reset()
		return
	if cover != null and cover.is_active():
		fire_decision.reset()
	else:
		var stability: float = _current_firing_stability()
		var recovery_rate: float = maxf(0.0, stability - previous_stability) / maxf(elapsed, 0.0001)
		var distance: float = actor.get_shot_origin().distance_to(point)
		var close_pressure: float = clampf(1.0 - distance / maxf(ranged_min_distance, 0.01), 0.0, 1.0)
		if fire_decision.choose_action(elapsed, stability, fire_stability_target, recovery_rate, close_pressure) != fire_decision.Action.FIRE:
			return
	if actor.try_fire():
		fire_decision.on_shot_fired()
		_record_burst_shot()


func _update_suppression_shooting(delta: float, movement_requested: bool) -> void:
	fire_decision.reset()
	# 压制不保留旧目击的反应进度；重新看到目标仍需遵守原反应时间。
	fire_reaction_elapsed = 0.0
	# 仅此动作允许未目击时按记忆开火；不读取墙后玩家的当前坐标。
	if not actor.can_use_firearms() or not ai.is_arena_active() or ai.player.is_dead() or ai.player.is_in_dialogue or cover.is_active():
		actor.update_weapon(delta)
		return
	var point: Vector3 = suppression.aim_point
	actor.update_weapon(delta, point)
	var moving: bool = movement_requested or Vector2(actor.velocity.x, actor.velocity.z).length() > 0.05
	if actor.get_shot_origin().distance_to(point) > actor.weapon.fire_range or fire_pause_remaining > 0.0 or (moving and not fire_while_moving):
		return
	if actor.try_fire():
		_record_burst_shot()
		suppression.on_shot_fired()


func _record_burst_shot() -> void:
	fire_burst_shots += 1
	if fire_burst_shots >= maxi(1, burst_shot_count):
		fire_burst_shots = 0
		fire_pause_remaining = maxf(0.0, burst_pause_seconds)


func _current_firing_stability() -> float:
	return actor.get_center_probability()


func reset_fire_timing() -> void:
	fire_decision.reset()
	fire_reaction_elapsed = 0.0
	fire_burst_shots = 0
	fire_pause_remaining = 0.0


func process_ranged_position(delta: float, sees_player: bool) -> Vector3:
	var band = _ranged_distance_band()
	var distance = ai._horizontal_distance(ai.last_known_position)
	var in_band = sees_player and distance >= band.x and distance <= band.y

	# HOLD 只表示“已经到达一个认可的射击位”。玩家明显改变距离或 LOS 后才重新选位。
	if ai.state == ai.State.HOLD_POSITION:
		if in_band and _has_clear_ray_to_known_position(actor.global_position):
			return Vector3.ZERO
		ai.state = ai.State.REPOSITION
		ranged_has_destination = false
		ranged_repath_timer = 0.0

	ranged_repath_timer = maxf(0.0, ranged_repath_timer - delta)
	if ranged_repath_timer <= 0.0:
		ranged_repath_timer = maxf(0.1, ranged_repath_seconds)
		var destination = agent.target_position
		var target_distance = ai._horizontal_distance_between(destination, ai.last_known_position)
		var valid_destination = (
			ranged_has_destination
			and target_distance >= band.x and target_distance <= band.y
			and ai.is_position_free(destination)
			and _has_clear_ray_to_known_position(destination)
		)

		# 玩家太近时，退路不能从玩家身边擦过去。
		if valid_destination and distance < band.x:
			var path = NavigationServer3D.map_get_path(
				agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers)
			valid_destination = not path.is_empty() and _retreat_path_is_safe(path, distance)

		if not valid_destination:
			ranged_has_destination = _choose_ranged_position(band, distance)
			if not ranged_has_destination:
				if not sees_player:
					ai.search.begin_tracking_or_search(true)
					return Vector3.ZERO
				if distance > band.y:
					# 没采到合适战术点时，至少先接近到有效射程。
					agent.target_position = ai.last_known_position
					ranged_has_destination = true
				elif in_band:
					# 当前已经能打，但没有更好的点，留在原地而不是无意义乱跑。
					ai.state = ai.State.HOLD_POSITION
					agent.target_position = actor.global_position
					return Vector3.ZERO
				else:
					agent.target_position = actor.global_position
					return Vector3.ZERO

	if not ranged_has_destination:
		return Vector3.ZERO

	var next_position = agent.get_next_path_position()
	if agent.is_navigation_finished():
		ranged_has_destination = false
		if sees_player:
			ai.state = ai.State.HOLD_POSITION
			agent.target_position = actor.global_position
		else:
			ai.search.begin_tracking_or_search(true)
		return Vector3.ZERO

	var direction = next_position - actor.global_position
	direction.y = 0.0
	return direction.normalized()


func _ranged_distance_band() -> Vector2:
	var minimum = maxf(1.0, ranged_min_distance)
	return Vector2(minimum, maxf(minimum + 1.0, ranged_max_distance))


func _choose_ranged_position(band: Vector2, current_distance: float) -> bool:
	var preferred_distance = (band.x + band.y) * 0.5
	var best_score = INF
	var best_position = Vector3.ZERO

	var current_radial = actor.global_position - ai.last_known_position
	current_radial.y = 0.0
	if current_radial.is_zero_approx():
		current_radial = Vector3.BACK
	else:
		current_radial = current_radial.normalized()

	var start_angle = atan2(current_radial.z, current_radial.x)

	# 在两个距离环上采样。候选点必须能射到“最后已知位置”，但评分不再只看距离。
	for radius in [preferred_distance, band.y - 0.25]:
		for index in range(16):
			var angle = start_angle + TAU * float(index) / 16.0
			var candidate: Vector3 = ai.last_known_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
			var nav_point = NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), candidate)
			if ai._horizontal_distance_between(candidate, nav_point) > 0.75:
				continue

			var destination = Vector3(nav_point.x, actor.global_position.y, nav_point.z)
			var distance = ai._horizontal_distance_between(destination, ai.last_known_position)
			if distance < band.x or distance > band.y:
				continue
			if not ai.is_position_free(destination) or not _has_clear_ray_to_known_position(destination):
				continue

			var path = NavigationServer3D.map_get_path(
				agent.get_navigation_map(), actor.global_position, nav_point, true, agent.navigation_layers)
			if path.is_empty() or path[path.size() - 1].distance_to(nav_point) > 0.5:
				continue
			if current_distance < band.x and not _retreat_path_is_safe(path, current_distance):
				continue

			var path_length = 0.0
			for step in range(1, path.size()):
				path_length += path[step - 1].distance_to(path[step])

			var candidate_radial = destination - ai.last_known_position
			candidate_radial.y = 0.0
			if candidate_radial.is_zero_approx():
				continue
			candidate_radial = candidate_radial.normalized()

			# 与当前径向越不同，越像主动侧移/换角度，而不是只前后保持距离。
			var flank_amount = 1.0 - absf(current_radial.dot(candidate_radial))
			# 有 LOS 的前提下，附近存在侧墙/后墙意味着更容易重新断线或撤回。
			var wall_support = _ranged_wall_support(destination)

			var score = path_length + absf(distance - preferred_distance) * 2.0
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
	var threat_direction = ai.last_known_position - point
	threat_direction.y = 0.0
	if threat_direction.is_zero_approx():
		return 0.0
	threat_direction = threat_direction.normalized()

	var side = threat_direction.cross(Vector3.UP).normalized()
	var away = -threat_direction
	var directions: Array[Vector3] = [side, -side, away]
	var hits = 0.0

	for probe_direction in directions:
		var from: Vector3 = point + Vector3.UP * 0.8
		var to: Vector3 = from + probe_direction * ranged_wall_probe_distance
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [actor.get_rid()])
		if is_instance_valid(ai.player) and ai.player is CollisionObject3D:
			query.exclude = [actor.get_rid(), ai.player.get_rid()]
		var hit: Dictionary = actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider is StaticBody3D:
			hits += 1.0

	return hits / 3.0


func _retreat_path_is_safe(path: PackedVector3Array, current_distance: float) -> bool:
	var threat = Vector2(ai.last_known_position.x, ai.last_known_position.z)
	var previous = Vector2(actor.global_position.x, actor.global_position.z)
	for point in path:
		var next = Vector2(point.x, point.z)
		var closest = Geometry2D.get_closest_point_to_segment(threat, previous, next)
		if closest.distance_to(threat) < maxf(0.1, current_distance - 0.2):
			return false
		previous = next
	return true


func _has_clear_ray_to_known_position(from: Vector3) -> bool:
	var query = PhysicsRayQueryParameters3D.create(
		from + Vector3.UP * 0.8, ai.last_known_position + Vector3.UP * 0.8, 1, [actor.get_rid()])
	# 检查的是已知位置与墙的关系；隐藏玩家的实体不能改变候选点评分。
	if is_instance_valid(ai.player) and ai.player is CollisionObject3D:
		query.exclude = [actor.get_rid(), ai.player.get_rid()]
	query.hit_from_inside = true
	return actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func reset() -> void:
	reset_fire_timing()
	ranged_repath_timer = 0.0
	ranged_has_destination = false


func step(delta: float, sees_player: bool) -> Vector3:
	if suppression.is_active():
		return suppression.step(delta, sees_player)
	if attack_position.is_active():
		return attack_position.step(delta, sees_player)
	if not is_enabled():
		return Vector3.ZERO
	if ai.state != ai.State.APPROACH:
		return process_ranged_position(delta, sees_player)
	var next_position: Vector3 = agent.get_next_path_position()
	var close_to_player: bool = sees_player and ai._horizontal_distance(ai.last_known_position) <= stopping_distance
	if close_to_player:
		actor.face_direction(ai.last_known_position - actor.global_position, delta)
		return Vector3.ZERO
	if agent.is_navigation_finished():
		return Vector3.ZERO
	var direction: Vector3 = next_position - actor.global_position
	direction.y = 0.0
	return direction.normalized()
