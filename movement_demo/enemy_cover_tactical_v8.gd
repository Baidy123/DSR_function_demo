extends Node

enum Phase { NONE, RUN_TO_COVER, HIDE, PEEK_OUT, WATCH }

@export_range(0.1, 5.0, 0.1) var shot_radius: float = 1.5
## 每次新的有效近身来弹触发“寻找掩体”的概率。0=从不找掩体，1=每次都找。
## 已经处于跑向掩体/躲藏/探头流程时不会重新掷骰子，避免连续来弹让行为反复取消。
@export_range(0.0, 1.0, 0.05) var take_cover_chance: float = 1.0
@export_range(0.1, 10.0, 0.1) var hide_seconds: float = 3.0
@export_range(0.1, 10.0, 0.1) var watch_seconds: float = 2.0
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier: float = 2.0
@export_range(0.1, 1.0, 0.1) var peek_speed_multiplier: float = 0.5
## 跑向掩体时改为“面向威胁撤退”的概率。0=永远转身跑，1=每次都掩护撤退。
@export_range(0.0, 1.0, 0.05) var covering_retreat_chance: float = 0.4
## 掩护撤退时的移动速度倍率；通常比直接冲向掩体慢。
@export_range(0.1, 1.5, 0.1) var covering_retreat_speed_multiplier: float = 0.8
## 掩体选位：朝远离威胁方向移动会得到奖励，朝威胁方向冲会被强烈惩罚。
@export_range(0.0, 10.0, 0.1) var away_from_threat_weight: float = 4.0
## 路径或掩体位置比当前位置更靠近威胁时的惩罚。
@export_range(0.0, 10.0, 0.1) var closer_to_threat_weight: float = 5.0
## 手动绑定是掩体判断的唯一依据：每个 Hide Marker3D 挂 cover_point_simple.gd，并指定自己的 Cover Body。
@export var require_assigned_cover: bool = true
## 玩家左右拉出的模拟距离；只用于“质量评分”，不会再要求所有射线 100% 通过。
@export_range(0.0, 2.0, 0.1) var cover_lateral_test_distance: float = 0.5
## 除了中心射线必须由指定墙挡住，辅助射线达到这个比例即可接受。
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
				if _selected_cover_blocks(enemy.global_position, threat_origin):
					covering_retreat = false
					phase = Phase.HIDE
					timer = hide_seconds
				else:
					# 到点后发现“自己的掩体”并没有真正挡在威胁与躲藏点之间，
					# 重新选一个正确的点；没有可用点再退出掩体行为。
					if _choose_cover():
						_start_move(Phase.RUN_TO_COVER, hide_position)
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
		if covering_retreat:
			return covering_retreat_speed_multiplier
		return run_speed_multiplier
	if phase == Phase.PEEK_OUT:
		return peek_speed_multiplier
	return 1.0


func state_label() -> String:
	if phase == Phase.RUN_TO_COVER and covering_retreat:
		return "掩护撤退"
	return ["", "跑向掩体", "掩体后躲藏", "慢慢探出", "观察最后目击位置"][phase]


func _start_move(next_phase: Phase, destination: Vector3) -> void:
	# 每次真正开始一次 RUN_TO_COVER 时只掷一次骰子。
	# 如果连续来弹只是刷新同一段跑掩体路径，不会反复切换撤退方式。
	var was_running_to_cover: bool = phase == Phase.RUN_TO_COVER
	phase = next_phase
	if phase == Phase.RUN_TO_COVER:
		if not was_running_to_cover:
			covering_retreat = randf() < covering_retreat_chance
	else:
		covering_retreat = false
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

		# 硬条件：玩家/威胁 -> Hide 中心，第一处碰撞必须是这个点手动绑定的墙。
		if require_assigned_cover:
			if not _center_hidden_by_cover(hiding, threat_origin, assigned_cover):
				rejected_cover += 1
				continue

			# 玩家左右拉出、AI身体宽度只作为“掩护质量”，不再一票否决。
			var quality: float = _cover_quality(hiding, threat_origin, assigned_cover)
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
			score -= _cover_quality(hiding, threat_origin, assigned_cover) * cover_quality_weight

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
