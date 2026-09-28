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

# 共用Utility标准，全部候选使用同一观察时长；以下为可调试玩值。
@export_group("Utility AI")
@export_range(1.0, 12.0, 0.5) var utility_horizon_seconds: float = 4.0
@export_range(0.0, 10.0, 0.1) var utility_fire_weight: float = 3.0
@export_range(0.0, 10.0, 0.1) var utility_risk_weight: float = 3.0
@export_range(0.0, 10.0, 0.1) var utility_information_weight: float = 1.0
@export_range(0.1, 2.0, 0.1) var utility_recheck_seconds: float = 0.4
@export_range(0.0, 3.0, 0.1) var utility_hold_seconds: float = 0.6
@export_range(0.0, 5.0, 0.1) var utility_switch_advantage: float = 0.5
## 没有目击、受伤或近弹的新证据时，旧威胁确定性每过这么多秒减半。
## 只影响风险估计，不删除位置记忆、不强制离开掩体；4秒为试玩初值。
@export_range(0.5, 30.0, 0.5) var utility_threat_half_life_seconds: float = 4.0
## 仅Debug总开关开启时输出选中动作及分数构成。
@export var debug_utility: bool = false
var utility_options: Array[Dictionary] = []
var utility_current: Dictionary = {}
var utility_unseen_seconds: float = 0.0
var utility_threat_age_seconds: float = 0.0
var utility_suppression_pending: bool = false
var utility_rejected_attack_points: Array[Vector3] = []
var _utility_blocked_destinations: Array[Dictionary] = []
var _utility_rejection_threat: Vector3 = Vector3.INF
var _utility_elapsed: float = 0.0
var _utility_timer: float = 0.0
# 兼容旧换弹检查接口；实际决策只使用上面的共用参数。
var reload_risk_weight: float:
	get: return utility_risk_weight
	set(value): utility_risk_weight = value
var reload_recheck_seconds: float:
	get: return utility_recheck_seconds
	set(value): utility_recheck_seconds = value
var reload_hold_seconds: float:
	get: return utility_hold_seconds
	set(value): utility_hold_seconds = value
var reload_switch_advantage: float:
	get: return utility_switch_advantage
	set(value): utility_switch_advantage = value
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
	for entry: Dictionary in _utility_blocked_destinations:
		entry.remaining -= maxf(0.0, delta)
	_utility_blocked_destinations = _utility_blocked_destinations.filter(func(entry): return entry.remaining > 0.0)
	recent_damage_pressure = maxf(0.0, recent_damage_pressure - delta * 0.5)
	nearby_shot_pressure = maxf(0.0, nearby_shot_pressure - delta * 0.5)
	if actor.is_dead or not is_arena_active() or player.is_dead() or player.is_in_dialogue:
		actor.cancel_reload()
		reset_actions()
		actor.velocity = Vector3.ZERO
		tactics.update_shooting(delta, false, false)
		return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	var sees_player: bool = perception.can_see_player()
	utility_threat_age_seconds += maxf(0.0, delta)
	if sees_player:
		utility_threat_age_seconds = 0.0
		search.noise_search_origin = Vector3.INF
		var new_seen_position: Vector3 = player.global_position
		if was_seeing_player:
			var seen_motion := new_seen_position - last_seen_position
			seen_motion.y = 0.0
			if seen_motion.length() > 0.05:
				last_seen_direction = seen_motion.normalized()
		last_seen_position = new_seen_position
		has_visual_memory = true
		is_alerted = true
		last_known_position = new_seen_position
		utility_unseen_seconds = 0.0
		utility_suppression_pending = false
	elif is_alerted:
		utility_unseen_seconds += delta
	if sees_player != was_seeing_player:
		if not sees_player:
			utility_suppression_pending = true
		invalidate_utility()
	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)
	if sees_player or (last_known_position.is_finite() and _utility_rejection_threat.is_finite() and last_known_position.distance_to(_utility_rejection_threat) > 0.5):
		utility_rejected_attack_points.clear()
	if action_selector.has_method("advance_evaluation"):
		action_selector.advance_evaluation(self, sees_player)
	_update_utility_decision(delta, sees_player)
	was_seeing_player = sees_player
	# 执行的是统一评估已选中的方案；空匣不会在此之前取得控制权。
	if utility_current.get("id", &"") == &"reload" and step_reload_plan(delta, sees_player):
		_update_label()
		return
	var direction := step_selected_action(delta, sees_player)
	var multiplier: float = 1.0
	var selected: StringName = utility_current.get("id", &"")
	if selected == &"cover":
		multiplier = cover.movement_multiplier()
		actor.face_direction(last_known_position - actor.global_position if cover.covering_retreat or direction.is_zero_approx() else direction, delta)
	elif selected == &"search":
		multiplier = search.movement_multiplier()
		actor.face_direction(search.facing_direction(direction), delta)
	elif selected in [&"suppression", &"exit_suppression"]:
		actor.face_direction(tactics.suppression.aim_point - actor.global_position, delta)
	elif is_alerted:
		actor.face_direction(last_known_position - actor.global_position, delta)
	elif not direction.is_zero_approx():
		actor.face_direction(direction, delta)
	actor.move_character(direction, delta, multiplier)
	tactics.update_shooting(delta, sees_player, not direction.is_zero_approx())
	_update_label()


func step_selected_action(delta: float, sees_player: bool) -> Vector3:
	var id: StringName = utility_current.get("id", &"")
	if id.is_empty() or id == &"reload":
		return Vector3.ZERO
	if id == &"cover" and cover.phase == cover.Phase.HIDE:
		# 是否继续躲藏由统一评估决定，不能另一个计时器抢先启动探头。
		return Vector3.ZERO
	if id == &"cover":
		# 来弹只更新威胁；保持原方案时，导航仍须朝已评分的目的地前进。
		if cover.phase == cover.Phase.RUN_TO_COVER:
			agent.target_position = cover.cover_detour_position if cover.cover_detour_active else cover.hide_position
		elif cover.phase == cover.Phase.PEEK_OUT:
			agent.target_position = cover.peek_position
	if id == &"engage" and combat_type == CombatType.RANGED:
		if utility_current.get("destination", {}).is_empty():
			state = State.HOLD_POSITION
			return Vector3.ZERO
		return tactics.step_evaluated_engagement(utility_current.destination, delta, sees_player)
	if id == &"engage" and combat_type == CombatType.MELEE and sees_player:
		if agent.target_position.distance_to(last_known_position) > 0.25:
			agent.target_position = last_known_position
	if id in [&"patrol", &"search"]:
		return actions[id].step(delta)
	return actions[id].step(delta, sees_player)


func invalidate_utility() -> void:
	_utility_timer = 0.0


func _utility_current_valid(sees_player: bool) -> bool:
	var id: StringName = utility_current.get("id", &"")
	if id.is_empty():
		return false
	if id == &"reload":
		return actor.can_use_firearms() and not reload_plan.is_empty() and (reload_destination.is_empty() or (can_use_action(&"cover") and cover.is_active()))
	if not can_use_action(id):
		return false
	match id:
		&"cover": return cover.is_active()
		&"attack_position": return tactics.attack_position.is_active() and tactics.can_use_attack_positions and actor.can_use_firearms()
		&"suppression", &"exit_suppression": return not sees_player and actions[id].is_active() and actor.can_use_firearms()
		&"search": return (is_alerted or search.noise_search_origin.is_finite()) and not sees_player and state in [State.SEARCH, State.TRACK, State.INVESTIGATE]
		&"patrol": return not is_alerted and state == State.PATROL
		&"engage": return is_alerted and sees_player
	return false


func _update_utility_decision(delta: float, sees_player: bool) -> void:
	_utility_elapsed += delta
	_utility_timer -= delta
	var valid := _utility_current_valid(sees_player)
	if _utility_timer > 0.0 and (valid or utility_current.is_empty()):
		return
	_utility_timer = utility_recheck_seconds
	utility_options = action_selector.assess_options(self, sees_player)
	var best: Dictionary = action_selector.choose_option(utility_options)
	var current_cost: float = INF
	for option: Dictionary in utility_options:
		if action_selector.same_option(option, utility_current):
			current_cost = option.cost
			# 保持动作时也展示本次实际比较的分数，避免调试面板显示旧代价。
			utility_current = option
	valid = valid and is_finite(current_cost)
	if best.is_empty():
		if not utility_current.is_empty():
			_cancel_utility_execution()
		state = State.IDLE
		return
	if valid and action_selector.same_option(best, utility_current):
		utility_current = best
		return
	if valid and (_utility_elapsed < utility_hold_seconds or best.cost + utility_switch_advantage >= current_cost):
		return
	_start_utility_option(best, sees_player)


func _cancel_utility_execution() -> void:
	# 基础换弹可与移动并行：战术切换不清掉已有换弹进度。
	_clear_reload_plan()
	for id in [&"cover", &"attack_position", &"suppression", &"exit_suppression"]:
		cancel_action(id)
	utility_current = {}
	agent.target_position = actor.global_position


func _start_utility_option(option: Dictionary, sees_player: bool) -> void:
	# 缓存候选在真正接管前复核，障碍/权限变化不能按旧高分穿墙。
	if option.id == &"cover" and option.get("mode") == &"peek":
		if not can_use_action(&"cover") or not is_position_free(option.destination.position) or cover_selection._path_to(actor.global_position, option.destination.position).is_empty():
			invalidate_utility()
			return
	elif option.id == &"cover" or (option.id == &"reload" and not option.destination.is_empty()):
		if not can_use_action(&"cover") or not _reload_destination_valid(option.destination):
			_reload_avoid_position = option.destination.hide
			invalidate_utility()
			return
	var preserve_search: bool = (option.id == &"search" and (
		(state == State.TRACK and search.has_suspected_position)
		or (state == State.SEARCH and search.search_sample_count > 0)
		or (state == State.INVESTIGATE and utility_current.get("id") == &"search")))
	var search_target: Vector3 = search.utility_destination()
	var same_reload_destination: bool = (utility_current.get("id") == &"reload" and option.id == &"reload"
		and not reload_destination.is_empty() and not option.destination.is_empty()
		and reload_destination.body == option.destination.body and reload_destination.hide.is_equal_approx(option.destination.hide))
	if not same_reload_destination:
		_cancel_utility_execution()
	utility_current = option
	_utility_elapsed = 0.0
	match option.id:
		&"reload": start_reload_plan(option)
		&"cover":
			if option.get("mode") == &"peek":
				cover.start_utility_peek(option.destination, _known_reload_threat())
			else:
				cover.start_reload_transfer(option.destination, _known_reload_threat(), option.get("mode") == &"covering_retreat")
		&"attack_position":
			if not tactics.attack_position.start_evaluated(option.destination, last_known_position):
				utility_current = {}
				invalidate_utility()
		&"engage":
			state = State.REPOSITION if combat_type == CombatType.RANGED else State.APPROACH
			tactics.reset_movement_progress()
			tactics.ranged_has_destination = false
			tactics.ranged_repath_timer = 0.0
			agent.target_position = option.destination.get("position", last_known_position)
		&"search":
			if preserve_search:
				agent.target_position = search_target
			else:
				search.begin_tracking_or_search(false)
		&"patrol": _start_random_patrol()
		&"suppression", &"exit_suppression":
			tactics.suppression = actions[option.id]
			utility_suppression_pending = false
			tactics.suppression.on_target_lost()
			if not tactics.suppression.is_active():
				utility_current = {}
				invalidate_utility()
	if debug_utility and actor.debug_settings.enabled:
		print("[AI][Utility] ", option.id, " ", option.get("plan", ""), " cost=", snappedf(option.cost, 0.01), " ", option.get("breakdown", {}))


## 旧测试/调用入口兼容；不再有只比较换弹并抢占其他动作的决策器。
func _update_reload_request(delta: float = 0.0) -> void:
	if not is_arena_active() or actor.is_dead or player.is_dead() or player.is_in_dialogue:
		actor.cancel_reload()
		reset_actions()
		return
	_update_utility_decision(delta, perception.can_see_player())


func _known_reload_threat() -> Vector3:
	if is_alerted and last_known_position.is_finite():
		return last_known_position
	return search.noise_search_origin


## 查询不改变动作，也不读取隐藏玩家。候选使用身体遮挡及真实导航路径。
func assess_reload_options() -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for option: Dictionary in action_selector.assess_options(self, perception.can_see_player()):
		if option.id == &"reload":
			options.append(option)
	return options


func _reload_risk_aversion() -> float:
	var missing_health: float = 1.0 - clampf(actor.health / maxf(actor.max_health, 1.0), 0.0, 1.0)
	var confidence := pow(0.5, utility_threat_age_seconds / maxf(0.5, utility_threat_half_life_seconds))
	return reload_risk_weight * confidence * (1.0 + missing_health + recent_damage_pressure + nearby_shot_pressure)


## 旧换弹评分接口复用共同窗口；转移期间恢复火力需等到抵达。
func reload_plan_costs(seconds: float, current_exposure: float, destination_exposure: float, fast: Dictionary, walking: Dictionary) -> Dictionary:
	# 兼容旧调用；评分公式与观察窗口都来自共同评估器。
	var horizon: float = utility_horizon_seconds
	return {
		&"here": action_selector.score_outcome(self, seconds, current_exposure * horizon).cost,
		&"after_cover": action_selector.score_outcome(self, fast.seconds + seconds, fast.exposure + destination_exposure * maxf(0.0, horizon - fast.seconds)).cost,
		&"on_way": action_selector.score_outcome(self, maxf(seconds, walking.seconds), walking.exposure + destination_exposure * maxf(0.0, horizon - walking.seconds)).cost
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
	return action_selector.assess_route(self, path, threat, cover.run_speed_multiplier, reload_seconds)


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


## 统一决策选中后执行换弹计划；路线复用Cover行动，不重写寻路。
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
			# 执行失败交回统一评估；不能私自选择原地换弹。
			_fail_reload_transfer()
			return false
		else:
			agent.target_position = cover.cover_detour_position if cover.cover_detour_active else reload_destination.hide
			direction = cover.step(delta, sees_player)
			if not cover.is_active():
				_fail_reload_transfer()
				return false
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


func _fail_reload_transfer() -> void:
	if not reload_destination.is_empty():
		_reload_avoid_position = reload_destination.hide
	_clear_reload_plan()
	utility_current = {}
	invalidate_utility()


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
		utility_threat_age_seconds = 0.0
		recent_damage_pressure = minf(2.0, recent_damage_pressure + 0.5 + damage / maxf(actor.max_health, 1.0))
		if cover.phase == cover.Phase.HIDE:
			_reload_avoid_position = actor.global_position
			# 原HIDE受击规则先退出，下帧根据新威胁重评；不取消弹药计时。
			reload_plan = &""
			reload_destination = {}
		invalidate_utility()
		var was_suppressing: bool = tactics.suppression.is_active()
		if attacker_position.is_finite():
			_investigate_attack(attacker_position)
		# 保持原顺序：更新受击记忆后再处理退出躲藏/冲刺。
		if was_suppressing:
			tactics.suppression.reset()
			state = State.REPOSITION
			invalidate_utility()
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
	utility_threat_age_seconds = 0.0
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


func try_attack_position(_from_hit: bool = false) -> void:
	# 目击/受击仅要求重新评估；不能绕过Utility抽概率启动动作。
	invalidate_utility()


func _on_attack_position_phase_changed(current_phase: int) -> void:
	state = State.HOLD_POSITION if current_phase == tactics.attack_position.Phase.HOLD else State.REPOSITION


# 动作只汇报结束与已知位置；接下来交战还是追踪，由决策层衔接。
func _on_attack_position_finished(sees_player: bool, known_position: Vector3, reason: String) -> void:
	if utility_current.get("id") == &"attack_position" and (reason.contains("无进展") or reason.contains("超时") or reason.contains("导航提前")):
		block_utility_destination(utility_current.destination.position)
	if not sees_player and utility_current.get("id") == &"attack_position":
		# 到过却没发现目标的观察点不再假设必有信息收益，直到获得新威胁信息。
		utility_rejected_attack_points.append(utility_current.destination.position)
		_utility_rejection_threat = known_position
	resume_after_action(sees_player, known_position)
	if cover_selection.debug_cover_selection:
		print("[AI][攻击占位] 结束：", reason, "；回到交战／追踪流程")


## 动作只汇报结果；跨动作衔接统一留在 AI，取消动作不触发此流程。
func resume_after_action(sees_player: bool, known_position: Vector3) -> void:
	if not sees_player and utility_current.get("mode") == &"peek":
		utility_rejected_attack_points.append(utility_current.destination.position)
		_utility_rejection_threat = known_position
	invalidate_utility()
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
	utility_suppression_pending = true
	invalidate_utility()


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
	if action_selector.has_method("reset_evaluation"):
		action_selector.reset_evaluation()
	utility_current = {}
	utility_options.clear()
	_utility_timer = 0.0
	_utility_elapsed = 0.0
	utility_unseen_seconds = 0.0
	utility_threat_age_seconds = 0.0
	utility_suppression_pending = false
	utility_rejected_attack_points.clear()
	_utility_blocked_destinations.clear()
	_utility_rejection_threat = Vector3.INF
	_clear_reload_plan()
	for action in actions.values():
		action.reset()
	fire_decision.reset()
	current_suppression = actions[&"suppression"]


func cancel_action(id: StringName) -> void:
	if actions.has(id):
		actions[id].reset()


## 实际走不动的目的地暂时排除；目击不清除，三秒后允许重新考虑。
func block_utility_destination(point: Vector3) -> void:
	_utility_blocked_destinations.append({"position": point, "remaining": 3.0})
	invalidate_utility()


func is_utility_destination_blocked(point: Vector3) -> bool:
	return _utility_blocked_destinations.any(func(entry): return _horizontal_distance_between(entry.position, point) < 0.75)


func _on_noise_heard(position: Vector3) -> void:
	if not can_use_action(&"search") or actor.is_dead or not is_arena_active():
		return
	# 真实目击与正在执行的战斗动作优先；声音不会每次都打断它们。
	if not reload_plan.is_empty() or perception.can_see_player() or cover.is_active() or tactics.attack_position.is_active() or tactics.suppression.is_active():
		return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	search.investigate_noise(position)
	invalidate_utility()
	_update_label()
