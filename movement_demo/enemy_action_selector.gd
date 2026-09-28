extends RefCounted

## 空间查询分摊到物理帧；每帧同时限制候选数量和耗时，不在工作线程调用物理查询。
const EVALUATION_POINTS_PER_FRAME := 24
const EVALUATION_BUDGET_USEC := 2000
const CACHED_DESTINATIONS := 6
const CACHE_LIFETIME_MSEC := 2000
var last_evaluation_usec := 0
var last_evaluated_count := 0
var total_evaluated_count := 0
var completed_attack_passes := 0
var _last_evaluation_frame := -1
var _attack_points: Array[Dictionary] = []
var _cover_points: Array[Dictionary] = []
var _engage_points: Array[Vector3] = []
var _engage_cache: Array[Dictionary] = []
var _engage_cursor := 0
var _attack_cursor := 0
var _cover_cursor := 0
var _evaluation_turn := 0
var _attack_cache: Array[Dictionary] = []
var _cover_cache: Array[Dictionary] = []
var _context_position := Vector3.INF
var _context_threat := Vector3.INF
var _context_weapon: Resource
var _context_reloading := false
var _geometry_signature := 0


func reset_evaluation() -> void:
	_attack_points.clear()
	_cover_points.clear()
	_engage_points.clear()
	_engage_cache.clear()
	_engage_cursor = 0
	_attack_cache.clear()
	_cover_cache.clear()
	_attack_cursor = 0
	_cover_cursor = 0
	_evaluation_turn = 0
	_last_evaluation_frame = -1
	_context_position = Vector3.INF
	_context_threat = Vector3.INF
	_geometry_signature = 0
	last_evaluation_usec = 0
	last_evaluated_count = 0
	total_evaluated_count = 0
	completed_attack_passes = 0


func cached_candidate_count() -> int:
	return _attack_cache.size() + _cover_cache.size() + _engage_cache.size()


func advance_evaluation(ai: Node, sees_player: bool) -> void:
	var frame := Engine.get_physics_frames()
	if frame == _last_evaluation_frame:
		return
	_last_evaluation_frame = frame
	var started := Time.get_ticks_usec()
	last_evaluated_count = 0
	var threat: Vector3 = ai._known_reload_threat()
	if not threat.is_finite() or ai.search.noise_search_origin.is_finite() or not ai.actor.can_use_firearms() or ai.actor.move_speed <= 0.0:
		_attack_cache.clear()
		_cover_cache.clear()
		_engage_cache.clear()
		last_evaluation_usec = Time.get_ticks_usec() - started
		return
	var regions: Array = []
	var geometry: Array = [NavigationServer3D.map_get_iteration_id(ai.agent.get_navigation_map())]
	for region in ai.get_tree().get_nodes_in_group("cover_region"):
		if not ai.navigation_region.is_ancestor_of(region):
			continue
		regions.append(region)
		var collision: CollisionShape3D = region.get_node_or_null("CollisionShape3D")
		geometry.append([region.get_instance_id(), collision.global_transform, collision.shape.size,
			region.hide_length_ratio, region.short_hide_length_ratio, region.hide_depth,
			region.wall_gap, region.sample_spacing, region.attack_inner_radius,
			region.attack_outer_radius, region.attack_sample_spacing])
	var signature := hash(geometry)
	var geometry_changed := signature != _geometry_signature
	var context_changed: bool = (not _context_position.is_finite()
		or _context_position.distance_to(ai.actor.global_position) > 0.5
		or not _context_threat.is_finite() or _context_threat.distance_to(threat) > 0.25
		or _context_weapon != ai.actor.weapon or _context_reloading != ai.actor.ammo.is_reloading)
	if geometry_changed or context_changed:
		_attack_cache.clear()
		_cover_cache.clear()
		_engage_cache.clear()
		_engage_points = ai.tactics.get_engagement_candidate_points()
		if not _engage_points.is_empty():
			_engage_cursor %= _engage_points.size()
		_context_position = ai.actor.global_position
		_context_threat = threat
		_context_weapon = ai.actor.weapon
		_context_reloading = ai.actor.ammo.is_reloading
		_cover_points.clear()
		for region in regions:
			for candidate: Dictionary in region.get_candidates(threat + Vector3.UP * 0.8, ai.actor.global_position):
				_cover_points.append({"hide": candidate.hide, "body": region})
		# 威胁移动只清理结果，保留扫描游标，避免后面的墙角永远没有机会。
		if not _cover_points.is_empty():
			_cover_cursor %= _cover_points.size()
	if geometry_changed:
		_geometry_signature = signature
		_attack_points.clear()
		for region in regions:
			for point: Vector3 in region.get_attack_candidates():
				_attack_points.append({"position": point, "body": region})
		if not _attack_points.is_empty():
			_attack_cursor %= _attack_points.size()
	_prune_cache(_cover_cache)
	_prune_cache(_attack_cache)
	var can_cover: bool = ai.can_use_action(&"cover") and ai.combat_type == ai.CombatType.RANGED and not _cover_points.is_empty()
	var can_attack: bool = ai.can_use_action(&"attack_position") and ai.tactics.can_use_attack_positions and not _attack_points.is_empty()
	var can_engage: bool = sees_player and ai.can_use_action(&"engage") and not _engage_points.is_empty()
	while last_evaluated_count < EVALUATION_POINTS_PER_FRAME and Time.get_ticks_usec() - started < EVALUATION_BUDGET_USEC and (can_cover or can_attack or can_engage):
		# 攻击扇环比躲藏点密集得多，三次攻击采样穿插一次躲藏采样。
		if can_engage and (_evaluation_turn % 8 == 1 or not (can_cover or can_attack)):
			var destination: Dictionary = ai.tactics.assess_engagement_point(_engage_points[_engage_cursor], threat)
			_engage_cursor = (_engage_cursor + 1) % _engage_points.size()
			if not destination.is_empty():
				var route := assess_route(ai, destination.path, threat, 1.0, _reload_seconds(ai) if ai.actor.ammo.is_reloading else 0.0)
				var exposure: float = route.exposure + _exposure(ai, destination.position, threat) * maxf(0.0, ai.utility_horizon_seconds - route.seconds)
				_store_candidate(_engage_cache, destination, score_outcome(ai, maxf(route.seconds, _ammo_wait(ai)), exposure).cost)
		elif can_attack and (_evaluation_turn % 4 != 0 or not can_cover):
			_evaluate_attack(ai, _attack_points[_attack_cursor], threat)
			_attack_cursor += 1
			if _attack_cursor == _attack_points.size():
				_attack_cursor = 0
				completed_attack_passes += 1
		else:
			_evaluate_cover(ai, _cover_points[_cover_cursor], threat)
			_cover_cursor = (_cover_cursor + 1) % _cover_points.size()
		_evaluation_turn += 1
		last_evaluated_count += 1
		total_evaluated_count += 1
	last_evaluation_usec = Time.get_ticks_usec() - started


func _evaluate_cover(ai: Node, destination: Dictionary, threat: Vector3) -> void:
	if not is_instance_valid(destination.body):
		return
	var selection = ai.cover_selection
	var target := threat + Vector3.UP * 0.8
	if not ai.is_position_free(destination.hide) or not selection._center_hidden_by_cover(destination.hide, target, destination.body):
		return
	if selection.require_assigned_cover:
		if selection._cover_quality(destination.hide, target, destination.body) < selection.minimum_cover_quality:
			return
	elif not selection.is_hidden_at(destination.hide, target):
		return
	var path: PackedVector3Array = selection._path_to(ai.actor.global_position, destination.hide)
	if path.is_empty():
		return
	var current := destination.duplicate()
	current.path = path
	var remaining := _reload_seconds(ai)
	var route := assess_route(ai, path, threat, ai.cover.run_speed_multiplier, remaining if ai.actor.ammo.is_reloading else 0.0)
	var exposure: float = route.exposure + _exposure(ai, current.hide, threat) * maxf(0.0, ai.utility_horizon_seconds - route.seconds)
	var cost: float = score_outcome(ai, ai.utility_horizon_seconds, exposure).cost
	if ai.actor.ammo.magazine_rounds == 0 or ai.actor.ammo.is_reloading or not ai.reload_plan.is_empty():
		if not ai.actor.ammo.is_reloading:
			cost = minf(cost, score_outcome(ai, route.seconds + remaining, exposure).cost)
		var walking := assess_route(ai, path, threat, ai.cover.run_speed_multiplier, remaining)
		var walking_exposure: float = walking.exposure + _exposure(ai, current.hide, threat) * maxf(0.0, ai.utility_horizon_seconds - walking.seconds)
		cost = minf(cost, score_outcome(ai, maxf(walking.seconds, remaining), walking_exposure).cost)
	_store_candidate(_cover_cache, current, cost)


func _evaluate_attack(ai: Node, destination: Dictionary, threat: Vector3) -> void:
	if not is_instance_valid(destination.body):
		return
	# 先做廉价距离过滤，再查询空间、导航和完整散布锥。
	if destination.position.distance_to(threat) > maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius):
		return
	var target := threat + Vector3.UP * 0.8
	var assessment: Dictionary = ai.cover_selection.assess_attack_point(destination.position, destination.body, target, target)
	if not assessment.usable:
		return
	var origin: Vector3 = destination.position + ai.actor.get_shot_origin() - ai.actor.global_position
	if not ai.tactics.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
		return
	var path: PackedVector3Array = ai.cover_selection._path_to(ai.actor.global_position, destination.position)
	if path.is_empty():
		return
	var current := destination.duplicate()
	current.path = path
	var route := assess_route(ai, path, threat, 1.0, _reload_seconds(ai))
	var exposure: float = route.exposure + _exposure(ai, current.position, threat) * maxf(0.0, ai.utility_horizon_seconds - route.seconds)
	var information: float = clampf(ai.utility_unseen_seconds, 0.0, ai.utility_horizon_seconds) * minf(1.0, route.seconds / maxf(0.1, ai.utility_horizon_seconds))
	_store_candidate(_attack_cache, current, score_outcome(ai, maxf(route.seconds, _ammo_wait(ai)), exposure, information).cost)


func _store_candidate(cache: Array[Dictionary], destination: Dictionary, cost: float) -> void:
	var point: Vector3 = destination.get("hide", destination.get("position", Vector3.INF))
	for index in range(cache.size() - 1, -1, -1):
		var previous: Dictionary = cache[index].destination
		if previous.get("body") == destination.get("body") and previous.get("hide", previous.get("position", Vector3.INF)).is_equal_approx(point):
			cache.remove_at(index)
	cache.append({"destination": destination, "cost": cost, "time": Time.get_ticks_msec()})
	cache.sort_custom(func(a: Dictionary, b: Dictionary): return a.cost < b.cost)
	if cache.size() > CACHED_DESTINATIONS:
		cache.resize(CACHED_DESTINATIONS)


func _prune_cache(cache: Array[Dictionary]) -> void:
	for index in range(cache.size() - 1, -1, -1):
		if (cache[index].destination.has("body") and not is_instance_valid(cache[index].destination.body)) or Time.get_ticks_msec() - cache[index].time > CACHE_LIFETIME_MSEC:
			cache.remove_at(index)


func _cached_destinations(cache: Array[Dictionary]) -> Array:
	_prune_cache(cache)
	var result: Array = []
	for entry: Dictionary in cache:
		result.append(entry.destination)
	return result

## AI 的只读评估工具；不启动动作、不修改记忆或导航目标。
## 所有候选统一比较未来同一段时间的火力缺失、暴露与信息损失。
func assess_options(ai: Node, sees_player: bool) -> Array[Dictionary]:
	advance_evaluation(ai, sees_player)
	var options: Array[Dictionary] = []
	var threat: Vector3 = ai._known_reload_threat()
	var horizon: float = maxf(0.1, ai.utility_horizon_seconds)
	var exposure: float = _exposure(ai, ai.actor.global_position, threat)
	var information: float = 0.0 if sees_player or not threat.is_finite() else clampf(ai.utility_unseen_seconds, 0.0, horizon)
	var reload_seconds: float = _reload_seconds(ai)
	var needs_reload: bool = ai.actor.can_use_firearms() and (ai.actor.ammo.magazine_rounds == 0 or ai.actor.ammo.is_reloading or not ai.reload_plan.is_empty())
	# 原地换弹也是普通候选，不享有优先调度；未知威胁不凭空读取玩家。
	if needs_reload:
		options.append(_option(ai, &"reload", {}, reload_seconds, exposure * horizon, information, &"here"))
	if sees_player and threat.is_finite() and ai.can_use_action(&"engage"):
		var wait: float = _ammo_wait(ai)
		var target: Vector3 = threat + Vector3.UP * 0.8
		if not sees_player or not ai.actor.can_use_firearms() or ai.actor.get_shot_origin().distance_to(target) > ai.actor.weapon.fire_range:
			wait = horizon
		elif not ai.tactics.has_clear_firing_lane(ai.actor.get_shot_origin(), target - ai.actor.get_shot_origin(), ai.actor.get_shot_origin().distance_to(target)):
			wait = horizon
		options.append(_option(ai, &"engage", {}, wait, exposure * horizon, information))
		if ai.combat_type == ai.CombatType.RANGED:
			var destinations: Array = _cached_destinations(_engage_cache)
			if ai.utility_current.get("id") == &"engage" and not ai.utility_current.destination.is_empty():
				destinations.append(ai.utility_current.destination)
			for destination: Dictionary in destinations:
				var validated: Dictionary = ai.tactics.assess_engagement_point(destination.position, threat)
				if validated.is_empty():
					continue
				var route := assess_route(ai, validated.path, threat, 1.0, reload_seconds if ai.actor.ammo.is_reloading else 0.0)
				var moving_exposure: float = route.exposure + _exposure(ai, validated.position, threat) * maxf(0.0, horizon - route.seconds)
				options.append(_option(ai, &"engage", validated, maxf(route.seconds, _ammo_wait(ai)), moving_exposure, information))
	if threat.is_finite():
		# 声源快照用于调查，不把“听见”当作已确认敌人的战术威胁。
		if not ai.search.noise_search_origin.is_finite():
			_assess_cover(ai, threat, information, needs_reload, reload_seconds, options)
			_assess_peek(ai, threat, information, sees_player, options)
			_assess_attack(ai, threat, information, options)
			_assess_suppression(ai, sees_player, exposure, information, options)
		if not sees_player and ai.can_use_action(&"search"):
			# 搜索沿当前有效导航目标推进；尚无目标时先按已知威胁规划，查询不设置导航。
			var point: Vector3 = ai.agent.target_position if ai.state in [ai.State.TRACK, ai.State.SEARCH, ai.State.INVESTIGATE] else threat
			var path: PackedVector3Array = ai.cover_selection._path_to(ai.actor.global_position, point)
			if not path.is_empty():
				var route: Dictionary = assess_route(ai, path, threat, ai.search.movement_multiplier(), reload_seconds if ai.actor.ammo.is_reloading else 0.0)
				options.append(_option(ai, &"search", {}, horizon, route.exposure + _exposure(ai, point, threat) * maxf(0.0, horizon - route.seconds), 0.0))
	elif ai.can_use_action(&"patrol") and (ai.state == ai.State.PATROL or ai.patrol_pause_timer <= 0.0):
		options.append(_option(ai, &"patrol", {}, horizon, 0.0, 0.0))
	return options


## 每项均以秒为单位，先截断到统一观察时长，再乘可调权重。
func score_outcome(ai: Node, unavailable_seconds: float, exposed_seconds: float, information_loss: float = 0.0) -> Dictionary:
	var horizon: float = maxf(0.1, ai.utility_horizon_seconds)
	var unavailable: float = clampf(unavailable_seconds, 0.0, horizon)
	# 近距离威胁的每秒暴露最高为2；时间窗仍相同，不抹掉该空间风险。
	var exposure: float = clampf(exposed_seconds, 0.0, horizon * 2.0)
	var information: float = clampf(information_loss, 0.0, horizon)
	var fire_cost: float = unavailable * maxf(0.0, ai.utility_fire_weight)
	var risk_cost: float = exposure * ai._reload_risk_aversion()
	var information_cost: float = information * maxf(0.0, ai.utility_information_weight)
	return {"cost": fire_cost + risk_cost + information_cost, "unavailable_seconds": unavailable,
		"exposed_seconds": exposure, "information_loss": information, "fire_cost": fire_cost,
		"risk_cost": risk_cost, "information_cost": information_cost}


func choose_option(options: Array) -> Dictionary:
	var best: Dictionary = {}
	for option: Dictionary in options:
		if is_finite(option.cost) and (best.is_empty() or option.cost < best.cost):
			best = option
	return best


func same_option(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	if a.get("id", &"") != b.get("id", &"") or a.get("plan", &"") != b.get("plan", &"") or a.get("mode", &"") != b.get("mode", &""):
		return false
	var first: Dictionary = a.get("destination", {})
	var second: Dictionary = b.get("destination", {})
	if first.is_empty() or second.is_empty():
		return first.is_empty() and second.is_empty()
	var first_point: Vector3 = first.get("position", first.get("hide", Vector3.INF))
	var second_point: Vector3 = second.get("position", second.get("hide", Vector3.INF))
	return first.get("body") == second.get("body") and first_point.is_equal_approx(second_point)


func _option(ai: Node, id: StringName, destination: Dictionary, unavailable: float, exposure: float, information: float, plan: StringName = &"") -> Dictionary:
	var breakdown: Dictionary = score_outcome(ai, unavailable, exposure, information)
	var result := {"id": id, "cost": breakdown.cost, "destination": destination, "breakdown": breakdown}
	if not plan.is_empty():
		result.plan = plan
	return result


func _reload_seconds(ai: Node) -> float:
	if not ai.actor.can_use_firearms():
		return 0.0
	if ai.actor.ammo.magazine_rounds > 0 and not ai.actor.ammo.is_reloading:
		return 0.0
	return maxf(0.1, ai.actor.weapon.reload_seconds) * (1.0 - ai.actor.ammo.reload_progress)


func _ammo_wait(ai: Node) -> float:
	if not ai.actor.can_use_firearms():
		return ai.utility_horizon_seconds
	if ai.actor.ammo.is_reloading:
		return _reload_seconds(ai)
	return 0.0 if ai.actor.ammo.magazine_rounds > 0 else ai.utility_horizon_seconds


func _exposure(ai: Node, point: Vector3, threat: Vector3) -> float:
	return ai._reload_exposure(point, threat) if threat.is_finite() else 0.0


func _assess_cover(ai: Node, threat: Vector3, information: float, needs_reload: bool, reload_seconds: float, options: Array[Dictionary]) -> void:
	if not ai.can_use_action(&"cover") or ai.actor.move_speed <= 0.0 or ai.combat_type != ai.CombatType.RANGED:
		return
	var horizon: float = ai.utility_horizon_seconds
	var destinations: Array = _cached_destinations(_cover_cache)
	# 采样点随身体位置变化。保留已选的准确落脚点，再按最新威胁及路径复核。
	if ai.cover.is_active():
		_append_cover_destination(ai, destinations, {"hide": ai.cover.hide_position, "body": ai.cover.active_cover_body})
	if not ai.reload_destination.is_empty():
		_append_cover_destination(ai, destinations, ai.reload_destination)
	for destination: Dictionary in destinations:
		if ai._reload_avoid_position.is_finite() and ai._horizontal_distance_between(destination.hide, ai._reload_avoid_position) < 0.9:
			continue
		if not ai._reload_destination_valid(destination):
			continue
		destination.path = ai.cover_selection._path_to(ai.actor.global_position, destination.hide)
		if destination.path.is_empty():
			continue
		var at_cover: float = _exposure(ai, destination.hide, threat)
		var remaining_reload: float = reload_seconds if ai.actor.ammo.is_reloading else 0.0
		var moving: Dictionary = assess_route(ai, destination.path, threat, ai.cover.run_speed_multiplier, remaining_reload)
		var cover_exposure: float = moving.exposure + at_cover * maxf(0.0, horizon - moving.seconds)
		options.append(_option(ai, &"cover", destination, horizon, cover_exposure, information))
		if ai.was_seeing_player and ai.can_use_action(&"covering_retreat") and ai.tactics.can_covering_retreat and ai.tactics.fire_while_moving and ai.actor.ammo.magazine_rounds > 0 and not ai.actor.ammo.is_reloading:
			var retreat_route := assess_route(ai, destination.path, threat, ai.cover.covering_retreat_speed_multiplier, 0.0)
			var retreat_exposure: float = retreat_route.exposure + at_cover * maxf(0.0, horizon - retreat_route.seconds)
			# 撤退期间能射击；进入躲藏后停火。遮挡路段不能算有效火力。
			var fire_seconds: float = minf(retreat_route.seconds, retreat_route.exposure)
			var retreat := _option(ai, &"cover", destination, horizon - fire_seconds, retreat_exposure, information)
			retreat.mode = &"covering_retreat"
			options.append(retreat)
		if not needs_reload:
			continue
		if not ai.actor.ammo.is_reloading:
			options.append(_option(ai, &"reload", destination, moving.seconds + reload_seconds, cover_exposure, information, &"after_cover"))
		var walking: Dictionary = assess_route(ai, destination.path, threat, ai.cover.run_speed_multiplier, reload_seconds)
		var walking_exposure: float = walking.exposure + at_cover * maxf(0.0, horizon - walking.seconds)
		options.append(_option(ai, &"reload", destination, maxf(walking.seconds, reload_seconds), walking_exposure, information, &"on_way"))


func _assess_peek(ai: Node, threat: Vector3, information: float, sees_player: bool, options: Array[Dictionary]) -> void:
	if sees_player or not ai.can_use_action(&"cover") or not ai.cover.is_active() or not is_instance_valid(ai.cover.active_cover_body):
		return
	var body = ai.cover.active_cover_body
	var points: Array[Vector3] = []
	for candidate: Dictionary in body.get_candidates(threat + Vector3.UP * 0.8, ai.actor.global_position):
		for point: Vector3 in candidate.peeks:
			if not points.has(point):
				points.append(point)
	for point: Vector3 in points:
		if ai.utility_rejected_attack_points.any(func(previous: Vector3): return previous.distance_to(point) < 0.25):
			continue
		if not ai.is_position_free(point) or not ai.cover_selection.has_clear_line(point + Vector3.UP * 0.8, threat + Vector3.UP * 0.8):
			continue
		var path: PackedVector3Array = ai.cover_selection._path_to(ai.actor.global_position, point)
		if path.is_empty():
			continue
		var route := assess_route(ai, path, threat, ai.cover.peek_speed_multiplier, _reload_seconds(ai) if ai.actor.ammo.is_reloading else 0.0)
		var horizon: float = ai.utility_horizon_seconds
		var exposure: float = route.exposure + _exposure(ai, point, threat) * maxf(0.0, horizon - route.seconds)
		var option := _option(ai, &"cover", {"hide": ai.cover.hide_position, "position": point, "body": body, "path": path}, horizon, exposure, information * minf(1.0, route.seconds / horizon))
		option.mode = &"peek"
		options.append(option)


func _append_cover_destination(ai: Node, destinations: Array, destination: Dictionary) -> void:
	if not ai._reload_destination_valid(destination):
		return
	for existing: Dictionary in destinations:
		if existing.body == destination.body and existing.hide.is_equal_approx(destination.hide):
			return
	var current: Dictionary = destination.duplicate()
	current.path = ai.cover_selection._path_to(ai.actor.global_position, current.hide)
	destinations.append(current)


func _assess_attack(ai: Node, threat: Vector3, information: float, options: Array[Dictionary]) -> void:
	if not ai.can_use_action(&"attack_position") or not ai.actor.can_use_firearms() or not ai.tactics.can_use_attack_positions or ai.actor.move_speed <= 0.0:
		return
	var target: Vector3 = threat + Vector3.UP * 0.8
	var assessments: Array = []
	for destination: Dictionary in _cached_destinations(_attack_cache):
		assessments.append({"usable": true, "position": destination.position, "cover": destination.body})
	var active = ai.actions[&"attack_position"]
	if active.is_active() and is_instance_valid(active.active_cover):
		assessments.append(ai.cover_selection.assess_attack_point(active.destination, active.active_cover, target, target))
	for assessment: Dictionary in assessments:
		if not assessment.usable or assessment.position.distance_to(threat) > maxf(ai.perception.sight_distance, ai.perception.close_awareness_radius):
			continue
		if ai.utility_rejected_attack_points.any(func(point: Vector3): return point.distance_to(assessment.position) < 0.25):
			continue
		var origin: Vector3 = assessment.position + ai.actor.get_shot_origin() - ai.actor.global_position
		if not ai.tactics.has_clear_firing_lane(origin, target - origin, origin.distance_to(target)):
			continue
		var path: PackedVector3Array = ai.cover_selection._path_to(ai.actor.global_position, assessment.position)
		if path.is_empty():
			continue
		var route: Dictionary = assess_route(ai, path, threat, 1.0, _reload_seconds(ai) if ai.actor.ammo.is_reloading else 0.0)
		var exposure: float = route.exposure + _exposure(ai, assessment.position, threat) * maxf(0.0, ai.utility_horizon_seconds - route.seconds)
		var destination := {"position": assessment.position, "body": assessment.cover, "path": path}
		var information_delay: float = information * minf(1.0, route.seconds / maxf(0.1, ai.utility_horizon_seconds))
		options.append(_option(ai, &"attack_position", destination, maxf(route.seconds, _ammo_wait(ai)), exposure, information_delay))


func _assess_suppression(ai: Node, sees_player: bool, exposure: float, information: float, options: Array[Dictionary]) -> void:
	if sees_player or not ai.actor.can_use_firearms():
		return
	for id: StringName in [&"suppression", &"exit_suppression"]:
		if not ai.can_use_action(id) or not ai.actions.has(id):
			continue
		var action = ai.actions[id]
		if not action.is_active() and not ai.utility_suppression_pending:
			continue
		if not action.utility_available():
			continue
		var duration: float = action.remaining if action.is_active() else maxf(0.1, action.duration_min)
		var horizon: float = ai.utility_horizon_seconds
		var available: float = maxf(0.0, minf(horizon, duration) - _ammo_wait(ai))
		available *= action.utility_fire_fraction()
		options.append(_option(ai, id, {}, horizon - available, exposure * horizon, information))


## 真实路径按半米积分；仅观察窗内的暴露计分，完整路程时间用于就绪预测。
## 换弹期间限普通速度，完成后恢复本动作速度；较慢动作不会被加速。
func assess_route(ai: Node, path: PackedVector3Array, threat: Vector3, multiplier: float, reload_seconds: float) -> Dictionary:
	var speed: float = maxf(0.01, ai.actor.move_speed * maxf(0.0, multiplier))
	var walk_speed: float = minf(speed, maxf(0.01, ai.actor.move_speed))
	var seconds: float = 0.0
	var exposure: float = 0.0
	var previous: Vector3 = ai.actor.global_position
	for point: Vector3 in path:
		var length: float = ai._horizontal_distance_between(previous, point)
		var samples: int = maxi(1, ceili(length / 0.5))
		for index: int in range(samples):
			var distance: float = length / samples
			var slow_distance: float = minf(distance, maxf(0.0, reload_seconds - seconds) * walk_speed)
			var duration: float = slow_distance / walk_speed + (distance - slow_distance) / speed
			var observed: float = minf(duration, maxf(0.0, ai.utility_horizon_seconds - seconds))
			if observed > 0.0:
				var sample: Vector3 = previous.lerp(point, (float(index) + 0.5) / samples)
				exposure += _exposure(ai, sample, threat) * observed
			seconds += duration
		previous = point
	return {"seconds": seconds, "exposure": exposure}


## 兼容动作执行分派；决策来自 assess_options，不在这里再次选方案。
func select_action(ai: Node) -> StringName:
	if ai.cover.is_active():
		return &"cover"
	match ai.state:
		ai.State.PATROL:
			return &"patrol"
		ai.State.INVESTIGATE, ai.State.TRACK, ai.State.SEARCH:
			return &"search"
		ai.State.APPROACH, ai.State.REPOSITION, ai.State.HOLD_POSITION:
			return _select_combat_action(ai)
	return &""


func _select_combat_action(ai: Node) -> StringName:
	if ai.current_suppression.is_active():
		return ai.current_suppression.action_id
	if ai.actions[&"attack_position"].is_active():
		return &"attack_position"
	return &"engage"
