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
var routes = preload("res://scripts/enemy/services/enemy_route_planner.gd").new()
var training: EnemyTrainingProfile
var unit: EnemyUnitProfile
var permitted: Dictionary = {}
var utility_current: Dictionary = {}
var utility_horizon_seconds := 4.0
var utility_fire_weight := 3.0
var utility_risk_weight := 3.0
var utility_information_weight := 1.0
var utility_threat_half_life_seconds := 4.0
var tactical_map
var cooperation
var squad_node: Node
var squad_coordinator
var _spawn_arena: WeakRef
var area_changed_this_refresh := false
var team_visual_contact := false
var _shared_visual: Dictionary = {}
var _shared_noise_id := 0
var _shared_notification_position := Vector3.INF
var _cooperation_identity: Array = []
var _coordination_configuration_revision := 0
var _coordination_environment_revision := 0
var _coordination_environment_signature: Array = []
var _coordination_reservation: Dictionary = {}
var _coordination_available_at := 0.0
var _coordination_busy_action: StringName = &""
var _coordination_busy_reason: StringName = &""
var _inspection_shared_report_id := -1
var _inspection_notification_id := -1
var avoid_position := Vector3.INF
var _posture_shapes: Dictionary = {}
var _geometry_evaluation_depth := 0
var _position_evaluation_cache: Dictionary = {}
var position_free_queries := 0
var _blocked_ally_paths: Array[Dictionary] = []
const ALLY_PATH_BLOCK_SECONDS := 4.0
const MAX_ALLY_PATH_BLOCKS := 6
var _exposure_cache: Dictionary = {}
var _exposure_geometry_cache: Array = []
var _risk_evaluation_cached := false
var _risk_evaluation_value := 0.0
var combat_type: int:
	get: return CombatType.RANGED if unit != null and unit.capabilities.has(&"firearms") else CombatType.MELEE
var patrol_pause_seconds: float:
	get: return setting(&"ai", &"patrol_pause_seconds", 1.5)
var attack_position_uncertainty: float:
	get: return setting(&"ai", &"attack_position_uncertainty", 1.0)
var reload_risk_weight: float:
	get: return utility_risk_weight

func setup(body: CharacterBody3D, perception_node: Node, selection_node: Node) -> void:
	if body.has_signal(&"ally_path_blocked") and not body.is_connected(&"ally_path_blocked", _on_ally_path_blocked):
		body.connect(&"ally_path_blocked", _on_ally_path_blocked)
	actor = body
	routes.context = self
	agent = body.get_node("NavigationAgent3D")
	refresh_environment()
	player = body.get_tree().get_first_node_in_group("player")
	perception = perception_node
	cover_selection = selection_node
	last_known_position = body.global_position
	last_seen_position = body.global_position

func setting(section: StringName, key: StringName, fallback: Variant = null, unit_defaults: Dictionary = {}) -> Variant:
	if section == &"cooperation" and cooperation != null and cooperation.has_team_binding(self):
		return cooperation.team_setting(self, key, fallback, unit_defaults)
	return training.setting(section, key, fallback, unit_defaults) if training != null else unit_defaults.get(key, fallback)

func team_cooperation_abilities() -> Dictionary:
	return cooperation.team_abilities(self) if cooperation != null else {}

func cooperation_level() -> int:
	if cooperation == null: return 0
	return cooperation.team_level(self)

func coordinated_cooperation_enabled() -> bool:
	return cooperation_enabled() and cooperation_level() == 2

func cooperation_member_count() -> int:
	var coordinator = _coordinator()
	return coordinator.registered_member_count() if coordinator != null else 0

func _coordinator():
	squad_coordinator = cooperation.coordinator_for(self) if cooperation != null else null
	return squad_coordinator

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
	area_changed_this_refresh = _spawn_arena == null or _spawn_arena.get_ref() != owner_arena
	var zone = environment.get("zone") as Area3D
	var navigation = environment.get("navigation") as NavigationRegion3D
	var changed: bool = arena != owner_arena or arena_zone != zone or navigation_region != navigation
	var next_squad := EnemyTeamCooperationBinding.squad_for_member(actor)
	var squad_changed: bool = squad_node != next_squad
	if changed:
		detach_environment()
		arena = owner_arena
		arena_zone = zone
		navigation_region = navigation
		cooperation = environment.get("cooperation")
		tactical_map = environment.get("tactical_map")
		if _spawn_arena == null or _spawn_arena.get_ref() != owner_arena:
			_spawn_position = actor.global_position
			_spawn_arena = weakref(owner_arena) if owner_arena != null else null
		_spawn_checked = false
		_environment_warning = ""
		if arena != null: arena.register_enemy(actor)
		if cooperation != null: cooperation.register(self)
		actor.configure_local_navigation(navigation_region, cooperation)
	if changed or squad_changed:
		if not changed:
			_clear_coordination_memory()
			_cooperation_identity.clear()
			_shared_visual.clear()
			team_visual_contact = false
			if cooperation != null: cooperation.register(self)
		squad_node = next_squad
		squad_coordinator = cooperation.coordinator_for(self) if cooperation != null and cooperation.has_method("coordinator_for") else cooperation
	if not is_instance_valid(player) or not player.is_inside_tree():
		player = actor.get_tree().get_first_node_in_group("player")
	return changed


func detach_environment() -> void:
	_clear_coordination_memory()
	_blocked_ally_paths.clear()
	if spatial != null: spatial.clear_cover_preparation()
	actor.configure_local_navigation(null, null)
	actor.configure_local_spacing(false)
	_inspection_shared_report_id = -1
	_inspection_notification_id = -1
	if cooperation != null: cooperation.unregister(actor.get_instance_id())
	cooperation = null
	squad_node = null
	squad_coordinator = null
	tactical_map = null
	_shared_visual.clear()
	_shared_notification_position = Vector3.INF
	team_visual_contact = false
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
			inside = AABB(-shape.shape.size * 0.5, shape.shape.size).has_point(shape.to_local(_spawn_position + Vector3.UP * actor.get_posture_body_height(false) * 0.5))
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
	var acquired := visible and not was_seeing_player
	sees_player = visible
	evidence_elapsed_seconds += maxf(0.0, delta)
	_expire_ally_path_blocks()
	actor.configure_local_spacing(cooperation != null and is_instance_valid(navigation_region) and not actor.is_dead, float(setting(&"cooperation", &"spacing_margin", 0.45)))
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
		last_seen_aim_position = perception.visible_aim_position(true) if actor.can_use_firearms() else Vector3.INF
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
			publish_suppression_evidence(&"visual_loss", last_seen_position, perception.last_observed_cover(last_seen_position))
			utility_suppression_pending = not is_executing_cover_plan()
		event_received.emit(&"visibility", {"visible": visible})
		invalidate_utility()
	perception.update_close_cover(delta)
	was_seeing_player = visible
	_update_cooperation_evidence(acquired)
	if state == State.IDLE:
		patrol_pause_timer = maxf(0.0, patrol_pause_timer - delta)

## 已观察事实的短期推断，不是玩家剩余换弹时间。
func observed_reload_window() -> float:
	var shared_remaining := 0.0
	if not sees_player and _shared_visual.get("reloading", false):
		shared_remaining = maxf(0.0, float(_shared_visual.get("reload_until", 0.0)) - evidence_elapsed_seconds)
	return maxf(observed_reload_remaining, shared_remaining)

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
	var chest: Vector3 = actor.get_torso_position()
	var closest := Geometry3D.get_closest_point_to_segment(chest, origin, endpoint)
	if chest.distance_to(closest) > float(setting(&"cover", &"shot_radius", 1.5)) or not cover_selection.has_clear_line(chest, closest):
		return
	_investigate_attack(Vector3(origin.x, actor.global_position.y, origin.z))
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

func _on_ally_path_blocked(blocker: Node3D, position: Vector3) -> void:
	if not is_instance_valid(blocker) or not position.is_finite() or cooperation == null or not cooperation.can_share_space(actor.get_instance_id(), blocker.get_instance_id()): return
	for entry: Dictionary in _blocked_ally_paths:
		if _ally_path_block_active(entry) and entry.blocker.get_ref() == blocker and _horizontal_distance_between(entry.position, position) < 0.5: return
	var own_shape: CollisionShape3D = actor.get_node("CollisionShape3D")
	var other_shape: CollisionShape3D = blocker.get_node("CollisionShape3D")
	var radius: float = own_shape.shape.radius * maxf(own_shape.global_basis.x.length(), own_shape.global_basis.z.length()) + other_shape.shape.radius * maxf(other_shape.global_basis.x.length(), other_shape.global_basis.z.length()) + 0.08
	if _blocked_ally_paths.size() >= MAX_ALLY_PATH_BLOCKS: _blocked_ally_paths.pop_front()
	_blocked_ally_paths.append({"blocker": weakref(blocker), "position": position, "radius": radius,
		"valid_until": evidence_elapsed_seconds + ALLY_PATH_BLOCK_SECONDS})
	_ally_paths_changed()

func _ally_path_block_active(entry: Dictionary) -> bool:
	if evidence_elapsed_seconds >= float(entry.valid_until) or cooperation == null: return false
	var blocker = entry.blocker.get_ref()
	if not is_instance_valid(blocker) or not cooperation.can_share_space(actor.get_instance_id(), blocker.get_instance_id()): return false
	var moved: Vector3 = blocker.global_position - entry.position
	return Vector2(moved.x, moved.z).length() < 0.5 and absf(moved.y) < 0.5

func _expire_ally_path_blocks() -> void:
	if _blocked_ally_paths.is_empty(): return
	var previous := _blocked_ally_paths.size()
	_blocked_ally_paths = _blocked_ally_paths.filter(_ally_path_block_active)
	if previous != _blocked_ally_paths.size(): _ally_paths_changed()

func _ally_paths_changed() -> void:
	# A new observed route obstruction invalidates cached destinations as well as
	# the selected plan. The existing spatial budget still rebuilds their costs.
	if spatial != null: spatial.reset_evaluation()
	invalidate_utility()

## Exact live filter after the navigation cache, so another destination using
## the same blocked passage is rejected too. Retreating away remains possible.
func is_ally_path_blocked(from: Vector3, path: PackedVector3Array) -> bool:
	if path.is_empty() or _blocked_ally_paths.is_empty(): return false
	for entry: Dictionary in _blocked_ally_paths:
		if not _ally_path_block_active(entry): continue
		var obstacle := Vector2(entry.position.x, entry.position.z)
		var previous: Vector3 = from
		for point: Vector3 in path:
			var start := Vector2(previous.x, previous.z)
			var finish := Vector2(point.x, point.z)
			var motion := finish - start
			if motion.is_zero_approx():
				previous = point
				continue
			var closest := Geometry2D.get_closest_point_to_segment(obstacle, start, finish)
			var ratio := clampf((closest - start).dot(motion) / motion.length_squared(), 0.0, 1.0)
			var height := lerpf(previous.y, point.y, ratio)
			if closest.distance_to(obstacle) < float(entry.radius) and absf(height - float(entry.position.y)) < 1.0:
				var leaving: bool = start.distance_to(obstacle) <= float(entry.radius) and finish.distance_to(obstacle) > start.distance_to(obstacle) and motion.dot(start - obstacle) >= 0.0
				if not leaving: return true
			previous = point
	return false

func reset_memory() -> void:
	_clear_coordination_memory()
	_blocked_ally_paths.clear()
	_inspection_shared_report_id = -1
	_inspection_notification_id = -1
	actor.configure_local_spacing(false)
	if cooperation != null: cooperation.release_member(actor.get_instance_id())
	_shared_visual.clear()
	_shared_notification_position = Vector3.INF
	team_visual_contact = false
	_cooperation_identity.clear()
	evidence_elapsed_seconds = 0.0
	memory_generation += 1
	suppression_evidence = {}
	exact_cover_clue = {}
	suppression_consumed_id = -1
	if perception != null: perception.reset_contact()
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
	last_seen_aim_position = Vector3.INF
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

## A synchronous read-only candidate batch; committed movement always queries live physics.
func begin_geometry_evaluation() -> void:
	if _geometry_evaluation_depth == 0:
		_position_evaluation_cache.clear()
		_exposure_cache.clear()
		_exposure_geometry_cache.clear()
		_risk_evaluation_cached = false
	_geometry_evaluation_depth += 1
	cover_selection.begin_geometry_evaluation()
	fire.begin_geometry_evaluation()
	spatial.begin_geometry_evaluation()

func end_geometry_evaluation() -> void:
	assert(_geometry_evaluation_depth > 0)
	_geometry_evaluation_depth -= 1
	spatial.end_geometry_evaluation()
	fire.end_geometry_evaluation()
	cover_selection.end_geometry_evaluation()
	if _geometry_evaluation_depth == 0:
		_position_evaluation_cache.clear()
		_exposure_cache.clear()
		_exposure_geometry_cache.clear()
		_risk_evaluation_cached = false

## Classify an actual occupied capsule after a failed clearance check. A bounded
## result containing only friendly bodies permits waiting, never walking through.
func is_position_blocked_by_allies(point: Vector3) -> bool:
	return not position_blocking_allies(point).is_empty()

func position_blocking_allies(point: Vector3) -> Array:
	if cooperation == null: return []
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	var capsule := CapsuleShape3D.new()
	capsule.radius = collision.shape.radius
	capsule.height = actor.get_posture_body_height(false)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (capsule.height * 0.5 + 0.05))
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	if is_instance_valid(player) and player is CollisionObject3D:
		query.exclude = [actor.get_rid(), player.get_rid()]
	position_free_queries += 1
	var hits: Array[Dictionary] = actor.get_world_3d().direct_space_state.intersect_shape(query, 8)
	if hits.is_empty() or hits.size() == 8: return []
	var allies: Array = []
	for hit: Dictionary in hits:
		var other = hit.get("collider")
		if not is_instance_valid(other) or not other is CharacterBody3D or not cooperation.can_share_space(actor.get_instance_id(), other.get_instance_id()): return []
		allies.append(other)
	return allies

func is_position_free(point: Vector3, include_player: bool = false, crouched: bool = false) -> bool:
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	var height: float = actor.get_posture_body_height(crouched)
	var evaluation_key := [point, include_player, crouched, height, collision.shape.radius, actor.collision_mask]
	if _geometry_evaluation_depth > 0 and _position_evaluation_cache.has(evaluation_key): return _position_evaluation_cache[evaluation_key]
	var key := Vector2(height, collision.shape.radius)
	if not _posture_shapes.has(key):
		var shape := CapsuleShape3D.new()
		shape.radius = collision.shape.radius
		shape.height = height
		_posture_shapes[key] = shape
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _posture_shapes[key]
	# 略高于地面，避免把正常接触地板误判成被墙堵住。
	query.transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * (actor.get_posture_body_height(crouched) * 0.5 + 0.05))
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	# 候选点评估排除玩家，不能借碰撞查询感知墙后位置；短段实际避障可包含身体。
	if not include_player and is_instance_valid(player) and player is CollisionObject3D:
		query.exclude = [actor.get_rid(), player.get_rid()]
	position_free_queries += 1
	var free: bool = actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
	if _geometry_evaluation_depth > 0: _position_evaluation_cache[evaluation_key] = free
	return free

## Posture and configuration stay fixed inside a synchronous read-only batch.
## Outside that scope both offsets and physics are read again, even in one frame.
func _exposure_geometry() -> Array:
	if _geometry_evaluation_depth > 0 and not _exposure_geometry_cache.is_empty(): return _exposure_geometry_cache
	var safe_distance := maxf(1.0, float(setting(&"tactics", &"ranged_min_distance", 4.0))) if combat_type == CombatType.RANGED else 3.0
	var geometry: Array = [actor.get_posture_eye_position(false, Vector3.ZERO), actor.get_posture_eye_position(true, Vector3.ZERO), actor.get_posture_muzzle_position(false, Vector3.ZERO), safe_distance]
	if _geometry_evaluation_depth > 0: _exposure_geometry_cache = geometry
	return geometry

func _reload_exposure(point: Vector3, threat: Vector3, body_protection: float = -1.0, crouched: bool = false) -> float:
	var key := [point, threat, body_protection, crouched]
	if _geometry_evaluation_depth > 0:
		var cached: float = _exposure_cache.get(key, -1.0)
		if cached >= 0.0: return cached
	var geometry := _exposure_geometry()
	var direction: Vector3 = point - threat
	direction.y = 0.0
	var exposed: float = 1.0 - clampf(body_protection, 0.0, 1.0)
	if body_protection < 0.0:
		exposed = 0.0
		var side: Vector3 = direction.normalized().cross(Vector3.UP) * 0.35
		var target_eye: Vector3 = point + geometry[1 if crouched else 0]
		var origin: Vector3 = threat + geometry[2]
		if cover_selection.environment_ray(origin, target_eye).is_empty(): exposed += 1.0 / 3.0
		if cover_selection.environment_ray(origin, target_eye + side).is_empty(): exposed += 1.0 / 3.0
		if cover_selection.environment_ray(origin, target_eye - side).is_empty(): exposed += 1.0 / 3.0
	var result := exposed * (1.0 + clampf(1.0 - direction.length() / float(geometry[3]), 0.0, 1.0))
	if _geometry_evaluation_depth > 0: _exposure_cache[key] = result
	return result

func _reload_risk_aversion() -> float:
	# Health, known contact and pressure stay fixed during this read-only batch.
	if _geometry_evaluation_depth > 0 and _risk_evaluation_cached: return _risk_evaluation_value
	var missing_health: float = 1.0 - clampf(actor.health / maxf(actor.max_health, 1.0), 0.0, 1.0)
	var confidence := pow(0.5, utility_threat_age_seconds / maxf(0.5, utility_threat_half_life_seconds))
	# 看到/记得玩家都不等于正在受压，否则墙角每次重新目击都会立刻退回去。
	# 暴露几何用于选路；除来弹和伤势外，当前可见目标的逼近也形成避险需求。
	var close_pressure := 0.0
	if sees_player and combat_type == CombatType.RANGED and last_known_position.is_finite():
		var safe_distance: float = maxf(1.0, float(setting(&"tactics", &"ranged_min_distance", 4.0)))
		close_pressure = 2.0 * clampf(1.0 - _horizontal_distance(last_known_position) / safe_distance, 0.0, 1.0)
	var result: float = reload_risk_weight * (confidence * (missing_health + recent_damage_pressure + nearby_shot_pressure) + close_pressure)
	if _geometry_evaluation_depth > 0:
		_risk_evaluation_value = result
		_risk_evaluation_cached = true
	return result


## 旧换弹评分接口复用共同窗口；转移期间恢复火力需等到抵达。


func publish_suppression_evidence(source: StringName, position: Vector3, cover: Object = null) -> Dictionary:
	_evidence_serial += 1
	var duration := float(setting(&"suppression", &"duration_max", 5.0))
	var aim := last_seen_aim_position if source == &"visual_loss" and position.is_equal_approx(last_seen_position) else Vector3.INF
	var evidence := {"source": source, "position": position, "aim_position": aim, "captured_at": evidence_elapsed_seconds, "valid_until": evidence_elapsed_seconds + maxf(duration, 0.1), "id": _evidence_serial, "low_cover_context": is_instance_valid(cover) and cover.has_method("is_low_cover") and cover.is_low_cover()}
	# A same-frame close-wall clue remains useful for investigation, but cannot
	# replace the body sample genuinely observed just before visual loss.
	var personal_live: bool = suppression_evidence.get("source", &"") == &"visual_loss" and evidence_elapsed_seconds < float(suppression_evidence.get("valid_until", 0.0))
	if source == &"visual_loss" or not personal_live:
		suppression_evidence = evidence
		utility_suppression_pending = source == &"visual_loss"
	if source in [&"visual_loss", &"close_cover_exact"]:
		_record_cover_inspection(evidence, cover)
	return evidence.duplicate()

func receive_exact_cover_clue(position: Vector3, cover: Object = null) -> void:
	if not position.is_finite() or sees_player: return
	exact_cover_clue = publish_suppression_evidence(&"close_cover_exact", position, cover)
	last_known_position = position
	is_alerted = true
	noise_search_origin = Vector3.INF
	utility_threat_age_seconds = 0.0
	event_received.emit(&"exact_cover_clue", exact_cover_clue.duplicate())
	invalidate_utility()

func suppression_basis() -> Dictionary:
	if not suppression_evidence.is_empty():
		return suppression_evidence.duplicate() if evidence_elapsed_seconds < float(suppression_evidence.valid_until) else {}
	# Legacy inspection/test API: visual memory alone never creates a new pending event.
	if has_visual_memory:
		return {"source": &"visual_loss", "position": last_seen_position, "aim_position": last_seen_aim_position, "captured_at": evidence_elapsed_seconds - utility_unseen_seconds, "valid_until": INF, "id": 0}
	return {}

func suppression_available(basis: Dictionary) -> bool:
	return not basis.is_empty() and evidence_elapsed_seconds < float(basis.valid_until) and int(basis.id) != suppression_consumed_id

func consume_suppression(basis: Dictionary) -> void:
	if int(basis.get("id", 0)) > 0: suppression_consumed_id = int(basis.id)
	utility_suppression_pending = false

func known_target_point(feet: Vector3) -> Vector3:
	if sees_player and feet.distance_to(last_known_position) < 0.1 and player.has_method("get_torso_position"):
		return feet + Vector3.UP * (player.get_torso_position().y - player.global_position.y)
	return actor.get_posture_eye_position(true, feet)

## Callers may retain this value as one observation snapshot for a preview batch.
## Hidden targets use a stated standing-height hypothesis, never their live pose.
func known_target_points(feet: Vector3) -> PackedVector3Array:
	if sees_player and feet.distance_to(last_known_position) < 0.1 and player.has_method("get_visibility_points"):
		var points := PackedVector3Array()
		for point: Vector3 in player.get_visibility_points():
			if perception._sees_point(point): points.append(point)
		return points
	return PackedVector3Array([actor.get_posture_eye_position(false, feet)])

## Investigation keeps a frozen clue longer than precise shooting evidence.
## Its lifetime never extends suppression authority or personal visibility.
func _record_cover_inspection(evidence: Dictionary, cover: Object = null) -> void:
	if not evidence.get("position", Vector3.INF).is_finite(): return
	var captured: float = evidence.get("captured_at", evidence_elapsed_seconds)
	var clue := {"target_id": cooperation_target_id(), "position": evidence.position,
		"id": evidence.get("id", 0), "source": evidence.get("source", &""),
		"captured_at": captured, "valid_until": captured + maxf(0.1, float(setting(&"cooperation", &"cover_inspection_seconds", 20.0))),
		"observer_position": evidence.get("observer_position", actor.global_position),
		"cover": weakref(cover) if is_instance_valid(cover) else null,
		"direction": last_seen_direction, "velocity": observed_velocity}
	if clue.target_id == 0 or evidence_elapsed_seconds >= clue.valid_until: return
	if _coordinator() != null: _coordinator().report_inspection(self, clue)

func _receive_shared_inspection() -> void:
	if cooperation == null or sees_player: return
	var clue: Dictionary = _coordinator().shared_inspection(self)
	if clue.is_empty() or int(clue.id) == _inspection_notification_id: return
	_inspection_notification_id = int(clue.id)
	if int(clue.get("observer_id", 0)) == actor.get_instance_id(): return
	# Investigation can be shared even when nobody has a current visual report.
	# This event grants no body aim sample, personal visibility or firing right.
	var offset: float = evidence_elapsed_seconds - cooperation.elapsed
	clue.captured_at = float(clue.captured_at) + offset
	clue.valid_until = float(clue.valid_until) + offset
	if has_visual_memory and float(clue.captured_at) < evidence_elapsed_seconds - utility_unseen_seconds: return
	last_known_position = clue.position
	is_alerted = true
	noise_search_origin = Vector3.INF
	event_received.emit(&"exact_cover_clue", clue)
	invalidate_utility()

func cover_inspection_evidence() -> Dictionary:
	if cooperation == null or sees_player: return {}
	var clue: Dictionary = _coordinator().shared_inspection(self)
	if not clue.is_empty():
		var offset: float = evidence_elapsed_seconds - cooperation.elapsed
		clue.captured_at = float(clue.captured_at) + offset
		clue.valid_until = float(clue.valid_until) + offset
	# The board owns invalidation on newer sight, identity and expired rounds;
	# a local fallback must not resurrect evidence it has revoked.
	return clue if clue.get("target_id", 0) == cooperation_target_id() and evidence_elapsed_seconds < float(clue.get("valid_until", -INF)) else {}

func cooperation_enabled() -> bool:
	return commanded()

func has_combat_contact() -> bool:
	return has_visual_memory or team_visual_contact

## Shared contact authorizes a combat approach, never personal sight or firing.
func fresh_shared_contact() -> Dictionary:
	if sees_player: return {}
	# A frozen radio report is no longer ongoing contact once everyone lost
	# sight. Investigation uses its own evidence without authorizing combat moves.
	if not cover_inspection_evidence().is_empty(): return {}
	var report: Dictionary = cooperation_target_evidence()
	if not report.get("shared", false) or report.get("source", &"") != &"shared_visual": return {}
	if report.get("target_id", 0) != cooperation_target_id() or not report.get("position", Vector3.INF).is_finite(): return {}
	return report if evidence_elapsed_seconds < float(report.get("valid_until", -INF)) else {}

## Both approach and search estimate recovery of observation from the same
## frozen report. This uses known geometry, not the hidden target's live pose.
func shared_contact_information(position: Vector3, arrival_seconds: float, report: Dictionary = {}) -> float:
	var horizon: float = utility_horizon_seconds
	if report.is_empty(): report = fresh_shared_contact()
	if report.is_empty() or not position.is_finite(): return horizon
	if not report.get("shared", false) or report.get("source", &"") != &"shared_visual": return horizon
	if evidence_elapsed_seconds >= float(report.get("valid_until", -INF)) or report.get("target_id", 0) != cooperation_target_id(): return horizon
	var feet: Vector3 = report.get("position", Vector3.INF)
	if not feet.is_finite() or position.distance_to(feet) > maxf(perception.sight_distance, perception.close_awareness_radius): return horizon
	var target: Vector3 = report.get("aim_position", Vector3.INF)
	if not target.is_finite(): target = actor.get_posture_eye_position(false, feet)
	if not cover_selection.has_clear_line(actor.get_posture_eye_position(false, position), target): return horizon
	var direction := Vector3(feet.x - position.x, 0.0, feet.z - position.z)
	var forward := Vector3(-actor.global_basis.z.x, 0.0, -actor.global_basis.z.z)
	var turn := 0.0
	if not direction.is_zero_approx() and not forward.is_zero_approx():
		turn = forward.angle_to(direction) / deg_to_rad(maxf(0.1, actor.turn_speed_degrees))
	return clampf(maxf(arrival_seconds, turn), 0.0, horizon)

func cooperation_target_id() -> int:
	return player.get_instance_id() if is_instance_valid(player) else 0

func cooperation_target_evidence() -> Dictionary:
	var personal_time := evidence_elapsed_seconds - utility_unseen_seconds
	if not sees_player and not _shared_visual.is_empty() and _shared_visual.get("target_id", 0) == cooperation_target_id() and (not has_visual_memory or float(_shared_visual.captured_at) >= personal_time):
		var report := _shared_visual.duplicate(true)
		report.confidence = pow(0.5, maxf(0.0, evidence_elapsed_seconds - float(report.captured_at)) / maxf(0.1, utility_threat_half_life_seconds))
		return report
	if not has_visual_memory or not last_seen_position.is_finite(): return {}
	return {"target_id": cooperation_target_id(), "position": last_seen_position, "aim_position": last_seen_aim_position, "direction": last_seen_direction, "velocity": observed_velocity,
		"captured_at": personal_time, "valid_until": personal_time + float(setting(&"cooperation", &"intel_seconds", 5.0)),
		"id": 0, "source": &"visual", "shared": false, "confidence": pow(0.5, utility_unseen_seconds / maxf(0.1, utility_threat_half_life_seconds))}

func _update_cooperation_evidence(acquired: bool = false) -> void:
	if cooperation == null: return
	var identity := [cooperation.get_instance_id(), EnemyTeamCooperationBinding.effective_faction(actor), EnemyTeamCooperationBinding.effective_communication_group(actor), cooperation_target_id(), cooperation.generation, cooperation.relation_revision]
	if identity != _cooperation_identity:
		if (team_visual_contact or _inspection_notification_id >= 0) and not has_visual_memory:
			last_known_position = noise_search_origin
			is_alerted = noise_search_origin.is_finite()
		_shared_visual.clear()
		_shared_notification_position = Vector3.INF
		team_visual_contact = false
		_inspection_shared_report_id = -1
		_inspection_notification_id = -1
		_cooperation_identity = identity
		cooperation.register(self)
	if sees_player: _coordinator().report_visual(self, acquired)
	if not sees_player:
		var noise: Dictionary = _coordinator().shared_noise(self)
		if not noise.is_empty() and noise.id != _shared_noise_id:
			_shared_noise_id = noise.id
			if not has_visual_memory or noise.captured_at > cooperation.elapsed - utility_unseen_seconds:
				noise_search_origin = noise.position
				last_known_position = noise.position
				is_alerted = true
				event_received.emit(&"noise", {"position": noise.position, "shared": true})
				invalidate_utility()
	_receive_shared_inspection()
	var report: Dictionary = _coordinator().shared_visual(self)
	if report.is_empty(): return
	# Convert the common arena clock without rejuvenating the original observation.
	var offset: float = evidence_elapsed_seconds - cooperation.elapsed
	for key in [&"captured_at", &"valid_until", &"reload_until"]:
		report[key] = float(report.get(key, 0.0)) + offset
	var old: Dictionary = _shared_visual
	if not old.is_empty() and int(report.id) < int(old.id): return
	if not old.is_empty() and int(report.id) == int(old.id):
		_shared_visual = report # Re-map original timestamps if this individual was inactive.
		return
	_shared_visual = report
	if cooperation.registered_member_count() > 1 and not sees_player and not _coordinator().has_visual_contact(self) and int(report.id) != _inspection_shared_report_id:
		_inspection_shared_report_id = int(report.id)
		var active: Dictionary = _coordinator().shared_inspection(self)
		# Alternating observers can publish every frame. A live frozen round
		# already identifies this cover; do not repeat its geometry query.
		if active.is_empty() or active.position.distance_to(report.position) >= 0.5:
			var cover := cover_selection.confirmed_suppression_cover(report.position) as Object
			if is_instance_valid(cover):
				var clue := report.duplicate(true)
				clue.source = &"shared_visual"
				# The receiving observer defines the occluding face once. Target
				# position/time still come exclusively from the frozen report.
				clue.observer_position = actor.global_position
				_record_cover_inspection(clue, cover)
	var first_contact := not team_visual_contact
	team_visual_contact = true
	if sees_player: return
	var personal_time: float = evidence_elapsed_seconds - utility_unseen_seconds
	if has_visual_memory and float(report.captured_at) < personal_time: return
	var reacquired: bool = int(report.get("contact_id", 0)) > int(old.get("contact_id", 0))
	var changed: bool = reacquired or first_contact or not _shared_notification_position.is_finite() or _shared_notification_position.distance_to(report.position) >= 0.5
	last_known_position = report.position
	is_alerted = true
	noise_search_origin = Vector3.INF
	utility_threat_age_seconds = maxf(0.0, evidence_elapsed_seconds - float(report.captured_at))
	if changed:
		_shared_notification_position = report.position
		var notification := report.duplicate(true)
		notification.reacquired = reacquired
		event_received.emit(&"cooperation_intel", notification)
		invalidate_utility()

var _cooperation_preview_snapshot: Dictionary = {}
var _cooperation_preview_depth := 0
var _cooperation_preview_sources: Dictionary = {}

## Candidate collection is read-only: share one observation across this batch,
## then discard it before action validation, reservations or physical execution.
func begin_cooperation_preview() -> void:
	if _cooperation_preview_depth == 0:
		_cooperation_preview_sources.clear()
		_cooperation_preview_snapshot = cooperation.snapshot(self, cooperation_target_id()) if cooperation_enabled() else {}
	_cooperation_preview_depth += 1

func end_cooperation_preview() -> void:
	assert(_cooperation_preview_depth > 0)
	_cooperation_preview_depth -= 1
	if _cooperation_preview_depth == 0:
		_cooperation_preview_snapshot = {}
		_cooperation_preview_sources.clear()

func cooperation_snapshot(target_id: int = 0) -> Dictionary:
	if cooperation == null: return {"members": [], "physical_members": [], "requests": [], "supports": [], "threats": [], "revision": 0}
	if not _cooperation_preview_snapshot.is_empty() and (target_id == 0 or target_id == cooperation_target_id()): return _cooperation_preview_snapshot
	return cooperation.snapshot(self, cooperation_target_id() if target_id == 0 else target_id)


func cooperation_search_available(point: Vector3, _radius: float = 0.0) -> bool:
	return cooperation.search_available(self, point) if cooperation != null else true

func cooperation_publish_checked(points: PackedVector3Array) -> void:
	if _coordinator() != null and not noise_search_origin.is_finite(): _coordinator().report_checked(self, points)

func cooperation_checked_points() -> Array[Dictionary]:
	if _coordinator() == null or noise_search_origin.is_finite(): return []
	var points: Array[Dictionary] = _coordinator().shared_checked(self)
	var offset: float = evidence_elapsed_seconds - cooperation.elapsed
	for item in points:
		item.observed_at += offset
		item.valid_until += offset
	return points

func cooperation_clear_execution(_reason: StringName = &"switch") -> void:
	if cooperation != null: cooperation.clear_execution(actor.get_instance_id())
	_coordination_reservation = {}

func _clear_coordination_memory() -> void:
	_coordination_available_at = 0.0
	_coordination_busy_action = &""
	_coordination_busy_reason = &""
	_coordination_reservation = {}
	_coordination_environment_signature.clear()

func coordination_assignment() -> Dictionary:
	return _coordinator().assignment(self) if commanded() and _coordinator() != null else {}

func prepare_coordination_evaluation() -> void:
	# Public body/position reservations also protect actors outside a Squad.
	if cooperation != null and cooperation.registered_member_count() > 1: _publish_coordination_versions()

func coordination_search_revision() -> int:
	return tactical_map.revision() if tactical_map != null else 0

func advance_coordination_map(max_points: int, deadline_usec: int, frame: int) -> int:
	if tactical_map == null or not commanded(): return 0
	return int(tactical_map.advance_preparation(max_points, deadline_usec, frame).points)

func coordination_now() -> float:
	return cooperation.elapsed if cooperation != null else evidence_elapsed_seconds

## Forward only already acquired reports, with their original identities/times.
## Team planning evidence never grants this actor personal firing permission.
func publish_coordination_noise(position: Vector3) -> void:
	if _coordinator() != null: _coordinator().report_noise(self, position)

func coordination_debug_snapshot() -> Dictionary:
	if not is_instance_valid(actor) or actor.is_dead or not is_arena_active(): return {}
	var result: Dictionary = _coordinator().debug_member_snapshot(self) if _coordinator() != null else {}
	result.actor_id = actor.get_instance_id()
	result.name = str(actor.name)
	result.position = actor.global_position
	result.action = utility_current.get("id", &"none")
	# Execution facts are separate from planning status. An unassigned member
	# can still be searching, firing or reloading through the same personal AI.
	result.cooperation_level = cooperation_level()
	result.moving = not actor.get_local_movement_velocity().is_zero_approx() or Vector2(actor.velocity.x, actor.velocity.z).length_squared() > 0.0025
	result.reloading = actor.ammo.is_reloading
	result.reload_remaining = maxf(0.1, actor.weapon.reload_seconds) * (1.0 - actor.ammo.reload_progress) if actor.weapon != null and actor.ammo.is_reloading else 0.0
	var availability := coordination_motion_state()
	result.available_in = availability.available_in
	if availability.available_in > 0.0: result.reason = availability.availability_reason
	var destination: Variant = utility_current.get("destination", {})
	result.personal_goal = utility_current.get("route_target", destination.get("position", destination.get("hide", Vector3.INF))) if destination is Dictionary else Vector3.INF
	if result.moving and not result.personal_goal.is_finite(): result.personal_goal = agent.target_position
	# Reading the agent's existing path does not request or advance navigation.
	# Only show it for an actually moving personal action with this same goal.
	if not commanded() and result.get("route", PackedVector3Array()).is_empty() and result.moving and result.personal_goal.is_finite() and agent.target_position.distance_to(result.personal_goal) < 0.1:
		var path := agent.get_current_navigation_path()
		var index := agent.get_current_navigation_path_index()
		if index >= 0 and index < path.size():
			result.route = PackedVector3Array([actor.global_position])
			result.route.append_array(path.slice(index))
	return result

## Public physical facts for squad planning. No action instance or private
## state machine is exposed; capability changes are read on every query.
func coordination_motion_state() -> Dictionary:
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	var radius: float = collision.shape.radius * maxf(collision.global_basis.x.length(), collision.global_basis.z.length())
	var available_in := maxf(0.0, _coordination_available_at - evidence_elapsed_seconds)
	return {"actor_id": actor.get_instance_id(), "position": actor.global_position,
		"velocity": actor.velocity, "radius": radius, "move_speed": actor.move_speed,
		"spacing_margin": float(setting(&"cooperation", &"spacing_margin", 0.45)),
		"available_in": available_in, "availability_reason": _coordination_busy_reason if available_in > 0.0 else &"",
		"movable": available_in <= 0.0 and actor.can_move() and not actor.is_dead and not actor.is_vaulting() and not actor.melee_active}

## Local route feasibility is queried through Context, independently of which
## installed action will later accept and execute the squad's task.
func coordinated_stationary_members() -> Array:
	return _coordinator().member_ids() if commanded() else []

func personal_position_choices(options: Array[Dictionary]) -> Array[Dictionary]:
	if cooperation == null or cooperation.registered_member_count() <= 1 or not _publish_coordination_versions():
		var independent_choices: Array[Dictionary] = []
		for candidate in options:
			var independent := candidate.duplicate() if candidate.has("coordination_offer") else candidate
			independent.erase("coordination_offer")
			independent_choices.append(independent)
		return independent_choices
	var result: Array[Dictionary] = []
	var candidate_offers: Array[Dictionary] = []
	var distinct_offers: Array[Dictionary] = []
	var position_indices: Dictionary = {}
	# This loop only projects candidates. The member identity cannot change
	# until it returns; reservation filtering and transactions still read live.
	var identity: Dictionary = cooperation.coordination_identity(self)
	for candidate in options:
		var offer := _basic_coordination_offer(candidate, identity)
		candidate_offers.append(offer)
		if not offer.is_empty() and not position_indices.has(offer.position):
			position_indices[offer.position] = distinct_offers.size()
			distinct_offers.append(offer)
	var available: Array[bool] = cooperation.reservation_offers_available(self, distinct_offers)
	for index in options.size():
		var candidate: Dictionary = options[index]
		var offer: Dictionary = candidate_offers[index]
		if offer.is_empty():
			var independent := candidate.duplicate() if candidate.has("coordination_offer") else candidate
			independent.erase("coordination_offer")
			result.append(independent)
			continue
		if not available[position_indices[offer.position]]: continue
		var choice := candidate.duplicate()
		choice.coordination_offer = offer
		result.append(choice)
	return result

func _publish_coordination_versions() -> bool:
	if cooperation == null or not is_instance_valid(navigation_region): return false
	var map: RID = agent.get_navigation_map()
	var navigation_revision: int = NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0
	var signature: Array = [navigation_region.get_instance_id(), spatial._geometry, navigation_revision]
	if signature != _coordination_environment_signature:
		_coordination_environment_signature = signature
		_coordination_environment_revision += 1
	return cooperation.publish_member_versions(self, {"config_revision": _coordination_configuration_revision,
		"environment_revision": _coordination_environment_revision, "navigation_revision": navigation_revision})

func coordination_configuration_changed() -> void:
	_coordination_configuration_revision += 1

func _basic_coordination_offer(candidate: Dictionary, prepared_identity: Variant = null) -> Dictionary:
	var destination: Dictionary = candidate.get("destination", {})
	var point: Vector3 = candidate.get("route_target", destination.get("position", destination.get("hide", Vector3.INF)))
	if not point.is_finite(): return {}
	if _horizontal_distance(point) <= 0.12 and absf(actor.global_position.y - point.y) <= 0.5: return {}
	var identity: Dictionary = cooperation.coordination_identity(self) if prepared_identity == null else prepared_identity
	if identity.is_empty(): return {}
	var owner: StringName = candidate.get("id", &"")
	var offer: Dictionary = identity.duplicate()
	var key := str([owner, candidate.get("plan", &""), candidate.get("mode", &""), point])
	offer.merge({"scope": &"basic", "role": &"independent_position", "offer_key": key,
		"owner_action": owner, "position_set_key": str(point), "position": point,
		"target_id": 0, "evidence_id": 0, "path_summary": {},
		"captured_at": evidence_elapsed_seconds, "valid_until": evidence_elapsed_seconds + 0.5})
	return offer

## Prepare follows the action's live validate and precedes clearing its old
## execution. The pending token survives that clear; begin failure only rolls it back.
func prepare_coordination_choice(candidate: Dictionary) -> Dictionary:
	var offer: Dictionary = candidate.get("coordination_offer", {})
	if offer.is_empty() or cooperation == null or cooperation.registered_member_count() <= 1: return {"required": false, "token": {}}
	var path: PackedVector3Array = candidate.get("destination", {}).get("path", PackedVector3Array())
	var length := 0.0
	var previous: Vector3 = actor.global_position
	for point: Vector3 in path:
		length += _horizontal_distance_between(previous, point)
		previous = point
	if path.is_empty(): length = _horizontal_distance(offer.position)
	var duration := clampf(length / maxf(0.1, actor.move_speed) + utility_horizon_seconds, 4.0, 30.0)
	return {"required": true, "token": cooperation.prepare_reservation(self, offer, duration)}

func commit_coordination_choice(transaction: Dictionary) -> bool:
	if not transaction.get("required", false): return true
	var token: Dictionary = transaction.get("token", {})
	if cooperation == null or token.is_empty(): return false
	if not cooperation.commit_reservation(self, token): return false
	_coordination_reservation = token
	return true

func rollback_coordination_choice(transaction: Dictionary) -> void:
	if cooperation != null and transaction.get("required", false): cooperation.rollback_reservation(self, transaction.get("token", {}))

## A continuing, already begun and currently validated action may acquire a new
## basic lease after its previous one expires. Existing leases never gain time.
## Dynamic personal destinations use the existing basic lease, never a team
## permission or a second reservation. Preparation remains read-only elsewhere.
func maintain_personal_destination(candidate: Dictionary) -> bool:
	if cooperation == null: return true
	var choice := candidate.duplicate()
	choice.coordination_offer = _basic_coordination_offer(choice)
	return maintain_coordination_choice(choice)

func maintain_coordination_choice(candidate: Dictionary) -> bool:
	var offer: Dictionary = candidate.get("coordination_offer", {})
	if cooperation == null: return true
	if offer.is_empty() or cooperation.registered_member_count() <= 1:
		if not _coordination_reservation.is_empty(): cooperation.release_reservation(self, _coordination_reservation)
		_coordination_reservation = {}
		return true
	if not _coordination_reservation.is_empty() and _coordination_reservation.get("offer_key") == offer.offer_key and cooperation.validate_reservation(self, _coordination_reservation): return true
	var transaction := prepare_coordination_choice(candidate)
	if commit_coordination_choice(transaction): return true
	rollback_coordination_choice(transaction)
	return false

func cooperation_line_safe(origin: Vector3, endpoint: Vector3) -> bool:
	if not _cooperation_preview_snapshot.is_empty():
		return cooperation.line_safe_from_members(self, origin, endpoint, _cooperation_preview_snapshot.get("physical_members", _cooperation_preview_snapshot.members))
	return cooperation.line_safe(self, origin, endpoint) if cooperation != null else true

func cooperation_publish_execution(output: Dictionary) -> void:
	if cooperation == null: return
	var firearms: bool = actor.can_use_firearms()
	var rounds: int = actor.ammo.magazine_rounds
	var intent: Dictionary = output.get("fire", {})
	var target := Vector3.INF
	if not intent.is_empty():
		target = intent.get("point", Vector3.INF) if intent.get("mode", &"") == &"memory" else (last_seen_aim_position if sees_player else Vector3.INF)
	var ready := false
	var supported := 0.0
	var cycle_resume := -1.0
	var moving: bool = not actor.get_local_movement_velocity().is_zero_approx() or Vector2(actor.velocity.x, actor.velocity.z).length_squared() > 0.0025
	if firearms and target.is_finite() and rounds > 0 and not actor.ammo.is_reloading and not actor.is_vaulting() and not actor.melee_active and actor.shooting_enabled:
		var origin: Vector3 = actor.get_shot_origin()
		var desired: Vector3 = target - origin
		ready = not desired.is_zero_approx() and actor.aim_acquired and actor.aim_direction.angle_to(desired) <= actor.AIM_ACQUIRE_ANGLE and desired.length() <= actor.weapon.fire_range
		ready = ready and (intent.get("mode", &"") == &"memory" or fire.fire_reaction_elapsed >= fire.fire_reaction_seconds)
		ready = ready and (intent.get("mode", &"") == &"memory" or fire.fire_decision.selected_action != fire.fire_decision.Action.STEADY)
		ready = ready and fire.has_clear_firing_lane(origin, desired, desired.length()) and cooperation_line_safe(origin, target)
		ready = ready and (not moving or fire.fire_while_moving)
		# Execution fires along the current gun direction. A nearby clear target
		# ray alone cannot publish support while that actual ray still hits a wall.
		if ready and not actor.aim_direction.is_equal_approx(desired.normalized()):
			ready = fire.has_clear_firing_lane(origin, actor.aim_direction, desired.length())
		if ready and fire.fire_pause_remaining > 0.0:
			cycle_resume = fire.support_cycle_resume_seconds(intent, moving)
			ready = false
		if ready:
			supported = minf(utility_horizon_seconds, fire.burst_window_seconds(intent.get("support_intent", false)))
	var task: Dictionary = utility_current.get("cooperation", {})
	cooperation.publish_status(self, {"position": actor.global_position, "target_id": cooperation_target_id(), "ready": ready,
		"firearms": firearms, "reloading": actor.ammo.is_reloading, "rounds": rounds, "support_seconds": supported,
		"support_cycle_valid": cycle_resume >= 0.0, "support_resume_seconds": cycle_resume,
		"melee_threat_seconds": melee.support_window(sees_player),
		"aim_position": target, "forward": actor.aim_direction, "moving": moving,
		"health_ratio": actor.health / maxf(1.0, actor.max_health), "pressure": recent_damage_pressure + nearby_shot_pressure,
		"magazine_capacity": actor.weapon.magazine_capacity if firearms else 0, "can_move": actor.can_move(), "lane_id": &"target",
		"position_lane_id": task.get("lane_id", &""),
		"beneficiary_id": task.get("beneficiary_id", 0), "request_id": task.get("request_id", 0),
		"reload_seconds": actor.weapon.reload_seconds * (1.0 - actor.ammo.reload_progress) if firearms and actor.ammo.is_reloading else 0.0})


var _battle_capabilities: Dictionary = {}

func commanded() -> bool:
	return cooperation != null and cooperation.has_team_binding(self) and cooperation_level() > 0

## AI publishes only successfully instantiated actions, after equipment setup.
func install_member_capabilities(value: Dictionary) -> void:
	_battle_capabilities = value.duplicate(true)

func member_capability_snapshot() -> Dictionary:
	return _battle_capabilities.duplicate(true)

func member_runtime_snapshot() -> Dictionary:
	var result := coordination_motion_state()
	result.merge({"visible": sees_player, "health": actor.health,
		"rounds": actor.ammo.magazine_rounds, "can_reload": actor.can_use_firearms() and actor.ammo.can_reload(),
		"reloading": actor.ammo.is_reloading, "reload_remaining": actor.weapon.reload_seconds * (1.0 - actor.ammo.reload_progress) if actor.weapon != null and actor.ammo.is_reloading else 0.0,
		"occupied": actor.is_vaulting() or actor.melee_active or not actor.can_move(),
		"firearms": actor.can_use_firearms(), "can_attack": actor.shooting_enabled and not actor.is_vaulting() and not actor.melee_active,
		"blocked_paths": _blocked_ally_paths.size()}, true)
	return result

func validate_command_post(task: Dictionary, profile: Dictionary) -> bool:
	var action: StringName = task.get("action", &"")
	if profile.is_empty() or not profile.get("ready", false) or not can_use_action(action): return false
	if not profile.actions.has(action) or not profile.actions[action].roles.has(task.get("role")): return false
	if not task.get("position", Vector3.INF).is_finite(): return false
	if task.role in [&"reload", &"support"] and not actor.can_use_firearms(): return false
	var path: PackedVector3Array = task.get("route", PackedVector3Array())
	return not path.is_empty() and _horizontal_distance_between(path[-1], task.position) <= 0.1

func command_observation_valid(task: Dictionary) -> bool:
	if _horizontal_distance(task.get("position", Vector3.INF)) > 0.18: return false
	var point: Vector3 = task.get("look_position", Vector3.INF)
	if not point.is_finite(): return false
	var direction := point - actor.global_position
	direction.y = 0.0
	if direction.length() > perception.sight_distance: return false
	if direction.length() > 0.2 and -actor.global_basis.z.dot(direction.normalized()) < 0.5: return false
	return cover_selection.has_clear_line(actor.get_posture_eye_position(false), point + Vector3.UP * 0.7)

func accept_command(task: Dictionary) -> bool:
	return commanded() and _coordinator().accept(self, task)

func report_command(task: Dictionary, state: StringName, facts: Dictionary = {}) -> bool:
	if not commanded(): return false
	var report := task.duplicate(true)
	report.merge(facts, true)
	report.merge({"state": state, "position": actor.global_position, "velocity": actor.velocity}, true)
	return _coordinator().report(self, report)

func command_permission(task: Dictionary) -> Dictionary:
	return _coordinator().motion_permission(self, task) if commanded() else {"allowed": false, "waiting_for": []}

func command_support_pressure() -> float:
	return _coordinator().support_demand(self) if commanded() else 0.0
