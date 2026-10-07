extends RefCounted

## 每个搜索动作独有的覆盖进度。处理采样、排序、可达性和覆盖遮挡，不改变动作和导航目标。
var pending: Array[Vector3] = []
var uncovered: Array[Vector3] = []
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
	sample_count = 0

func build(shared_context, origin: Vector3, radius_setting: float, coverage_radius: float, snap_tolerance: float) -> void:
	context = shared_context
	search_origin = origin
	search_radius = radius_setting
	search_coverage_radius = coverage_radius
	search_nav_snap_tolerance = snap_tolerance
	pending.clear()
	uncovered.clear()
	sample_count = 0
	var radius: float = maxf(1.0, search_radius)
	# 均匀采样近似面积；每轮随机转动采样网，避免目标坐标固定。
	var spacing: float = maxf(0.5, maxf(search_coverage_radius * 0.5, radius / 18.0))
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


func point_cost(point: Vector3, predicted: Vector3) -> float:
	var origin: Vector3 = search_origin
	var prediction: Vector3 = origin
	var confidence := 0.0
	if context.has_visual_memory and not context.noise_search_origin.is_finite() and not context.last_seen_direction.is_zero_approx():
		prediction = predicted
		confidence = pow(0.5, context.utility_unseen_seconds / 4.0)
	var offset := point - origin
	offset.y = 0.0
	var backwards := maxf(0.0, -offset.dot(context.last_seen_direction))
	return lerpf(offset.length(), context._horizontal_distance_between(point, prediction) + backwards, confidence) + context._horizontal_distance(point) * 0.25


func take_next(prediction: Vector3) -> Dictionary:
	# 候选已有空间/路径过滤；这里只做廉价排序，选中后重新核实路径。
	while not pending.is_empty():
		var chosen_index := 0
		var best_cost := point_cost(pending[0], prediction)
		for candidate_index in range(1, pending.size()):
			var cost := point_cost(pending[candidate_index], prediction)
			if cost < best_cost:
				chosen_index = candidate_index
				best_cost = cost
		var destination: Vector3 = pending[chosen_index]
		pending.remove_at(chosen_index)
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			agent.get_navigation_map(), actor.global_position, destination, true, agent.navigation_layers
		)
		if path.is_empty() or context._horizontal_distance_between(path[path.size() - 1], destination) > 0.2:
			continue
		return {"position": destination, "path": path}
	return {}
