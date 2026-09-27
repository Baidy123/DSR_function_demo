extends Node

# AI 统一更新各板块、保存共享目击记忆并切换主状态；板块不各自运行物理循环。
const Actor = preload("res://enemy_actor.gd")

enum State { IDLE, APPROACH, INVESTIGATE, SEARCH, DEAD, PATROL, REPOSITION, HOLD_POSITION, TRACK }
enum CombatType { MELEE, RANGED }
## 近战沿用接近行为，尚无近战攻击；远程寻找射击位置并开火。
var combat_type: CombatType:
	get: return get_node("../UnitType").combat_type
	set(value): get_node("../UnitType").combat_type = value


## 每次巡逻抵达后停留的时间。
var patrol_pause_seconds: float:
	get: return _training_setting(&"patrol_pause_seconds", 1.5)
	set(value): _set_training_setting(&"patrol_pause_seconds", value)
## 受击时只知道攻击者附近区域，不持续获取攻击者坐标。
var attack_position_uncertainty: float:
	get: return _training_setting(&"attack_position_uncertainty", 1.0)
	set(value): _set_training_setting(&"attack_position_uncertainty", value)


var state: State = State.IDLE
var last_known_position: Vector3
## 只由真实目击更新；来弹推测不能覆盖它。
var last_seen_position: Vector3
var has_visual_memory: bool = false
## 玩家连续可见时估计出的最后移动方向。
var last_seen_direction: Vector3 = Vector3.ZERO
var was_seeing_player: bool = false


## 唯一的“知道玩家”标志。被目击、受击或近身来弹触发后都会设为 true；
## 搜索彻底结束后才恢复为 false。
var is_alerted: bool = false


var player: Node3D
var patrol_pause_timer: float = 0.0

@onready var actor: Actor = get_parent()
@onready var agent: NavigationAgent3D = actor.get_node("NavigationAgent3D")
@onready var arena_zone: Area3D = actor.get_node("../CombatZone")
@onready var navigation_region: NavigationRegion3D = actor.get_node("../NavigationRegion3D")
var tactics
var search
var actions: Dictionary = {}
var action_selector = preload("res://enemy_action_selector.gd").new()
var fire_decision
var current_suppression
var unit_type: Node
var training: Node
var _search_was_allowed: bool = true
@onready var perception = $Perception
@onready var cover_selection = $Cover
var cover

# 首版试玩值。风险承受与位置遮挡分开，代价越低越优。
@export_group("换弹决策")
@export_range(0.0, 10.0, 0.1) var reload_risk_weight: float = 3.0
@export_range(0.1, 2.0, 0.1) var reload_recheck_seconds: float = 0.4
@export_range(0.0, 3.0, 0.1) var reload_hold_seconds: float = 0.6
@export_range(0.0, 5.0, 0.1) var reload_switch_advantage: float = 0.5
var reload_plan: StringName = &""
var reload_destination: Dictionary = {}
var reload_options: Array[Dictionary] = []
var recent_damage_pressure: float = 0.0
var nearby_shot_pressure: float = 0.0
var _reload_plan_elapsed: float = 0.0
var _reload_check_timer: float = 0.0
var _reload_avoid_position: Vector3 = Vector3.INF


func _ready() -> void:
	unit_type = get_node("../UnitType")
	training = get_node("../Training")
	actions = unit_type.create_actions()
	tactics = actions[&"engage"]
	search = actions[&"search"]
	cover = actions[&"cover"]
	current_suppression = actions[&"suppression"]
	fire_decision = preload("res://enemy_fire_decision.gd").new()
	fire_decision.setup(self, &"fire_decision")
	for action in actions.values():
		action.setup(self)
	tactics.attack_position.phase_changed.connect(_on_attack_position_phase_changed)
	tactics.attack_position.finished.connect(_on_attack_position_finished)
	cover.finished.connect(resume_after_action)
	actions[&"suppression"].finished.connect(resume_after_action)
	actions[&"exit_suppression"].finished.connect(resume_after_action)
	perception.noise_heard.connect(_on_noise_heard)
	add_to_group("shot_listener")
	player = get_tree().get_first_node_in_group("player")
	actor.hit_received.connect(_on_hit_received)
	actor.reset_completed.connect(_reset_decisions)


func is_active() -> bool:
	return is_alerted and not actor.is_dead


func _reset_decisions() -> void:
	reset_actions()
	recent_damage_pressure = 0.0
	nearby_shot_pressure = 0.0
	_reload_avoid_position = Vector3.INF
	state = State.IDLE
	is_alerted = false
	last_known_position = actor.global_position
	last_seen_position = actor.global_position
	last_seen_direction = Vector3.ZERO
	was_seeing_player = false
	has_visual_memory = false
	patrol_pause_timer = patrol_pause_seconds
	agent.target_position = actor.global_position
	_update_label()


## 玩家入场才运行 AI；入场本身不等于发现玩家。
func is_arena_active() -> bool:
	return is_instance_valid(player) and arena_zone.overlaps_body(player)


func _physics_process(delta: float) -> void:
	_enforce_action_permissions()
	recent_damage_pressure = maxf(0.0, recent_damage_pressure - delta * 0.5)
	nearby_shot_pressure = maxf(0.0, nearby_shot_pressure - delta * 0.5)
	if actor.is_dead or not is_arena_active():
		actor.cancel_reload()
		reset_actions()
		tactics.update_shooting(delta, false, false)
		return

	# 地图同步完成前不能请求路径。
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return

	var sees_player: bool = perception.can_see_player()
	var lost_player_this_frame: bool = was_seeing_player and not sees_player
	var saw_player_this_frame: bool = sees_player and not was_seeing_player

	# 只用“连续两帧都真正看见玩家”来估计移动方向。
	# 这样不需要额外的“是否曾目击玩家”状态，也不会把第一次看见时的长距离差误当成移动。
	if sees_player:
		search.noise_search_origin = Vector3.INF
		var new_seen_position = player.global_position
		if was_seeing_player:
			var seen_motion = new_seen_position - last_seen_position
			seen_motion.y = 0.0
			if seen_motion.length() > 0.05:
				last_seen_direction = seen_motion.normalized()
		last_seen_position = new_seen_position
		has_visual_memory = true
		if tactics.suppression.is_active():
			tactics.suppression.finish(true)

	# 先更新真正目击到的记忆，再评估空匣，避免感知前就无条件开始换弹。
	if sees_player:
		is_alerted = true
		last_known_position = last_seen_position
	_update_reload_request(delta)
	if step_reload_plan(delta, sees_player):
		was_seeing_player = sees_player
		_update_label()
		return

	# 躲藏循环优先处理。躲在墙后时“看不见玩家”是主动行为，不在这里触发丢失目标判定；
	# 如果探头后仍未重新发现玩家，Cover 汇报结束，由 AI 衔接 TRACK/SEARCH。
	if action_selector.select_action(self) == &"cover":
		on_tactical_action_started(&"cover")
		if sees_player:
			is_alerted = true
			last_known_position = last_seen_position
			search.has_suspected_position = false
			search.search_hint_timer = 0.0
		var cover_direction: Vector3 = step_selected_action(delta, sees_player)
		# 躲藏／探头因重新目击结束时，这一次接敌也可以触发攻击占位。
		if not cover.is_active() and saw_player_this_frame:
			try_attack_position()
		if cover.phase == cover.Phase.RUN_TO_COVER and not cover.covering_retreat and not cover_direction.is_zero_approx():
			# 普通跑掩体：直接朝移动方向转身冲过去。
			actor.face_direction(cover_direction, delta)
		else:
			# 掩护撤退、躲藏和探头均面向最后已知威胁；脚下仍沿导航路径移动。
			actor.face_direction(cover.look_position - actor.global_position, delta)
		actor.move_character(cover_direction, delta, cover.movement_multiplier())
		tactics.update_shooting(delta, sees_player, not cover_direction.is_zero_approx())
		was_seeing_player = sees_player
		_update_label()
		return

	was_seeing_player = sees_player

	# 只要真正看到玩家，就进入唯一的“知道玩家”状态，并持续刷新最后已知位置。
	if sees_player:
		is_alerted = true
		last_known_position = player.global_position
		search.has_suspected_position = false
		search.track_timer = 0.0
		search.search_hint_timer = 0.0

		if combat_type == CombatType.RANGED:
			if state != State.REPOSITION and state != State.HOLD_POSITION:
				state = State.REPOSITION
				tactics.ranged_repath_timer = 0.0
				tactics.ranged_has_destination = false
		else:
			if state != State.APPROACH or agent.target_position.distance_to(last_known_position) > 0.25:
				agent.target_position = last_known_position
			state = State.APPROACH
		search.search_timer = 0.0
		search.search_pause_timer = 0.0
		search.search_is_pausing = false

	# 真实失视先尝试压制；没有接管的攻击动作时才转入原追踪／搜索。
	elif lost_player_this_frame:
		start_suppression()
		if not tactics.attack_position.is_active() and not tactics.suppression.is_active():
			search.begin_tracking_or_search(true)

	# 没有可用方向信息时，旧的近战调查仍可走到最后目击位置再搜索。
	elif state == State.APPROACH:
		state = State.INVESTIGATE
		agent.target_position = last_known_position

	if saw_player_this_frame:
		try_attack_position()
	var direction = Vector3.ZERO

	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)
		if patrol_pause_timer <= 0.0:
			_start_random_patrol()

	else:
		direction = step_selected_action(delta, sees_player)

	# 远程走位和 TRACK 允许侧移/后退，同时把武器方向保持在威胁方向。
	if state == State.REPOSITION or state == State.HOLD_POSITION:
		var facing_position: Vector3 = tactics.suppression.aim_point if tactics.suppression.is_active() else last_known_position
		actor.face_direction(facing_position - actor.global_position, delta)
	elif state == State.TRACK or state == State.SEARCH:
		var facing: Vector3 = search.facing_direction(direction)
		if not facing.is_zero_approx():
			actor.face_direction(facing, delta)
	elif not direction.is_zero_approx():
		actor.face_direction(direction, delta)

	actor.move_character(direction, delta, search.movement_multiplier())
	tactics.update_shooting(delta, sees_player, not direction.is_zero_approx())
	_update_label()


## 选择器只返回 ID，AI 负责调用兵种提供的实际实现，且一次只更新一个动作。
func step_selected_action(delta: float, sees_player: bool) -> Vector3:
	var id: StringName = action_selector.select_action(self)
	if id.is_empty():
		return Vector3.ZERO
	if id in [&"patrol", &"search"]:
		return actions[id].step(delta)
	return actions[id].step(delta, sees_player)


## AI决定时机；身体只执行固定耗时的基础换弹。
func _update_reload_request(delta: float = 0.0) -> void:
	if not is_arena_active() or actor.is_dead or player.is_dead() or player.is_in_dialogue or not actor.can_use_firearms():
		actor.cancel_reload()
		_clear_reload_plan()
		return
	if reload_plan.is_empty():
		if actor.ammo.magazine_rounds > 0 and not actor.ammo.is_reloading:
			return
		reload_options = assess_reload_options()
		start_reload_plan(choose_reload_option(reload_options))
		return
	_reload_plan_elapsed += delta
	_reload_check_timer -= delta
	# 已补满时继续原转移；到点后step交回正常接敌。
	if actor.ammo.magazine_rounds > 0 and not actor.ammo.is_reloading:
		return
	var invalid: bool = not reload_destination.is_empty() and (not can_use_action(&"cover") or not cover.is_active())
	if not invalid and _reload_check_timer > 0.0:
		return
	_reload_check_timer = reload_recheck_seconds
	if not reload_destination.is_empty():
		invalid = invalid or not _reload_destination_valid(reload_destination)
	if not invalid and cover.phase == cover.Phase.HIDE:
		return
	reload_options = assess_reload_options()
	var best: Dictionary = choose_reload_option(reload_options)
	var current_cost: float = INF
	for option: Dictionary in reload_options:
		if _same_reload_option(option):
			current_cost = option.cost
	# 路线/权限失效不受保持期限制；轻微分差不重启转移。
	if invalid or (_reload_plan_elapsed >= reload_hold_seconds and best.cost + reload_switch_advantage < current_cost):
		if not _same_reload_option(best):
			start_reload_plan(best)


func _known_reload_threat() -> Vector3:
	if is_alerted and last_known_position.is_finite():
		return last_known_position
	return search.noise_search_origin


## 查询不改变动作，也不读取隐藏玩家。候选使用身体遮挡及真实导航路径。
func assess_reload_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	if not actor.can_use_firearms():
		return options
	var seconds: float = maxf(0.1, actor.weapon.reload_seconds) * (1.0 - actor.ammo.reload_progress)
	var threat: Vector3 = _known_reload_threat()
	var exposure: float = _reload_exposure(actor.global_position, threat) if threat.is_finite() else 0.0
	options.append({"plan": &"here", "cost": seconds + _reload_risk_aversion() * exposure * (seconds + 2.0), "destination": {}})
	if not threat.is_finite() or not can_use_action(&"cover") or actor.move_speed <= 0.0:
		return options
	var destinations: Array = cover_selection.get_reload_cover_candidates(threat + Vector3.UP * 0.8)
	# 区域采样会随角色移动变化，必须把当前固定目的地放回比较，不能把它误当作失效。
	if not reload_destination.is_empty() and _reload_destination_valid(reload_destination):
		var current: Dictionary = reload_destination.duplicate()
		current.path = cover_selection._path_to(actor.global_position, current.hide)
		destinations.append(current)
	for destination: Dictionary in destinations:
		if _reload_avoid_position.is_finite() and _horizontal_distance_between(destination.hide, _reload_avoid_position) < 0.9:
			continue
		var at_cover: float = _reload_exposure(destination.hide, threat)
		var fast: Dictionary = _reload_route_cost(destination.path, threat, 0.0)
		var walking: Dictionary = _reload_route_cost(destination.path, threat, seconds)
		var costs: Dictionary = reload_plan_costs(seconds, exposure, at_cover, fast, walking)
		if not actor.ammo.is_reloading:
			options.append({"plan": &"after_cover", "cost": costs.after_cover, "destination": destination})
		options.append({"plan": &"on_way", "cost": costs.on_way, "destination": destination})
	return options


func _reload_risk_aversion() -> float:
	var missing_health: float = 1.0 - clampf(actor.health / maxf(actor.max_health, 1.0), 0.0, 1.0)
	return reload_risk_weight * (1.0 + missing_health + recent_damage_pressure + nearby_shot_pressure)


## 无火力时间 + 暴露时间代价；额外观察两秒，避免只看换完的一瞬间。
## 转移期间沿用跑掩体禁射规则，所以恢复火力还要等到抵达。
func reload_plan_costs(seconds: float, current_exposure: float, destination_exposure: float, fast: Dictionary, walking: Dictionary) -> Dictionary:
	var risk: float = _reload_risk_aversion()
	return {
		&"here": seconds + risk * current_exposure * (seconds + 2.0),
		&"after_cover": fast.seconds + seconds + risk * (fast.exposure + destination_exposure * (seconds + 2.0)),
		&"on_way": maxf(seconds, walking.seconds) + risk * (walking.exposure + destination_exposure * (maxf(0.0, seconds - walking.seconds) + 2.0))
	}


func _reload_exposure(point: Vector3, threat: Vector3) -> float:
	var direction: Vector3 = point - threat
	direction.y = 0.0
	var side: Vector3 = direction.normalized().cross(Vector3.UP) * 0.35
	var exposed: float = 0.0
	for offset: Vector3 in [Vector3.ZERO, side, -side]:
		if cover_selection.has_clear_line(threat + Vector3.UP * 0.8, point + Vector3.UP * 0.8 + offset):
			exposed += 1.0 / 3.0
	return exposed * (1.0 + clampf(1.0 - direction.length() / 3.0, 0.0, 1.0))


func _reload_route_cost(path: PackedVector3Array, threat: Vector3, reload_seconds: float) -> Dictionary:
	var fast_speed: float = maxf(0.01, actor.move_speed * cover.run_speed_multiplier)
	var walk_speed: float = minf(fast_speed, actor.move_speed)
	var seconds: float = 0.0
	var exposure: float = 0.0
	var previous: Vector3 = actor.global_position
	for point: Vector3 in path:
		var length: float = _horizontal_distance_between(previous, point)
		var samples: int = maxi(1, ceili(length))
		for index in range(samples):
			var distance: float = length / samples
			var slow_distance: float = minf(distance, maxf(0.0, reload_seconds - seconds) * walk_speed)
			var duration: float = slow_distance / walk_speed + (distance - slow_distance) / fast_speed
			var sample: Vector3 = previous.lerp(point, (float(index) + 0.5) / samples)
			exposure += _reload_exposure(sample, threat) * duration
			seconds += duration
		previous = point
	return {"seconds": seconds, "exposure": exposure}


func choose_reload_option(options: Array) -> Dictionary:
	var best: Dictionary = {}
	for option: Dictionary in options:
		if best.is_empty() or option.cost < best.cost:
			best = option
	return best


func _same_reload_option(option: Dictionary) -> bool:
	if option.plan != reload_plan:
		return false
	if option.destination.is_empty() or reload_destination.is_empty():
		return option.destination.is_empty() and reload_destination.is_empty()
	return option.destination.body == reload_destination.body and option.destination.hide.is_equal_approx(reload_destination.hide)


func _reload_destination_valid(destination: Dictionary) -> bool:
	var threat: Vector3 = _known_reload_threat()
	return (threat.is_finite() and is_instance_valid(destination.body)
		and cover_selection._selected_cover_blocks(destination.hide, threat + Vector3.UP * 0.8, destination.body)
		and is_position_free(destination.hide)
		and not cover_selection._path_to(actor.global_position, destination.hide).is_empty())


func start_reload_plan(option: Dictionary) -> void:
	if option.is_empty():
		return
	var same_destination: bool = (not reload_destination.is_empty() and not option.destination.is_empty()
		and reload_destination.body == option.destination.body and reload_destination.hide.is_equal_approx(option.destination.hide)
		and cover.is_active())
	reload_plan = option.plan
	reload_destination = option.destination
	_reload_plan_elapsed = 0.0
	_reload_check_timer = reload_recheck_seconds
	cancel_action(&"attack_position")
	cancel_action(current_suppression.action_id)
	if reload_destination.is_empty():
		cover.reset()
		agent.target_position = actor.global_position
	elif not same_destination:
		cover.start_reload_transfer(reload_destination, _known_reload_threat())
	if reload_plan != &"after_cover":
		actor.request_reload()
	if cover_selection.debug_cover_selection:
		print("[AI][换弹决策] ", reload_plan, "；代价=", snappedf(option.cost, 0.01))


## 持有计划时独占调度；路线复用原Cover行动，不重写寻路。
func step_reload_plan(delta: float, sees_player: bool) -> bool:
	if reload_plan.is_empty():
		return false
	var arrived: bool = reload_destination.is_empty() or cover.phase == cover.Phase.HIDE
	if arrived and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > 0:
		_clear_reload_plan()
		_reload_avoid_position = Vector3.INF
		if is_alerted:
			resume_after_action(sees_player, last_known_position)
		else:
			state = State.IDLE
		return false
	var direction: Vector3 = Vector3.ZERO
	if not arrived:
		if not can_use_action(&"cover") or not cover.is_active():
			# 行动执行失败，停止等待这个目的地；保留剩余换弹进度。
			start_reload_plan({"plan": &"here", "cost": 0.0, "destination": {}})
		else:
			agent.target_position = cover.cover_detour_position if cover.cover_detour_active else reload_destination.hide
			direction = cover.step(delta, sees_player)
			if not cover.is_active():
				start_reload_plan({"plan": &"here", "cost": 0.0, "destination": {}})
	if cover.phase == cover.Phase.HIDE and not actor.ammo.is_reloading and actor.ammo.magazine_rounds == 0:
		actor.request_reload()
	var threat: Vector3 = _known_reload_threat()
	if not direction.is_zero_approx():
		actor.face_direction(direction, delta)
	elif threat.is_finite():
		actor.face_direction(threat - actor.global_position, delta)
	actor.move_character(direction, delta, cover.movement_multiplier() if not reload_destination.is_empty() else 1.0)
	tactics.update_shooting(delta, sees_player, not direction.is_zero_approx())
	return true


func _clear_reload_plan() -> void:
	if not reload_destination.is_empty():
		cover.reset()
	reload_plan = &""
	reload_destination = {}
	reload_options.clear()
	_reload_check_timer = 0.0
	_reload_plan_elapsed = 0.0


## 各板块共用身体空间查询；排除玩家，避免借查询感知隐藏位置。
func is_position_free(point: Vector3) -> bool:
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	# 略高于地面，避免把正常接触地板误判成被墙堵住。
	query.transform = Transform3D(Basis.IDENTITY, point + collision.position + Vector3.UP * 0.05)
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	# 候选点评估只检查障碍，不能借碰撞查询感知墙后玩家的位置。
	if is_instance_valid(player) and player is CollisionObject3D:
		query.exclude = [actor.get_rid(), player.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _start_random_patrol() -> void:
	actions[&"patrol"].start()


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z).length()


func _horizontal_distance_between(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_hit_received(damage: float, attacker_position: Vector3) -> void:
	if actor.is_dead:
		reset_actions()
		is_alerted = false
		state = State.DEAD
		search.search_sweep_points.clear()
		search.search_uncovered_points.clear()
		search.search_sample_count = 0
		search.search_current_target_active = false
	elif damage > 0.0:
		recent_damage_pressure = minf(2.0, recent_damage_pressure + 0.5 + damage / maxf(actor.max_health, 1.0))
		if not reload_plan.is_empty() and cover.phase == cover.Phase.HIDE:
			_reload_avoid_position = actor.global_position
			# 原HIDE受击规则先退出，下帧根据新威胁重评；不取消弹药计时。
			reload_plan = &""
			reload_destination = {}
		var was_suppressing: bool = tactics.suppression.is_active()
		if attacker_position.is_finite():
			_investigate_attack(attacker_position)
		# 保持原顺序：更新受击记忆后再处理退出躲藏/冲刺。
		if was_suppressing:
			tactics.suppression.reset()
			state = State.REPOSITION
			cover.take_cover_after_suppression_hit()
		else:
			if cover != null:
				cover.on_damage_received()
			if attacker_position.is_finite():
				try_attack_position(true)
	_update_label()


func _investigate_attack(attacker_position: Vector3) -> void:
	# 区外来弹不提前启动调查；伤害结算仍由 receive_hit() 处理。
	if not is_arena_active():
		return
	search.noise_search_origin = Vector3.INF
	# 受击或近身来弹直接进入唯一的“知道玩家”状态。
	# attacker_position 仍可带误差，但不再区分“只警觉、尚未目击”这种记忆状态。
	is_alerted = true

	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(0.25, 1.0) * attack_position_uncertainty

	last_known_position = attacker_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	last_known_position.y = actor.global_position.y

	state = State.REPOSITION if combat_type == CombatType.RANGED else State.INVESTIGATE
	tactics.ranged_repath_timer = 0.0
	tactics.ranged_has_destination = false
	search.search_timer = 0.0
	search.search_pause_timer = 0.0
	search.search_is_pausing = false
	search.search_hint_timer = 0.0
	agent.target_position = last_known_position


func _update_label() -> void:
	var names = ["巡逻停留", "看见玩家", "前往最后位置", "警戒搜索", "已死亡", "随机巡逻", "寻找射击位置", "保持射击位置", "架枪追踪"]
	if state == State.REPOSITION and _horizontal_distance(last_known_position) < tactics._ranged_distance_band().x:
		names[State.REPOSITION] = "寻找后退路线"
	var knowledge_text = "知道玩家" if is_alerted else "未激活"
	if search.noise_search_origin.is_finite():
		knowledge_text = "听到声音"

	var state_text: String = cover.state_label() if cover != null and cover.is_active() else names[state]
	if tactics.attack_position.is_active():
		state_text = tactics.attack_position.state_label()
	if tactics.suppression.is_active():
		state_text = tactics.suppression.state_label()
	if search.noise_search_origin.is_finite() and not cover.is_active():
		if state == State.TRACK:
			state_text = "调查声源"
		elif state == State.SEARCH:
			state_text = "声源附近搜索"
	var type_text = "近战" if combat_type == CombatType.MELEE else "远程"
	if not reload_plan.is_empty():
		state_text = {&"here": "原地换弹", &"after_cover": "先到掩体再换弹", &"on_way": "边转移边换弹"}[reload_plan]
	if actor.ammo.is_reloading:
		state_text += " · 换弹中 %d%%" % floori(actor.ammo.reload_progress * 100.0)
	actor.set_status_text("%s敌人：%s\n生命 %d / %d\n%s" % [
		type_text,
		state_text,
		ceili(actor.health),
		ceili(actor.max_health),
		knowledge_text
	])

# 原属性名转发至Training，避免维护两份配置。
func _training_setting(key: StringName, _fallback: Variant) -> Variant:
	return get_node("../Training").get("ai_" + String(key))


func _set_training_setting(key: StringName, value: Variant) -> void:
	get_node("../Training").set("ai_" + String(key), value)


func try_attack_position(from_hit: bool = false) -> void:
	if not reload_plan.is_empty():
		return
	if not from_hit and not has_visual_memory:
		return
	if not tactics.attack_position.can_start():
		return
	var trigger := "中弹" if from_hit else "新目击"
	if randf() >= clampf(tactics.attack_position_chance, 0.0, 1.0):
		if cover_selection.debug_cover_selection:
			print("[AI][攻击占位] 本次", trigger, "未触发，chance=", tactics.attack_position_chance)
		return
	var known_position: Vector3 = last_known_position if from_hit else last_seen_position
	if tactics.attack_position.start(known_position, from_hit) and cover_selection.debug_cover_selection:
		print("[AI][攻击占位] ", trigger, "触发，开始检查墙角区域")


func _on_attack_position_phase_changed(current_phase: int) -> void:
	state = State.HOLD_POSITION if current_phase == tactics.attack_position.Phase.HOLD else State.REPOSITION


# 动作只汇报结束与已知位置；接下来交战还是追踪，由决策层衔接。
func _on_attack_position_finished(sees_player: bool, known_position: Vector3, reason: String) -> void:
	resume_after_action(sees_player, known_position)
	if cover_selection.debug_cover_selection:
		print("[AI][攻击占位] 结束：", reason, "；回到交战／追踪流程")


## 动作只汇报结果；跨动作衔接统一留在 AI，取消动作不触发此流程。
func resume_after_action(sees_player: bool, known_position: Vector3) -> void:
	tactics.ranged_has_destination = false
	tactics.ranged_repath_timer = 0.0
	agent.target_position = actor.global_position
	if sees_player:
		state = State.REPOSITION
	else:
		last_known_position = known_position
		search.begin_tracking_or_search(true)


## 躲藏中受击保持原规则：回到接敌，并以已有受击记忆作为导航目标。
func resume_engagement_after_cover_hit() -> void:
	state = State.REPOSITION
	tactics.ranged_has_destination = false
	tactics.ranged_repath_timer = 0.0
	agent.target_position = last_known_position


## 成功取得战术控制权后才取消互斥动作，候选失败不能抢占。
func on_tactical_action_started(id: StringName) -> void:
	if id == &"cover":
		cancel_action(&"attack_position")
		cancel_action(current_suppression.action_id)
	elif id in [&"suppression", &"exit_suppression"]:
		cancel_action(&"attack_position")


func start_suppression() -> void:
	if tactics.suppression.is_active():
		return
	tactics.exit_suppression.on_target_lost()
	if tactics.exit_suppression.is_active():
		tactics.suppression = tactics.exit_suppression
	else:
		tactics.suppression = tactics.area_suppression
		tactics.suppression.on_target_lost()


func can_use_action(id: StringName) -> bool:
	return is_instance_valid(unit_type) and is_instance_valid(training) and unit_type.has_action(id) and training.allows_action(id)


func notice_shot(origin: Vector3, endpoint: Vector3) -> void:
	cover.notice_shot(origin, endpoint)


func _enforce_action_permissions() -> void:
	var search_allowed := can_use_action(&"search")
	var search_reenabled := search_allowed and not _search_was_allowed
	_search_was_allowed = search_allowed
	var interrupted := false
	for id in [&"cover", &"attack_position", &"suppression", &"exit_suppression"]:
		var action = actions[id]
		if action.is_active() and not can_use_action(id):
			action.reset()
			interrupted = true
	if cover.covering_retreat and not can_use_action(&"covering_retreat"):
		cover.covering_retreat = false
	if state == State.PATROL and not can_use_action(&"patrol"):
		interrupted = true
	if state in [State.TRACK, State.SEARCH, State.INVESTIGATE] and not can_use_action(&"search"):
		search.reset()
		interrupted = true
	if interrupted or (search_reenabled and state == State.IDLE and is_alerted):
		state = State.IDLE
		agent.target_position = actor.global_position
		tactics.ranged_has_destination = false
		tactics.ranged_repath_timer = 0.0
		# 恢复权限后用原记忆继续，不等待新的目击/受击，也不借机生成隐藏位置提示。
		if is_alerted and not actor.is_dead and is_arena_active():
			if was_seeing_player and can_use_action(&"engage"):
				state = State.REPOSITION if combat_type == CombatType.RANGED else State.APPROACH
			elif search_allowed:
				search.begin_tracking_or_search(false)


func reset_actions() -> void:
	_clear_reload_plan()
	for action in actions.values():
		action.reset()
	fire_decision.reset()
	current_suppression = actions[&"suppression"]


func cancel_action(id: StringName) -> void:
	if actions.has(id):
		actions[id].reset()


func _on_noise_heard(position: Vector3) -> void:
	if not can_use_action(&"search") or actor.is_dead or not is_arena_active():
		return
	# 真实目击与正在执行的战斗动作优先；声音不会每次都打断它们。
	if not reload_plan.is_empty() or perception.can_see_player() or cover.is_active() or tactics.attack_position.is_active() or tactics.suppression.is_active():
		return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	search.investigate_noise(position)
	_update_label()
