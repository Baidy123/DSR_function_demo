extends RefCounted


enum Phase { NONE, RUN_TO_COVER, HIDE, PEEK_OUT, WATCH }

## 抵达 Peek 后最多观察多少秒；看见玩家会提前结束，否则转入追踪或搜索。
var watch_seconds: float:
	get: return _setting(&"watch_seconds", 2.0)
	set(value): _set_setting(&"watch_seconds", value)
## 转身跑向掩体时相对于敌人 Move Speed 的速度倍率。
var run_speed_multiplier: float:
	get: return _setting(&"run_speed_multiplier", 2.0)
	set(value): _set_setting(&"run_speed_multiplier", value)
## 从躲藏位置移向 Peek 点时相对于敌人 Move Speed 的速度倍率。
var peek_speed_multiplier: float:
	get: return _setting(&"peek_speed_multiplier", 0.5)
	set(value): _set_setting(&"peek_speed_multiplier", value)
## 跑向掩体时改为“面向威胁撤退”的概率。0=永远转身跑，1=每次都掩护撤退。
## 掩护撤退时的移动速度倍率；通常比直接冲向掩体慢。
var covering_retreat_speed_multiplier: float:
	get: return _setting(&"covering_retreat_speed_multiplier", 0.8)
	set(value): _set_setting(&"covering_retreat_speed_multiplier", value)
## RUN_TO_COVER 期间每次真正受到伤害时，放弃掩护撤退并改为全速冲刺的概率。
## 每次受伤都会重新判定；0=中弹也继续掩护撤退，1=一中弹就立刻冲刺。

## 跑向掩体时，连续这么多秒未朝下一个寻路拐点有效推进，就尝试临时绕行。
var cover_stuck_repath_seconds: float:
	get: return _setting(&"cover_stuck_repath_seconds", 0.8)
	set(value): _set_setting(&"cover_stuck_repath_seconds", value)
## 在上面的时间窗口内，至少要朝 NavigationAgent 当前的下一个路径点靠近这么远，才算确实有进展。
## 贴墙左右抖动、原地滑动不会再误判成正常前进。
var cover_stuck_min_progress_distance: float:
	get: return _setting(&"cover_stuck_min_progress_distance", 0.08)
	set(value): _set_setting(&"cover_stuck_min_progress_distance", value)
## 同一次跑向掩体最多尝试多少次临时绕行；全部失败后退出本次掩体行为，避免永久卡住。
var cover_max_detour_retries: int:
	get: return _setting(&"cover_max_detour_retries", 4)
	set(value): _set_setting(&"cover_max_detour_retries", value)
## 卡住时，临时绕行点离当前位置的大致距离。
var cover_detour_distance: float:
	get: return _setting(&"cover_detour_distance", 1.5)
	set(value): _set_setting(&"cover_detour_distance", value)
## 卡住时优先向当前“去掩体方向”的左右多少度寻找临时绕行点。
var cover_detour_angle_degrees: float:
	get: return _setting(&"cover_detour_angle_degrees", 65.0)
	set(value): _set_setting(&"cover_detour_angle_degrees", value)
## 距离临时绕行点小于这个值时，认为绕行完成并重新追原 Hide。
var cover_detour_arrival_distance: float:
	get: return _setting(&"cover_detour_arrival_distance", 0.45)
	set(value): _set_setting(&"cover_detour_arrival_distance", value)


# 命中通知先于同一枪的近身来弹通知；本帧退出躲藏后不再被后者重新送回掩体。

var phase: Phase = Phase.NONE
var hide_position: Vector3
var peek_position: Vector3
var look_position: Vector3
var threat_origin: Vector3
var timer: float = 0.0
var active_cover_body: StaticBody3D = null
## 本次 RUN_TO_COVER 是否采用面向威胁的掩护撤退。
var covering_retreat: bool = false
## 本次绕出的动作级速度；负数沿用普通探头训练，不写回共享资源。
var _peek_speed_override := -1.0

## RUN_TO_COVER 的“朝当前路径点靠近”监测与临时绕行状态。
var cover_progress_waypoint: Vector3 = Vector3.ZERO
var cover_progress_best_distance: float = INF
var cover_stuck_timer: float = 0.0
var cover_detour_active: bool = false
var cover_detour_position: Vector3 = Vector3.ZERO
var cover_detour_side: float = 1.0
var cover_detour_retries: int = 0



func reset() -> void:
	phase = Phase.NONE
	timer = 0.0
	hide_position = enemy.global_position
	peek_position = enemy.global_position
	look_position = enemy.global_position
	threat_origin = enemy.global_position
	active_cover_body = null
	covering_retreat = false
	_peek_speed_override = -1.0
	cover_progress_waypoint = enemy.global_position
	cover_progress_best_distance = INF
	cover_stuck_timer = 0.0
	cover_detour_active = false
	cover_detour_position = enemy.global_position
	cover_detour_side = 1.0
	cover_detour_retries = 0


func is_active() -> bool:
	return phase != Phase.NONE


# 收到的是已经被第一个碰撞物截断的实际弹道，不是无限延长的射线。


func step(delta: float, sees_player: bool) -> Vector3:
	if not context.can_use_action(permission_id):
		reset()
		return Vector3.ZERO
	if not context.unit.supports([&"locomotion"]):
		reset()
		return Vector3.ZERO
	if sees_player:
		look_position = context.last_known_position

	var timer_delta: float = delta
	# 转移时限按动作请求速度估算；换弹临时限速时同步放慢扣时，兼容途中开始/结束。
	# 只调整总行程时限，下面的卡住检测仍按真实时间运行。
	if phase == Phase.RUN_TO_COVER or phase == Phase.PEEK_OUT:
		var requested: float = movement_multiplier()
		if requested > 0.0:
			timer_delta *= enemy.get_effective_movement_multiplier(requested) / requested
	timer = maxf(0.0, timer - timer_delta)

	if phase == Phase.HIDE:
		return Vector3.ZERO

	if phase == Phase.WATCH:
		if sees_player or timer <= 0.0:
			_finish(sees_player)
		return Vector3.ZERO

	# 已经开始探头时如果真实发现玩家，也直接交战，不必把探头路径走完。
	if phase == Phase.PEEK_OUT and sees_player:
		if selection.debug_cover_selection:
			print("[AI][掩体] PEEK_OUT 中重新发现玩家 -> 直接交战")
		_finish(true)
		return Vector3.ZERO

	if phase == Phase.RUN_TO_COVER or phase == Phase.PEEK_OUT:
		var final_destination: Vector3 = hide_position if phase == Phase.RUN_TO_COVER else peek_position

		# RUN_TO_COVER 卡住时，NavigationAgent 会临时去一个绕行点。
		# 绕行点到达后再继续追最终 Hide。
		if phase == Phase.RUN_TO_COVER and cover_detour_active:
			var detour_reached: bool = (
				context._horizontal_distance(cover_detour_position) <= cover_detour_arrival_distance
			)
			if detour_reached:
				cover_detour_active = false
				enemy.agent.target_position = hide_position
				_reset_cover_progress_monitor()
				if selection.debug_cover_selection:
					print("[AI][掩体] 临时绕行完成 -> 继续跑向原 Hide")
				return Vector3.ZERO
			elif enemy.agent.is_navigation_finished():
				# Agent 提前结束但并没有真正走到临时点：这个绕行点也不可靠，换一个。
				cover_detour_active = false
				cover_stuck_timer = 0.0
				_reset_cover_progress_monitor()
				if _try_cover_detour():
					return Vector3.ZERO
				_finish(sees_player)
				return Vector3.ZERO

		var next_position: Vector3 = enemy.agent.get_next_path_position()
		var distance_to_destination: float = context._horizontal_distance(final_destination)

		# 靠近 Hide 不代表已经躲好：必须由当前实际位置验证掩护。
		# 未躲好时继续最后一小段，不能重选同一个点并不断刷新计时器。
		var near_destination: bool = distance_to_destination <= 0.7
		var reached_destination: bool
		if phase == Phase.PEEK_OUT:
			# 真正走到墙角外且射界通畅才进入观察，不能提前 0.7 米停在墙后。
			reached_destination = distance_to_destination <= 0.12 and _peek_has_los(enemy.global_position)
		else:
			reached_destination = near_destination and _selected_cover_blocks(enemy.global_position, threat_origin)
		if reached_destination:
			cover_detour_active = false
			_reset_cover_progress_monitor()
			covering_retreat = false
			phase = Phase.HIDE if phase == Phase.RUN_TO_COVER else Phase.WATCH
			timer = 0.0 if phase == Phase.HIDE else watch_seconds
			enemy.agent.target_position = enemy.global_position
			return Vector3.ZERO

		# Agent 会在到点前结束路径；仅在最后短段身体空间通畅时继续走向 Hide/Peek。
		# 仍经过下方超时与卡住检查，不穿过墙角。
		var finishing_move: bool = (
			not cover_detour_active and near_destination
			and _cover_short_segment_is_clear(final_destination)
		)
		if finishing_move:
			next_position = final_destination

		# Agent 认为导航结束，但实际上还没到 Hide。
		# 跑掩体时先主动绕行，而不是直接保持 RUN_TO_COVER 卡死。
		if enemy.agent.is_navigation_finished() and not finishing_move:
			if phase == Phase.RUN_TO_COVER:
				if _try_cover_detour():
					return Vector3.ZERO
				if selection.debug_cover_selection:
					print("[AI][掩体] 导航提前结束且无法绕行 -> 退出本次掩体转移")
			_finish(sees_player)
			return Vector3.ZERO

		if timer <= 0.0:
			if phase == Phase.RUN_TO_COVER and _try_cover_detour():
				timer = maxf(timer, 2.0)
				return Vector3.ZERO
			_finish(sees_player)
			return Vector3.ZERO

		# RUN_TO_COVER 不再只看“角色有没有动”。
		# 只有确实朝 NavigationAgent 当前给出的下一个路径点靠近，才算有进展。
		# 因此贴墙左右抖动、沿错误方向滑动，都不会不断重置卡住计时器。
		if phase == Phase.RUN_TO_COVER:
			if _cover_navigation_is_stuck(next_position, delta):
				_reset_cover_progress_monitor()

				if _try_cover_detour():
					return Vector3.ZERO

				if selection.debug_cover_selection:
					print(
						"[AI][掩体] RUN_TO_COVER 无法朝路径点推进，且找不到可用绕行点 retries=",
						cover_detour_retries,
						"/",
						cover_max_detour_retries
					)
				_finish(sees_player)
				return Vector3.ZERO

		var direction: Vector3 = next_position - enemy.global_position
		direction.y = 0.0
		if direction.is_zero_approx():
			# 让卡住计时继续累积，下一轮会自动尝试临时绕行。
			return Vector3.ZERO
		return direction.normalized()

	return Vector3.ZERO


func movement_multiplier() -> float:
	if phase == Phase.RUN_TO_COVER:
		if covering_retreat:
			return covering_retreat_speed_multiplier
		return run_speed_multiplier
	if phase == Phase.PEEK_OUT:
		return _peek_speed_override if _peek_speed_override >= 0.0 else peek_speed_multiplier
	return 1.0


func state_label() -> String:
	if phase == Phase.RUN_TO_COVER and cover_detour_active:
		return "绕行去掩体"
	if phase == Phase.RUN_TO_COVER and covering_retreat:
		return "掩护撤退"
	return ["", "跑向掩体", "掩体后躲藏", "慢慢探出", "观察最后目击位置"][phase]


## AI已比较好目的地；复用原转移和卡住处理，换弹结束由AI交接。
func start_reload_transfer(destination: Dictionary, known_position: Vector3, retreat: bool = false) -> void:
	reset()
	hide_position = destination.hide
	active_cover_body = destination.body
	look_position = known_position
	threat_origin = known_position + Vector3.UP * 0.8
	_start_move(Phase.RUN_TO_COVER, hide_position, retreat)
	_refresh_move_timer(hide_position)


func start_utility_peek(destination: Dictionary, known_position: Vector3, speed_multiplier: float = -1.0) -> void:
	reset()
	_peek_speed_override = speed_multiplier
	hide_position = destination.hide
	peek_position = destination.position
	active_cover_body = destination.body
	look_position = known_position
	threat_origin = known_position + Vector3.UP * 0.8
	_start_move(Phase.PEEK_OUT, peek_position)


func _start_move(next_phase: Phase, destination: Vector3, evaluated_retreat: Variant = null) -> void:
	var was_running_to_cover: bool = phase == Phase.RUN_TO_COVER
	phase = next_phase

	if phase == Phase.RUN_TO_COVER:
		if not was_running_to_cover:
			covering_retreat = bool(evaluated_retreat) if evaluated_retreat != null else false
			_reset_cover_progress_monitor()
			cover_detour_active = false
			cover_detour_position = enemy.global_position
			cover_detour_side = 1.0 if randf() < 0.5 else -1.0
			cover_detour_retries = 0
	else:
		covering_retreat = false
		cover_detour_active = false
		cover_stuck_timer = 0.0

	enemy.agent.target_position = destination
	_refresh_move_timer(destination)

# 只由真正扣血的存活分支调用；receive_hit 已更新攻击者的大体位置。


func on_damage_received() -> void:
	if not context.is_arena_active():
		return
	if phase == Phase.HIDE:
		reset()
		context.resume_engagement_after_cover_hit()
		if selection.debug_cover_selection:
			print("[AI][掩体] 躲藏中受伤 -> 退出躲藏，回到接敌流程")
		return
	on_damage_during_transfer()


func on_damage_during_transfer() -> void:
	if phase != Phase.RUN_TO_COVER:
		return

	# receive_hit() 会先把 NavigationAgent 目标改成攻击者位置，Cover 必须立即把导航夺回来。
	# 如果正在临时绕行，就继续走绕行点；否则继续追原 Hide。
	enemy.agent.target_position = cover_detour_position if cover_detour_active else hide_position
	context.invalidate_utility()


func _reset_cover_progress_monitor() -> void:
	cover_progress_waypoint = enemy.global_position
	cover_progress_best_distance = INF
	cover_stuck_timer = 0.0


## 判断 NPC 是否真的卡住。
## 监测的是“到当前 next path point 的距离有没有持续下降”，而不是角色有没有发生任意位移。


func _cover_navigation_is_stuck(next_position: Vector3, delta: float) -> bool:
	var waypoint: Vector3 = Vector3(
		next_position.x,
		enemy.global_position.y,
		next_position.z
	)

	# NavigationAgent 换了下一个路径点，说明路径有推进；重新观察新 waypoint。
	if context._horizontal_distance_between(cover_progress_waypoint, waypoint) > 0.25:
		cover_progress_waypoint = waypoint
		cover_progress_best_distance = context._horizontal_distance(waypoint)
		cover_stuck_timer = 0.0
		return false

	var distance_to_waypoint: float = context._horizontal_distance(waypoint)

	if is_inf(cover_progress_best_distance):
		cover_progress_best_distance = distance_to_waypoint
		cover_stuck_timer = 0.0
		return false

	# 只有真正比历史最好距离更靠近路径点，才算有效推进。
	if distance_to_waypoint <= cover_progress_best_distance - cover_stuck_min_progress_distance:
		cover_progress_best_distance = distance_to_waypoint
		cover_stuck_timer = 0.0
		return false

	cover_stuck_timer += delta
	return cover_stuck_timer >= cover_stuck_repath_seconds


## 对“当前角色位置 -> 临时绕行点”做短距离身体空间检查。
## 这里只用于脱离墙角，不会把整条长导航路径限制得过严。


func _cover_short_segment_is_clear(destination: Vector3) -> bool:
	var start: Vector3 = enemy.global_position
	var horizontal_destination: Vector3 = Vector3(
		destination.x,
		start.y,
		destination.z
	)
	var distance: float = context._horizontal_distance_between(start, horizontal_destination)
	if distance <= 0.01:
		return false

	var sample_spacing: float = 0.20
	var sample_count: int = maxi(1, int(ceil(distance / sample_spacing)))

	for sample_index in range(1, sample_count + 1):
		var t: float = float(sample_index) / float(sample_count)
		var sample: Vector3 = start.lerp(horizontal_destination, t)
		if not context.is_position_free(sample, true):
			return false

	return true


## RUN_TO_COVER 物理卡住时，先找一个当前位置附近的临时侧向 NavMesh 点。
## 到达临时点后再继续追原 hide_position，避免反复请求同一条贴墙角的坏路径。


func _try_cover_detour() -> bool:
	if phase != Phase.RUN_TO_COVER:
		return false
	if cover_detour_retries >= maxi(1, cover_max_detour_retries):
		return false

	var base_direction: Vector3 = hide_position - enemy.global_position
	base_direction.y = 0.0
	if base_direction.is_zero_approx():
		return false
	base_direction = base_direction.normalized()

	var preferred_side: float = cover_detour_side
	var base_angle: float = clampf(cover_detour_angle_degrees, 20.0, 120.0)

	var angle_offsets: Array[float] = [
		base_angle * preferred_side,
		-base_angle * preferred_side,
		90.0 * preferred_side,
		-90.0 * preferred_side,
		minf(140.0, base_angle + 35.0) * preferred_side,
		-minf(140.0, base_angle + 35.0) * preferred_side
	]

	var distances: Array[float] = [
		maxf(0.5, cover_detour_distance),
		maxf(0.75, cover_detour_distance * 1.5)
	]

	var best_position: Vector3 = Vector3.ZERO
	var best_score: float = INF

	for distance_value: float in distances:
		for angle_offset: float in angle_offsets:
			var detour_direction: Vector3 = base_direction.rotated(
				Vector3.UP,
				deg_to_rad(angle_offset)
			).normalized()

			var raw_target: Vector3 = enemy.global_position + detour_direction * distance_value
			var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
				context.navigation_region.get_rid(),
				raw_target
			)

			# 如果候选被吸附得太远，说明这个方向并没有真实可走空间。
			if context._horizontal_distance_between(raw_target, nav_point) > 0.75:
				continue

			var candidate: Vector3 = Vector3(
				nav_point.x,
				enemy.global_position.y,
				nav_point.z
			)

			if context._horizontal_distance(candidate) < 0.45:
				continue
			if not context.is_position_free(candidate):
				continue

			# 临时绕行就是为了从当前墙角直接挪出去。
			# 除了 NavMesh 可达，还要求这段短距离用 NPC 自己的碰撞体实际走得通。
			if not _cover_short_segment_is_clear(candidate):
				continue

			var path: PackedVector3Array = selection._path_to(enemy.global_position, candidate)
			if path.is_empty():
				continue

			# 优先容易到达、同时不会把自己带得离最终 Hide 太远的临时点。
			var score: float = selection._path_length_from_path(path)
			score += context._horizontal_distance_between(candidate, hide_position) * 0.2

			if score < best_score:
				best_score = score
				best_position = candidate

	if is_inf(best_score):
		cover_detour_retries += 1
		cover_detour_side *= -1.0
		if selection.debug_cover_selection:
			print(
				"[AI][掩体] 找不到临时绕行点 retry=",
				cover_detour_retries,
				"/",
				cover_max_detour_retries
			)
		return false

	cover_detour_retries += 1
	cover_detour_side *= -1.0
	cover_detour_active = true
	cover_detour_position = best_position
	_reset_cover_progress_monitor()
	cover_stuck_timer = 0.0

	enemy.agent.target_position = cover_detour_position
	timer = maxf(timer, 2.0)

	if selection.debug_cover_selection:
		print(
			"[AI][掩体] RUN_TO_COVER 卡住 -> 临时绕行 ",
			cover_detour_position,
			" retry=",
			cover_detour_retries,
			"/",
			cover_max_detour_retries
		)

	return true


func _refresh_move_timer(destination: Vector3) -> void:
	var length: float = selection._path_length(enemy.global_position, destination)
	timer = length / maxf(0.1, enemy.move_speed * movement_multiplier()) + 2.0
	if is_inf(timer):
		timer = 0.0


func _finish(sees_player: bool) -> void:
	var remembered: Vector3 = look_position
	# 移动阶段退出意味着没有抵达；绕行耗尽后不能下一轮又选择同一个点。
	if phase == Phase.RUN_TO_COVER or (phase == Phase.PEEK_OUT and not sees_player):
		context.block_utility_destination(hide_position if phase == Phase.RUN_TO_COVER else peek_position)
	reset()
	context.resume_after_action(sees_player, remembered)


func _peek_has_los(point: Vector3) -> bool:
	return selection._peek_has_los(point, look_position)


func _selected_cover_blocks(point: Vector3, origin: Vector3) -> bool:
	return selection._selected_cover_blocks(point, origin, active_cover_body)


var context
var permission_id: StringName
var parameters: Dictionary = {}
var enemy:
	get: return context.actor
var selection:
	get: return context.cover_selection

func setup(shared_context, owner_id: StringName, defaults: Dictionary = {}) -> void:
	context = shared_context
	permission_id = owner_id
	parameters = defaults
	reset()

func _setting(key: StringName, fallback: Variant) -> Variant:
	return context.training.setting(&"cover", key, fallback, parameters)

func _set_setting(key: StringName, value: Variant) -> void:
	context.training.set_setting(&"cover", key, value)
