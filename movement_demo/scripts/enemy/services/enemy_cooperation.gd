extends RefCounted

const SquadCoordination = preload("res://scripts/enemy/services/squad_coordination.gd")

## One board per arena. All stored observations are value snapshots; members are weak.
var elapsed := 0.0
var generation := 0
var revision := 0
var relation_revision := 0
var _serial := 0
var _members: Dictionary = {}
var _reports: Dictionary = {}
var _checked: Dictionary = {}
var _relations: Dictionary = {}
var _inspection_reports: Dictionary = {}
var _reservations: Dictionary = {}
var _member_serial := 0
var _teams: Dictionary = {}
var _team_by_member: Dictionary = {}
var _team_settings: Dictionary = {}
var _team_setting_versions: Dictionary = {}
var _team_bindings_fingerprint := 0
var _team_bindings_initialized := false
var _team_config_serial := 0
## Positions are locally validated before this service reserves them.
## A reservation carries no tactical assignment or permission to execute a body.
const MAX_BASIC_RESERVATION_SECONDS := 30.0

## Explicit squads own their tactical state; this adapter serves legacy members.
var _legacy_coordinator = SquadCoordination.new()
var _squads: Dictionary = {}
var last_advance_usec := 0
var last_region_usec := 0

func _init() -> void:
	_legacy_coordinator.bind_environment(self)

func coordinator_for(context):
	if context != null and is_instance_valid(context.actor):
		var member: Dictionary = _members.get(context.actor.get_instance_id(), {})
		var squad_id: int = member.get("squad_id", 0)
		if squad_id != 0 and _squads.has(squad_id):
			var node = _squads[squad_id].node.get_ref()
			if is_instance_valid(node): return node.coordinator
		if member.is_empty():
			var squad := EnemyTeamCooperationBinding.squad_for_member(context.actor)
			if squad != null: return register_squad(squad)
	return _legacy_coordinator

func _coordinators() -> Array:
	var result: Array = [_legacy_coordinator]
	for entry: Dictionary in _squads.values():
		var node = entry.node.get_ref()
		if is_instance_valid(node): result.append(node.coordinator)
	return result

func register_squad(node: Node):
	var id := node.get_instance_id()
	if not _squads.has(id):
		_serial += 1
		_squads[id] = {"node": weakref(node), "team_id": _serial, "fingerprint": 0}
		node.attach_to_area(self, _serial)
	_refresh_squad(node, _squads[id])
	return node.coordinator

func unregister_squad(node: Node) -> void:
	var id := node.get_instance_id()
	if not _squads.has(id): return
	node.coordinator.reset()
	for member_id in _members.keys():
		if _members[member_id].get("squad_id", 0) == id: unregister(member_id)
	_squads.erase(id)
	_rebuild_teams()

func _refresh_squad(node: Node, entry: Dictionary) -> void:
	var fingerprint: int = node.fingerprint()
	if entry.fingerprint == fingerprint and node.coordinator.configuration_revision > 0: return
	entry.fingerprint = fingerprint
	node.coordinator.configure_profile(node.squad_configuration())
	for member_id: int in _members:
		if _members[member_id].get("squad_id", 0) == node.get_instance_id(): _release_member_reservations(member_id, true)
	revision += 1

func refresh_squads() -> void:
	for id in _squads.keys():
		var node = _squads[id].node.get_ref()
		if not is_instance_valid(node):
			_squads.erase(id)
			continue
		_refresh_squad(node, _squads[id])
	for id in _members.keys():
		var context = _context(id)
		if context != null and is_instance_valid(context.actor) and not _member_domain_matches(context.actor, _members[id]): register(context)

func member_faction(actor: Node) -> StringName:
	return EnemyTeamCooperationBinding.effective_faction(actor)

func member_group(actor: Node) -> StringName:
	return EnemyTeamCooperationBinding.effective_communication_group(actor)

func _squad_id(actor: Node) -> int:
	var squad := EnemyTeamCooperationBinding.squad_for_member(actor)
	return squad.get_instance_id() if squad != null else 0

## Diagnostic values only. Runtime reservation code never reads squad plans.
func coordination_debug_snapshot(field: StringName) -> Dictionary:
	var result: Dictionary = {}
	for coordinator in _coordinators():
		var value = coordinator.get(field)
		if value is Dictionary: result.merge(value.duplicate(true))
	return result

func configure_team_bindings(bindings: Array) -> void:
	var fingerprints: Array = []
	for binding in bindings: fingerprints.append(binding.fingerprint() if binding is EnemyTeamCooperationBinding else 0)
	var fingerprint := hash(fingerprints)
	if _team_bindings_initialized and fingerprint == _team_bindings_fingerprint: return
	_team_bindings_initialized = true
	_team_bindings_fingerprint = fingerprint
	var next: Dictionary = {}
	for binding in bindings:
		if not binding is EnemyTeamCooperationBinding: continue
		var key: String = binding.squad_key()
		if next.has(key):
			next[key].diagnostic = "同一小队存在重复绑定，战术安排已停用。"
			next[key].level = 0
			continue
		var profile = binding.profile
		next[key] = {"level": int(profile.level) if profile != null else 0,
			"values": profile.values() if profile != null else {},
			"overridden": profile.overridden.duplicate() if profile != null else PackedStringArray(),
			"diagnostic": "小队缺少团队意识配置。" if profile == null else ""}
	var changed: Array = []
	for key in _team_settings:
		if not next.has(key): changed.append(key)
	for key in next:
		if next[key] != _team_settings.get(key, {}): changed.append(key)
	if changed.is_empty(): return
	for key in changed:
		_team_config_serial += 1
		_team_setting_versions[key] = _team_config_serial
	for id: int in _members:
		if _members[id].get("squad_id", 0) != 0: continue
		if not changed.has(_members[id].domain): continue
		release_member(id)
		_drop_coordination_plan(int(_team_by_member.get(id, 0)), &"team_configuration")
	_team_settings = next
	_rebuild_teams()
	revision += 1

func _team_setting_key(context) -> String:
	if context == null or not is_instance_valid(context.actor): return ""
	var member: Dictionary = _members.get(context.actor.get_instance_id(), {})
	return member.domain if not member.is_empty() and _member_domain_matches(context.actor, member) else _domain(context.actor)

func has_team_binding(context) -> bool:
	if _team_settings.is_empty() and _direct_area_member(context): return false
	if context != null and is_instance_valid(context.actor) and _squad_id(context.actor) != 0: return true
	return not _team_settings.is_empty() and _team_settings.has(_team_setting_key(context))

## A direct child of its area cannot also have a Squad ancestor inside that area.
## Check the live parent, so this avoids repeated discovery without caching identity.
func _direct_area_member(context) -> bool:
	return context != null and is_instance_valid(context.actor) and context.actor.get_parent() == context.arena

func _squad_for_context(context) -> Node:
	return EnemyTeamCooperationBinding.squad_for_member(context.actor) if context != null and is_instance_valid(context.actor) else null

func team_abilities(context) -> Dictionary:
	var squad := _squad_for_context(context)
	if squad != null:
		var coordinator = register_squad(squad)
		return {"level": coordinator.configuration.get("level", 0), "squad_key": String(squad.name),
			"team_config_revision": coordinator.configuration_revision, "diagnostic": coordinator.configuration.get("diagnostic", "")}
	if _team_settings.is_empty(): return {}
	var key := _team_setting_key(context)
	if not _team_settings.has(key): return {}
	var settings: Dictionary = _team_settings[key]
	return {"level": settings.level, "squad_key": key, "team_config_revision": _team_setting_versions[key], "diagnostic": settings.diagnostic}

func team_level(context, legacy_level: int = 0) -> int:
	if _team_settings.is_empty() and _direct_area_member(context): return legacy_level
	var squad := _squad_for_context(context)
	if squad != null: return int(register_squad(squad).configuration.get("level", legacy_level))
	if _team_settings.is_empty(): return legacy_level
	var settings: Dictionary = _team_settings.get(_team_setting_key(context), {})
	return int(settings.get("level", legacy_level))

func team_configuration_revision(context) -> int:
	if _team_setting_versions.is_empty() and _direct_area_member(context): return 0
	var squad := _squad_for_context(context)
	if squad != null: return register_squad(squad).configuration_revision
	if _team_setting_versions.is_empty(): return 0
	return int(_team_setting_versions.get(_team_setting_key(context), 0))

func team_setting(context, key: StringName, fallback: Variant, unit_defaults: Dictionary = {}) -> Variant:
	var squad := _squad_for_context(context)
	var settings: Dictionary = register_squad(squad).configuration if squad != null else _team_settings.get(_team_setting_key(context), {})
	if key == &"level": return settings.get("level", fallback)
	var values: Dictionary = settings.get("values", {})
	if values.has(key) and (settings.overridden.has(String(key)) or not unit_defaults.has(key)): return values[key]
	return unit_defaults.get(key, fallback)

func team_configuration_diagnostics() -> Dictionary:
	var result: Dictionary = {}
	for key in _team_settings:
		if not String(_team_settings[key].diagnostic).is_empty(): result[key] = _team_settings[key].diagnostic
	return result

func _rebuild_teams() -> void:
	var groups: Array = []
	var ids: Array = _members.keys()
	ids.sort()
	for id: int in ids:
		if _members[id].get("squad_id", 0) != 0: continue
		if not can_cooperate(id, id): continue
		var placed := false
		for group: Array in groups:
			if group.all(func(other): return can_cooperate(id, int(other))):
				group.append(id)
				placed = true
				break
		if not placed: groups.append([id])
	var next: Dictionary = {}
	_team_by_member.clear()
	for group: Array in groups:
		var key := JSON.stringify(group)
		var team: Dictionary = _teams.get(key, {})
		if team.is_empty():
			_serial += 1
			team = {"team_id": _serial, "members": group.duplicate()}
		next[key] = team
		for id: int in group: _team_by_member[id] = int(team.team_id)
	_teams = next
	var legacy_members: Dictionary = {}
	var legacy_mapping: Dictionary = {}
	for id: int in ids:
		if _members[id].get("squad_id", 0) == 0:
			legacy_members[id] = _members[id]
			legacy_mapping[id] = _team_by_member.get(id, 0)
	_legacy_coordinator.sync_members(legacy_members, _teams, legacy_mapping)
	for squad_id: int in _squads:
		var entry: Dictionary = _squads[squad_id]
		var node = entry.node.get_ref()
		if not is_instance_valid(node): continue
		var members: Dictionary = {}
		var mapping: Dictionary = {}
		for id: int in ids:
			if _members[id].get("squad_id", 0) != squad_id: continue
			members[id] = _members[id]
			mapping[id] = entry.team_id
			_team_by_member[id] = entry.team_id
		node.coordinator.sync_members(members, {str(squad_id): {"team_id": entry.team_id, "members": members.keys()}}, mapping)

func _reservation_member_valid(context) -> bool:
	if context == null or not is_instance_valid(context.actor): return false
	var id: int = context.actor.get_instance_id()
	return (_members.has(id) and _context(id) == context and context.cooperation == self
		and context.actor.is_inside_tree() and not context.actor.is_dead
		and is_instance_valid(context.arena) and context.arena.is_ancestor_of(context.actor)
		and _member_domain_matches(context.actor, _members[id]))

## Trusted Context glue publishes these revisions before it submits an offer.
## Register alone remains compatible, but cannot silently authorize version zero.

func publish_member_versions(context, versions: Dictionary) -> bool:
	for key in [&"config_revision", &"environment_revision", &"navigation_revision"]:
		if typeof(versions.get(key)) != TYPE_INT or int(versions[key]) < 0: return false
	register(context)
	if not _reservation_member_valid(context): return false
	var member: Dictionary = _members[context.actor.get_instance_id()]
	var changed: bool = not member.versions_published
	for key in [&"config_revision", &"environment_revision", &"navigation_revision"]:
		changed = changed or member[key] != versions[key]
	if not changed: return true
	_release_member_reservations(context.actor.get_instance_id(), true)
	coordinator_for(context).invalidate_member(context.actor.get_instance_id())
	for key in [&"config_revision", &"environment_revision", &"navigation_revision"]: member[key] = versions[key]
	member.versions_published = true
	revision += 1
	return true

func coordination_identity(context) -> Dictionary:
	if not _reservation_member_valid(context): return {}
	var id: int = context.actor.get_instance_id()
	var member: Dictionary = _members[id]
	return {"actor_id": id, "generation": generation, "member_generation": member.member_generation,
		"team_id": _team_by_member.get(id, 0), "domain": member.domain, "relation_revision": relation_revision,
		"config_revision": member.config_revision, "environment_revision": member.environment_revision,
		"navigation_revision": member.navigation_revision, "versions_published": member.versions_published,
		"team_config_revision": team_configuration_revision(context)}

func _reservation_text(value: Variant) -> bool:
	return (value is String or value is StringName) and not String(value).is_empty()

func _reservation_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))

func _reservation_summary_valid(summary: Variant) -> bool:
	if not summary is Dictionary: return false
	if summary.has("corridor_key") and not (summary.corridor_key is String or summary.corridor_key is StringName): return false
	if summary.has("exclusive_corridor") and not summary.exclusive_corridor is bool: return false
	var blocked: Variant = summary.get("blocked_position_sets", [])
	if not blocked is Array or blocked.size() > 32: return false
	for key in blocked:
		if not _reservation_text(key): return false
	if summary.has("firing_lane"):
		var lane: Variant = summary.firing_lane
		if not lane is Dictionary: return false
		for key in [&"origin", &"endpoint"]:
			if not lane.get(key) is Vector3 or not lane[key].is_finite(): return false
	return true

func _reservation_summary(summary: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in [&"corridor_key", &"exclusive_corridor", &"blocked_position_sets"]:
		if summary.has(key): result[key] = summary[key].duplicate() if summary[key] is Array else summary[key]
	if summary.has("firing_lane"):
		result.firing_lane = {"origin": summary.firing_lane.origin, "endpoint": summary.firing_lane.endpoint}
	return result

func _reservation_footprint(context, position: Vector3) -> Dictionary:
	var shape_node = context.actor.get_node_or_null("CollisionShape3D")
	var radius := 0.35
	if shape_node is CollisionShape3D and shape_node.shape is CapsuleShape3D:
		var scale: Vector3 = shape_node.global_basis.get_scale().abs()
		radius = shape_node.shape.radius * maxf(scale.x, scale.z)
	return {"position": position, "radius": radius,
		"height": maxf(radius * 2.0, context.actor.get_body_height() * absf(context.actor.global_basis.get_scale().y)),
		"margin": maxf(0.0, float(context.setting(&"cooperation", &"spacing_margin", 0.45)))}

func _reservation_offer_valid(context, offer: Dictionary) -> bool:
	if not _reservation_member_valid(context) or not _members[context.actor.get_instance_id()].versions_published: return false
	if int(offer.get("team_config_revision", 0)) != team_configuration_revision(context): return false
	if offer.get("scope") != &"basic" or offer.get("role") != &"independent_position": return false
	for key in [&"offer_key", &"owner_action", &"position_set_key"]:
		if not _reservation_text(offer.get(key)): return false
	if not context.can_use_action(StringName(offer.owner_action)): return false
	if not offer.get("position") is Vector3 or not offer.position.is_finite() or not _reservation_summary_valid(offer.get("path_summary", {})): return false
	var identity := coordination_identity(context)
	for key in [&"actor_id", &"generation", &"member_generation", &"config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if typeof(offer.get(key)) != TYPE_INT or offer[key] != identity[key]: return false
	for key in [&"target_id", &"evidence_id"]:
		if typeof(offer.get(key)) != TYPE_INT or offer[key] < 0: return false
	if offer.target_id != 0 and offer.target_id != context.cooperation_target_id(): return false
	if not _reservation_number(offer.get("captured_at")) or not _reservation_number(offer.get("valid_until")): return false
	return offer.captured_at >= 0.0 and offer.captured_at <= context.evidence_elapsed_seconds and offer.valid_until > context.evidence_elapsed_seconds

func _reservation_valid(entry: Dictionary) -> bool:
	if entry.get("scope") == &"tactical" and not _tactical_reservation_valid(entry): return false
	var context = _context(int(entry.owner_id))
	if not _reservation_member_valid(context) or entry.generation != generation or entry.expires_at <= elapsed: return false
	if int(entry.get("team_config_revision", 0)) != team_configuration_revision(context): return false
	if entry.phase == &"pending" and entry.accept_until <= elapsed: return false
	if not context.can_use_action(StringName(entry.owner_action)): return false
	if entry.target_id != 0 and context.cooperation_target_id() != entry.target_id: return false
	var identity := coordination_identity(context)
	for key in [&"member_generation", &"domain", &"config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if entry[key] != identity[key]: return false
	return true

func _reservation_token(context, token: Dictionary) -> Dictionary:
	if not _reservation_member_valid(context) or typeof(token.get("reservation_id")) != TYPE_INT: return {}
	var entry: Dictionary = _reservations.get(token.reservation_id, {})
	if entry.is_empty() or entry.owner_id != context.actor.get_instance_id() or not _reservation_valid(entry): return {}
	for key in [&"generation", &"member_generation", &"owner_action", &"offer_key", &"position_set_key", &"position", &"created_at", &"expires_at"]:
		if token.get(key) != entry[key]: return {}
	return entry

func _reservation_geometry_conflict(first: Dictionary, second: Dictionary) -> bool:
	var a: Dictionary = first.get("path_summary", {})
	var b: Dictionary = second.get("path_summary", {})
	if _reservation_text(first.get("position_set_key")) and first.position_set_key == second.get("position_set_key"): return true
	if a.get("blocked_position_sets", []).has(second.get("position_set_key")) or b.get("blocked_position_sets", []).has(first.get("position_set_key")): return true
	if _reservation_text(a.get("corridor_key")) and a.corridor_key == b.get("corridor_key") and (a.get("exclusive_corridor", false) or b.get("exclusive_corridor", false)): return true
	var vertical_overlap: bool = first.position.y < second.position.y + second.height and second.position.y < first.position.y + first.height
	var separation: Vector3 = first.position - second.position
	var clearance: float = first.radius + second.radius + maxf(first.margin, second.margin)
	if vertical_overlap and Vector2(separation.x, separation.z).length_squared() < clearance * clearance: return true
	if _reservation_lane_crosses(first, b.get("firing_lane", {})) or _reservation_lane_crosses(second, a.get("firing_lane", {})): return true
	return false

func _reservation_lane_crosses(footprint: Dictionary, lane: Dictionary) -> bool:
	if lane.is_empty() or lane.origin.distance_squared_to(lane.endpoint) <= 0.0001: return false
	var bottom: Vector3 = footprint.position + Vector3.UP * footprint.radius
	var top: Vector3 = footprint.position + Vector3.UP * (footprint.height - footprint.radius)
	var nearest: PackedVector3Array = Geometry3D.get_closest_points_between_segments(bottom, top, lane.origin, lane.endpoint)
	return nearest[0].distance_squared_to(nearest[1]) < pow(float(footprint.radius) + 0.1, 2.0)

func _reservation_position_available(context, entry: Dictionary, except_id: int = 0) -> bool:
	var owner: int = context.actor.get_instance_id()
	var current := entry.duplicate()
	current.merge(_reservation_footprint(context, entry.position), true)
	if entry.get("scope") == &"tactical": current.path_summary = _coordination_physical_summary(context, entry.get("path_summary", {}), entry.target_id)
	for other: Dictionary in _reservations.values():
		if other.reservation_id == except_id or other.owner_id == owner or not _reservation_valid(other) or not can_share_space(owner, other.owner_id): continue
		for projection: Dictionary in _reservation_projections(other):
			var actual := projection.duplicate()
			actual.merge(_reservation_footprint(_context(other.owner_id), projection.position), true)
			if other.get("scope") == &"tactical": actual.path_summary = _coordination_physical_summary(_context(other.owner_id), projection.get("path_summary", {}), other.target_id)
			if _reservation_geometry_conflict(current, actual): return false
	for id: int in _members:
		if id == owner or not can_share_space(owner, id): continue
		var other = _context(id)
		if not _reservation_member_valid(other): continue
		var body := _reservation_footprint(other, other.actor.global_position)
		if _reservation_geometry_conflict(current, body): return false
		var status: Dictionary = _members[id].status
		if _coordination_actual(other, int(status.get("target_id", 0))).fire_ready:
			var endpoint: Vector3 = status.get("aim_position", Vector3.INF)
			if endpoint.is_finite() and _reservation_lane_crosses(current, {"origin": other.actor.get_shot_origin(), "endpoint": endpoint}): return false
	return true

## Local to one synchronous read-only query. Never retained across publication,
## reservation transactions, body execution, or another query in the same frame.
func _reservation_obstacles(context, except_id: int = 0) -> Array[Dictionary]:
	var owner: int = context.actor.get_instance_id()
	var obstacles: Array[Dictionary] = []
	for other: Dictionary in _reservations.values():
		if other.reservation_id == except_id or other.owner_id == owner or not _reservation_valid(other) or not can_share_space(owner, other.owner_id): continue
		for projection: Dictionary in _reservation_projections(other):
			var actual := projection.duplicate()
			actual.merge(_reservation_footprint(_context(other.owner_id), projection.position), true)
			if other.get("scope") == &"tactical": actual.path_summary = _coordination_physical_summary(_context(other.owner_id), projection.get("path_summary", {}), other.target_id)
			obstacles.append(actual)
	for id: int in _members:
		if id == owner or not can_share_space(owner, id): continue
		var other = _context(id)
		if not _reservation_member_valid(other): continue
		var body := _reservation_footprint(other, other.actor.global_position)
		var status: Dictionary = _members[id].status
		if _coordination_actual(other, int(status.get("target_id", 0))).fire_ready:
			var endpoint: Vector3 = status.get("aim_position", Vector3.INF)
			if endpoint.is_finite(): body.path_summary = {"firing_lane": {"origin": other.actor.get_shot_origin(), "endpoint": endpoint}}
		obstacles.append(body)
	return obstacles

## Candidate filtering is read-only. Callers keep no-destination personal
## firing/self-preservation options outside this destination-reservation gate.

func reservation_offer_available(context, offer: Dictionary) -> bool:
	if not _reservation_offer_valid(context, offer): return false
	var entry := _reservation_footprint(context, offer.position)
	entry.position_set_key = offer.position_set_key
	entry.path_summary = _reservation_summary(offer.get("path_summary", {}))
	return _reservation_position_available(context, entry)

## Each offer keeps its full identity, permission and expiry validation. Only
## the common physical facts are prepared once; no caller receives the snapshot.
func reservation_offers_available(context, offers: Array[Dictionary]) -> Array[bool]:
	var result: Array[bool] = []
	# A single offer needs no shared obstacle array; transactions also retain
	# their live early-out query above.
	if offers.size() <= 1:
		for offer in offers: result.append(reservation_offer_available(context, offer))
		return result
	var obstacles: Array[Dictionary] = []
	var footprint: Dictionary = {}
	for offer: Dictionary in offers:
		if not _reservation_offer_valid(context, offer):
			result.append(false)
			continue
		if footprint.is_empty():
			footprint = _reservation_footprint(context, Vector3.ZERO)
			obstacles = _reservation_obstacles(context)
		var entry := footprint.duplicate()
		entry.position = offer.position
		entry.position_set_key = offer.position_set_key
		entry.path_summary = _reservation_summary(offer.get("path_summary", {}))
		var available := true
		for obstacle: Dictionary in obstacles:
			if _reservation_geometry_conflict(entry, obstacle):
				available = false
				break
		result.append(available)
	return result

## Offer times use the caller's evidence clock; token times use the board clock.
## Prepare never releases the old accepted position or starts an action.

func prepare_reservation(context, offer: Dictionary, duration: float = 4.0) -> Dictionary:
	if not is_finite(duration) or duration <= 0.0 or not _reservation_offer_valid(context, offer): return {}
	var owner: int = context.actor.get_instance_id()
	for current: Dictionary in _reservations.values():
		if current.owner_id == owner and current.phase == &"pending" and current.offer_key == offer.offer_key and current.position == offer.position and current.position_set_key == offer.position_set_key and current.owner_action == StringName(offer.owner_action) and current.path_summary == _reservation_summary(offer.get("path_summary", {})) and _reservation_valid(current):
			return current.duplicate(true) if _reservation_position_available(context, current, current.reservation_id) else {}
	var entry := _reservation_footprint(context, offer.position)
	entry.merge(coordination_identity(context))
	entry.merge({"owner_id": owner, "owner_action": StringName(offer.owner_action), "offer_key": offer.offer_key,
		"scope": &"basic", "role": &"independent_position", "position_set_key": offer.position_set_key,
		"path_summary": _reservation_summary(offer.get("path_summary", {})), "target_id": offer.target_id, "evidence_id": offer.evidence_id,
		"phase": &"pending", "created_at": elapsed, "expires_at": elapsed + minf(duration, MAX_BASIC_RESERVATION_SECONDS),
		"accept_until": elapsed + float(offer.valid_until) - context.evidence_elapsed_seconds})
	entry.accept_until = minf(entry.accept_until, entry.expires_at)
	if not _reservation_position_available(context, entry): return {}
	for id in _reservations.keys():
		if _reservations[id].owner_id == owner and _reservations[id].phase == &"pending": _reservations.erase(id)
	_serial += 1
	entry.reservation_id = _serial
	_reservations[_serial] = entry
	revision += 1
	return entry.duplicate(true)

func validate_reservation(context, token: Dictionary) -> bool:
	var entry := _reservation_token(context, token)
	return not entry.is_empty() and _reservation_position_available(context, entry, int(entry.reservation_id))

## Called only after local validate/begin succeeds. No clock or offer is renewed.

func commit_reservation(context, token: Dictionary) -> bool:
	var entry := _reservation_token(context, token)
	if entry.is_empty() or not _reservation_position_available(context, entry, int(entry.reservation_id)): return false
	if entry.phase == &"accepted": return true
	for id in _reservations.keys():
		if id != entry.reservation_id and _reservations[id].owner_id == entry.owner_id and _reservations[id].phase == &"accepted": _reservations.erase(id)
	entry.phase = &"accepted"
	entry.accepted_at = elapsed
	revision += 1
	return true

func rollback_reservation(context, token: Dictionary) -> void:
	var entry := _reservation_token(context, token)
	if not entry.is_empty() and entry.phase == &"pending":
		_reservations.erase(entry.reservation_id)
		revision += 1

func release_reservation(context, token: Dictionary) -> void:
	var entry := _reservation_token(context, token)
	if not entry.is_empty():
		_reservations.erase(entry.reservation_id)
		revision += 1

func _release_member_reservations(owner: int, include_pending: bool) -> void:
	for id in _reservations.keys():
		if _reservations[id].owner_id == owner and (include_pending or _reservations[id].phase == &"accepted"):
			_reservations.erase(id)

## Cross-radio callers see only friendly physical occupancy, never evidence,
## target IDs, action intent or the endpoints of another group's firing lane.

func reservation_snapshot(context) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _reservation_member_valid(context): return result
	var owner: int = context.actor.get_instance_id()
	for entry: Dictionary in _reservations.values():
		if not _reservation_valid(entry) or not can_share_space(owner, int(entry.owner_id)): continue
		for projection: Dictionary in _reservation_projections(entry):
			var footprint := _reservation_footprint(_context(entry.owner_id), projection.position)
			result.append({"reservation_id": entry.reservation_id, "actor_id": entry.owner_id, "kind": &"reservation",
				"phase": entry.phase, "position": projection.position, "radius": footprint.radius, "height": footprint.height,
				"margin": footprint.margin, "position_set_key": projection.position_set_key, "created_at": entry.created_at,
				"expires_at": entry.expires_at, "generation": entry.generation})
	return result

func advance(delta: float) -> void:
	var started := Time.get_ticks_usec()
	refresh_squads()
	elapsed += maxf(0.0, delta)
	for id in _members.keys():
		var context = _context(id)
		if context == null or not is_instance_valid(context.actor) or not context.actor.is_inside_tree() or context.actor.is_dead:
			unregister(id)
	for key in _checked.keys():
		if elapsed >= _checked[key].valid_until: _checked.erase(key)
	for key in _inspection_reports.keys():
		if elapsed >= float(_inspection_reports[key].valid_until): _inspection_reports.erase(key)
	for reservation_id in _reservations.keys():
		if not _reservation_valid(_reservations[reservation_id]):
			_reservations.erase(reservation_id)
			revision += 1
	last_region_usec = Time.get_ticks_usec() - started
	_legacy_coordinator.advance()
	for entry: Dictionary in _squads.values():
		var node = entry.node.get_ref()
		if is_instance_valid(node): node.advance_from_area(Engine.get_physics_frames())
	last_advance_usec = Time.get_ticks_usec() - started

func reset() -> void:
	generation += 1
	elapsed = 0.0
	_reports.clear()
	_checked.clear()
	_inspection_reports.clear()
	_reservations.clear()
	_clear_coordination()
	for member in _members.values():
		member.status = {}
		member.activity = {}
	revision += 1

func register(context) -> bool:
	var id: int = context.actor.get_instance_id()
	var squad := EnemyTeamCooperationBinding.squad_for_member(context.actor)
	if squad != null: register_squad(squad)
	var changed: bool = _members.has(id) and (not _member_domain_matches(context.actor, _members[id]) or _context(id) != context)
	if changed: unregister(id)
	if not _members.has(id):
		_member_serial += 1
		_members[id] = {"context": weakref(context), "domain": _domain(context.actor), "faction": member_faction(context.actor), "group": member_group(context.actor), "squad_id": _squad_id(context.actor), "status": {}, "activity": {},
			"member_generation": _member_serial, "versions_published": false, "config_revision": 0, "environment_revision": 0, "navigation_revision": 0}
		_rebuild_teams()
		revision += 1
	return changed

func unregister(id: int) -> void:
	if not _members.has(id): return
	release_member(id)
	_members.erase(id)
	_rebuild_teams()
	revision += 1

func release_member(id: int) -> void:
	coordinator_for(_context(id)).release_member(id)
	_release_member_reservations(id, true)
	if _members.has(id): _members[id].status = {}
	revision += 1

## Ending an action is not ending the body's reload or leaving the team.
## Dependent allies keep their finite leases while the same real need exists.

func clear_execution(id: int) -> void:
	_release_member_reservations(id, false)
	coordinator_for(_context(id)).clear_execution(id)
	if _members.has(id):
		var status: Dictionary = _members[id].status
		if not status.is_empty():
			status.ready = false
			status.support_seconds = 0.0
			status.support_cycle_valid = false
			status.support_resume_seconds = -1.0
			status.support_request = {}
			status.erase("support_request_id")
			status.erase("support_request_id_signature")
	# updated_at remains the time of the real publication, not this cancellation.
	revision += 1

func _context(id: int):
	return _members[id].context.get_ref() if _members.has(id) else null

## Cheap invalidation hint only; eligibility still uses the full domain checks.

func registered_member_count() -> int:
	return _members.size()

func _domain(actor) -> String:
	return JSON.stringify([String(member_faction(actor)), String(member_group(actor))])

## Compare live fields on every check; serialization is only needed for keys.

func _member_domain_matches(actor, member: Dictionary) -> bool:
	# One live ancestor walk checks all identity fields; do not cache eligibility.
	var parent: Node = actor.get_parent()
	if int(member.get("squad_id", 0)) == 0 and parent != null and parent.has_method("enemy_environment"):
		return actor.faction_id == member.faction and actor.communication_group == member.group
	var squad := EnemyTeamCooperationBinding.squad_for_member(actor)
	if squad != null:
		return squad.get_instance_id() == int(member.get("squad_id", 0)) and squad.faction_id == member.faction and squad.communication_group == member.group
	return int(member.get("squad_id", 0)) == 0 and actor.faction_id == member.faction and actor.communication_group == member.group

func _key(domain: String, target: int) -> String:
	return "%s:%s:%s" % [generation, domain, target]

func set_relation(first: StringName, second: StringName, relation: StringName) -> void:
	if _relations.get([first, second]) == relation and _relations.get([second, first]) == relation: return
	_relations[[first, second]] = relation
	_relations[[second, first]] = relation
	_reservations.clear()
	_clear_coordination()
	_rebuild_teams()
	_inspection_reports.clear()
	relation_revision += 1
	revision += 1

func is_hostile(observer_faction: StringName, target_faction: StringName) -> bool:
	if observer_faction == target_faction: return false
	var initial: StringName = &"hostile" if (observer_faction == &"enemy" and target_faction == &"player") or (observer_faction == &"player" and target_faction == &"enemy") else &"neutral"
	return _relations.get([observer_faction, target_faction], initial) == &"hostile"

func can_share_intel(sender_id: int, receiver_id: int) -> bool:
	if not _members.has(sender_id) or not _members.has(receiver_id): return false
	for id in [sender_id, receiver_id]:
		var context = _context(id)
		if context == null or not is_instance_valid(context.actor) or context.actor.is_dead or not _member_domain_matches(context.actor, _members[id]): return false
	var first: Dictionary = _members[sender_id]
	var second: Dictionary = _members[receiver_id]
	return first.group == second.group and (first.faction == second.faction or _relations.get([first.faction, second.faction], &"") == &"allied")

func can_cooperate(first_id: int, second_id: int) -> bool:
	if not can_share_intel(first_id, second_id): return false
	return _cooperation_domains_match(first_id, second_id)

## Only after the same synchronous read has validated both live identities.
func _cooperation_domains_match(first_id: int, second_id: int) -> bool:
	var first_squad: int = _members[first_id].get("squad_id", 0)
	var second_squad: int = _members[second_id].get("squad_id", 0)
	if first_squad != 0 or second_squad != 0: return first_squad != 0 and first_squad == second_squad
	var first: String = _members[first_id].domain
	var second: String = _members[second_id].domain
	return first == second or (not _team_settings.has(first) and not _team_settings.has(second))

## Physical courtesy does not require belonging to the same radio group.

func can_share_space(first_id: int, second_id: int) -> bool:
	for id in [first_id, second_id]:
		var context = _context(id)
		if context == null or not is_instance_valid(context.actor) or not context.actor.is_inside_tree() or context.actor.is_dead: return false
	var first = _context(first_id).actor
	var second = _context(second_id).actor
	var first_faction := member_faction(first)
	var second_faction := member_faction(second)
	return first_faction == second_faction or _relations.get([first_faction, second_faction], &"") == &"allied"

func publish_visual(context) -> void:
	if not context.sees_player or not context.last_seen_position.is_finite(): return
	var observer: int = context.actor.get_instance_id()
	if not _members.has(observer): register(context)
	var target: int = context.cooperation_target_id()
	if target == 0: return
	for inspection_key in _inspection_reports.keys():
		var investigation: Dictionary = _inspection_reports[inspection_key]
		if investigation.target_id != target or not _inspection_domain_matches(context, investigation): continue
		if investigation.source != &"shared_visual" or investigation.position.distance_to(context.last_seen_position) >= 0.5:
			_inspection_reports.erase(inspection_key)
			_drop_inspection_claims(int(investigation.id))
	var key := _key(_members[observer].domain, target)
	var old: Dictionary = _reports.get(key, {})
	var reloading: bool = context.observed_reload_remaining > 0.0
	if not old.is_empty() and old.observer_id == observer and elapsed - float(old.captured_at) < 0.2 and old.position.distance_to(context.last_seen_position) < 0.1 and old.reloading == reloading:
		_publish_visual_coordination(context, old)
		return
	_serial += 1
	_reports[key] = {"target_id": target, "observer_id": observer, "faction": member_faction(context.actor), "group": member_group(context.actor),
		"position": context.last_seen_position, "observer_position": context.actor.global_position, "aim_position": context.last_seen_aim_position, "direction": context.last_seen_direction, "velocity": context.observed_velocity,
		"captured_at": elapsed, "valid_until": elapsed + maxf(0.1, context.setting(&"cooperation", &"intel_seconds", 5.0)),
		"id": _serial, "generation": generation, "source": &"shared_visual", "shared": true,
		"reloading": reloading, "reload_until": elapsed + context.observed_reload_remaining}
	revision += 1
	_publish_visual_coordination(context, _reports[key])

## Personal sight is also a real source. evidence() intentionally excludes
## the sender, so forwarding only received radio intel would miss visible teams.

func _publish_visual_coordination(context, report: Dictionary) -> void:
	if _members.size() <= 1 or not context.cooperation_enabled(): return
	var offset: float = context.evidence_elapsed_seconds - elapsed
	var captured: float = float(report.captured_at) + offset
	publish_coordination_source(context, {"source_id": int(report.id), "source": &"observation_memory",
		"target_id": int(report.target_id), "position": report.position, "captured_at": captured,
		"valid_until": captured + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0))})

func _inspection_domain_matches(context, report: Dictionary) -> bool:
	return report.get("group") == member_group(context.actor) and (report.get("faction") == member_faction(context.actor) or _relations.get([report.get("faction"), member_faction(context.actor)], &"") == &"allied")

func _drop_inspection_claims(inspection_id: int) -> void:
	for coordinator in _coordinators(): coordinator._drop_inspection_claims(inspection_id)

func publish_inspection(context, evidence: Dictionary) -> Dictionary:
	var target: int = int(evidence.get("target_id", 0))
	var point: Vector3 = evidence.get("position", Vector3.INF)
	if target == 0 or target != context.cooperation_target_id() or not point.is_finite(): return {}
	if not _members.has(context.actor.get_instance_id()): register(context)
	var key := _key(_domain(context.actor), target)
	var offset: float = elapsed - context.evidence_elapsed_seconds
	var deadline: float = float(evidence.get("valid_until", -INF)) + offset
	if deadline <= elapsed: return {}
	var cover = evidence.get("cover")
	if cover is WeakRef: cover = cover.get_ref()
	var cover_id: int = cover.get_instance_id() if is_instance_valid(cover) else 0
	var captured: float = float(evidence.get("captured_at", context.evidence_elapsed_seconds)) + offset
	var old: Dictionary = _inspection_reports.get(key, {})
	if not old.is_empty() and float(old.valid_until) > elapsed and int(old.cover_id) == cover_id and old.position.distance_to(point) < 0.5:
		if evidence.get("source") == &"shared_visual" or absf(captured - float(old.captured_at)) <= 0.75: return old.duplicate(true)
	if not old.is_empty(): _drop_inspection_claims(int(old.id))
	_serial += 1
	var value := evidence.duplicate(true)
	value.merge({"id": _serial, "target_id": target, "position": point, "observer_id": context.actor.get_instance_id(),
		"faction": member_faction(context.actor), "group": member_group(context.actor), "generation": generation,
		"captured_at": captured, "valid_until": deadline, "cover_id": cover_id, "cover": weakref(cover) if is_instance_valid(cover) else null,
		"checked_ends": [], "source": evidence.get("source", &"visual_loss")}, true)
	_inspection_reports[key] = value
	revision += 1
	return value.duplicate(true)

func inspection_evidence(context, target: int) -> Dictionary:
	var best: Dictionary = {}
	for report: Dictionary in _inspection_reports.values():
		if int(report.target_id) != target or float(report.valid_until) <= elapsed or not _inspection_domain_matches(context, report): continue
		if best.is_empty() or int(report.id) > int(best.id): best = report
	return best.duplicate(true)

## Read-only stable allocation of the two end roles. Positions rank suitable
## bodies; each action still proves its own exact route before taking a lease.

func inspection_eligible_count(context, target: int) -> int:
	return coordinator_for(context).inspection_eligible_count(context, target)

func inspection_end(context, geometry: Dictionary) -> int:
	return coordinator_for(context).inspection_end(context, geometry)

func inspection_revision(context, inspection_id: int) -> int:
	return coordinator_for(context).inspection_revision(context, inspection_id)

func inspection_partner_ready(context, token: Dictionary) -> bool:
	return coordinator_for(context).inspection_partner_ready(context, token)

func complete_inspection(context, token: Dictionary) -> void:
	coordinator_for(context).complete_inspection(context, token)

func evidence(context, target: int) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	if not _members.has(id): return {}
	var best: Dictionary = {}
	for report in _reports.values():
		if report.target_id != target or report.observer_id == id: continue
		if report.group != member_group(context.actor): continue
		if report.faction != member_faction(context.actor) and _relations.get([report.faction, member_faction(context.actor)], &"") != &"allied": continue
		if best.is_empty() or int(report.id) > int(best.id): best = report
	return best.duplicate(true)

func publish_status(context, status: Dictionary) -> void:
	var id: int = context.actor.get_instance_id()
	if not _members.has(id): register(context)
	var old: Dictionary = _members[id].status
	var entry := status.duplicate(true)
	for kind in [&"reload", &"support"]:
		var field: String = "%s_request_id" % kind
		var signature: Array = [entry.get("target_id", 0), kind, entry.get("support_request", {}).get("kind", &"") if kind == &"support" else &"reload"]
		var requested: bool = entry.get("reloading", false) if kind == &"reload" else not entry.get("support_request", {}).is_empty()
		if requested:
			if old.get(field + "_signature", []) != signature:
				_serial += 1
				entry[field] = _serial
			else:
				entry[field] = old[field]
			entry[field + "_signature"] = signature
	entry.id = id
	entry.updated_at = elapsed
	_members[id].status = entry
	# Activity outlives an execution switch. Clearing a fire intent must not
	# momentarily remove a living participant from the opposite-side quota.
	_members[id].activity = {"target_id": entry.get("target_id", 0), "updated_at": elapsed}
	var changed: bool = old.is_empty() or old.get("ready", false) != entry.get("ready", false) or old.get("reloading", false) != entry.get("reloading", false) or old.get("moving", false) != entry.get("moving", false) or old.get("target_id", 0) != entry.get("target_id", 0)
	var old_position: Vector3 = old.get("position", Vector3.INF)
	var new_position: Vector3 = entry.get("position", Vector3.INF)
	if old_position.is_finite() and new_position.is_finite():
		changed = changed or coordinator_for(context).crossed_flank(context, old_position, new_position)
	if changed: revision += 1

func snapshot(context, target: int) -> Dictionary:
	return _snapshot(context, target, false)

## Fire timing only needs current requests and support windows. Use the same
## live validation as the full snapshot without copying unrelated member data.
func support_snapshot(context, target: int) -> Dictionary:
	return _snapshot(context, target, true)

func _snapshot(context, target: int, support_only: bool) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	var result := {"requests": [], "supports": []} if support_only else {"members": [], "physical_members": [], "requests": [], "claims": [], "supports": [], "threats": [], "revision": revision, "generation": generation, "elapsed": elapsed}
	for other_id in _members:
		if support_only and other_id == id: continue
		var other = _context(other_id)
		if other == null or not is_instance_valid(other.actor) or other.actor.is_dead or not other.actor.is_inside_tree(): continue
		var status: Dictionary = _members[other_id].status
		if status.is_empty() or elapsed - float(status.updated_at) > 0.35: continue
		var shares_intel := can_share_intel(other_id, id)
		if not support_only and (shares_intel or can_share_space(other_id, id)): result.physical_members.append({"id": other_id, "position": status.position})
		if not shares_intel: continue
		var cooperative := _cooperation_domains_match(other_id, id)
		if support_only and (not cooperative or int(status.get("target_id", 0)) != target): continue
		var age: float = maxf(0.0, elapsed - float(status.updated_at))
		var support_seconds: float = maxf(0.0, float(status.get("support_seconds", 0.0)) - age)
		var fire_unavailable: bool = other.actor.ammo.is_reloading or other.actor.ammo.magazine_rounds <= 0 or not other.actor.shooting_enabled or other.actor.is_vaulting() or other.actor.melee_active
		if fire_unavailable: support_seconds = 0.0
		# Reduced queries only read stored status; all returned values are new.
		var member: Dictionary = status if support_only else status.duplicate(true)
		if not support_only:
			member.support_seconds = support_seconds
			if support_seconds <= 0.0: member.ready = false
			member.support_resume_seconds = maxf(0.0, float(member.get("support_resume_seconds", 0.0)) - age) if member.get("support_cycle_valid", false) else -1.0
			if fire_unavailable:
				member.support_cycle_valid = false
				member.support_resume_seconds = -1.0
			member.can_cooperate = cooperative
			result.members.append(member)
		if not cooperative: continue
		# Requests retain their published duration; only support windows age here.
		if int(member.get("target_id", 0)) != target: continue
		if not support_only:
			var threat_seconds: float = maxf(0.0, float(member.get("melee_threat_seconds", 0.0)) - age)
			if threat_seconds > 0.0:
				result.threats.append({"owner_id": other_id, "support_seconds": threat_seconds, "lane_id": &"target", "position": member.position, "kind": &"melee"})
		if member.get("ready", false) and support_seconds > 0.0:
			var support: Dictionary = {"support_seconds": support_seconds, "moving": member.get("moving", false), "lane_id": member.get("lane_id", &"target")} if support_only else member.duplicate(true)
			support.owner_id = other_id
			result.supports.append(support)
		if member.get("reloading", false) and other_id != id:
			result.requests.append({"id": member.reload_request_id, "request_id": member.reload_request_id, "kind": &"reload", "target_id": target, "beneficiary_id": other_id,
				"position": member.position, "duration": member.get("reload_seconds", 0.0), "remaining": member.get("reload_seconds", 0.0), "lane_id": &"target"})
		var need: Dictionary = member.get("support_request", {})
		if not need.is_empty() and other_id != id:
			result.requests.append({"id": member.support_request_id, "request_id": member.support_request_id, "kind": need.get("kind", &"move"), "target_id": target, "beneficiary_id": other_id,
				"position": member.position, "remaining": maxf(0.0, float(need.get("duration", 0.0))), "lane_id": need.get("lane_id", &"target")})
	coordinator_for(context).append_snapshot(context, target, result, not support_only)
	return result

## Physical safety spans friendly radio groups; it shares no target intelligence.
## Same freshness and stored body positions as snapshot().physical_members,
## without constructing unrelated support, request or claim dictionaries.

func line_safe(context, origin: Vector3, endpoint: Vector3) -> bool:
	var id: int = context.actor.get_instance_id()
	for other_id in _members:
		if other_id == id or not can_share_space(other_id, id): continue
		var other = _context(other_id)
		if other == null or not is_instance_valid(other.actor) or other.actor.is_dead or not other.actor.is_inside_tree(): continue
		var status: Dictionary = _members[other_id].status
		if status.is_empty() or elapsed - float(status.updated_at) > 0.35: continue
		if _position_blocks_line(status.position, origin, endpoint): return false
	return true

## An already validated snapshot is reusable only inside its synchronous preview
## batch. Execution callers use line_safe() and recheck current membership.

func line_safe_from_members(context, origin: Vector3, endpoint: Vector3, members: Array) -> bool:
	var id: int = context.actor.get_instance_id()
	for member in members:
		if member.id != id and _position_blocks_line(member.position, origin, endpoint): return false
	return true

func _position_blocks_line(position: Vector3, origin: Vector3, endpoint: Vector3) -> bool:
	var torso := position + Vector3.UP * 0.9
	var closest := Geometry3D.get_closest_point_to_segment(torso, origin, endpoint)
	return Vector2(torso.x - closest.x, torso.z - closest.z).length() < 0.4 and absf(torso.y - closest.y) < 0.9

## Read-only proposal. The first successful claim freezes the frame; previews
## neither create a round nor extend its deadline.

func flank_opportunity(context) -> Dictionary:
	return coordinator_for(context).flank_opportunity(context)

func flank_geometry_revision(context) -> int:
	return coordinator_for(context).flank_geometry_revision(context)

func claim(context, task: Dictionary) -> Dictionary:
	return coordinator_for(context).claim(context, task)

func update_claim(context, token: Dictionary, state: Dictionary) -> bool:
	return coordinator_for(context).update_claim(context, token, state)

func release(context, token: Dictionary) -> void:
	coordinator_for(context).release(context, token)

func search_available(context, point: Vector3, radius: float) -> bool:
	return coordinator_for(context).search_available(context, point, radius)

func publish_checked(context, points: PackedVector3Array) -> void:
	if not context.cooperation_enabled(): return
	var id: int = context.actor.get_instance_id()
	var target: int = context.cooperation_target_id()
	var domain: String = _domain(context.actor)
	for point in points:
		if not point.is_finite(): continue
		var grid := Vector3i(roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0))
		var key := [domain, target, grid]
		_checked[key] = {"position": point, "observer_id": id, "target_id": target, "domain": domain, "observed_at": elapsed,
			"valid_until": elapsed + maxf(0.1, context.setting(&"cooperation", &"checked_point_seconds", 3.0))}

func checked_points(context) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var domain: String = _domain(context.actor)
	var target: int = context.cooperation_target_id()
	var id: int = context.actor.get_instance_id()
	for entry in _checked.values():
		if entry.domain == domain and entry.target_id == target and entry.observer_id != id and entry.valid_until > elapsed:
			result.append(entry.duplicate(true))
	return result

func reload_opportunity(context) -> Dictionary:
	return coordinator_for(context).reload_opportunity(context)

func candidate_seconds(context, candidate: Dictionary) -> float:
	return coordinator_for(context).candidate_seconds(context, candidate)

func support_pressure(context) -> float:
	return coordinator_for(context).support_pressure(context)

func _clear_coordination() -> void:
	for coordinator in _coordinators(): coordinator.reset()

func _coordination_team(context) -> int:
	return coordinator_for(context)._coordination_team(context)

func _coordination_key(team_id: int, target_id: int) -> String:
	return _legacy_coordinator._coordination_key(team_id, target_id)

func publish_noise_source(context, position: Vector3) -> void:
	coordinator_for(context).publish_noise_source(context, position)

func publish_coordination_source(context, source: Dictionary) -> void:
	coordinator_for(context).publish_coordination_source(context, source)

func _active_coordination_source(key: String) -> Dictionary:
	return _legacy_coordinator._active_coordination_source(key)

func coordination_source(context, target_id: int = 0) -> Dictionary:
	return coordinator_for(context).coordination_source(context, target_id)

func submit_offers(context, offers: Array) -> bool:
	return coordinator_for(context).submit_offers(context, offers)

func _coordination_team_members(team_id: int) -> Array:
	return _legacy_coordinator._coordination_team_members(team_id)

func _coordination_actual(context, target_id: int) -> Dictionary:
	var stored: Dictionary = _members[context.actor.get_instance_id()].status
	var age: float = elapsed - float(stored.get("updated_at", -INF))
	var remaining: float = maxf(0.0, float(stored.get("support_seconds", 0.0)) - age)
	var ready: bool = age <= 0.35 and int(stored.get("target_id", 0)) == target_id and stored.get("ready", false) and remaining > 0.0
	ready = ready and context.actor.can_use_firearms() and context.actor.shooting_enabled and not context.actor.ammo.is_reloading and context.actor.ammo.magazine_rounds > 0 and not context.actor.is_vaulting() and not context.actor.melee_active
	return {"captured_at": elapsed, "valid_until": elapsed + 0.001 if not ready else minf(elapsed + remaining, float(stored.updated_at) + 0.35),
		"fire_ready": ready, "measured_support_seconds": remaining if ready else 0.0}

func _coordination_physical_summary(context, summary: Dictionary, target_id: int) -> Dictionary:
	var result := summary.duplicate(true)
	var footprint := _reservation_footprint(context, context.actor.global_position)
	result.body_radius = footprint.radius
	result.body_height = footprint.height
	result.spacing_margin = footprint.margin
	# Preview promises never introduce a firing line. Only an existing finite
	# actual support fact contributes its currently legal physical segment.
	result.erase("firing_lane")
	if _coordination_actual(context, target_id).fire_ready:
		var endpoint: Vector3 = _members[context.actor.get_instance_id()].status.get("aim_position", Vector3.INF)
		if endpoint.is_finite(): result.firing_lane = {"origin": context.actor.get_shot_origin(), "endpoint": endpoint}
	return result

## Physical occupancy spans squads and radio groups; no task authority is shared.
func coordination_occupancy(context, horizon: float) -> Array:
	var result: Array = []
	var owner: int = context.actor.get_instance_id()
	for id: int in _members:
		var other = _context(id)
		if not _reservation_member_valid(other) or not can_share_space(owner, id): continue
		var footprint := _reservation_footprint(other, other.actor.global_position)
		result.append({"actor_id": id, "kind": &"body", "position": footprint.position,
			"captured_at": elapsed, "valid_until": elapsed + horizon,
			"path_summary": _coordination_physical_summary(other, {}, other.cooperation_target_id())})
	for reservation: Dictionary in _reservations.values():
		if not _reservation_valid(reservation) or not can_share_space(owner, reservation.owner_id): continue
		for projection: Dictionary in _reservation_projections(reservation):
			var summary := _coordination_physical_summary(_context(reservation.owner_id), projection.get("path_summary", {}), reservation.target_id)
			result.append({"actor_id": reservation.owner_id, "kind": &"reservation", "position": projection.position,
				"reservation_id": reservation.reservation_id, "position_set_key": projection.position_set_key,
				"captured_at": elapsed, "valid_until": reservation.expires_at, "path_summary": summary})
	return result

func assignment_decision_revision(context) -> int:
	return coordinator_for(context).assignment_decision_revision(context)

func _assignment_for_owner(owner_id: int) -> Dictionary:
	return _legacy_coordinator._assignment_for_owner(owner_id)

func assignment(context) -> Dictionary:
	return coordinator_for(context).assignment(context)

func assignment_support(context) -> Dictionary:
	return coordinator_for(context).assignment_support(context)

func _reservation_projections(entry: Dictionary) -> Array:
	if entry.get("scope") == &"tactical" and entry.phase == &"pending" and entry.get("selected_offer_key", "") == "":
		return entry.get("alternatives", [])
	return [entry]

func _tactical_reservation_valid(reservation: Dictionary) -> bool:
	var owner = coordinator_for(_context(int(reservation.owner_id)))
	return reservation.get("coordinator_id", 0) == owner.get_instance_id() and owner.reservation_current(int(reservation.reservation_id), int(reservation.assignment_id), int(reservation.owner_id))

## Internal read-only lease views. All writes go through the area transaction API.
func reservation_value(id: int) -> Dictionary:
	return _reservations.get(id, {})

func reservation_values() -> Array:
	return _reservations.values()

func has_reservation(id: int) -> bool:
	return _reservations.has(id)

func store_tactical_reservation(owner, value: Dictionary) -> void:
	var context = _context(int(value.owner_id))
	if context == null or coordinator_for(context) != owner: return
	var entry := value.duplicate(true)
	entry.coordinator_id = owner.get_instance_id()
	_reservations[int(entry.reservation_id)] = entry

func release_tactical_reservation(owner, id: int) -> void:
	var entry: Dictionary = _reservations.get(id, {})
	if not entry.is_empty() and entry.get("coordinator_id", 0) == owner.get_instance_id(): _reservations.erase(id)

func attach_recommendation(context, reservation_id: int, recommendation_id: int, expires_at: float) -> Dictionary:
	var entry: Dictionary = _reservations.get(reservation_id, {})
	if entry.is_empty() or entry.owner_id != context.actor.get_instance_id() or not _reservation_valid(entry): return {}
	entry.recommendation_id = recommendation_id
	entry.expires_at = minf(entry.expires_at, expires_at)
	return entry.duplicate(true)

func prepare_assignment(context, identity: Dictionary, offer_key: String) -> Dictionary:
	return coordinator_for(context).prepare_assignment(context, identity, offer_key)

func commit_assignment(context, identity: Dictionary, reservation_token: Dictionary) -> bool:
	return coordinator_for(context).commit_assignment(context, identity, reservation_token)

func rollback_assignment(context, identity: Dictionary, reservation_token: Dictionary) -> void:
	coordinator_for(context).rollback_assignment(context, identity, reservation_token)

func report_assignment(context, report: Dictionary) -> bool:
	return coordinator_for(context).report_assignment(context, report)

func coordination_checked_points(context, target_id: int = 0) -> Array[Dictionary]:
	return coordinator_for(context).coordination_checked_points(context, target_id)

func _coordination_requests(ids: Array, source: Dictionary) -> Array:
	return _legacy_coordinator._coordination_requests(ids, source)

func publish_personal_baseline(context, summary: Dictionary) -> void:
	coordinator_for(context).publish_personal_baseline(context, summary)

func _coordination_snapshot(team_id: int, source: Dictionary, ids: Array) -> Dictionary:
	return _legacy_coordinator._coordination_snapshot(team_id, source, ids)

func _coordination_find_source(team_id: int, ids: Array) -> Dictionary:
	return _legacy_coordinator._coordination_find_source(team_id, ids)

func _drop_coordination_plan(team_id: int, _reason: StringName) -> void:
	_legacy_coordinator._drop_coordination_plan(team_id, _reason)

func recommendation(context) -> Dictionary:
	return coordinator_for(context).recommendation(context)

func recommendation_available(context, identity: Dictionary, offer_key: String) -> bool:
	return coordinator_for(context).recommendation_available(context, identity, offer_key)

func prepare_recommendation(context, advice: Dictionary, key: String, offer: Dictionary, duration: float) -> Dictionary:
	return coordinator_for(context).prepare_recommendation(context, advice, key, offer, duration)

func accept_recommendation(context, advice: Dictionary, token: Dictionary) -> bool:
	return coordinator_for(context).accept_recommendation(context, advice, token)
