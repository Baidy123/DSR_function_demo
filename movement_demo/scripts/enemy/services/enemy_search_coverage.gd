extends RefCounted

## 每个搜索动作独有的覆盖进度。处理采样、排序、可达性和覆盖遮挡，不改变动作和导航目标。
var pending: Array[Vector3] = []
var uncovered: Array[Vector3] = []
## 优先核实的既有掩体出口；不改变区域面积样本与覆盖率分母。
var focus_points: Array[Vector3] = []
var sample_count := 0
var context
var search_origin := Vector3.ZERO
var search_radius := 1.0
var search_coverage_radius := 1.0
var search_nav_snap_tolerance := 0.65
var actor:
	get: return context.actor
var agent:
	get: return context.agent

func reset() -> void:
	pending.clear()
	uncovered.clear()
	focus_points.clear()
	sample_count = 0

func build(shared_context, origin: Vector3, radius_setting: float, coverage_radius: float, snap_tolerance: float) -> void:
	context = shared_context
	search_origin = origin
	search_radius = radius_setting
	search_coverage_radius = coverage_radius
	search_nav_snap_tolerance = snap_tolerance
	pending.clear()
	uncovered.clear()
	focus_points.clear()
	sample_count = 0
	var radius: float = maxf(1.0, search_radius)
	# 均匀采样近似面积；每轮随机转动采样网，避免目标坐标固定。
	var spacing: float = maxf(0.5, maxf(search_coverage_radius * 0.5, radius / 18.0))
	if _uses_team_grid():
		# 合作者使用同一世界格；共享的已查点可精确匹配，不把墙另一侧的近点算作已观察。
		for x in range(int(floor((search_origin.x - radius) / spacing)), int(ceil((search_origin.x + radius) / spacing)) + 1):
			for z in range(int(floor((search_origin.z - radius) / spacing)), int(ceil((search_origin.z + radius) / spacing)) + 1):
				var point := Vector3(x * spacing, search_origin.y, z * spacing)
				if context._horizontal_distance_between(point, search_origin) <= radius: _append_point(point)
		uncovered.assign(pending)
		sample_count = uncovered.size()
		return
	var angle: float = randf() * TAU
	var extent: int = int(ceil(radius / spacing))
	for x in range(-extent, extent + 1):
		for z in range(-extent, extent + 1):
			var offset = Vector3(x * spacing, 0, z * spacing)
			if offset.length() > radius:
				continue
			_append_point(search_origin + offset.rotated(Vector3.UP, angle))
	uncovered.assign(pending)
	sample_count = uncovered.size()


func _append_point(raw_point: Vector3) -> bool:
	var nav_point: Vector3 = NavigationServer3D.region_get_closest_point(
		context.navigation_region.get_rid(), raw_point
	)
	if context._horizontal_distance_between(raw_point, nav_point) > search_nav_snap_tolerance:
		return false
	var destination = Vector3(nav_point.x, actor.global_position.y, nav_point.z)
	if context._horizontal_distance_between(destination, search_origin) > search_radius:
		return false
	if not context.is_position_free(destination):
		return false
	# 只统计本轮起点所在连通区域内可达的地面。
	var path: PackedVector3Array = NavigationServer3D.map_get_path(
		agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
	)
	if path.is_empty() or context._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
		return false
	for existing: Vector3 in pending:
		if context._horizontal_distance_between(existing, destination) < 0.3:
			return false
	pending.append(destination)
	return true


func fraction() -> float:
	if sample_count == 0:
		return 1.0
	return 1.0 - float(uncovered.size()) / float(sample_count)


func mark(point: Vector3) -> void:
	# 仍只在到达调查点时计数；用实际站位检查遮挡，不能隔墙排除藏身处。
	# 复用感知的视角、距离和环境射线，不以隐藏玩家身体作为覆盖探针。
	var covered: Dictionary = {}
	for index in range(uncovered.size() - 1, -1, -1):
		var sample: Vector3 = uncovered[index]
		if context._horizontal_distance_between(point, sample) <= search_coverage_radius \
			and context.perception.can_observe_position(sample):
			covered[sample] = true
			uncovered.remove_at(index)
	for index in range(pending.size() - 1, -1, -1):
		if covered.has(pending[index]):
			pending.remove_at(index)
	if context.cooperation_enabled() and not covered.is_empty():
		var observed := PackedVector3Array()
		for sample: Vector3 in covered: observed.append(sample)
		context.cooperation_publish_checked(observed)


func _uses_team_grid() -> bool:
	if not context.cooperation_enabled(): return false
	for member: Dictionary in context.cooperation_snapshot().get("members", []):
		if int(member.get("id", 0)) != actor.get_instance_id() and member.get("can_cooperate", false): return true
	return false


func _available(point: Vector3, checked: Dictionary) -> bool:
	if not context.cooperation_enabled(): return true
	if not context.cooperation_search_available(point, float(context.setting(&"cooperation", &"search_claim_radius", 1.0))): return false
	# 只排除同一个量化地面样本；共享负证据不修改个人覆盖率，过期后仍能重新选中。
	var key := point.snapped(Vector3.ONE * 0.01)
	return not checked.has(key)


func point_cost(point: Vector3, predicted: Vector3, evidence: Dictionary = {}) -> float:
	var origin: Vector3 = search_origin
	var prediction: Vector3 = origin
	var confidence := 0.0
	if evidence.is_empty(): evidence = context.cooperation_target_evidence()
	var direction: Vector3 = evidence.get("direction", context.last_seen_direction)
	var age: float = maxf(0.0, context.evidence_elapsed_seconds - float(evidence.get("captured_at", context.evidence_elapsed_seconds - context.utility_unseen_seconds)))
	if context.has_combat_contact() and not context.noise_search_origin.is_finite() and not direction.is_zero_approx():
		prediction = predicted
		confidence = pow(0.5, age / 4.0)
	var offset := point - origin
	offset.y = 0.0
	var backwards := maxf(0.0, -offset.dot(direction))
	return lerpf(offset.length(), context._horizontal_distance_between(point, prediction) + backwards, confidence) + context._horizontal_distance(point) * 0.25


func prepare_focus(checked: Array[Vector3]) -> void:
	focus_points.clear()
	# 只查看最后目击附近至多两个已有掩体，每个取当前面两端；不推测隐藏玩家位置。
	var nearby: Array[Dictionary] = []
	for region in context.spatial.regions():
		var box := region.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if box == null or box.disabled or not box.shape is BoxShape3D or (region.collision_layer & 1) == 0: continue
		var half: Vector3 = box.shape.size * 0.5
		var local: Vector3 = box.to_local(search_origin)
		var surface: Vector3 = box.to_global(Vector3(clampf(local.x, -half.x, half.x), local.y, clampf(local.z, -half.z, half.z)))
		var distance: float = context._horizontal_distance_between(search_origin, surface)
		if distance <= float(context.setting(&"selection", &"cover_inference_distance", 1.75)):
			nearby.append({"body": region, "distance": distance})
	nearby.sort_custom(func(a, b): return a.distance < b.distance)
	for index in mini(2, nearby.size()):
		var peeks: Array[Vector3] = []
		var nearest := INF
		for candidate in nearby[index].body.get_candidates(search_origin + Vector3.UP * 0.8, actor.global_position):
			var distance: float = context._horizontal_distance(candidate.hide)
			if distance < nearest:
				nearest = distance
				peeks.assign(candidate.peeks)
		for point in peeks:
			var nav: Vector3 = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), point)
			var destination := Vector3(nav.x, actor.global_position.y, nav.z)
			if context._horizontal_distance_between(point, destination) > search_nav_snap_tolerance or context._horizontal_distance_between(search_origin, destination) > search_radius: continue
			if checked.any(func(previous): return previous.distance_to(destination) < 0.75) or focus_points.any(func(previous): return previous.distance_to(destination) < 0.3): continue
			if context.is_position_free(destination): focus_points.append(destination)


func _take_focus(prediction: Vector3, checked: Dictionary = {}, evidence: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	var best_cost := INF
	var chosen := -1
	for index in range(focus_points.size() - 1, -1, -1):
		var point: Vector3 = focus_points[index]
		if not _available(point, checked): continue
		var path: PackedVector3Array = context.cover_selection._path_to(actor.global_position, point)
		if path.is_empty() or not context.is_position_free(point):
			focus_points.remove_at(index)
			# 逆序删除仅移动此前已选的更高索引。
			if chosen > index: chosen -= 1
			continue
		var cost: float = point_cost(point, prediction, evidence) + context.cover_selection._path_length_from_path(path) * 0.35
		if cost < best_cost:
			chosen = index
			best_cost = cost
			best = {"position": point, "path": path}
	if chosen >= 0: focus_points.remove_at(chosen)
	return best


func take_next(prediction: Vector3, prefer_focus: bool = false) -> Dictionary:
	var checked: Dictionary = {}
	var evidence: Dictionary = context.cooperation_target_evidence()
	if context.cooperation_enabled():
		for report: Dictionary in context.cooperation_checked_points():
			var observed: Vector3 = report.get("position", Vector3.INF)
			if observed.is_finite() and float(report.get("valid_until", 0.0)) > context.evidence_elapsed_seconds and float(report.get("observed_at", -INF)) >= float(evidence.get("captured_at", -INF)):
				checked[observed.snapped(Vector3.ONE * 0.01)] = true
	if prefer_focus:
		var focus := _take_focus(prediction, checked, evidence)
		if not focus.is_empty(): return focus
	# 候选已有空间/路径过滤；这里只做廉价排序，选中后重新核实路径。
	while not pending.is_empty():
		var chosen_index := -1
		var best_cost := INF
		for candidate_index in range(pending.size()):
			if not _available(pending[candidate_index], checked): continue
			var cost := point_cost(pending[candidate_index], prediction, evidence)
			if cost < best_cost:
				chosen_index = candidate_index
				best_cost = cost
		if chosen_index < 0: return {}
		var destination: Vector3 = pending[chosen_index]
		pending.remove_at(chosen_index)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
		)
		if path.is_empty() or context._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
			continue
		return {"position": destination, "path": path}
	return {}
