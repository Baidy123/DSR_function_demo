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
var fire_decision
var current_suppression
var unit_type: Node
var training: Node
var _search_was_allowed: bool = true
@onready var perception = $Perception
@onready var cover_selection = $Cover
var cover


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
	add_to_group("shot_listener")
	player = get_tree().get_first_node_in_group("player")
	actor.hit_received.connect(_on_hit_received)
	actor.reset_completed.connect(_reset_decisions)


func is_active() -> bool:
	return is_alerted and not actor.is_dead


func _reset_decisions() -> void:
	reset_actions()
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
	if actor.is_dead or not is_arena_active():
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

	# 躲藏循环优先处理。躲在墙后时“看不见玩家”是主动行为，不在这里触发丢失目标判定；
	# 如果探头后仍未重新发现玩家，由 Cover 自己进入 TRACK/SEARCH。
	if cover != null and cover.is_active():
		tactics.attack_position.reset()
		tactics.suppression.reset()
		if sees_player:
			is_alerted = true
			last_known_position = last_seen_position
			search.has_suspected_position = false
			search.search_hint_timer = 0.0
		var cover_direction: Vector3 = cover.step(delta, sees_player)
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

	elif state == State.PATROL:
		direction = actions[&"patrol"].step(delta)
	elif state in [State.INVESTIGATE, State.TRACK, State.SEARCH]:
		direction = search.step(delta)
	elif state in [State.APPROACH, State.REPOSITION, State.HOLD_POSITION]:
		direction = tactics.step(delta, sees_player)

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

	var state_text: String = cover.state_label() if cover != null and cover.is_active() else names[state]
	if tactics.attack_position.is_active():
		state_text = tactics.attack_position.state_label()
	if tactics.suppression.is_active():
		state_text = tactics.suppression.state_label()
	var type_text = "近战" if combat_type == CombatType.MELEE else "远程"
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
	tactics.ranged_has_destination = false
	tactics.ranged_repath_timer = 0.0
	agent.target_position = actor.global_position
	if sees_player:
		state = State.REPOSITION
	else:
		last_known_position = known_position
		search.begin_tracking_or_search(true)
	if cover_selection.debug_cover_selection:
		print("[AI][攻击占位] 结束：", reason, "；回到交战／追踪流程")


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
	for action in actions.values():
		action.reset()
	fire_decision.reset()
	current_suppression = actions[&"suppression"]


func cancel_action(id: StringName) -> void:
	if actions.has(id):
		actions[id].reset()
