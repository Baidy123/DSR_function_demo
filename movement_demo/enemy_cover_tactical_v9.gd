extends Node

enum Phase { NONE, RUN_TO_COVER, HIDE, PEEK_OUT, WATCH }

## 敌人胸部到实际弹道线段的警戒半径（米）；墙挡住来弹时不会隔墙触发。
@export_range(0.1, 5.0, 0.1) var shot_radius: float = 1.5
## 每次新的有效近身来弹触发“寻找掩体”的概率。0=从不找掩体，1=每次都找。
## 已经处于跑向掩体/躲藏/探头流程时不会重新掷骰子，避免连续来弹让行为反复取消。
@export_range(0.0, 1.0, 0.05) var take_cover_chance: float = 1.0
## 到达有效躲藏位置后等待探头的秒数；新来弹可重新计时，真正看见玩家则立即结束躲藏。
@export_range(0.1, 10.0, 0.1) var hide_seconds: float = 3.0
## 抵达 Peek 后最多观察多少秒；看见玩家会提前结束，否则转入追踪或搜索。
@export_range(0.1, 10.0, 0.1) var watch_seconds: float = 2.0
## 转身跑向掩体时相对于敌人 Move Speed 的速度倍率。
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier: float = 2.0
## 从躲藏位置移向 Peek 点时相对于敌人 Move Speed 的速度倍率。
@export_range(0.1, 1.0, 0.1) var peek_speed_multiplier: float = 0.5
## 跑向掩体时改为“面向威胁撤退”的概率。0=永远转身跑，1=每次都掩护撤退。
@export_range(0.0, 1.0, 0.05) var covering_retreat_chance: float = 0.4
## 掩护撤退时的移动速度倍率；通常比直接冲向掩体慢。
@export_range(0.1, 1.5, 0.1) var covering_retreat_speed_multiplier: float = 0.8
## RUN_TO_COVER 期间每次真正受到伤害时，放弃掩护撤退并改为全速冲刺的概率。
## 每次受伤都会重新判定；0=中弹也继续掩护撤退，1=一中弹就立刻冲刺。
@export_range(0.0, 1.0, 0.05) var damage_force_sprint_chance: float = 0.5

@export_group("Cover Transfer Recovery")
## 跑向掩体时，连续这么多秒未朝下一个寻路拐点有效推进，就尝试临时绕行。
@export_range(0.2, 3.0, 0.1) var cover_stuck_repath_seconds: float = 0.8
## 在上面的时间窗口内，至少要朝 NavigationAgent 当前的下一个路径点靠近这么远，才算确实有进展。
## 贴墙左右抖动、原地滑动不会再误判成正常前进。
@export_range(0.02, 0.5, 0.01) var cover_stuck_min_progress_distance: float = 0.08
## 同一次跑向掩体最多尝试多少次临时绕行；全部失败后退出本次掩体行为，避免永久卡住。
@export_range(1, 8, 1) var cover_max_detour_retries: int = 4
## 卡住时，临时绕行点离当前位置的大致距离。
@export_range(0.5, 4.0, 0.25) var cover_detour_distance: float = 1.5
## 卡住时优先向当前“去掩体方向”的左右多少度寻找临时绕行点。
@export_range(20.0, 120.0, 5.0) var cover_detour_angle_degrees: float = 65.0
## 距离临时绕行点小于这个值时，认为绕行完成并重新追原 Hide。
@export_range(0.1, 1.0, 0.05) var cover_detour_arrival_distance: float = 0.45

@export_group("Cover Selection")
## 掩体选位：朝远离威胁方向移动会得到奖励，朝威胁方向冲会被强烈惩罚。
@export_range(0.0, 10.0, 0.1) var away_from_threat_weight: float = 4.0
## 路径或掩体位置比当前位置更靠近威胁时的惩罚。
@export_range(0.0, 10.0, 0.1) var closer_to_threat_weight: float = 5.0
## 开启时，Hide 必须挂 cover_point.gd、指定 Cover Body，且由该墙挡住中心射线。
## 关闭时改用中心和身体两侧都被静态墙遮挡的判定，不要求绑定指定墙。
@export var require_assigned_cover: bool = true
## 模拟威胁左右移动的距离（米）；仅在要求指定掩体时参与质量门槛和评分，0 表示不做横向模拟。
@export_range(0.0, 2.0, 0.1) var cover_lateral_test_distance: float = 0.5
## 要求指定掩体时，采样射线中被该墙挡住的最低比例（0～1）；中心射线还必须单独通过检查。
@export_range(0.0, 1.0, 0.05) var minimum_cover_quality: float = 0.20
## 掩护质量越高，越优先选择。
@export_range(0.0, 10.0, 0.1) var cover_quality_weight: float = 3.0
## Peek 点当前能直接看到威胁时的选位奖励。Peek 看不到不会淘汰这个 Hide，只是不获得奖励。
@export_range(0.0, 10.0, 0.1) var peek_los_weight: float = 1.5
## 调试时打印每类淘汰原因。
@export var debug_cover_selection: bool = true

var phase: Phase = Phase.NONE
var hide_position: Vector3
var peek_position: Vector3
var look_position: Vector3
var threat_origin: Vector3
var timer: float = 0.0
var active_cover_body: StaticBody3D = null
## 本次 RUN_TO_COVER 是否采用面向威胁的掩护撤退。
var covering_retreat: bool = false

## RUN_TO_COVER 的“朝当前路径点靠近”监测与临时绕行状态。
var cover_progress_waypoint: Vector3 = Vector3.ZERO
var cover_progress_best_distance: float = INF
var cover_stuck_timer: float = 0.0
var cover_detour_active: bool = false
var cover_detour_position: Vector3 = Vector3.ZERO
var cover_detour_side: float = 1.0
var cover_detour_retries: int = 0

@onready var enemy = get_parent()


func _ready() -> void:
	add_to_group("shot_listener")


func reset() -> void:
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
	# 场外射击不能在玩家进入竞技场前启动掩体动作。
	if not enemy.is_arena_active() or enemy.is_dead or enemy.combat_type != enemy.CombatType.RANGED:
		return
	var chest: Vector3 = enemy.global_position + Vector3.UP * 0.8
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
	if chest.distance_to(closest) > shot_radius:
		return
	# 警戒球可能伸到墙另一侧；墙挡住近处弹道时不能隔墙触发。
	if not has_clear_line(chest, closest):
		return
	enemy._investigate_attack(origin - Vector3.UP * 0.8)
	look_position = enemy.last_known_position
	threat_origin = origin

	# 只有“新开始一次掩体反应”时才掷骰子。
	# 没触发掩体行为时，_investigate_attack() 已经让敌人进入“知道玩家”状态，
	# 所以它仍会按主 AI 的 REPOSITION / TRACK 等逻辑反应，而不是完全无视枪击。
	if not is_active() and randf() > take_cover_chance:
		if debug_cover_selection:
			print("[Cover] 本次未触发寻找掩体，chance=", take_cover_chance)
		return

	# 已经选中的 Hide 只要仍然能真正挡住威胁、质量合格，就可以继续复用。
	# Peek 当前看不到玩家不再让整个掩体失效；之后探头失败会自然进入 TRACK / SEARCH。
	var can_reuse: bool = (
		is_active()
		and _selected_cover_blocks(hide_position, origin)
		and (
			not require_assigned_cover
			or _cover_quality(hide_position, origin, active_cover_body) >= minimum_cover_quality
		)
	)
	if not can_reuse and not _choose_cover():
		reset()
		return
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
	if enemy.combat_type != enemy.CombatType.RANGED:
		reset()
		return Vector3.ZERO
	if sees_player:
		look_position = enemy.last_known_position

	timer = maxf(0.0, timer - delta)

	if phase == Phase.HIDE:
		# 躲在掩体后时，只要重新真实看到玩家，就立刻结束 Cover 流程回到主 AI 交战。
		# 不再等 hide_seconds，也不再进入 PEEK_OUT。
		if sees_player:
			if debug_cover_selection:
				print("[Cover] HIDE 中重新发现玩家 -> 直接交战，跳过 PEEK")
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
		if debug_cover_selection:
			print("[Cover] PEEK_OUT 中重新发现玩家 -> 直接交战")
		_finish(true)
		return Vector3.ZERO

	if phase == Phase.RUN_TO_COVER or phase == Phase.PEEK_OUT:
		var final_destination: Vector3 = hide_position if phase == Phase.RUN_TO_COVER else peek_position

		# RUN_TO_COVER 卡住时，NavigationAgent 会临时去一个绕行点。
		# 绕行点到达后再继续追最终 Hide。
		if phase == Phase.RUN_TO_COVER and cover_detour_active:
			var detour_reached: bool = (
				enemy._horizontal_distance(cover_detour_position) <= cover_detour_arrival_distance
			)
			if detour_reached:
				cover_detour_active = false
				enemy.agent.target_position = hide_position
				_reset_cover_progress_monitor()
				if debug_cover_selection:
					print("[Cover] 临时绕行完成 -> 继续跑向原 Hide")
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
		var distance_to_destination: float = enemy._horizontal_distance(final_destination)

		# 靠近 Hide 不代表已经躲好：必须由当前实际位置验证掩护。
		# 未躲好时继续最后一小段，不能重选同一个点并不断刷新计时器。
		var near_destination: bool = distance_to_destination <= 0.7
		var reached_destination: bool = near_destination and (
			phase == Phase.PEEK_OUT
			or _selected_cover_blocks(enemy.global_position, threat_origin)
		)
		if reached_destination:
			cover_detour_active = false
			_reset_cover_progress_monitor()
			covering_retreat = false
			phase = Phase.HIDE if phase == Phase.RUN_TO_COVER else Phase.WATCH
			timer = hide_seconds if phase == Phase.HIDE else watch_seconds
			enemy.agent.target_position = enemy.global_position
			return Vector3.ZERO

		# Agent 可在距离目标 0.4 米处结束；墙角处这仍可能暴露。
		# 仅在短段身体空间通畅时补走到 Hide，仍经过下方超时与卡住检查。
		var finishing_hide: bool = (
			phase == Phase.RUN_TO_COVER and not cover_detour_active
			and near_destination and _cover_short_segment_is_clear(hide_position)
		)
		if finishing_hide:
			next_position = hide_position

		# Agent 认为导航结束，但实际上还没到 Hide。
		# 跑掩体时先主动绕行，而不是直接保持 RUN_TO_COVER 卡死。
		if enemy.agent.is_navigation_finished() and not finishing_hide:
			if phase == Phase.RUN_TO_COVER:
				if _try_cover_detour():
					return Vector3.ZERO
				if debug_cover_selection:
					print("[Cover] 导航提前结束且无法绕行 -> 退出本次掩体转移")
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

				if debug_cover_selection:
					print(
						"[Cover] RUN_TO_COVER 无法朝路径点推进，且找不到可用绕行点 retries=",
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


func _start_move(next_phase: Phase, destination: Vector3) -> void:
	# 初次开始一次 RUN_TO_COVER 时，用 covering_retreat_chance 决定是转身冲刺还是掩护撤退。
	# 后续真正受伤时由 on_damage_during_transfer() 另外逐次判定是否改为冲刺。
	var was_running_to_cover: bool = phase == Phase.RUN_TO_COVER
	phase = next_phase

	if phase == Phase.RUN_TO_COVER:
		if not was_running_to_cover:
			covering_retreat = randf() < covering_retreat_chance
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

func on_damage_during_transfer() -> void:
	if phase != Phase.RUN_TO_COVER:
		return

	# receive_hit() 会先把 NavigationAgent 目标改成攻击者位置，Cover 必须立即把导航夺回来。
	# 如果正在临时绕行，就继续走绕行点；否则继续追原 Hide。
	enemy.agent.target_position = cover_detour_position if cover_detour_active else hide_position

	# 每次真正受到伤害都重新判定。只要当前还在掩护撤退，成功就放弃慢速后撤并全速冲刺。
	var force_sprint: bool = randf() < damage_force_sprint_chance
	if covering_retreat and force_sprint:
		covering_retreat = false
		if debug_cover_selection:
			print("[Cover] 掩护转移中受伤 -> 改为全速冲刺，chance=", damage_force_sprint_chance)
	elif debug_cover_selection and covering_retreat:
		print("[Cover] 掩护转移中受伤 -> 继续掩护撤退，chance=", damage_force_sprint_chance)

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
	if enemy._horizontal_distance_between(cover_progress_waypoint, waypoint) > 0.25:
		cover_progress_waypoint = waypoint
		cover_progress_best_distance = enemy._horizontal_distance(waypoint)
		cover_stuck_timer = 0.0
		return false

	var distance_to_waypoint: float = enemy._horizontal_distance(waypoint)

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
	var distance: float = enemy._horizontal_distance_between(start, horizontal_destination)
	if distance <= 0.01:
		return false

	var sample_spacing: float = 0.20
	var sample_count: int = maxi(1, int(ceil(distance / sample_spacing)))

	for sample_index in range(1, sample_count + 1):
		var t: float = float(sample_index) / float(sample_count)
		var sample: Vector3 = start.lerp(horizontal_destination, t)
		if not enemy._ranged_point_is_free(sample):
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
				enemy.navigation_region.get_rid(),
				raw_target
			)

			# 如果候选被吸附得太远，说明这个方向并没有真实可走空间。
			if enemy._horizontal_distance_between(raw_target, nav_point) > 0.75:
				continue

			var candidate: Vector3 = Vector3(
				nav_point.x,
				enemy.global_position.y,
				nav_point.z
			)

			if enemy._horizontal_distance(candidate) < 0.45:
				continue
			if not enemy._ranged_point_is_free(candidate):
				continue

			# 临时绕行就是为了从当前墙角直接挪出去。
			# 除了 NavMesh 可达，还要求这段短距离用 NPC 自己的碰撞体实际走得通。
			if not _cover_short_segment_is_clear(candidate):
				continue

			var path: PackedVector3Array = _path_to(enemy.global_position, candidate)
			if path.is_empty():
				continue

			# 优先容易到达、同时不会把自己带得离最终 Hide 太远的临时点。
			var score: float = _path_length_from_path(path)
			score += enemy._horizontal_distance_between(candidate, hide_position) * 0.2

			if score < best_score:
				best_score = score
				best_position = candidate

	if is_inf(best_score):
		cover_detour_retries += 1
		cover_detour_side *= -1.0
		if debug_cover_selection:
			print(
				"[Cover] 找不到临时绕行点 retry=",
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

	if debug_cover_selection:
		print(
			"[Cover] RUN_TO_COVER 卡住 -> 临时绕行 ",
			cover_detour_position,
			" retry=",
			cover_detour_retries,
			"/",
			cover_max_detour_retries
		)

	return true

func _refresh_move_timer(destination: Vector3) -> void:
	var length: float = _path_length(enemy.global_position, destination)
	timer = length / maxf(0.1, enemy.move_speed * movement_multiplier()) + 2.0
	if is_inf(timer):
		timer = 0.0


func _finish(sees_player: bool) -> void:
	var remembered: Vector3 = look_position
	reset()
	enemy.ranged_has_destination = false
	enemy.ranged_repath_timer = 0.0
	enemy.agent.target_position = enemy.global_position
	if sees_player:
		enemy.state = enemy.State.REPOSITION
	else:
		enemy.last_known_position = remembered
		# 探头没重新发现玩家时，不立刻机械搜索；先尝试一次模糊方向追踪。
		enemy._begin_tracking_or_search(true)


func _choose_cover() -> bool:
	var points = enemy.get_parent().get_node_or_null("CoverPositions")
	if points == null:
		if debug_cover_selection:
			print("[Cover] 找不到 CoverPositions")
		return false

	var best_score: float = INF
	var best_cover: StaticBody3D = null
	var current_threat_distance: float = enemy._horizontal_distance_between(
		enemy.global_position, threat_origin
	)

	var total_points: int = 0
	var rejected_type: int = 0
	var rejected_assignment: int = 0
	var rejected_space: int = 0
	var rejected_cover: int = 0
	var rejected_quality: int = 0
	var no_peek_los: int = 0
	var rejected_path: int = 0

	for child in points.get_children():
		total_points += 1

		if not child is Marker3D:
			rejected_type += 1
			continue

		var point: Marker3D = child as Marker3D
		var peek: Marker3D = point.get_node_or_null("Peek") as Marker3D
		if peek == null:
			rejected_type += 1
			continue

		# 不依赖 class_name。只读取 Marker3D 脚本导出的 cover_body 属性。
		var assigned_cover: StaticBody3D = null
		if "cover_body" in point:
			assigned_cover = point.get("cover_body") as StaticBody3D

		if require_assigned_cover and not is_instance_valid(assigned_cover):
			rejected_assignment += 1
			continue

		var hiding: Vector3 = point.global_position
		var peeking: Vector3 = peek.global_position

		if not enemy._ranged_point_is_free(hiding) or not enemy._ranged_point_is_free(peeking):
			rejected_space += 1
			continue

		# 同一候选的质量同时用于门槛与评分，复用结果以免重复发射整组射线。
		var quality: float = 0.0
		# 硬条件：玩家/威胁 -> Hide 中心，第一处碰撞必须是这个点手动绑定的墙。
		if require_assigned_cover:
			if not _center_hidden_by_cover(hiding, threat_origin, assigned_cover):
				rejected_cover += 1
				continue

			# 玩家左右拉出、AI身体宽度只作为“掩护质量”，不再一票否决。
			quality = _cover_quality(hiding, threat_origin, assigned_cover)
			if quality < minimum_cover_quality:
				rejected_quality += 1
				continue
		else:
			if not is_hidden_at(hiding, threat_origin):
				rejected_cover += 1
				continue

		# Peek 能看到威胁只作为“更喜欢这个掩体”的评分项，不再是一票否决。
		# 这样只要 Hide 本身真的安全，NPC 就会先去躲；之后探头看不到再进入 TRACK / SEARCH。
		var peek_has_los: bool = has_clear_line(
			peeking + Vector3.UP * 0.8,
			look_position + Vector3.UP * 0.8
		)
		if not peek_has_los:
			no_peek_los += 1

		var path: PackedVector3Array = _path_to(enemy.global_position, hiding)
		var peek_path: PackedVector3Array = _path_to(hiding, peeking)
		if path.is_empty() or peek_path.is_empty():
			rejected_path += 1
			continue

		var length: float = _path_length_from_path(path)

		var move_direction: Vector3 = hiding - enemy.global_position
		move_direction.y = 0.0
		var away_direction: Vector3 = enemy.global_position - threat_origin
		away_direction.y = 0.0

		var away_alignment: float = 0.0
		if not move_direction.is_zero_approx() and not away_direction.is_zero_approx():
			away_alignment = move_direction.normalized().dot(away_direction.normalized())

		var cover_threat_distance: float = enemy._horizontal_distance_between(
			hiding, threat_origin
		)
		var min_path_distance: float = _minimum_path_distance_to_threat(
			path, threat_origin
		)

		var score: float = length
		score -= maxf(0.0, away_alignment) * away_from_threat_weight
		score += maxf(0.0, -away_alignment) * away_from_threat_weight
		score += maxf(
			0.0, current_threat_distance - cover_threat_distance
		) * closer_to_threat_weight
		score += maxf(
			0.0, current_threat_distance - min_path_distance
		) * closer_to_threat_weight

		if require_assigned_cover:
			score -= quality * cover_quality_weight

		# Peek 有直接射界时奖励，但没有射界仍然是合法掩体。
		if peek_has_los:
			score -= peek_los_weight

		if score < best_score:
			best_score = score
			hide_position = hiding
			peek_position = peeking
			best_cover = assigned_cover

	if is_inf(best_score):
		if debug_cover_selection:
			print(
				"[Cover] 无有效点 total=", total_points,
				" type/peek=", rejected_type,
				" assignment=", rejected_assignment,
				" space=", rejected_space,
				" wrongCover=", rejected_cover,
				" quality=", rejected_quality,
				" peekNoLOS(kept)=", no_peek_los,
				" path=", rejected_path
			)
		return false

	active_cover_body = best_cover

	if debug_cover_selection:
		var quality: float = 1.0
		if require_assigned_cover and is_instance_valid(active_cover_body):
			quality = _cover_quality(hide_position, threat_origin, active_cover_body)
		var selected_peek_has_los: bool = has_clear_line(
			peek_position + Vector3.UP * 0.8,
			look_position + Vector3.UP * 0.8
		)
		print(
			"[Cover] 选择 Hide=", hide_position,
			" Cover=", active_cover_body.name if is_instance_valid(active_cover_body) else "unassigned",
			" quality=", quality,
			" peekLOS=", selected_peek_has_los
		)

	return true


func _path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(enemy.navigation_region.get_rid(), to)
	if enemy._horizontal_distance_between(nav_point, to) > 0.6:
		return PackedVector3Array()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		enemy.agent.get_navigation_map(), from, nav_point, true, enemy.agent.navigation_layers)
	if path.is_empty() or path[path.size() - 1].distance_to(nav_point) > 0.5:
		return PackedVector3Array()
	return path


func _path_length_from_path(path: PackedVector3Array) -> float:
	var length: float = 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func _minimum_path_distance_to_threat(path: PackedVector3Array, threat: Vector3) -> float:
	if path.is_empty():
		return INF
	var threat_2d: Vector2 = Vector2(threat.x, threat.z)
	var previous: Vector2 = Vector2(enemy.global_position.x, enemy.global_position.z)
	var minimum: float = previous.distance_to(threat_2d)
	for point in path:
		var next: Vector2 = Vector2(point.x, point.z)
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(threat_2d, previous, next)
		minimum = minf(minimum, closest.distance_to(threat_2d))
		previous = next
	return minimum


func _path_length(from: Vector3, to: Vector3) -> float:
	var path: PackedVector3Array = _path_to(from, to)
	if path.is_empty():
		return INF
	return _path_length_from_path(path)


func _selected_cover_blocks(point: Vector3, origin: Vector3) -> bool:
	if require_assigned_cover:
		return (
			is_instance_valid(active_cover_body)
			and _center_hidden_by_cover(point, origin, active_cover_body)
		)
	return is_hidden_at(point, origin)


func _center_hidden_by_cover(
	point: Vector3,
	origin: Vector3,
	expected_cover: StaticBody3D
) -> bool:
	if not is_instance_valid(expected_cover):
		return false

	var query: PhysicsRayQueryParameters3D = _ray_query(
		origin,
		point + Vector3.UP * 0.8
	)
	var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == expected_cover


func _cover_quality(
	point: Vector3,
	origin: Vector3,
	expected_cover: StaticBody3D
) -> float:
	if not is_instance_valid(expected_cover):
		return 0.0

	var target_center: Vector3 = point + Vector3.UP * 0.8
	var direction: Vector3 = target_center - origin
	direction.y = 0.0
	if direction.is_zero_approx():
		return 0.0

	var side: Vector3 = direction.normalized().cross(Vector3.UP)

	var body_offsets: Array[Vector3] = [
		Vector3.ZERO,
		side * 0.35,
		-side * 0.35
	]

	var threat_offsets: Array[Vector3] = [Vector3.ZERO]
	if cover_lateral_test_distance > 0.0:
		threat_offsets.append(side * cover_lateral_test_distance)
		threat_offsets.append(-side * cover_lateral_test_distance)

	var total: int = 0
	var protected: int = 0

	for threat_offset: Vector3 in threat_offsets:
		for body_offset: Vector3 in body_offsets:
			total += 1
			var query: PhysicsRayQueryParameters3D = _ray_query(
				origin + threat_offset,
				target_center + body_offset
			)
			var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(query)

			if not hit.is_empty() and hit.collider == expected_cover:
				protected += 1

	if total <= 0:
		return 0.0
	return float(protected) / float(total)


func is_hidden_at(point: Vector3, origin: Vector3) -> bool:
	# 中心和身体两侧都应被墙挡住，避免停在墙角时半个身子仍暴露。
	var direction: Vector3 = point + Vector3.UP * 0.8 - origin
	direction.y = 0.0
	var side: Vector3 = direction.normalized().cross(Vector3.UP) * 0.4
	var body_offsets: Array[Vector3] = [Vector3.ZERO, side, -side]
	for offset: Vector3 in body_offsets:
		var query: PhysicsRayQueryParameters3D = _ray_query(origin, point + Vector3.UP * 0.8 + offset)
		var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider is StaticBody3D:
			return false
	return true


func has_clear_line(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.000001:
		return true
	return enemy.get_world_3d().direct_space_state.intersect_ray(_ray_query(from, to)).is_empty()


func _ray_query(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [enemy.get_rid()])
	if is_instance_valid(enemy.player) and enemy.player is CollisionObject3D:
		query.exclude = [enemy.get_rid(), enemy.player.get_rid()]
	query.hit_from_inside = true
	return query
