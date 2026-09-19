extends Node

enum Phase { NONE, RUN_TO_COVER, HIDE, PEEK_OUT, WATCH }

@export_range(0.1, 5.0, 0.1) var shot_radius: float = 1.5
@export_range(0.1, 10.0, 0.1) var hide_seconds: float = 3.0
@export_range(0.1, 10.0, 0.1) var watch_seconds: float = 2.0
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier: float = 2.0
@export_range(0.1, 1.0, 0.1) var peek_speed_multiplier: float = 0.5

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
	var closest := Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
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
		var destination := hide_position if phase == Phase.RUN_TO_COVER else peek_position
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
	var length := _path_length(enemy.global_position, destination)
	timer = length / maxf(0.1, enemy.move_speed * movement_multiplier()) + 2.0
	if is_inf(timer):
		timer = 0.0


func _finish(sees_player: bool) -> void:
	var remembered := look_position
	reset()
	enemy.ranged_has_destination = false
	enemy.ranged_repath_timer = 0.0
	enemy.agent.target_position = enemy.global_position
	if sees_player:
		enemy.state = enemy.State.REPOSITION
	else:
		enemy.last_known_position = remembered
		enemy._begin_search()


func _choose_cover() -> bool:
	var points = enemy.get_parent().get_node_or_null("CoverPositions")
	if points == null:
		return false
	var best_length := INF
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
		var length := _path_length(enemy.global_position, hiding)
		if is_inf(length) or is_inf(_path_length(hiding, peeking)):
			continue
		if length < best_length:
			best_length = length
			hide_position = hiding
			peek_position = peeking
	return not is_inf(best_length)


func _path_length(from: Vector3, to: Vector3) -> float:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(enemy.navigation_region.get_rid(), to)
	if enemy._horizontal_distance_between(nav_point, to) > 0.6:
		return INF
	var path := NavigationServer3D.map_get_path(
		enemy.agent.get_navigation_map(), from, nav_point, true, enemy.agent.navigation_layers)
	if path.is_empty() or path[path.size() - 1].distance_to(nav_point) > 0.5:
		return INF
	var length := 0.0
	for index in range(1, path.size()):
		length += path[index - 1].distance_to(path[index])
	return length


func is_hidden_at(point: Vector3, origin: Vector3) -> bool:
	# 中心和身体两侧都应被墙挡住，避免停在墙角时半个身子仍暴露。
	var direction := point + Vector3.UP * 0.8 - origin
	direction.y = 0.0
	var side := direction.normalized().cross(Vector3.UP) * 0.4
	for offset in [Vector3.ZERO, side, -side]:
		var query := _ray_query(origin, point + Vector3.UP * 0.8 + offset)
		var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or not hit.collider is StaticBody3D:
			return false
	return true


func has_clear_line(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.000001:
		return true
	return enemy.get_world_3d().direct_space_state.intersect_ray(_ray_query(from, to)).is_empty()


func _ray_query(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1, [enemy.get_rid()])
	if is_instance_valid(enemy.player) and enemy.player is CollisionObject3D:
		query.exclude = [enemy.get_rid(), enemy.player.get_rid()]
	query.hit_from_inside = true
	return query
