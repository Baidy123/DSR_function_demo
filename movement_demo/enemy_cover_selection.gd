extends Node

# 掩体选位：只返回可用位置及遮挡评估，不执行转移、躲藏或开火。
## 掩体选位：朝远离威胁方向移动会得到奖励，朝威胁方向冲会被强烈惩罚。
@export_range(0.0, 10.0, 0.1) var away_from_threat_weight: float = 4.0
## 路径或掩体位置比当前位置更靠近威胁时的惩罚。
@export_range(0.0, 10.0, 0.1) var closer_to_threat_weight: float = 5.0
## 开启时额外使用所属掩体的质量门槛和评分；关闭时要求身体中心及两侧被静态墙遮挡。
## 两种模式都必须先位于威胁对侧，且中心射线被当前掩体挡住；不再手动指定 Cover Body。
@export var require_assigned_cover: bool = true
## 模拟威胁左右移动的距离（米）；仅在要求指定掩体时参与质量门槛和评分，0 表示不做横向模拟。
@export_range(0.0, 2.0, 0.1) var cover_lateral_test_distance: float = 0.5
## 要求指定掩体时，采样射线中被该墙挡住的最低比例（0～1）；中心射线还必须单独通过检查。
@export_range(0.0, 1.0, 0.05) var minimum_cover_quality: float = 0.20
## 掩护质量越高，越优先选择。
@export_range(0.0, 10.0, 0.1) var cover_quality_weight: float = 3.0
## 调试时打印区域候选数量、合格数量及最终选择的掩体和位置。
@export var debug_cover_selection: bool = true
## Debug运行时显示攻击候选评估：绿=可用，红=淘汰；只按最后目击位置查询，不控制AI动作。
@export var debug_attack_points: bool = true

@onready var ai = get_parent()
@onready var enemy = get_parent().get_parent()


func _ready() -> void:
	if OS.is_debug_build():
		var preview := preload("res://attack_point_preview.gd").new()
		preview.name = "AttackPreview"
		add_child(preview)


## 保留所有候选的评估结果，供查看淘汰原因；不改变状态、导航目的地或射击请求。
## threat_origin / target_point 均为调用者已有的信息，不在此读取玩家实时位置。
func get_attack_assessments(threat_origin: Vector3, target_point: Vector3) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for region in get_tree().get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(region):
			continue
		for point: Vector3 in region.get_attack_candidates():
			results.append(assess_attack_point(point, region, threat_origin, target_point))
	return results


func assess_attack_point(point: Vector3, region: StaticBody3D, threat_origin: Vector3, target_point: Vector3) -> Dictionary:
	var result := {"position": point, "cover": region, "space_free": false,
		"reachable": false, "clear_shot": false, "in_range": false,
		"protection": 0.0, "usable": false, "reason": "导航未就绪"}
	if not is_instance_valid(region) or not point.is_finite() or not threat_origin.is_finite() or not target_point.is_finite():
		result.reason = "无效位置"
		return result
	if NavigationServer3D.map_get_iteration_id(enemy.agent.get_navigation_map()) == 0:
		return result
	result.space_free = ai.is_position_free(point)
	var path := _path_to(enemy.global_position, point)
	# 不能把截止在另一侧导航边缘的部分路径当成到达。
	result.reachable = not path.is_empty() and ai._horizontal_distance_between(path[path.size() - 1], point) <= 0.05
	var shot_origin: Vector3 = point + (enemy.get_shot_origin() - enemy.global_position)
	result.clear_shot = shot_origin.distance_squared_to(target_point) > 0.000001 and has_clear_line(shot_origin, target_point)
	result.in_range = enemy.weapon != null and shot_origin.distance_to(target_point) <= enemy.weapon.fire_range
	result.protection = _attack_body_protection(point, threat_origin, region)
	if not result.space_free:
		result.reason = "空间被占"
	elif not result.reachable:
		result.reason = "不可达"
	elif enemy.weapon == null:
		result.reason = "无武器"
	elif not result.in_range:
		result.reason = "超射程"
	elif not result.clear_shot:
		result.reason = "射界受阻"
	elif result.protection < 0.0:
		result.reason = "身体形状不支持"
	elif is_zero_approx(result.protection):
		result.reason = "无遮挡"
	elif result.protection >= 1.0:
		result.reason = "完全遮挡"
	else:
		result.usable = true
		result.reason = "可用"
	return result


# 用现有胶囊身体中部的上/中/下 × 左/中/右共9个采样点估算，不把比例当精确面积。
# 只计所属掩体的遮挡，旁边不相关的墙不能让这个点冒充“有掩护”。
func _attack_body_protection(point: Vector3, threat_origin: Vector3, region: StaticBody3D) -> float:
	var collision: CollisionShape3D = enemy.get_node("CollisionShape3D")
	if not collision.shape is CapsuleShape3D:
		return -1.0
	var center: Vector3 = point + collision.global_position - enemy.global_position
	var direction := center - threat_origin
	direction.y = 0.0
	if direction.is_zero_approx():
		return 0.0
	var side := direction.normalized().cross(Vector3.UP)
	var radius: float = collision.shape.radius * minf(collision.global_basis.x.length(), collision.global_basis.z.length())
	var vertical: float = maxf(0.0, collision.shape.height * 0.5 - collision.shape.radius) * 0.7 * collision.global_basis.y.length()
	var protected := 0
	for height in [-vertical, 0.0, vertical]:
		for width in [-radius * 0.8, 0.0, radius * 0.8]:
			var sample: Vector3 = center + Vector3.UP * height + side * width
			var hit: Dictionary = enemy.get_world_3d().direct_space_state.intersect_ray(_ray_query(threat_origin, sample))
			if not hit.is_empty() and hit.collider == region:
				protected += 1
	return float(protected) / 9.0


func choose_cover(threat_origin: Vector3, look_position: Vector3) -> Dictionary:
	var hide_position := Vector3.ZERO
	var peek_position := Vector3.ZERO
	var best_score: float = INF
	var best_cover: StaticBody3D = null
	var current_threat_distance: float = ai._horizontal_distance_between(enemy.global_position, threat_origin)
	var candidate_count: int = 0
	var viable_count: int = 0

	# 每个掩体自己提供四面区域；候选只来自本竞技场，且已经筛到威胁的对侧。
	for region in get_tree().get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(region):
			continue
		for candidate in region.get_candidates(threat_origin, enemy.global_position):
			candidate_count += 1
			var hiding: Vector3 = candidate.hide
			if not ai.is_position_free(hiding):
				continue
			# “位于背面”还不等于真的安全：必须由当前掩体挡住射线。
			if not _center_hidden_by_cover(hiding, threat_origin, region):
				continue
			var quality: float = _cover_quality(hiding, threat_origin, region)
			if require_assigned_cover:
				if quality < minimum_cover_quality:
					continue
			elif not is_hidden_at(hiding, threat_origin):
				continue
			var path: PackedVector3Array = _path_to(enemy.global_position, hiding)
			if path.is_empty():
				continue
			var peeking: Vector3 = _choose_peek(hiding, candidate.peeks, look_position)
			if not peeking.is_finite():
				continue
			viable_count += 1

			var length: float = _path_length_from_path(path)
			var move_direction: Vector3 = hiding - enemy.global_position
			move_direction.y = 0.0
			var away_direction: Vector3 = enemy.global_position - threat_origin
			away_direction.y = 0.0
			var away_alignment: float = 0.0
			if not move_direction.is_zero_approx() and not away_direction.is_zero_approx():
				away_alignment = move_direction.normalized().dot(away_direction.normalized())
			var cover_threat_distance: float = ai._horizontal_distance_between(hiding, threat_origin)
			var min_path_distance: float = _minimum_path_distance_to_threat(path, threat_origin)

			var score: float = length
			score -= maxf(0.0, away_alignment) * away_from_threat_weight
			score += maxf(0.0, -away_alignment) * away_from_threat_weight
			score += maxf(0.0, current_threat_distance - cover_threat_distance) * closer_to_threat_weight
			score += maxf(0.0, current_threat_distance - min_path_distance) * closer_to_threat_weight
			if require_assigned_cover:
				score -= quality * cover_quality_weight
			if score < best_score:
				best_score = score
				hide_position = hiding
				peek_position = peeking
				best_cover = region

	if is_inf(best_score):
		if debug_cover_selection:
			print("[AI][掩体] 四面区域无有效躲藏/探头组合，候选=", candidate_count)
		return {}
	if debug_cover_selection:
		print("[AI][掩体] 区域选位 Cover=", best_cover.name, " Hide=", hide_position,
			" Peek=", peek_position, " 合格候选=", viable_count)
	return {"hide": hide_position, "peek": peek_position, "body": best_cover}


# 用已知威胁位置检测射界；不以墙后玩家的新坐标来调整 Peek。


func _peek_has_los(point: Vector3, look_position: Vector3) -> bool:
	return has_clear_line(point + Vector3.UP * 0.8, look_position + Vector3.UP * 0.8)


func _choose_peek(hiding: Vector3, points: Array, look_position: Vector3) -> Vector3:
	var best := Vector3.INF
	var best_length := INF
	for point: Vector3 in points:
		if not ai.is_position_free(point) or not _peek_has_los(point, look_position):
			continue
		var path := _path_to(hiding, point)
		if path.is_empty():
			continue
		var length := _path_length_from_path(path)
		if length < best_length:
			best = point
			best_length = length
	return best


func _path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), to)
	# 导航只允许厘米级水平误差；不能把墙外/地图外的点吸附到边缘后当作可达。
	# 当前烘焙导航比地面高约 0.3 米，因此高度单独留出容差。
	if ai._horizontal_distance_between(nav_point, to) > 0.05 or absf(nav_point.y - to.y) > 0.5:
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


func _selected_cover_blocks(point: Vector3, origin: Vector3, active_cover_body: StaticBody3D) -> bool:
	if not is_instance_valid(active_cover_body) or not active_cover_body.is_hiding_position(point, origin):
		return false
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
	if is_instance_valid(ai.player) and ai.player is CollisionObject3D:
		query.exclude = [enemy.get_rid(), ai.player.get_rid()]
	query.hit_from_inside = true
	return query
