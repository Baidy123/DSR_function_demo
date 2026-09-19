extends CharacterBody3D

enum State { IDLE, APPROACH, INVESTIGATE, SEARCH, DEAD, PATROL }

@export var move_speed: float = 2.0
@export var sight_distance: float = 10.0
@export_range(10.0, 360.0, 5.0) var sight_angle_degrees: float = 120.0
@export var search_seconds: float = 2.0
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
var search_timer: float = 0.0
var search_start_angle: float = 0.0
var health: float = 100.0
var is_dead: bool = false
var player: Node3D
var initial_transform: Transform3D
var initial_body_transform: Transform3D
var death_tween: Tween
var patrol_pause_timer: float = 0.0

@onready var agent: NavigationAgent3D = $NavigationAgent3D
@onready var arena_zone: Area3D = $"../CombatZone"


func _ready() -> void:
	initial_transform = transform
	initial_body_transform = $Body.transform
	player = get_tree().get_first_node_in_group("player")
	reset_target()


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
	search_timer = 0.0
	patrol_pause_timer = patrol_pause_seconds
	search_start_angle = rotation.y
	last_known_position = global_position
	agent.target_position = global_position
	_update_label()


func _physics_process(delta: float) -> void:
	if is_dead:
		return
	# 地图同步完成前不能请求路径。
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0:
		return
	var sees_player: bool = can_see_player()
	if sees_player:
		# 只有真正看见玩家，才能更新这个位置；墙后不会读取新位置来追踪。
		last_known_position = player.global_position
		if state != State.APPROACH or agent.target_position.distance_to(last_known_position) > 0.25:
			agent.target_position = last_known_position
		state = State.APPROACH
	elif state == State.APPROACH:
		state = State.INVESTIGATE
		agent.target_position = last_known_position

	var direction := Vector3.ZERO
	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)
		if patrol_pause_timer <= 0.0:
			_start_random_patrol()
	if state == State.APPROACH or state == State.INVESTIGATE or state == State.PATROL:
		# 每个物理帧更新导航路径；只沿导航点移动，不直冲障碍物。
		var next_position: Vector3 = agent.get_next_path_position()
		var close_to_player: bool = sees_player and _horizontal_distance(last_known_position) <= stopping_distance
		if not close_to_player and not agent.is_navigation_finished():
			direction = next_position - global_position
			direction.y = 0.0
			direction = direction.normalized()
		elif state == State.INVESTIGATE:
			state = State.SEARCH
			search_timer = search_seconds
			search_start_angle = rotation.y
		elif state == State.PATROL:
			state = State.IDLE
			patrol_pause_timer = patrol_pause_seconds
		if close_to_player:
			_face_direction(last_known_position - global_position, delta)
	elif state == State.SEARCH:
		search_timer = maxf(0.0, search_timer - delta)
		var progress: float = 1.0 - search_timer / maxf(search_seconds, 0.01)
		rotation.y = search_start_angle + sin(progress * TAU) * deg_to_rad(60.0)
		if search_timer <= 0.0:
			state = State.IDLE
			patrol_pause_timer = patrol_pause_seconds

	if not direction.is_zero_approx():
		_face_direction(direction, delta)
	velocity.x = direction.x * move_speed
	velocity.z = direction.z * move_speed
	if not is_on_floor():
		velocity += get_gravity() * delta
	else:
		velocity.y = 0.0
	move_and_slide()
	_update_label()


func _start_random_patrol() -> void:
	var region: NavigationRegion3D = $"../NavigationRegion3D"
	# 只从本竞技场的导航区域选点，避免走进连接通道或其他场地。
	for attempt in range(12):
		var destination := NavigationServer3D.region_get_random_point(region.get_rid(), agent.navigation_layers, true)
		if _horizontal_distance(destination) < 2.0:
			continue
		var path := NavigationServer3D.map_get_path(agent.get_navigation_map(), global_position, destination, true, agent.navigation_layers)
		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 0.5:
			continue
		# 烘焙网格高于脚底；目标也需换成角色脚底高度才能正确判定抵达。
		destination.y -= agent.path_height_offset
		agent.target_position = destination
		state = State.PATROL
		return
	# 没有合适的点时稍后重试，避免每一帧重复查找。
	patrol_pause_timer = maxf(patrol_pause_seconds, 0.5)


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
		player.global_position + Vector3.UP * 0.8, 1, [get_rid()])
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.collider == player


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(point.x - global_position.x, point.z - global_position.z).length()


func _face_direction(direction: Vector3, delta: float) -> void:
	if Vector2(direction.x, direction.z).is_zero_approx():
		return
	rotation.y = rotate_toward(rotation.y, atan2(-direction.x, -direction.z), deg_to_rad(turn_speed_degrees) * delta)


func receive_hit(damage: float, attacker_position: Vector3 = Vector3.INF) -> void:
	if is_dead:
		return
	health = maxf(0.0, health - maxf(damage, 0.0))
	if health <= 0.0:
		is_dead = true
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
	var angle: float = randf_range(0.0, TAU)
	var radius: float = randf_range(0.25, 1.0) * attack_position_uncertainty
	last_known_position = attacker_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	last_known_position.y = global_position.y
	state = State.INVESTIGATE
	search_timer = 0.0
	agent.target_position = last_known_position


func _update_label() -> void:
	var names := ["巡逻停留", "看见玩家", "前往最后位置", "搜索", "已死亡", "随机巡逻"]
	$Label.text = "敌人：%s\n生命 %d / %d" % [names[state], ceili(health), ceili(max_health)]
