extends "res://enemy_action.gd"

signal finished(sees_player: bool, known_position: Vector3)

enum Phase { NONE, RUN_TO_COVER, HIDE, PEEK_OUT, WATCH }

## 敌人胸部到实际弹道线段的警戒半径（米）；墙挡住来弹时不会隔墙触发。
var shot_radius: float:
	get: return _setting(&"shot_radius", 1.5)
	set(value): _set_setting(&"shot_radius", value)
## 每次新的有效近身来弹触发“寻找掩体”的概率。0=从不找掩体，1=每次都找。
## 已经处于跑向掩体/躲藏/探头流程时不会重新掷骰子，避免连续来弹让行为反复取消。
var take_cover_chance: float:
	get: return _setting(&"take_cover_chance", 1.0)
	set(value): _set_setting(&"take_cover_chance", value)
## 到达有效躲藏位置后等待探头的秒数；新来弹可重新计时，真正看见玩家则立即结束躲藏。
var hide_seconds: float:
	get: return _setting(&"hide_seconds", 3.0)
	set(value): _set_setting(&"hide_seconds", value)
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
var covering_retreat_chance: float:
	get: return _setting(&"covering_retreat_chance", 0.4)
	set(value): _set_setting(&"covering_retreat_chance", value)
## 掩护撤退时的移动速度倍率；通常比直接冲向掩体慢。
var covering_retreat_speed_multiplier: float:
	get: return _setting(&"covering_retreat_speed_multiplier", 0.8)
	set(value): _set_setting(&"covering_retreat_speed_multiplier", value)
## RUN_TO_COVER 期间每次真正受到伤害时，放弃掩护撤退并改为全速冲刺的概率。
## 每次受伤都会重新判定；0=中弹也继续掩护撤退，1=一中弹就立刻冲刺。
var damage_force_sprint_chance: float:
	get: return _setting(&"damage_force_sprint_chance", 0.5)
	set(value): _set_setting(&"damage_force_sprint_chance", value)

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
var _hide_damage_frame: int = -1

var phase: Phase = Phase.NONE
var hide_position: Vector3
var peek_position: Vector3
var look_position: Vector3
var threat_origin: Vector3
var timer: float = 0.0
var active_cover_body: StaticBody3D = null
## 本次 RUN_TO_COVER 是否采用面向威胁的掩护撤退。
var covering_retreat: bool = false
var utility_driven := false

## RUN_TO_COVER 的“朝当前路径点靠近”监测与临时绕行状态。
var cover_progress_waypoint: Vector3 = Vector3.ZERO
var cover_progress_best_distance: float = INF
var cover_stuck_timer: float = 0.0
var cover_detour_active: bool = false
var cover_detour_position: Vector3 = Vector3.ZERO
var cover_detour_side: float = 1.0
var cover_detour_retries: int = 0



func reset() -> void:
	utility_driven = false
	_hide_damage_frame = -1
	phase = Phase.NONE
	timer = 0.0
	hide_position = enemy.global_position
	peek_position = enemy.global_position
	look_position = enemy.global_position
	threat_origin = enemy.global_position
	active_cover_body = null
	covering_retreat = false
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


func notice_shot(origin: Vector3, endpoint: Vector3) -> void:
	if _hide_damage_frame == Engine.get_physics_frames():
		return
	# 场外射击不能在玩家进入竞技场前启动掩体动作。
	if not ai.is_arena_active() or enemy.is_dead or ai.combat_type != ai.CombatType.RANGED:
		return
	var chest: Vector3 = enemy.global_position + Vector3.UP * 0.8
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
	if chest.distance_to(closest) > shot_radius:
		return
	# 警戒球可能伸到墙另一侧；墙挡住近处弹道时不能隔墙触发。
	if not selection.has_clear_line(chest, closest):
		return
	ai._investigate_attack(origin - Vector3.UP * 0.8)
	ai.nearby_shot_pressure = minf(1.0, ai.nearby_shot_pressure + 0.15)
	# 来弹只更新威胁和压力，由统一Utility决定是否转移，不抽概率直接抢占。
	ai.invalidate_utility()


# 压制中真正受伤时必定尝试找掩体，但仍须有合法可达的躲藏位置。
func take_cover_after_suppression_hit() -> void:
	if not ai.is_arena_active() or enemy.is_dead or ai.combat_type != ai.CombatType.RANGED:
		return
	_try_take_cover(ai.last_known_position + Vector3.UP * 0.8, true)
	# 同一枪的来弹通知不能在选择失败后重新抽选／更改本次反应。
	_hide_damage_frame = Engine.get_physics_frames()


func _try_take_cover(origin: Vector3, force_attempt: bool = false) -> void:
	if not is_enabled():
		return
	look_position = ai.last_known_position
	threat_origin = origin

	# 只有“新开始一次掩体反应”时才掷骰子。
	# 没触发掩体行为时，_investigate_attack() 已经让敌人进入“知道玩家”状态，
	# 所以它仍会按主 AI 的 REPOSITION / TRACK 等逻辑反应，而不是完全无视枪击。
	if not force_attempt and not is_active() and randf() > take_cover_chance:
		if selection.debug_cover_selection:
			print("[AI][掩体] 本次未触发寻找掩体，chance=", take_cover_chance)
		return

	# 已经选中的 Hide 只要仍然能真正挡住威胁、质量合格，就可以继续复用。
	# Peek 当前看不到玩家不再让整个掩体失效；之后探头失败会自然进入 TRACK / SEARCH。
	var can_reuse: bool = (
		is_active()
		and _selected_cover_blocks(hide_position, origin)
		and (
			not selection.require_assigned_cover
			or selection._cover_quality(hide_position, origin, active_cover_body) >= selection.minimum_cover_quality
		)
	)
	if not can_reuse and not _choose_cover():
		reset()
		return
	# 成功进入躲藏流程才抢占主动攻击占位；概率失败或无有效掩体不打断。
	ai.on_tactical_action_started(&"cover")
	if phase == Phase.RUN_TO_COVER and can_reuse:
		# 连续来弹保持原绕行目标和计时，不能每枪重启转移。
		enemy.agent.target_position = cover_detour_position if cover_detour_active else hide_position
		return
	if phase == Phase.HIDE and can_reuse:
		timer = hide_seconds
		enemy.agent.target_position = enemy.global_position
	else:
		_start_move(Phase.RUN_TO_COVER, hide_position)


func step(delta: float, sees_player: bool) -> Vector3:
	if not is_enabled():
		reset()
		return Vector3.ZERO
	if ai.combat_type != ai.CombatType.RANGED:
		reset()
		return Vector3.ZERO
	if sees_player:
		look_position = ai.last_known_position

	var timer_delta: float = delta
	# 转移时限按动作请求速度估算；换弹临时限速时同步放慢扣时，兼容途中开始/结束。
	# 只调整总行程时限，下面的卡住检测仍按真实时间运行。
	if phase == Phase.RUN_TO_COVER or phase == Phase.PEEK_OUT:
		var requested: float = movement_multiplier()
		if requested > 0.0:
			timer_delta *= enemy.get_effective_movement_multiplier(requested) / requested
	timer = maxf(0.0, timer - timer_delta)

	if phase == Phase.HIDE:
		# 躲在掩体后时，只要重新真实看到玩家，就立刻结束 Cover 流程回到主 AI 交战。
		# 不再等 hide_seconds，也不再进入 PEEK_OUT。
		if sees_player:
			if selection.debug_cover_selection:
				print("[AI][掩体] HIDE 中重新发现玩家 -> 直接交战，跳过 PEEK")
			_finish(true)
			return Vector3.ZERO

		if timer <= 0.0:
			_start_move(Phase.PEEK_OUT, peek_position)
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
				ai._horizontal_distance(cover_detour_position) <= cover_detour_arrival_distance
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
		var distance_to_destination: float = ai._horizontal_distance(final_destination)

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
			timer = hide_seconds if phase == Phase.HIDE else watch_seconds
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
		return peek_speed_multiplier
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
	utility_driven = true
	_refresh_move_timer(hide_position)


func start_utility_peek(destination: Dictionary, known_position: Vector3) -> void:
	reset()
	hide_position = destination.hide
	peek_position = destination.position
	active_cover_body = destination.body
	look_position = known_position
	threat_origin = known_position + Vector3.UP * 0.8
	_start_move(Phase.PEEK_OUT, peek_position)
	utility_driven = true


func _start_move(next_phase: Phase, destination: Vector3, evaluated_retreat: Variant = null) -> void:
	# 初次开始一次 RUN_TO_COVER 时，用 covering_retreat_chance 决定是转身冲刺还是掩护撤退。
	# 后续真正受伤时由 on_damage_during_transfer() 另外逐次判定是否改为冲刺。
	var was_running_to_cover: bool = phase == Phase.RUN_TO_COVER
	phase = next_phase

	if phase == Phase.RUN_TO_COVER:
		if not was_running_to_cover:
			covering_retreat = bool(evaluated_retreat) if evaluated_retreat != null else (ai.can_use_action(&"covering_retreat") and randf() < covering_retreat_chance)
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
	if not ai.is_arena_active():
		return
	if phase == Phase.HIDE:
		reset()
		_hide_damage_frame = Engine.get_physics_frames()
		ai.resume_engagement_after_cover_hit()
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
	if utility_driven:
		# 实际伤害已增加AI压力，由共同评分决定是否改为冲刺。
		ai.invalidate_utility()
		return

	# 每次真正受到伤害都重新判定。只要当前还在掩护撤退，成功就放弃慢速后撤并全速冲刺。
	var force_sprint: bool = randf() < damage_force_sprint_chance
	if covering_retreat and force_sprint:
		covering_retreat = false
		if selection.debug_cover_selection:
			print("[AI][掩体] 掩护转移中受伤 -> 改为全速冲刺，chance=", damage_force_sprint_chance)
	elif selection.debug_cover_selection and covering_retreat:
		print("[AI][掩体] 掩护转移中受伤 -> 继续掩护撤退，chance=", damage_force_sprint_chance)

	# 受伤导致导航目标被改写后重新计算剩余路程和超时；如果已经切冲刺，也按新速度刷新。
	var remaining_time: float = timer
	_refresh_move_timer(hide_position)
	timer = minf(timer, remaining_time)


## 重置 RUN_TO_COVER 的路径推进监测。


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
	if ai._horizontal_distance_between(cover_progress_waypoint, waypoint) > 0.25:
		cover_progress_waypoint = waypoint
		cover_progress_best_distance = ai._horizontal_distance(waypoint)
		cover_stuck_timer = 0.0
		return false

	var distance_to_waypoint: float = ai._horizontal_distance(waypoint)

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
	var distance: float = ai._horizontal_distance_between(start, horizontal_destination)
	if distance <= 0.01:
		return false

	var sample_spacing: float = 0.20
	var sample_count: int = maxi(1, int(ceil(distance / sample_spacing)))

	for sample_index in range(1, sample_count + 1):
		var t: float = float(sample_index) / float(sample_count)
		var sample: Vector3 = start.lerp(horizontal_destination, t)
		if not ai.is_position_free(sample):
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
				ai.navigation_region.get_rid(),
				raw_target
			)

			# 如果候选被吸附得太远，说明这个方向并没有真实可走空间。
			if ai._horizontal_distance_between(raw_target, nav_point) > 0.75:
				continue

			var candidate: Vector3 = Vector3(
				nav_point.x,
				enemy.global_position.y,
				nav_point.z
			)

			if ai._horizontal_distance(candidate) < 0.45:
				continue
			if not ai.is_position_free(candidate):
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
			score += ai._horizontal_distance_between(candidate, hide_position) * 0.2

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
	reset()
	finished.emit(sees_player, remembered)


func _choose_cover() -> bool:
	var result: Dictionary = selection.choose_cover(threat_origin, look_position)
	if result.is_empty():
		return false
	hide_position = result.hide
	peek_position = result.peek
	active_cover_body = result.body
	return true


func _peek_has_los(point: Vector3) -> bool:
	return selection._peek_has_los(point, look_position)


func _selected_cover_blocks(point: Vector3, origin: Vector3) -> bool:
	return selection._selected_cover_blocks(point, origin, active_cover_body)
