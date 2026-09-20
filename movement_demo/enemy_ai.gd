extends Node

# AI 统一更新各板块、保存共享目击记忆并切换主状态；板块不各自运行物理循环。
const Actor = preload("res://enemy_actor.gd")

enum State { IDLE, APPROACH, INVESTIGATE, SEARCH, DEAD, PATROL, REPOSITION, HOLD_POSITION, TRACK }
enum CombatType { MELEE, RANGED }
## 近战沿用接近行为，尚无近战攻击；远程寻找射击位置并开火。
@export var combat_type: CombatType = CombatType.MELEE


## 每次巡逻抵达后停留的时间。
@export_range(0.0, 10.0, 0.1) var patrol_pause_seconds: float = 1.5
## 受击时只知道攻击者附近区域，不持续获取攻击者坐标。
@export_range(0.0, 5.0, 0.1) var attack_position_uncertainty: float = 1.0


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
@onready var tactics = $Tactics
@onready var search = $Search
@onready var perception = $Perception
@onready var cover_selection = $Cover
@onready var cover = $Tactics/CoverAction


func _ready() -> void:
	player = get_tree().get_first_node_in_group("player")
	actor.hit_received.connect(_on_hit_received)
	actor.reset_completed.connect(_reset_decisions)


func is_active() -> bool:
	return is_alerted and not actor.is_dead


func _reset_decisions() -> void:
	tactics.reset()
	search.reset()
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
	if actor.is_dead or not is_arena_active():
		tactics.attack_position.reset()
		tactics.suppression.reset()
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
			tactics.attack_position.on_player_seen()
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
		tactics.start_suppression()
		if not tactics.attack_position.is_active() and not tactics.suppression.is_active():
			search.begin_tracking_or_search(true)

	# 没有可用方向信息时，旧的近战调查仍可走到最后目击位置再搜索。
	elif state == State.APPROACH:
		state = State.INVESTIGATE
		agent.target_position = last_known_position

	if saw_player_this_frame:
		tactics.attack_position.on_player_seen()
	var direction = Vector3.ZERO

	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)
		if patrol_pause_timer <= 0.0:
			_start_random_patrol()

	elif state == State.PATROL:
		var next_position: Vector3 = agent.get_next_path_position()
		if not agent.is_navigation_finished():
			direction = next_position - actor.global_position
			direction.y = 0.0
			direction = direction.normalized()
		else:
			state = State.IDLE
			patrol_pause_timer = patrol_pause_seconds
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
	# 激活期间不允许随机巡逻。正常情况下 SEARCH 结束时才会解除警戒。
	if is_alerted:
		return

	# 只从本竞技场的导航区域选点，避免走进连接通道或其他场地。
	for attempt in range(12):
		var destination = NavigationServer3D.region_get_random_point(
			navigation_region.get_rid(),
			agent.navigation_layers,
			true
		)

		if _horizontal_distance(destination) < 2.0:
			continue

		var path = NavigationServer3D.map_get_path(
			agent.get_navigation_map(),
			actor.global_position,
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


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z).length()


func _horizontal_distance_between(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _on_hit_received(damage: float, attacker_position: Vector3) -> void:
	if actor.is_dead:
		tactics.attack_position.reset()
		tactics.suppression.reset()
		tactics.reset_fire_timing()
		if cover != null:
			cover.reset()
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
				tactics.attack_position.on_damage_received()
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
