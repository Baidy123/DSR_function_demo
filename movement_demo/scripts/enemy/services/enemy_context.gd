extends "res://scripts/enemy/services/enemy_memory.gd"

## 只提供公共能力、记忆和事件；不持有 AI 控制器或可选动作实例。
signal reevaluate
signal event_received(event: StringName, data: Dictionary)
var actor: CharacterBody3D
var player: Node3D
var agent: NavigationAgent3D
var arena_zone: Area3D
var navigation_region: NavigationRegion3D
var arena: Node3D
var _spawn_position := Vector3.ZERO
var _spawn_checked := false
var _spawn_valid := false
var _environment_warning := ""
var perception: Node
var cover_selection: Node
var fire
var melee
var spatial
var training: EnemyTrainingProfile
var unit: EnemyUnitProfile
var permitted: Dictionary = {}
var utility_current: Dictionary = {}
var utility_horizon_seconds := 4.0
var utility_fire_weight := 3.0
var utility_risk_weight := 3.0
var utility_information_weight := 1.0
var utility_threat_half_life_seconds := 4.0
var avoid_position := Vector3.INF
var _exposure_frame := -1
var _exposure_cache: Dictionary = {}
var _exposure_safe_distance := 3.0
var combat_type: int:
	get: return CombatType.RANGED if unit != null and unit.capabilities.has(&"firearms") else CombatType.MELEE
var patrol_pause_seconds: float:
	get: return setting(&"ai", &"patrol_pause_seconds", 1.5)
var attack_position_uncertainty: float:
	get: return setting(&"ai", &"attack_position_uncertainty", 1.0)
var reload_risk_weight: float:
	get: return utility_risk_weight

func setup(body: CharacterBody3D, perception_node: Node, selection_node: Node) -> void:
	actor = body
	agent = body.get_node("NavigationAgent3D")
	refresh_environment()
	player = body.get_tree().get_first_node_in_group("player")
	perception = perception_node
	cover_selection = selection_node
	last_known_position = body.global_position
	last_seen_position = body.global_position

func setting(section: StringName, key: StringName, fallback: Variant = null) -> Variant:
	return training.setting(section, key, fallback) if training != null else fallback

func get_tree() -> SceneTree:
	return actor.get_tree()

func can_use_action(id: StringName) -> bool:
	return permitted.has(id)

func is_arena_active() -> bool:
	return environment_ready() and is_instance_valid(player) and player.is_inside_tree() and arena_zone.overlaps_body(player)


## 只向父级寻找最近的竞技场，允许中间有 Enemies 等整理容器。
func refresh_environment() -> bool:
	var owner_arena := actor.get_parent()
	while owner_arena != null and not owner_arena.has_method("enemy_environment"):
		owner_arena = owner_arena.get_parent()
	var environment: Dictionary = owner_arena.enemy_environment() if owner_arena != null else {}
	var zone = environment.get("zone") as Area3D
	var navigation = environment.get("navigation") as NavigationRegion3D
	var changed: bool = arena != owner_arena or arena_zone != zone or navigation_region != navigation
	if changed:
		detach_environment()
		arena = owner_arena
		arena_zone = zone
		navigation_region = navigation
		_spawn_position = actor.global_position
		_spawn_checked = false
		_environment_warning = ""
		if arena != null: arena.register_enemy(actor)
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = actor.get_tree().get_first_node_in_group("player")
	return changed


func detach_environment() -> void:
	if is_instance_valid(arena): arena.unregister_enemy(actor)
	arena = null
	arena_zone = null
	navigation_region = null
	_spawn_checked = false
	_spawn_valid = false


func environment_ready() -> bool:
	if not is_instance_valid(arena_zone) or not is_instance_valid(navigation_region):
		_warn_environment("需要放在带 CombatZone 和 NavigationRegion3D 的竞技场内")
		return false
	if not navigation_region.is_inside_tree() or not navigation_region.enabled or navigation_region.navigation_mesh == null:
		_spawn_checked = false
		return false
	var map := navigation_region.get_navigation_map()
	if not map.is_valid() or NavigationServer3D.map_get_iteration_id(map) == 0:
		return false
	# 同一导航地图已同步，不代表刚拖入/重新挂载的区域已经完成同步。
	if NavigationServer3D.region_get_iteration_id(navigation_region.get_rid()) == 0:
		return false
	if agent.get_navigation_map() != map: agent.set_navigation_map(map)
	if not _spawn_checked:
		var shape := arena_zone.get_node_or_null("CollisionShape3D") as CollisionShape3D
		var inside := false
		if shape != null and not shape.disabled and shape.shape is BoxShape3D:
			inside = AABB(-shape.shape.size * 0.5, shape.shape.size).has_point(shape.to_local(_spawn_position + Vector3.UP * 0.8))
		var point := NavigationServer3D.region_get_closest_point(navigation_region.get_rid(), _spawn_position)
		_spawn_valid = inside and _horizontal_distance_between(point, _spawn_position) <= 0.05 and absf(point.y - _spawn_position.y) <= 0.5 and is_position_free(_spawn_position)
		_spawn_checked = true
		if not _spawn_valid: _warn_environment("出生点必须在本竞技场战斗区域及可站立导航范围内")
	return _spawn_valid


func _warn_environment(message: String) -> void:
	if _environment_warning == message: return
	_environment_warning = message
	push_warning("%s：%s；敌人保持待命。" % [actor.get_path(), message])

func invalidate_utility() -> void:
	reevaluate.emit()

func is_executing_cover_plan() -> bool:
	return utility_current.get("conceals", false)

func observe_visual_motion(displacement: Vector3, delta: float, continuous: bool) -> void:
	if not continuous:
		observed_velocity = Vector3.ZERO
		last_seen_direction = Vector3.ZERO
		return
	if delta <= 0.0: return
	displacement.y = 0.0
	observed_velocity = observed_velocity.lerp(displacement / delta, 1.0 - exp(-delta / 0.35))
	last_seen_direction = observed_velocity.normalized() if observed_velocity.length() >= 0.1 else Vector3.ZERO

func _known_reload_threat() -> Vector3:
	return last_known_position if is_alerted and last_known_position.is_finite() else noise_search_origin

func update_evidence(delta: float, visible: bool) -> void:
	sees_player = visible
	evidence_elapsed_seconds += maxf(0.0, delta)
	_update_reload_observation(delta, visible)
	recent_damage_pressure = maxf(0.0, recent_damage_pressure - delta * 0.5)
	nearby_shot_pressure = maxf(0.0, nearby_shot_pressure - delta * 0.5)
	utility_threat_age_seconds += delta
	for entry in blocked_destinations:
		entry.remaining -= delta
	blocked_destinations = blocked_destinations.filter(func(entry): return entry.remaining > 0.0)
	if visible:
		var position: Vector3 = player.global_position
		var displacement := position - last_seen_position
		observe_visual_motion(displacement, delta, was_seeing_player)
		last_seen_position = position
		last_known_position = position
		has_visual_memory = true
		is_alerted = true
		noise_search_origin = Vector3.INF
		utility_threat_age_seconds = 0.0
		utility_unseen_seconds = 0.0
		utility_suppression_pending = false
		utility_rejected_attack_points.clear()
	elif is_alerted:
		utility_unseen_seconds += delta
	if visible != was_seeing_player:
		if not visible:
			utility_suppression_pending = not is_executing_cover_plan()
		event_received.emit(&"visibility", {"visible": visible})
		invalidate_utility()
	was_seeing_player = visible
	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)

## 已观察事实的短期推断，不是玩家剩余换弹时间。
func observed_reload_window() -> float:
	return observed_reload_remaining

func _update_reload_observation(delta: float, visible: bool) -> void:
	var had_opportunity := observed_reload_remaining > 0.0
	observed_reload_remaining = maxf(0.0, observed_reload_remaining - maxf(0.0, delta))
	if visible:
		if perception.observes_reload(true):
			reload_observation_elapsed += maxf(0.0, delta)
			if reload_observation_elapsed >= maxf(0.0, float(setting(&"perception", &"reload_observation_seconds", 0.15))):
				observed_reload_remaining = maxf(0.0, float(setting(&"perception", &"reload_memory_seconds", 0.8)))
		else:
			reload_observation_elapsed = 0.0
			observed_reload_remaining = 0.0
	else:
		reload_observation_elapsed = 0.0
	if had_opportunity != (observed_reload_remaining > 0.0):
		event_received.emit(&"reload_observation", {"available": observed_reload_remaining > 0.0})
		invalidate_utility()

func _investigate_attack(position: Vector3) -> void:
	if not is_arena_active():
		return
	is_alerted = true
	noise_search_origin = Vector3.INF
	utility_threat_age_seconds = 0.0
	var angle := randf_range(0.0, TAU)
	var radius := randf_range(0.25, 1.0) * attack_position_uncertainty
	last_known_position = position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	last_known_position.y = actor.global_position.y
	event_received.emit(&"threat", {"position": last_known_position})
	invalidate_utility()

func notice_shot(origin: Vector3, endpoint: Vector3) -> void:
	if not is_arena_active() or actor.is_dead:
		return
	var chest := actor.global_position + Vector3.UP * 0.8
	var closest := Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
	if chest.distance_to(closest) > float(setting(&"cover", &"shot_radius", 1.5)) or not cover_selection.has_clear_line(chest, closest):
		return
	_investigate_attack(origin - Vector3.UP * 0.8)
	nearby_shot_pressure = minf(1.0, nearby_shot_pressure + 0.15)
	event_received.emit(&"near_shot", {})
	invalidate_utility()

func resume_after_action(_visible: bool, _position: Vector3) -> void:
	investigation_hint_allowed = true
	invalidate_utility()

func resume_engagement_after_cover_hit() -> void:
	avoid_position = actor.global_position
	invalidate_utility()

func block_utility_destination(point: Vector3) -> void:
	blocked_destinations.append({"position": point, "remaining": 3.0})
	invalidate_utility()

func is_utility_destination_blocked(point: Vector3) -> bool:
	return blocked_destinations.any(func(entry): return _horizontal_distance_between(entry.position, point) < 0.75)

func reset_memory() -> void:
	evidence_elapsed_seconds = 0.0
	memory_generation += 1
	reload_observation_elapsed = 0.0
	observed_reload_remaining = 0.0
	investigation_hint_allowed = true
	state = State.IDLE
	is_alerted = false
	has_visual_memory = false
	was_seeing_player = false
	sees_player = false
	last_known_position = actor.global_position
	last_seen_position = actor.global_position
	last_seen_direction = Vector3.ZERO
	observed_velocity = Vector3.ZERO
	noise_search_origin = Vector3.INF
	recent_damage_pressure = 0.0
	nearby_shot_pressure = 0.0
	utility_threat_age_seconds = 0.0
	utility_unseen_seconds = 0.0
	utility_suppression_pending = false
	utility_rejected_attack_points.clear()
	blocked_destinations.clear()
	avoid_position = Vector3.INF
	patrol_pause_timer = patrol_pause_seconds


func _horizontal_distance(point: Vector3) -> float:
	return Vector2(point.x - actor.global_position.x, point.z - actor.global_position.z).length()

func _horizontal_distance_between(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func is_position_free(point: Vector3, include_player: bool = false) -> bool:
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	var query = PhysicsShapeQueryParameters3D.new()
	query.shape = collision.shape
	# 略高于地面，避免把正常接触地板误判成被墙堵住。
	query.transform = Transform3D(Basis.IDENTITY, point + collision.position + Vector3.UP * 0.05)
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	# 候选点评估排除玩家，不能借碰撞查询感知墙后位置；短段实际避障可包含身体。
	if not include_player and is_instance_valid(player) and player is CollisionObject3D:
		query.exclude = [actor.get_rid(), player.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func _reload_exposure(point: Vector3, threat: Vector3, body_protection: float = -1.0) -> float:
	var frame := Engine.get_physics_frames()
	if _exposure_frame != frame:
		_exposure_frame = frame
		_exposure_cache.clear()
		_exposure_safe_distance = maxf(1.0, float(setting(&"tactics", &"ranged_min_distance", 4.0))) if combat_type == CombatType.RANGED else 3.0
	var key := [point, threat, body_protection]
	if _exposure_cache.has(key): return _exposure_cache[key]
	var direction: Vector3 = point - threat
	direction.y = 0.0
	var side: Vector3 = direction.normalized().cross(Vector3.UP) * 0.35
	var exposed: float = 1.0 - clampf(body_protection, 0.0, 1.0)
	if body_protection < 0.0:
		exposed = 0.0
		var query: PhysicsRayQueryParameters3D = cover_selection._ray_query(threat + Vector3.UP * 0.8, point + Vector3.UP * 0.8)
		var space := actor.get_world_3d().direct_space_state
		for offset: Vector3 in [Vector3.ZERO, side, -side]:
			query.to = point + Vector3.UP * 0.8 + offset
			if space.intersect_ray(query).is_empty():
				exposed += 1.0 / 3.0
	var result := exposed * (1.0 + clampf(1.0 - direction.length() / _exposure_safe_distance, 0.0, 1.0))
	_exposure_cache[key] = result
	return result

func _reload_risk_aversion() -> float:
	var missing_health: float = 1.0 - clampf(actor.health / maxf(actor.max_health, 1.0), 0.0, 1.0)
	var confidence := pow(0.5, utility_threat_age_seconds / maxf(0.5, utility_threat_half_life_seconds))
	# 看到/记得玩家都不等于正在受压，否则墙角每次重新目击都会立刻退回去。
	# 暴露几何用于选路；除来弹和伤势外，当前可见目标的逼近也形成避险需求。
	var close_pressure := 0.0
	if sees_player and combat_type == CombatType.RANGED and last_known_position.is_finite():
		var safe_distance: float = maxf(1.0, float(setting(&"tactics", &"ranged_min_distance", 4.0)))
		close_pressure = 2.0 * clampf(1.0 - _horizontal_distance(last_known_position) / safe_distance, 0.0, 1.0)
	return reload_risk_weight * (confidence * (missing_health + recent_damage_pressure + nearby_shot_pressure) + close_pressure)


## 旧换弹评分接口复用共同窗口；转移期间恢复火力需等到抵达。
