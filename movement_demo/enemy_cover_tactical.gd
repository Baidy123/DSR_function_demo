extends Node

enum Phase { NONE, RUN_TO_COVER, HIDE, PEEK_OUT, WATCH }

@export_range(0.1, 5.0, 0.1) var shot_radius: float = 1.5
@export_range(0.1, 10.0, 0.1) var hide_seconds: float = 3.0
@export_range(0.1, 10.0, 0.1) var watch_seconds: float = 2.0
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier: float = 2.0
@export_range(0.1, 1.0, 0.1) var peek_speed_multiplier: float = 0.5
## 掩体选位：朝远离威胁方向移动会得到奖励，朝威胁方向冲会被强烈惩罚。
@export_range(0.0, 10.0, 0.1) var away_from_threat_weight: float = 4.0
## 路径或掩体位置比当前位置更靠近威胁时的惩罚。
@export_range(0.0, 10.0, 0.1) var closer_to_threat_weight: float = 5.0

var phase: Phase = Phase.NONE
var hide_position: Vector3
var peek_position: Vector3
var look_position: Vector3
var threat_origin: Vector3
var timer: float = 0.0

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


func is_active() -> bool:
	return phase != Phase.NONE


# 收到的是已经被第一个碰撞物截断的实际弹道，不是无限延长的射线。
func notice_shot(origin: Vector3, endpoint: Vector3) -> void:
	if enemy.is_dead or enemy.combat_type != enemy.CombatType.RANGED:
		return
	var chest: Vector3 = enemy.global_position + Vector3.UP * 0.8
	var closest: Vector3 = Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
	if chest.distance_to(closest) > shot_radius:
		return
	# 警戒球可能伸到墙另一侧；墙挡住近处弹道时不能隔墙触发。
	if not has_clear_line(chest, closest):
		return
	enemy._investigate_attack(origin - Vector3.UP * 0.8)
	look_position = enemy.last_seen_position if enemy.has_seen_player else enemy.last_known_position
	threat_origin = origin
	var can_reuse := is_active() and is_hidden_at(hide_position, origin) and has_clear_line(
		peek_position + Vector3.UP * 0.8, look_position + Vector3.UP * 0.8)
	if not can_reuse and not _choose_cover():
		reset()
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
		look_position = enemy.last_seen_position
	timer = maxf(0.0, timer - delta)
	if phase == Phase.HIDE:
		if timer <= 0.0:
			_start_move(Phase.PEEK_OUT, peek_position)
		return Vector3.ZERO
	if phase == Phase.WATCH:
		if sees_player or timer <= 0.0:
			_finish(sees_player)
		return Vector3.ZERO
	if phase == Phase.RUN_TO_COVER or phase == Phase.PEEK_OUT:
		var next_position: Vector3 = enemy.agent.get_next_path_position()
		var destination: Vector3 = hide_position if phase == Phase.RUN_TO_COVER else peek_position
		if enemy.agent.is_navigation_finished():
			if enemy._horizontal_distance(destination) > 0.7:
				_finish(sees_player)
			elif phase == Phase.RUN_TO_COVER:
				if is_hidden_at(enemy.global_position, threat_origin):
					phase = Phase.HIDE
					timer = hide_seconds
				else:
					_finish(sees_player)
			else:
				phase = Phase.WATCH
				timer = watch_seconds
			return Vector3.ZERO
		if timer <= 0.0:
			# 点位被挪动或路径堵死时退出，避免永久卡在跑向掩体。
			_finish(sees_player)
			return Vector3.ZERO
		var direction: Vector3 = next_position - enemy.global_position
		direction.y = 0.0
		return direction.normalized()
	return Vector3.ZERO


func movement_multiplier() -> float:
	if phase == Phase.RUN_TO_COVER:
		return run_speed_multiplier
	if phase == Phase.PEEK_OUT:
		return peek_speed_multiplier
	return 1.0


func state_label() -> String:
	return ["", "跑向掩体", "掩体后躲藏", "慢慢探出", "观察最后目击位置"][phase]


func _start_move(next_phase: Phase, destination: Vector3) -> void:
	phase = next_phase
	enemy.agent.target_position = destination
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
		return false

	var best_score: float = INF
	var current_threat_distance: float = enemy._horizontal_distance_between(enemy.global_position, threat_origin)

	for point in points.get_children():
		var peek = point.get_node_or_null("Peek")
		if not point is Marker3D or not peek is Marker3D:
			continue

		var hiding: Vector3 = point.global_position
		var peeking: Vector3 = peek.global_position
		if not enemy._ranged_point_is_free(hiding) or not enemy._ranged_point_is_free(peeking):
			continue
		if not is_hidden_at(hiding, threat_origin):
			continue
		if not has_clear_line(peeking + Vector3.UP * 0.8, look_position + Vector3.UP * 0.8):
			continue

		var path: PackedVector3Array = _path_to(enemy.global_position, hiding)
		var peek_path: PackedVector3Array = _path_to(hiding, peeking)
		if path.is_empty() or peek_path.is_empty():
			continue

		var length: float = _path_length_from_path(path)
		var move_direction: Vector3 = hiding - enemy.global_position
		move_direction.y = 0.0
		var away_direction: Vector3 = enemy.global_position - threat_origin
		away_direction.y = 0.0

		var away_alignment: float = 0.0
		if not move_direction.is_zero_approx() and not away_direction.is_zero_approx():
			away_alignment = move_direction.normalized().dot(away_direction.normalized())

		var cover_threat_distance: float = enemy._horizontal_distance_between(hiding, threat_origin)
		var min_path_distance: float = _minimum_path_distance_to_threat(path, threat_origin)

		# 分数越低越好：短路径是基础，但安全方向可以压过“最近掩体”。
		var score: float = length
		score -= maxf(0.0, away_alignment) * away_from_threat_weight
		score += maxf(0.0, -away_alignment) * away_from_threat_weight
		score += maxf(0.0, current_threat_distance - cover_threat_distance) * closer_to_threat_weight
		score += maxf(0.0, current_threat_distance - min_path_distance) * closer_to_threat_weight

		if score < best_score:
			best_score = score
			hide_position = hiding
			peek_position = peeking

	return not is_inf(best_score)


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
