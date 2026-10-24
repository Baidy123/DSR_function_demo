extends RefCounted

## 所有动作的统一协议。实例只属于一个敌人；定义与参数资源不存执行进度。
var context
var definition: EnemyActionDefinition
var action_id: StringName
var config_section: StringName
var route_motion = preload("res://scripts/enemy/actions/enemy_route_motion.gd").new()
var plan: Dictionary = {}
var _running := false
var _standalone_settings: Dictionary = {}
var _battle_settings: Dictionary = {}
var actor:
	get: return context.actor if context != null else null
var enemy:
	get: return actor
var agent:
	get: return context.agent
var selection:
	get: return context.cover_selection

func setup(shared_context, section: StringName = &"") -> void:
	context = shared_context
	if not section.is_empty():
		config_section = section

func configuration_changed() -> void:
	config_section = definition.config_section

func is_enabled() -> bool:
	return context != null and context.can_use_action(action_id)

func _setting(key: StringName, fallback: Variant) -> Variant:
	if context != null and context.commanded() and _battle_settings.has(key): return _battle_settings[key]
	if context != null and (context.training != null or (config_section == &"cooperation" and context.cooperation != null and context.cooperation.has_team_binding(context))):
		return context.setting(config_section, key, fallback, definition.parameters if definition != null else {})
	return _standalone_settings.get(key, definition.parameters.get(key, fallback) if definition != null else fallback)

func _set_setting(key: StringName, value: Variant) -> void:
	if context != null and context.training != null:
		context.training.set_setting(config_section, key, value)
	else:
		_standalone_settings[key] = value

func collect_candidates(_visible: bool) -> Array[Dictionary]:
	return []

func validate(candidate: Dictionary, _visible: bool) -> bool:
	if not is_enabled():
		return false
	var destination: Dictionary = candidate.get("destination", {})
	if destination.is_empty():
		return true
	var point: Vector3 = destination.get("position", destination.get("hide", Vector3.INF))
	return point.is_finite() and context.is_position_free(point) and not context.routes.planning_path(actor.global_position, point).is_empty()

func begin(candidate: Dictionary, _visible: bool) -> bool:
	plan = candidate
	route_motion.begin(candidate.get("route", {}))
	_running = true
	return true

func valid(visible: bool) -> bool:
	return _running and validate(plan, visible)

func tick(_delta: float, _visible: bool) -> Dictionary:
	return motion(Vector3.ZERO)

func cancel(_reason: StringName = &"switch") -> void:
	_running = false
	route_motion.reset()
	plan = {}
	reset()

func reset() -> void:
	pass

func can_interrupt(_next: Dictionary, _visible: bool) -> bool:
	return true

func hold_released() -> bool:
	return false

func on_event(_event: StringName, _data: Dictionary) -> void:
	pass

func on_shot_fired() -> void:
	pass

func state_label() -> String:
	return definition.display_name if definition != null else String(action_id)

func motion(direction: Vector3, multiplier: float = 1.0, facing: Vector3 = Vector3.INF, fire_request: Dictionary = {}, melee_request: Dictionary = {}) -> Dictionary:
	if not facing.is_finite():
		facing = context.last_known_position - actor.global_position if context.is_alerted else direction
	return {"direction": direction, "multiplier": multiplier, "facing": facing, "fire": fire_request, "melee": melee_request, "running": _running}

func option(destination: Dictionary, unavailable: float, exposure: float, information: float = 0.0, variant: StringName = &"") -> Dictionary:
	return {"id": action_id, "destination": destination, "plan": variant,
		"outcome": {"unavailable_seconds": unavailable, "exposed_seconds": exposure, "information_loss": information}}

func evaluation_points() -> Array:
	return []

## Changes to this action's non-geometric inputs invalidate only its own queue.
func evaluation_revision() -> int:
	return 0

func evaluate_point(_point: Variant) -> Dictionary:
	return {}

func evaluation_weight() -> int:
	return 1

## 仅控制空间查询预算，不影响动作评分、解锁或选择优先级。
func evaluation_priority_count() -> int:
	return 0

func evaluation_channel() -> StringName:
	return action_id


func execute_tick(delta: float, visible: bool) -> Dictionary:
	var output := tick(delta, visible) if route_motion.route.is_empty() else route_tick(delta, visible)
	if not _running:
		route_motion.reset()
		return output
	return route_motion.apply(context, output, delta)

func route_multiplier() -> float:
	return 1.0

func expand_route_candidates(candidates: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for candidate in candidates:
		var destination: Dictionary = candidate.get("destination", {})
		var point: Vector3 = candidate.get("route_target", destination.get("position", destination.get("hide", Vector3.INF)))
		# Action collection has already validated the ordinary destination under its
		# own spatial budget. Never repeat every path query in synchronous scoring.
		if not context.routes.requires_vault(point) or not candidate.get("route", {}).is_empty(): result.append(candidate)
		if not point.is_finite() or not candidate.get("route", {}).is_empty(): continue
		var alternatives: Array[Dictionary] = context.routes.alternatives(point)
		if alternatives.is_empty(): continue
		var path: PackedVector3Array = destination.get("path", PackedVector3Array())
		if path.is_empty(): path = context.routes.planning_path(actor.global_position, point)
		if path.is_empty(): continue
		var threat: Vector3 = context._known_reload_threat()
		if not threat.is_finite(): continue
		var multiplier := route_multiplier()
		var wait: float = context.spatial._reload_seconds(context) if actor.ammo.is_reloading else 0.0
		var original: Dictionary = context.spatial.assess_route(context, path, threat, multiplier, wait)
		for route in alternatives:
			var assessment: Dictionary = context.routes.assessment(route, multiplier, threat, wait)
			var alternative := candidate.duplicate(true)
			alternative.route = route
			var outcome: Dictionary = alternative.outcome
			var horizon: float = context.utility_horizon_seconds
			var time_change: float = assessment.seconds - original.seconds
			if float(outcome.unavailable_seconds) < horizon:
				outcome.unavailable_seconds = clampf(float(outcome.unavailable_seconds) + time_change, 0.0, horizon)
			# Vault interrupts fire and reload, even if the ordinary approach could shoot.
			outcome.unavailable_seconds = maxf(float(outcome.unavailable_seconds), minf(horizon, assessment.vault_seconds + wait))
			var at_destination: float = context._reload_exposure(point, threat, -1.0, destination.get("crouch", false))
			outcome.exposed_seconds = maxf(0.0, float(outcome.exposed_seconds) + assessment.exposure - original.exposure + at_destination * (maxf(0.0, horizon - assessment.seconds) - maxf(0.0, horizon - original.seconds)))
			outcome.information_loss = minf(horizon, maxf(0.0, float(outcome.information_loss) + time_change) + minf(horizon, assessment.vault_seconds))
			# A soft preference uses the existing shared score; geometry and actual
			# time/exposure remain unchanged. Base candidates never receive it.
			outcome.preference_credit = float(outcome.get("preference_credit", 0.0)) + maxf(0.0, float(context.setting(&"selection", &"vault_preference", 6.0)))
			result.append(alternative)
	if _running and not route_motion.route.is_empty() and valid(context.sees_player):
		var continuing := plan.duplicate(true)
		result.append(continuing)
	return result

func route_tick(_delta: float, _visible: bool) -> Dictionary:
	return motion(Vector3.ZERO, route_multiplier())


## These task kinds are declared by installed executors, never inferred from
## a unit's display name or silently granted by the team awareness setting.
func command_roles() -> Array[StringName]:
	return []

## The shared post adapter is also the default implementation for ordinary
## route/observation actions. Specialized tactics override this same protocol.
func prepare_command_offers(query: Dictionary, cursor: Dictionary, deadline_usec: int) -> Dictionary:
	if command_roles().is_empty(): return {"done": true, "offers": [], "reason": &"command_adapter_missing"}
	var work := cursor.duplicate(true)
	var index: int = work.get("index", 0)
	var count: int = work.get("count", 0)
	var sites: Array = query.get("sites", [])
	var offers: Array[Dictionary] = []
	while index < sites.size() and Time.get_ticks_usec() < deadline_usec:
		var site: Dictionary = sites[index].duplicate(true)
		var role: StringName = site.get("role", &"search" if query.objective.phase == &"search" else (&"engage" if query.objective.phase == &"contact" else &"patrol"))
		if not site.has("defense_post") and (query.body.reloading or query.body.can_reload and query.body.rounds == 0): role = &"reload"
		if not command_roles().has(role):
			index += 1
			continue
		site.role = role
		site.detour_variant = int(work.get("detour", 0))
		var offer := command_site_offer(query, site)
		if offer.get("retry_detour", false):
			work.detour = site.detour_variant + 1
		else:
			work.detour = 0
			index += 1
			if not offer.is_empty():
				offers.append(offer)
				count += 1
		break # One geometry unit per turn; the AI rotates through executors.
	work.index = index
	work.count = count
	return {"offers": offers, "next_cursor": work, "done": index >= sites.size() or count >= 6}

func command_site_offer(query: Dictionary, site: Dictionary) -> Dictionary:
	return preload("res://scripts/enemy/services/enemy_search_formation.gd").candidate(context, query.profile, query.body, site, query.objective, query.previous, action_id)

func validate_command_offer(query: Dictionary, offer: Dictionary) -> Dictionary:
	var valid_offer: bool = is_enabled() and offer.get("action") == action_id and command_roles().has(offer.get("role"))
	valid_offer = valid_offer and query.profile.get("actions", {}).has(action_id)
	valid_offer = valid_offer and query.profile.get("actions", {}).get(action_id, {}).get("attack_modes", [&"personal_sight"]).has(offer.get("attack", &"personal_sight"))
	return {"valid": valid_offer, "reason": &"" if valid_offer else &"executor_unavailable"}

func command_default_assignment() -> bool:
	return true

## Pure execution facts published by AI; the context never owns action objects.
func command_runtime_state() -> Dictionary:
	return {}

func freeze_command_capability() -> Dictionary:
	var values = {}
	var keys: Array = definition.parameters.keys() if definition != null else []
	var settings = context.training.module(config_section) if context.training != null else null
	if settings != null:
		for property in settings.get_property_list():
			if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and not property.name in [&"section", &"overridden"] and not keys.has(property.name): keys.append(property.name)
	for key in keys:
		var value = context.setting(config_section, key, null, definition.parameters if definition != null else {})
		if not value is Object: values[key] = value
	_battle_settings = values.duplicate(true)
	return {"roles": command_roles(), "parameters": values, "attack_modes": [&"personal_sight"], "default_assignment": command_default_assignment(), "implementation": get_script().resource_path,
		"required_capabilities": definition.required_capabilities.duplicate(),
		"basis": "installed:%s;unit-capabilities:%s;equipment-validated" % [action_id, definition.required_capabilities]}

var command: Dictionary = {}
var _command_index = 1
var _command_approach_index = -1
var _command_observe = 0.0
var _command_started = false
var _command_path_check = 0.0
var _command_attack_blocked = 0.0

func begin_command(task: Dictionary) -> bool:
	if not is_enabled() or not command_roles().has(task.get("role")): return false
	command = task.duplicate(true)
	plan = {"id": action_id, "plan": &"squad_command", "destination": {"position": task.position, "path": task.route}}
	_running = true
	_command_index = 1
	_command_approach_index = -1
	var staging: Vector3 = task.get("staging_position", Vector3.INF)
	for index in task.route.size():
		if preload("res://scripts/enemy/services/squad_contract.gd").horizontal(task.route[index], staging) <= 0.05:
			_command_approach_index = index
			break
	_command_observe = 0.0
	_command_started = false
	_command_path_check = 0.0
	_command_attack_blocked = 0.0
	return true

## Updating the same approved finite step does not restart its action timers.
func continue_command(task: Dictionary) -> void:
	var route_changed: bool = command.get("route") != task.get("route")
	command = task.duplicate(true)
	plan.destination = {"position": task.position, "path": task.route}
	if route_changed:
		_command_index = 1
		_command_approach_index = -1
		for index in task.route.size():
			if context._horizontal_distance_between(task.route[index], task.get("staging_position", Vector3.INF)) <= 0.05:
				_command_approach_index = index
				break

func command_look_position(fallback: Vector3 = Vector3.INF) -> Vector3:
	if not fallback.is_finite(): fallback = command.get("look_position", actor.global_position)
	var approach: Vector3 = command.get("approach_look_position", Vector3.INF)
	if command.get("role") == &"search" and approach.is_finite() and _command_index <= _command_approach_index:
		if context._horizontal_distance(command.staging_position) > 0.08: return approach
	return fallback

## Shared route following belongs to the action, like existing route_motion.
## Task work remains in its installed executor. No target/role is chosen here.
func execute_command(delta: float, visible: bool) -> Dictionary:
	var output = motion(Vector3.ZERO, 1.0, command_look_position() - actor.global_position)
	if visible: output.facing = context.last_known_position - actor.global_position
	output.scheduled_members = context.coordinated_stationary_members()
	if command.is_empty(): return output
	# Close defense is a body ability shared by all installed command executors.
	# Keep the owner intent alive throughout windup/recovery: body occupancy must
	# not cancel the very swing that caused it. The task and route stay unchanged.
	if context.melee.is_active_for(action_id) or (context.command_melee_enabled() and context.melee.can_request(visible)):
		output.facing = context.player.global_position - actor.global_position if visible else Vector3.ZERO
		output.melee = {"owner": action_id}
		context.report_command(command, &"occupied", {"reason": &"melee"})
		return output
	if actor.is_vaulting() or actor.melee_active or not actor.can_move():
		context.report_command(command, &"occupied", {"reason": &"body_busy"})
		return output
	var permission: Dictionary = context.command_permission(command)
	var path: PackedVector3Array = command.route
	while _command_index < path.size() and context._horizontal_distance(path[_command_index]) < 0.06: _command_index += 1
	if not visible: output.facing = command_look_position() - actor.global_position
	var arrived: bool = context._horizontal_distance(command.position) <= 0.08
	# A replacement inspection may end beside the body while requiring a
	# different preparation post first. Proximity cannot skip that route leg.
	if command.role == &"search" and _command_index <= _command_approach_index: arrived = false
	if arrived and visible and not actor.can_use_firearms() and command.role in [&"engage", &"flank"] and command.get("contact_post", true):
		# Test geometry facing the visible target, independently of actual
		# turning, cooldown and recovery. Those are valid reasons to hold.
		var toward: Vector3 = context.last_known_position - actor.global_position
		toward.y = 0.0
		if actor.melee_target_reachable(context.player, context.melee.weapon_settings(), toward.normalized()):
			_command_attack_blocked = 0.0
		else:
			_command_attack_blocked += delta
			if _command_attack_blocked >= 0.5:
				context.report_command(command, &"blocked", {"reason": &"attack_geometry"})
				return output
	else: _command_attack_blocked = 0.0
	if not permission.get("allowed", false):
		if not command.role in [&"search", &"reload"]:
			output.merge(command_work(delta, visible, arrived if command.role in [&"shelter", &"cover_peek"] else false), true)
		context.report_command(command, &"waiting", {"reason": permission.get("reason", &"passage"), "waiting_for": permission.get("waiting_for", [])})
		return output
	if not arrived:
		var waypoint: Vector3 = path[mini(_command_index, path.size() - 1)]
		var direction = waypoint - actor.global_position
		direction.y = 0.0
		_command_path_check -= delta
		if _command_path_check <= 0.0:
			_command_path_check = 0.2
			var shape: CollisionShape3D = actor.get_node("CollisionShape3D")
			if not preload("res://scripts/systems/character_geometry.gd").can_sweep(actor, actor.global_position, actor.global_position.move_toward(waypoint, 0.5), actor.get_body_height(), shape.shape.radius, true):
				context.report_command(command, &"blocked", {"reason": &"static_obstacle"})
				return output
		output.direction = direction.normalized()
		var speed := float(command.get("speed_multiplier", 1.0))
		var approach: Vector3 = command.get("staging_position", command.position)
		var travelling: bool = context._horizontal_distance(command.position) > 1.4 and context._horizontal_distance(approach) > 1.4
		if travelling and (command.role == &"flank" or command.has("overwatch_for") or permission.get("hurry", false)):
			speed = maxf(speed, float(command.get("run_speed_multiplier", speed)))
		if command.role == &"search" and context.coordination_now() < float(command.get("pursuit_until", -INF)) and context._horizontal_distance(approach) > 1.4:
			speed = maxf(speed, float(command.get("pursuit_multiplier", speed)))
		output.multiplier = minf(speed * float(permission.get("speed_scale", 1.0)), direction.length() / maxf(0.001, actor.move_speed * delta))
		output.stop_position = waypoint
		if not visible and not command.role in [&"search", &"engage", &"flank", &"support"]: output.facing = direction
	output.merge(command_work(delta, visible, arrived), true)
	if command.role in [&"patrol", &"move"] and arrived:
		_command_observe += delta
		if _command_observe >= (0.5 if command.role == &"patrol" else 0.0): context.report_command(command, &"complete")
	elif not command.role in [&"search", &"reload", &"shelter", &"cover_peek"]:
		context.report_command(command, &"executing", {"progress": 1.0 if arrived else 0.0})
	return output

func command_work(_delta: float, _visible: bool, _arrived: bool) -> Dictionary:
	return {}
