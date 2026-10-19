extends Node

# 掩体选位：只返回可用位置及遮挡评估，不执行转移、躲藏或开火。
## 开启时额外使用所属掩体的质量门槛和评分；关闭时要求身体中心及两侧被静态墙遮挡。
## 两种模式都必须先位于威胁对侧，且中心射线被当前掩体挡住；不再手动指定 Cover Body。
var require_assigned_cover: bool:
	get: return _training_setting(&"require_assigned_cover", true)
	set(value): _set_training_setting(&"require_assigned_cover", value)
## 模拟威胁左右移动的距离（米）；仅在要求指定掩体时参与质量门槛和评分，0 表示不做横向模拟。
var cover_lateral_test_distance: float:
	get: return _training_setting(&"cover_lateral_test_distance", 0.5)
	set(value): _set_training_setting(&"cover_lateral_test_distance", value)
## 要求指定掩体时，采样射线中被该墙挡住的最低比例（0～1）；中心射线还必须单独通过检查。
var minimum_cover_quality: float:
	get: return _training_setting(&"minimum_cover_quality", 0.20)
	set(value): _set_training_setting(&"minimum_cover_quality", value)
## 调试时打印区域候选数量、合格数量及最终选择的掩体和位置。
var debug_cover_selection: bool:
	get: return _training_setting(&"debug_cover_selection", true)
	set(value): _set_training_setting(&"debug_cover_selection", value)
## Debug运行时显示攻击区域：绿=可用，橙=未通过，暗红=内圈禁用；只用目击记忆。
var debug_attack_points: bool:
	get: return _training_setting(&"debug_attack_points", true)
	set(value): _set_training_setting(&"debug_attack_points", value)

var ai:
	get: return get_parent().context
@onready var enemy = get_parent().get_parent()
var attack_geometry = preload("res://scripts/enemy/services/enemy_attack_geometry.gd").new()
var _geometry_evaluation_depth := 0
var _environment_ray_cache: Dictionary = {}
var _environment_query: PhysicsRayQueryParameters3D
var _environment_space: PhysicsDirectSpaceState3D
var environment_ray_queries := 0


func _ready() -> void:
	if OS.is_debug_build():
		var preview := preload("res://scripts/debug/attack_point_preview.gd").new()
		preview.name = "AttackPreview"
		add_child(preview)

func begin_geometry_evaluation() -> void:
	if _geometry_evaluation_depth == 0:
		_environment_ray_cache.clear()
		_environment_query = null
		_environment_space = null
	_geometry_evaluation_depth += 1

func end_geometry_evaluation() -> void:
	assert(_geometry_evaluation_depth > 0)
	_geometry_evaluation_depth -= 1
	if _geometry_evaluation_depth == 0:
		_environment_ray_cache.clear()
		_environment_query = null
		_environment_space = null

## Only these fixed environment queries exclude actor and player; vision queries
## that must hit the player retain their own unmodified physics query.
func environment_ray(from: Vector3, to: Vector3) -> Dictionary:
	var key := [from, to]
	if _geometry_evaluation_depth > 0 and _environment_ray_cache.has(key): return _environment_ray_cache[key]
	environment_ray_queries += 1
	if _geometry_evaluation_depth <= 0:
		return enemy.get_world_3d().direct_space_state.intersect_ray(_ray_query(from, to))
	# The existing batch is synchronous and read-only. Exclusions, collision mask
	# and world are identical for these environment rays; only endpoints vary.
	# Keep _ray_query() independent because other callers may change its flags.
	if _environment_query == null:
		_environment_query = _ray_query(from, to)
		_environment_space = enemy.get_world_3d().direct_space_state
	else:
		_environment_query.from = from
		_environment_query.to = to
	var hit: Dictionary = _environment_space.intersect_ray(_environment_query)
	_environment_ray_cache[key] = hit
	return hit


## 保留所有候选的评估结果，供查看淘汰原因；不改变状态、导航目的地或射击请求。
## threat_origin / target_point 均为调用者已有的信息，不在此读取玩家实时位置。
func get_attack_assessments(threat_origin: Vector3, target_point: Vector3, known_samples: Variant = null) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for region in get_tree().get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(region):
			continue
		for cell in attack_cells(region, threat_origin):
			results.append(assess_attack_cell(cell, threat_origin, target_point, known_samples))
	return results


func attack_cells(region: StaticBody3D, threat: Vector3) -> Array[Dictionary]:
	return attack_geometry.cells(ai, region, threat)

func assess_attack_cell(cell: Dictionary, threat: Vector3, target: Vector3, known_samples: Variant = null) -> Dictionary:
	if cell.body.is_low_cover() and known_samples != null:
		target = low_cover_attack_target(cell.position, known_samples)
	var result := assess_attack_point(cell.position, cell.body, threat, target)
	result.polygon = cell.polygon
	return result

## A future standing muzzle may see a head/shoulder while the torso is blocked.
## All samples are supplied by the caller's observation snapshot.
func low_cover_attack_target(feet: Vector3, known_samples: PackedVector3Array) -> Vector3:
	var origin: Vector3 = enemy.get_posture_muzzle_position(false, feet)
	for point: Vector3 in known_samples:
		if enemy.weapon != null and origin.distance_to(point) <= enemy.weapon.fire_range and has_clear_line(origin, point) and ai.fire.has_clear_firing_lane(origin, point - origin, origin.distance_to(point)):
			return point
	return Vector3.INF


func assess_attack_point(point: Vector3, region: StaticBody3D, threat_origin: Vector3, target_point: Vector3, require_all_metrics: bool = true) -> Dictionary:
	var result := {"position": point, "cover": region, "space_free": false,
		"reachable": false, "clear_shot": false, "in_range": false,
		"protection": 0.0, "fire_quality": 0.0, "usable": false, "reason": "导航未就绪"}
	if not is_instance_valid(region) or not point.is_finite() or not threat_origin.is_finite() or not target_point.is_finite():
		result.reason = "无效位置"
		return result
	if NavigationServer3D.map_get_iteration_id(enemy.agent.get_navigation_map()) == 0:
		return result
	result.space_free = ai.is_position_free(point)
	var path := _path_to(enemy.global_position, point)
	# 不能把截止在另一侧导航边缘的部分路径当成到达。
	result.reachable = not path.is_empty() and ai._horizontal_distance_between(path[path.size() - 1], point) <= 0.05
	var shot_origin: Vector3 = enemy.get_posture_muzzle_position(false, point)
	result.clear_shot = shot_origin.distance_squared_to(target_point) > 0.000001 and has_clear_line(shot_origin, target_point)
	result.in_range = enemy.weapon != null and shot_origin.distance_to(target_point) <= enemy.weapon.fire_range
	# Budgeted action collection only needs viable destinations; the preview keeps
	# all original diagnostics. Rejected geometry cannot benefit from 35 more rays.
	if not require_all_metrics and (not result.space_free or not result.reachable or not result.clear_shot or not result.in_range):
		return result
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
	elif not region.is_low_cover() and result.protection < float(_training_setting(&"attack_minimum_protection", 0.2)):
		result.reason = "身体缺少掩护"
	elif not region.is_low_cover() and result.protection > float(_training_setting(&"attack_maximum_protection", 0.65)):
		result.reason = "身体遮挡过多"
	elif not _attack_wall_clearance(point, region):
		result.reason = "过于贴近墙角"
	elif point.distance_to(Vector3(target_point.x, point.y, target_point.z)) > maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius):
		result.reason = "超感知距离"
	elif not ai.fire.has_clear_firing_lane(shot_origin, target_point - shot_origin, shot_origin.distance_to(target_point)):
		result.reason = "枪口空间受阻"
	else:
		result.usable = true
		result.reason = "可用"
		result.fire_quality = ai.fire.firing_lane_quality(shot_origin, target_point - shot_origin, shot_origin.distance_to(target_point))
	return result


## 保留身体到墙面的余量；导航可站立并不代表贴角处适合稳定架枪。
func _attack_wall_clearance(point: Vector3, region: StaticBody3D) -> bool:
	var wall := region.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var body := enemy.get_node("CollisionShape3D") as CollisionShape3D
	if wall == null or not wall.shape is BoxShape3D or not body.shape is CapsuleShape3D:
		return false
	var local := wall.to_local(point)
	var half: Vector3 = wall.shape.size * 0.5
	# 相邻墙角的扇环可能重叠，不能借另一个扇环绕过任何墙角的禁用内圈。
	if not region.is_low_cover():
		for x in [-half.x, half.x]:
			for z in [-half.z, half.z]:
				if Vector2(local.x - x, local.z - z).length() < region.attack_inner_radius:
					return false
	var nearest := wall.to_global(Vector3(clampf(local.x, -half.x, half.x), local.y, clampf(local.z, -half.z, half.z)))
	var radius: float = body.shape.radius * maxf(body.global_basis.x.length(), body.global_basis.z.length())
	return ai._horizontal_distance_between(point, nearest) >= radius + 0.1


func _attack_body_protection(point: Vector3, threat_origin: Vector3, region: StaticBody3D) -> float:
	return attack_geometry.protection(ai, point, threat_origin, region)


## 用已知威胁位置检测探头射界，不读取墙后玩家的新坐标。
func _peek_has_los(point: Vector3, look_position: Vector3) -> bool:
	return has_clear_line(enemy.get_posture_eye_position(false, point), enemy.get_posture_eye_position(false, look_position))


var _path_frame := -1
var _path_cache: Dictionary = {}

func _path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	if _path_frame != Engine.get_physics_frames():
		_path_frame = Engine.get_physics_frames()
		_path_cache.clear()
	var key := [from, to, enemy.agent.navigation_layers, NavigationServer3D.map_get_iteration_id(enemy.agent.get_navigation_map())]
	if not _path_cache.has(key): _path_cache[key] = _query_path_to(from, to)
	var path: PackedVector3Array = _path_cache[key]
	return PackedVector3Array() if ai.is_ally_path_blocked(from, path) else path

func _query_path_to(from: Vector3, to: Vector3) -> PackedVector3Array:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(ai.navigation_region.get_rid(), to)
	# 导航只允许厘米级水平误差；不能把墙外/地图外的点吸附到边缘后当作可达。
	# 当前烘焙导航比地面高约 0.3 米，因此高度单独留出容差。
	if ai._horizontal_distance_between(nav_point, to) > 0.05 or absf(nav_point.y - to.y) > 0.5:
		return PackedVector3Array()
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		enemy.agent.get_navigation_map(), from, nav_point, true, enemy.agent.navigation_layers)
	# A partial path can end near a disconnected island. Vertical bake tolerance
	# must not also permit half a metre of missing horizontal connectivity.
	if path.is_empty() or ai._horizontal_distance_between(path[path.size() - 1], to) > 0.05 or absf(path[path.size() - 1].y - nav_point.y) > 0.5:
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


func _selected_cover_blocks(point: Vector3, origin: Vector3, active_cover_body: StaticBody3D, crouched: bool = false) -> bool:
	if not is_instance_valid(active_cover_body) or not active_cover_body.is_hiding_position(point, origin):
		return false
	if require_assigned_cover:
		return (
			is_instance_valid(active_cover_body)
			and _center_hidden_by_cover(point, origin, active_cover_body, crouched)
		)
	return is_hidden_at(point, origin)


func _center_hidden_by_cover(
	point: Vector3,
	origin: Vector3,
	expected_cover: StaticBody3D,
	crouched: bool = false
) -> bool:
	if not is_instance_valid(expected_cover):
		return false

	var hit: Dictionary = environment_ray(origin, enemy.get_posture_eye_position(crouched, point))
	return not hit.is_empty() and hit.collider == expected_cover


func _cover_quality(
	point: Vector3,
	origin: Vector3,
	expected_cover: StaticBody3D,
	crouched: bool = false
) -> float:
	if not is_instance_valid(expected_cover):
		return 0.0

	var target_center: Vector3 = enemy.get_posture_eye_position(crouched, point)
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
			var hit: Dictionary = environment_ray(origin + threat_offset, target_center + body_offset)

			if not hit.is_empty() and hit.collider == expected_cover:
				protected += 1

	if total <= 0:
		return 0.0
	return float(protected) / float(total)


func is_hidden_at(point: Vector3, origin: Vector3) -> bool:
	# 中心和身体两侧都应被墙挡住，避免停在墙角时半个身子仍暴露。
	var direction: Vector3 = enemy.get_posture_eye_position(false, point) - origin
	direction.y = 0.0
	var side: Vector3 = direction.normalized().cross(Vector3.UP) * 0.4
	var body_offsets: Array[Vector3] = [Vector3.ZERO, side, -side]
	for offset: Vector3 in body_offsets:
		var hit: Dictionary = environment_ray(origin, enemy.get_posture_eye_position(false, point) + offset)
		if hit.is_empty() or not hit.collider is StaticBody3D:
			return false
	return true


func has_clear_line(from: Vector3, to: Vector3) -> bool:
	if from.distance_squared_to(to) < 0.000001:
		return true
	return environment_ray(from, to).is_empty()


## 先确认冻结线索的实际遮挡归属，再评估该墙出口；不能因出口不可射改认邻墙。
func suppression_geometry(known: Vector3) -> Dictionary:
	var region := confirmed_suppression_cover(known)
	if region == null: return {}
	var geometry := _suppression_cover_geometry(region, known)
	if geometry.is_empty(): return {}
	var box := region.get_node("CollisionShape3D") as CollisionShape3D
	var half: Vector3 = box.shape.size * 0.5
	var local := box.to_local(known)
	var surface := box.to_global(Vector3(clampf(local.x, -half.x, half.x), local.y, clampf(local.z, -half.z, half.z)))
	var inference_distance: float = _training_setting(&"cover_inference_distance", 1.75)
	geometry.confidence = 1.0 - 0.5 * clampf(ai._horizontal_distance_between(known, surface) / maxf(0.1, inference_distance), 0.0, 1.0)
	return geometry


## 只读冻结脚底点与静态遮挡。正反射线必须指向同一墙，拒绝前后叠墙和身体采样的歧义。
func confirmed_suppression_cover(known: Vector3) -> StaticBody3D:
	if not known.is_finite(): return null
	var origin: Vector3 = enemy.get_shot_origin()
	# 低墙可能挡腿而不挡眼睛；这里不读取目标当前是否蹲下。
	var low_point := known + Vector3.UP * 0.15
	var hit: Dictionary = environment_ray(origin, low_point)
	var region := hit.get("collider") as StaticBody3D
	if region == null or not region.is_in_group("cover_region") or not ai.navigation_region.is_ancestor_of(region): return null
	var box := region.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if box == null or box.disabled or not box.shape is BoxShape3D or (region.collision_layer & 1) == 0: return null
	var half: Vector3 = box.shape.size * 0.5
	var local := box.to_local(known)
	var surface := box.to_global(Vector3(clampf(local.x, -half.x, half.x), local.y, clampf(local.z, -half.z, half.z)))
	if ai._horizontal_distance_between(known, surface) > float(_training_setting(&"cover_inference_distance", 1.75)): return null
	var direction: Vector3 = known - enemy.global_position
	direction.y = 0.0
	var radius: float = enemy.get_node("CollisionShape3D").shape.radius
	var side: Vector3 = direction.normalized().cross(Vector3.UP) * radius * 0.75
	for target: Vector3 in [low_point, low_point + side, low_point - side, known + Vector3.UP * enemy.get_posture_body_height(false) * 0.5]:
		var forward: Dictionary = environment_ray(origin, target)
		var backward: Dictionary = environment_ray(target, origin)
		if forward.is_empty() and backward.is_empty(): continue
		if forward.get("collider") != region or backward.get("collider") != region: return null
	return region


func _suppression_cover_geometry(region: StaticBody3D, known: Vector3) -> Dictionary:
	if not is_instance_valid(region) or confirmed_suppression_cover(known) != region: return {}
	var box := region.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var body := enemy.get_node("CollisionShape3D") as CollisionShape3D
	if box == null or box.disabled or not box.shape is BoxShape3D or (region.collision_layer & 1) == 0: return {}
	if not body.shape is CapsuleShape3D: return {}
	var half: Vector3 = box.shape.size * 0.5
	var observer := box.to_local(enemy.global_position)
	# 使用面向敌人的墙面两端；从短边观察时不能仍取长轴出口。
	var along_x := absf(observer.z) / half.z >= absf(observer.x) / half.x
	var along_axis := box.global_basis.x if along_x else box.global_basis.z
	var across_axis := box.global_basis.z if along_x else box.global_basis.x
	var half_along: float = half.x if along_x else half.z
	var half_across: float = half.z if along_x else half.x
	var side := signf(observer.z if along_x else observer.x)
	if is_zero_approx(side): return {}
	var radius: float = body.shape.radius * maxf(body.global_basis.x.length(), body.global_basis.z.length())
	var margin_along := (radius + 0.1) / along_axis.length()
	var margin_across := (radius + 0.1) / across_axis.length()
	var memory := box.to_local(known)
	var memory_along: float = memory.x if along_x else memory.z
	var memory_across: float = memory.z if along_x else memory.x
	# 正面中部的邻墙不代表玩家躲在墙后；记忆应在背侧或接近能绕出的端部。
	if memory_across * side > half_across and absf(memory_along) < half_along - margin_along: return {}
	var result := {"body": region, "first": [], "second": [], "open_sides": 0, "balance": 0.0}
	var centers: Array[Vector3] = []
	for end in [-1.0, 1.0]:
		var points: Array[Vector3] = []
		var passable := false
		centers.append(_suppression_point(box, along_x, end * (half_along + margin_along), side * (half_across + margin_across)))
		# 小范围的端部通道，独立于攻击站位的270度扇环，避免打到无关区域。
		for offset in [0.0, 0.15, 0.3]:
			var along: float = end * (half_along + margin_along + offset / along_axis.length())
			var start := _suppression_point(box, along_x, along, -side * (half_across + margin_across))
			var finish := _suppression_point(box, along_x, along, side * (half_across + margin_across))
			if not suppression_passage_free(start, finish): continue
			passable = true
			# 瞄准身体绕出墙后的可见入口；墙厚中线在斜视角下仍可能被本墙遮住。
			var target: Vector3 = enemy.get_posture_eye_position(true, finish)
			if enemy.weapon != null and enemy.get_shot_origin().distance_to(target) <= enemy.weapon.fire_range and has_clear_line(enemy.get_shot_origin(), target):
				points.append(target)
		result["first" if end < 0.0 else "second"] = points
		result.open_sides += int(passable)
	var first_distance: float = ai._horizontal_distance_between(enemy.global_position, centers[0])
	var second_distance: float = ai._horizontal_distance_between(enemy.global_position, centers[1])
	# 归一化到两出口间距：0=基本站在一端，1=到两端等距；不读取玩家位置。
	result.balance = 1.0 - clampf(absf(first_distance - second_distance) / maxf(0.1, centers[0].distance_to(centers[1])), 0.0, 1.0)
	return result


func _suppression_point(box: CollisionShape3D, along_x: bool, along: float, across: float) -> Vector3:
	return box.to_global(Vector3(along, -box.shape.size.y * 0.5, across) if along_x else Vector3(across, -box.shape.size.y * 0.5, along))


## 扫过完整身体，不能把射线穿得过的窄缝或孤立落脚点当成出入口。
func suppression_passage_free(start: Vector3, finish: Vector3) -> bool:
	var body := enemy.get_node("CollisionShape3D") as CollisionShape3D
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = body.shape
	query.transform = Transform3D(body.global_basis, start + body.global_position - enemy.global_position + Vector3.UP * 0.05)
	query.collision_mask = enemy.collision_mask
	query.exclude = _ray_query(start, finish).exclude
	query.margin = 0.02
	var space: PhysicsDirectSpaceState3D = enemy.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	query.motion = finish - start
	var travel: PackedFloat32Array = space.cast_motion(query)
	if travel[0] < 1.0: return false
	query.transform.origin += query.motion
	query.motion = Vector3.ZERO
	return space.intersect_shape(query, 1).is_empty()


func _ray_query(from: Vector3, to: Vector3) -> PhysicsRayQueryParameters3D:
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to, 1, [enemy.get_rid()])
	if is_instance_valid(ai.player) and ai.player is CollisionObject3D:
		query.exclude = [enemy.get_rid(), ai.player.get_rid()]
	query.hit_from_inside = true
	return query

# 原属性名转发至Training，避免维护两份配置。
func _training_setting(key: StringName, fallback: Variant) -> Variant:
	return ai.setting(&"selection", key, fallback)


func _set_training_setting(key: StringName, value: Variant) -> void:
	if ai.training != null: ai.training.set_setting(&"selection", key, value)
