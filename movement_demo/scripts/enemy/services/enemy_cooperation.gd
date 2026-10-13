extends RefCounted

const TeamPlanner = preload("res://scripts/enemy/services/enemy_team_planner.gd")

## One board per arena. All stored observations are value snapshots; members are weak.
var elapsed := 0.0
var generation := 0
var revision := 0
var relation_revision := 0
var _serial := 0
var _members: Dictionary = {}
var _reports: Dictionary = {}
var _claims: Dictionary = {}
var _checked: Dictionary = {}
var _relations: Dictionary = {}
var _flank_rounds: Dictionary = {}
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
# Tactical draft: shared observations and proposals are values. No action/body
# reference is retained or invoked by the planner or assignment transaction.
var _coordination_sources: Dictionary = {}
var _coordination_source_pool: Dictionary = {}
var _coordination_receipts: Dictionary = {}
var _coordination_offers: Dictionary = {}
var _coordination_plans: Dictionary = {}
var _coordination_environments: Dictionary = {}
var _coordination_due: Dictionary = {}
var _coordination_failures: Array[Dictionary] = []
var _coordination_counters: Dictionary = {}
var _coordination_checked: Dictionary = {}
var _team_planner = TeamPlanner.new()
const COORDINATION_PERIOD := 0.2 # Implementation default, not a user constraint.
const COORDINATION_ACCEPT_SECONDS := 1.0
const COORDINATION_WAIT_SECONDS := 2.0
const COORDINATION_MAX_SECONDS := 20.0
const COORDINATION_SOURCE_DISTANCE := 0.5
const COORDINATION_REPORT_SECONDS := 0.35
const FLANK_SIDE_MARGIN := 0.5
const FLANK_DESTINATION_SPACING := 1.2
# A completed 140-degree flank still fits inside a rotated half-plane. This
# default geometry guard prevents a new round from sending the front after it.
const FLANK_SEPARATION_COSINE := -0.5 # cos(120 degrees), horizontal directions.
const FLANK_GEOMETRY_MEMBER_STEP := 0.5
const FLANK_GEOMETRY_TARGET_STEP := 0.25

## Stage 2: positions are locally validated before this service reserves them.
## A reservation carries no tactical assignment or permission to execute a body.
const MAX_BASIC_RESERVATION_SECONDS := 30.0

## One value snapshot per squad, never one mutable Training per member.
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
	return _team_settings.has(_team_setting_key(context))

func team_abilities(context) -> Dictionary:
	var key := _team_setting_key(context)
	if not _team_settings.has(key): return {}
	var settings: Dictionary = _team_settings[key]
	return {"level": settings.level, "squad_key": key, "team_config_revision": _team_setting_versions[key], "diagnostic": settings.diagnostic}

func team_level(context, legacy_level: int = 0) -> int:
	var settings: Dictionary = _team_settings.get(_team_setting_key(context), {})
	return int(settings.get("level", legacy_level))

func team_configuration_revision(context) -> int:
	return int(_team_setting_versions.get(_team_setting_key(context), 0))

func team_setting(context, key: StringName, fallback: Variant, unit_defaults: Dictionary = {}) -> Variant:
	var settings: Dictionary = _team_settings.get(_team_setting_key(context), {})
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
	_coordination_offers.erase(context.actor.get_instance_id())
	_invalidate_coordination_member(context.actor.get_instance_id(), &"member_version_changed")
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

## Candidate filtering is read-only. Callers keep no-destination personal
## firing/self-preservation options outside this destination-reservation gate.
func reservation_offer_available(context, offer: Dictionary) -> bool:
	if not _reservation_offer_valid(context, offer): return false
	var entry := _reservation_footprint(context, offer.position)
	entry.position_set_key = offer.position_set_key
	entry.path_summary = _reservation_summary(offer.get("path_summary", {}))
	return _reservation_position_available(context, entry)

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
	elapsed += maxf(0.0, delta)
	for id in _members.keys():
		var context = _context(id)
		if context == null or not is_instance_valid(context.actor) or not context.actor.is_inside_tree() or context.actor.is_dead:
			unregister(id)
	for token in _claims.keys():
		var claim: Dictionary = _claims[token]
		var context = _context(claim.owner_id)
		if elapsed >= claim.expires_at or context == null or not context.cooperation_enabled() or not context.can_use_action(claim.owner_action) or context.cooperation_target_id() != claim.target_id:
			_claims.erase(token)
			revision += 1
	for key in _checked.keys():
		if elapsed >= _checked[key].valid_until: _checked.erase(key)
	for key in _inspection_reports.keys():
		if elapsed >= float(_inspection_reports[key].valid_until): _inspection_reports.erase(key)
	_maintain_flank_rounds()
	for reservation_id in _reservations.keys():
		if not _reservation_valid(_reservations[reservation_id]):
			_reservations.erase(reservation_id)
			revision += 1
	_advance_coordination()

func reset() -> void:
	generation += 1
	elapsed = 0.0
	_reports.clear()
	_claims.clear()
	_checked.clear()
	_flank_rounds.clear()
	_inspection_reports.clear()
	_reservations.clear()
	_clear_coordination()
	for member in _members.values():
		member.status = {}
		member.activity = {}
	revision += 1

func register(context) -> bool:
	var id: int = context.actor.get_instance_id()
	var changed: bool = _members.has(id) and (not _member_domain_matches(context.actor, _members[id]) or _context(id) != context)
	if changed: unregister(id)
	if not _members.has(id):
		_member_serial += 1
		_members[id] = {"context": weakref(context), "domain": _domain(context.actor), "faction": context.actor.faction_id, "group": context.actor.communication_group, "status": {}, "activity": {},
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
	_release_member_reservations(id, true)
	_coordination_offers.erase(id)
	_invalidate_coordination_member(id, &"member_released")
	for token in _claims.keys():
		if _claims[token].owner_id == id or _claims[token].get("beneficiary_id", 0) == id: _claims.erase(token)
	if _members.has(id): _members[id].status = {}
	revision += 1

## Ending an action is not ending the body's reload or leaving the team.
## Dependent allies keep their finite leases while the same real need exists.
func clear_execution(id: int) -> void:
	_release_member_reservations(id, false)
	for token in _claims.keys():
		if int(_claims[token].owner_id) == id: _claims.erase(token)
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

func _claim_valid(entry: Dictionary) -> bool:
	var owner = _context(entry.owner_id)
	var valid: bool = entry.expires_at > elapsed and owner != null and is_instance_valid(owner.actor) and owner.actor.is_inside_tree() and owner.cooperation_enabled() and owner.can_use_action(entry.owner_action) and owner.cooperation_target_id() == entry.target_id
	if valid and entry.kind == &"inspect_end":
		var evidence := inspection_evidence(owner, entry.target_id)
		if evidence.is_empty() or int(evidence.id) != int(entry.get("inspection_id", -1)) or entry.get("domain", "") != _domain(owner.actor): return false
		var body = entry.get("cover").get_ref() if entry.get("cover") is WeakRef else null
		if not is_instance_valid(body) or not body is StaticBody3D or (body.collision_layer & 1) == 0 or not is_instance_valid(owner.navigation_region) or not owner.navigation_region.is_ancestor_of(body): return false
		var box = body.get_node_or_null("CollisionShape3D")
		return box is CollisionShape3D and not box.disabled and box.shape is BoxShape3D and box.global_transform == entry.get("cover_transform") and box.shape.size == entry.get("cover_size")
	if not valid or entry.kind != &"flank": return valid
	var round: Dictionary = _flank_rounds.get(entry.get("flank_round_id", 0), {})
	return not round.is_empty() and _flank_round_matches(round, owner)

func _domain(actor) -> String:
	return JSON.stringify([String(actor.faction_id), String(actor.communication_group)])

## Compare live fields on every check; serialization is only needed for keys.
func _member_domain_matches(actor, member: Dictionary) -> bool:
	return actor.faction_id == member.faction and actor.communication_group == member.group

func _key(domain: String, target: int) -> String:
	return "%s:%s:%s" % [generation, domain, target]

func set_relation(first: StringName, second: StringName, relation: StringName) -> void:
	if _relations.get([first, second]) == relation and _relations.get([second, first]) == relation: return
	_relations[[first, second]] = relation
	_relations[[second, first]] = relation
	_reservations.clear()
	_clear_coordination()
	_rebuild_teams()
	_claims.clear()
	_flank_rounds.clear()
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
	return first.faction_id == second.faction_id or _relations.get([first.faction_id, second.faction_id], &"") == &"allied"

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
	_reports[key] = {"target_id": target, "observer_id": observer, "faction": context.actor.faction_id, "group": context.actor.communication_group,
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
	return report.get("group") == context.actor.communication_group and (report.get("faction") == context.actor.faction_id or _relations.get([report.get("faction"), context.actor.faction_id], &"") == &"allied")

func _drop_inspection_claims(inspection_id: int) -> void:
	for token in _claims.keys():
		if int(_claims[token].get("inspection_id", -1)) == inspection_id: _claims.erase(token)
	revision += 1

## Called only for an acquired observation. Input uses the observer's clock;
## returned/shared values use board time and never gain life when read again.
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
		"faction": context.actor.faction_id, "group": context.actor.communication_group, "generation": generation,
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
func _inspection_eligible_members(context, target: int) -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	var owner: int = context.actor.get_instance_id()
	for id in _members:
		var other = _context(id)
		if other == null or not can_cooperate(id, owner) or not other.cooperation_enabled() or other.cooperation_target_id() != target or not other.is_alerted or not other.actor.can_move(): continue
		members.append({"id": id, "position": other.actor.global_position})
	return members

## Radio membership alone cannot provide a second capable investigator.
func inspection_eligible_count(context, target: int) -> int:
	return _inspection_eligible_members(context, target).size()

func inspection_end(context, geometry: Dictionary) -> int:
	if not context.cooperation_enabled(): return 0
	var evidence := inspection_evidence(context, geometry.target_id)
	if evidence.is_empty() or int(evidence.id) != int(geometry.inspection_id): return 0
	var owner: int = context.actor.get_instance_id()
	var occupied: Dictionary = {}
	for entry: Dictionary in _claims.values():
		if entry.kind != &"inspect_end" or int(entry.get("inspection_id", -1)) != int(evidence.id) or not _claim_valid(entry) or not can_cooperate(entry.owner_id, owner): continue
		if int(entry.owner_id) == owner: return int(entry.end)
		occupied[int(entry.end)] = int(entry.owner_id)
	var members := _inspection_eligible_members(context, int(geometry.target_id))
	if members.size() < 2: return 0
	var best: Dictionary = {}
	var best_cost := INF
	for first: Dictionary in members:
		for second: Dictionary in members:
			if first.id == second.id: continue
			if occupied.has(-1) and occupied[-1] != first.id: continue
			if occupied.has(1) and occupied[1] != second.id: continue
			var cost: float = first.position.distance_to(geometry.ends[-1].entry) + second.position.distance_to(geometry.ends[1].entry)
			if cost < best_cost - 0.001 or (absf(cost - best_cost) <= 0.001 and int(first.id) < int(best.get(-1, 9223372036854775807))):
				best_cost = cost
				best = {-1: first.id, 1: second.id}
	for end in [-1, 1]:
		if best.get(end, 0) == owner and not evidence.checked_ends.has(end): return end
	return 0

func inspection_revision(context, inspection_id: int) -> int:
	var state: Array = [generation, relation_revision, inspection_id]
	for id in _members:
		var other = _context(id)
		if other == null or not can_cooperate(id, context.actor.get_instance_id()) or not other.cooperation_enabled(): continue
		state.append([id, other.cooperation_target_id(), other.is_alerted, other.actor.can_move(), other.actor.global_position.snapped(Vector3.ONE * 0.5)])
	for entry: Dictionary in _claims.values():
		if entry.kind == &"inspect_end" and int(entry.get("inspection_id", -1)) == inspection_id and _claim_valid(entry): state.append([entry.owner_id, entry.end])
	var evidence := inspection_evidence(context, context.cooperation_target_id())
	state.append(evidence.get("checked_ends", []))
	return hash(state)

func inspection_partner_ready(context, token: Dictionary) -> bool:
	if not _claim_valid(token): return false
	for entry: Dictionary in _claims.values():
		if entry.kind != &"inspect_end" or entry.owner_id == context.actor.get_instance_id() or int(entry.get("inspection_id", -1)) != int(token.inspection_id) or not _claim_valid(entry): continue
		if not can_cooperate(entry.owner_id, context.actor.get_instance_id()): continue
		var other = _context(entry.owner_id)
		if int(entry.get("phase", 0)) >= 2 and other.actor.can_move() and other.actor.global_position.distance_to(entry.entry) <= 0.35: return true
	return false

func complete_inspection(context, token: Dictionary) -> void:
	if not _claim_valid(token): return
	if context.actor.global_position.distance_to(token.peek) > 0.35: return
	var known: Vector3 = token.get("geometry", {}).get("known", Vector3.INF)
	if not known.is_finite() or not context.perception.can_observe_position(known): return
	for report: Dictionary in _inspection_reports.values():
		if int(report.id) == int(token.inspection_id) and not report.checked_ends.has(int(token.end)): report.checked_ends.append(int(token.end))
	release(context, token)

func evidence(context, target: int) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	if not _members.has(id): return {}
	var best: Dictionary = {}
	for report in _reports.values():
		if report.target_id != target or report.observer_id == id: continue
		if report.group != context.actor.communication_group: continue
		if report.faction != context.actor.faction_id and _relations.get([report.faction, context.actor.faction_id], &"") != &"allied": continue
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
		for round: Dictionary in _flank_rounds.values():
			if _flank_round_matches(round, context) and _flank_opposite(round, old_position) != _flank_opposite(round, new_position): changed = true
	if changed: revision += 1

func snapshot(context, target: int) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	var result := {"members": [], "requests": [], "claims": [], "supports": [], "threats": [], "revision": revision, "generation": generation, "elapsed": elapsed}
	for other_id in _members:
		if not can_share_intel(other_id, id): continue
		var other = _context(other_id)
		if other == null or not is_instance_valid(other.actor) or other.actor.is_dead or not other.actor.is_inside_tree(): continue
		var status: Dictionary = _members[other_id].status
		if status.is_empty() or elapsed - float(status.updated_at) > 0.35: continue
		var member := status.duplicate(true)
		var age: float = maxf(0.0, elapsed - float(member.updated_at))
		member.support_seconds = maxf(0.0, float(member.get("support_seconds", 0.0)) - age)
		member.support_resume_seconds = maxf(0.0, float(member.get("support_resume_seconds", 0.0)) - age) if member.get("support_cycle_valid", false) else -1.0
		if member.support_seconds <= 0.0: member.ready = false
		if other.actor.ammo.is_reloading or other.actor.ammo.magazine_rounds <= 0 or not other.actor.shooting_enabled or other.actor.is_vaulting() or other.actor.melee_active:
			member.ready = false
			member.support_seconds = 0.0
			member.support_cycle_valid = false
			member.support_resume_seconds = -1.0
		# can_cooperate is the same predicate already checked above, with no
		# mutation or await between these reads.
		member.can_cooperate = true
		result.members.append(member)
		if int(member.get("target_id", 0)) != target: continue
		var threat_seconds: float = maxf(0.0, float(member.get("melee_threat_seconds", 0.0)) - maxf(0.0, elapsed - float(member.updated_at)))
		if threat_seconds > 0.0:
			result.threats.append({"owner_id": other_id, "support_seconds": threat_seconds, "lane_id": &"target", "position": member.position, "kind": &"melee"})
		if member.get("ready", false):
			var support := member.duplicate(true)
			support.owner_id = other_id
			result.supports.append(support)
		if member.get("reloading", false) and other_id != id:
			result.requests.append({"id": member.reload_request_id, "request_id": member.reload_request_id, "kind": &"reload", "target_id": target, "beneficiary_id": other_id,
				"position": member.position, "duration": member.get("reload_seconds", 0.0), "remaining": member.get("reload_seconds", 0.0), "lane_id": &"target"})
		var need: Dictionary = member.get("support_request", {})
		if not need.is_empty() and other_id != id:
			result.requests.append({"id": member.support_request_id, "request_id": member.support_request_id, "kind": need.get("kind", &"move"), "target_id": target, "beneficiary_id": other_id,
				"position": member.position, "remaining": maxf(0.0, float(need.get("duration", 0.0))), "lane_id": need.get("lane_id", &"target")})
	for claim in _claims.values():
		if claim.target_id != target or not _claim_valid(claim) or not can_cooperate(claim.owner_id, id): continue
		var copy: Dictionary = claim.duplicate(true)
		copy.remaining = claim.expires_at - elapsed
		result.claims.append(copy)
		if claim.kind in [&"advance", &"flank"] and claim.owner_id != id:
			var request := copy.duplicate(true)
			request.request_id = claim.id
			request.beneficiary_id = claim.owner_id
			request.lane_id = &"target"
			result.requests.append(request)
	var source := coordination_source(context, target)
	if not source.is_empty():
		for need: Dictionary in _coordination_requests(_coordination_team_members(source.team_id), source):
			if need.kind != &"advance" or need.actor_id == id: continue
			result.requests.append({"id": need.request_id, "request_id": need.request_id, "kind": &"advance",
				"target_id": target, "beneficiary_id": need.actor_id, "lane_id": &"target",
				"position": _context(need.actor_id).actor.global_position, "remaining": maxf(0.0, need.valid_until - elapsed)})
	return result

## Same membership/freshness and stored body positions as snapshot().members,
## without constructing unrelated support, request or claim dictionaries.
func line_safe(context, origin: Vector3, endpoint: Vector3) -> bool:
	var id: int = context.actor.get_instance_id()
	for other_id in _members:
		if other_id == id or not can_share_intel(other_id, id): continue
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
	var result := {"round_id": 0, "anchor": Vector3.INF, "front_axis": Vector3.ZERO, "capacity": 0, "remaining_slots": 0}
	if not context.cooperation_enabled(): return result
	var target: int = context.cooperation_target_id()
	var evidence: Dictionary = context.cooperation_target_evidence()
	if target == 0 or not _flank_evidence_live(context, evidence): return result
	var members := _flank_members(context, target)
	return _flank_opportunity_for_members(context, evidence, members)

## Only geometric inputs invalidate the bounded spatial queue. Report IDs,
## timestamps and firing cadence still reprice live candidates without clearing
## their geometry. Quantization is an invalidation hint, never an input to paths,
## occupancy, destination validation or actual movement.
func flank_geometry_revision(context) -> int:
	if not context.cooperation_enabled(): return 0
	var target: int = context.cooperation_target_id()
	var evidence: Dictionary = context.cooperation_target_evidence()
	if target == 0 or not _flank_evidence_live(context, evidence): return 0
	var members := _flank_members(context, target)
	if members.size() < 2: return 0
	members.sort_custom(func(a: Dictionary, b: Dictionary): return int(a.id) < int(b.id))
	var key: Array = [generation, context.actor.faction_id, context.actor.communication_group, target,
		_geometry_cell(evidence.position, FLANK_GEOMETRY_TARGET_STEP)]
	for member: Dictionary in members:
		key.append([member.id, _geometry_cell(member.position, FLANK_GEOMETRY_MEMBER_STEP)])
	var opportunity := _flank_opportunity_for_members(context, evidence, members)
	# Occupancy uses real body positions, so crossing a quota plane invalidates
	# immediately even when both positions fall inside the same half-metre cell.
	key.append([opportunity.round_id, opportunity.capacity, opportunity.remaining_slots])
	if opportunity.round_id != 0: key.append([opportunity.anchor, opportunity.front_axis])
	var slots: Array = []
	var id: int = context.actor.get_instance_id()
	for entry: Dictionary in _claims.values():
		if entry.target_id != target or entry.kind not in [&"advance", &"flank"] or not _claim_valid(entry) or not can_cooperate(entry.owner_id, id): continue
		slots.append([entry.id, entry.owner_id, entry.kind, entry.lane_id, entry.get("flank_destination", Vector3.INF)])
	slots.sort_custom(func(a: Array, b: Array): return int(a[0]) < int(b[0]))
	key.append(slots)
	return hash(key)

func _geometry_cell(position: Vector3, step: float) -> Vector3i:
	return Vector3i(roundi(position.x / step), roundi(position.y / step), roundi(position.z / step))

func _flank_opportunity_for_members(context, evidence: Dictionary, members: Array[Dictionary]) -> Dictionary:
	var result := {"round_id": 0, "anchor": Vector3.INF, "front_axis": Vector3.ZERO, "capacity": 0, "remaining_slots": 0}
	if members.size() < 2: return result
	var capacity := floori(members.size() / 2.0)
	for round: Dictionary in _flank_rounds.values():
		if not _flank_round_matches(round, context): continue
		# Do not rotate or start a second frame while the first round is alive.
		if evidence.position.distance_to(round.anchor) > 2.0: return result
		return {"round_id": round.id, "anchor": round.anchor, "front_axis": round.front_axis,
			"capacity": capacity, "remaining_slots": maxi(0, capacity - _flank_occupants(round, members).size()),
			"expires_at": round.expires_at, "remaining_seconds": maxf(0.0, round.expires_at - elapsed)}
	var anchor: Vector3 = evidence.position
	var axis := Vector3.ZERO
	var directions: Array[Vector3] = []
	for member: Dictionary in members:
		var radial: Vector3 = member.position - anchor
		radial.y = 0.0
		axis += radial
		directions.append(radial.normalized())
	if axis.is_zero_approx(): return result
	axis = axis.normalized()
	for member: Dictionary in members:
		if (member.position - anchor).dot(axis) <= FLANK_SIDE_MARGIN: return result
	for first in directions.size():
		for second in range(first + 1, directions.size()):
			if directions[first].dot(directions[second]) <= FLANK_SEPARATION_COSINE: return result
	return {"round_id": 0, "anchor": anchor, "front_axis": axis, "capacity": capacity, "remaining_slots": capacity}

func _flank_evidence_live(context, evidence: Dictionary) -> bool:
	return not evidence.is_empty() and evidence.get("target_id", 0) == context.cooperation_target_id() and evidence.get("position", Vector3.INF).is_finite() and float(evidence.get("valid_until", -INF)) > context.evidence_elapsed_seconds

func _flank_members(context, target: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var id: int = context.actor.get_instance_id()
	for other_id in _members:
		if not can_cooperate(other_id, id): continue
		var other = _context(other_id)
		if other == null or not other.actor.is_inside_tree() or other.cooperation_target_id() != target: continue
		var activity: Dictionary = _members[other_id].activity
		if activity.is_empty() or int(activity.get("target_id", 0)) != target or elapsed - float(activity.updated_at) > 0.35: continue
		result.append({"id": other_id, "position": other.actor.global_position})
	return result

func _flank_round_matches(round: Dictionary, context) -> bool:
	var id: int = context.actor.get_instance_id()
	if round.expires_at <= elapsed or round.generation != generation or round.target_id != context.cooperation_target_id(): return false
	if not _members.has(id) or not can_share_intel(id, id) or not context.actor.is_inside_tree(): return false
	return round.group == context.actor.communication_group and (round.faction == context.actor.faction_id or _relations.get([round.faction, context.actor.faction_id], &"") == &"allied")

func _flank_opposite(round: Dictionary, position: Vector3) -> bool:
	return (position - round.anchor).dot(round.front_axis) < -FLANK_SIDE_MARGIN

func _flank_occupants(round: Dictionary, members: Array[Dictionary]) -> Dictionary:
	var occupied: Dictionary = {}
	for member: Dictionary in members:
		if _flank_opposite(round, member.position): occupied[member.id] = true
	for entry: Dictionary in _claims.values():
		if entry.kind == &"flank" and entry.get("flank_round_id", 0) == round.id and _claim_valid(entry): occupied[entry.owner_id] = true
	return occupied

func _claim_flank(context, task: Dictionary) -> Dictionary:
	_maintain_flank_rounds()
	var id: int = context.actor.get_instance_id()
	var target: int = context.cooperation_target_id()
	if int(task.get("target_id", target)) != target or not context.can_use_action(task.get("owner_action", &"cooperate")): return {}
	var opportunity := flank_opportunity(context)
	if opportunity.capacity <= 0: return {}
	var anchor: Vector3 = task.get("flank_anchor", Vector3.INF)
	var axis: Vector3 = task.get("flank_axis", Vector3.ZERO)
	var destination: Vector3 = task.get("flank_destination", Vector3.INF)
	var proposed_round: int = task.get("flank_round_id", 0)
	if not anchor.is_finite() or not axis.is_finite() or not destination.is_finite(): return {}
	if anchor.distance_to(opportunity.anchor) > 0.1 or axis.distance_to(opportunity.front_axis) > 0.01: return {}
	if proposed_round != 0 and proposed_round != opportunity.round_id: return {}
	if (destination - opportunity.anchor).dot(opportunity.front_axis) >= -FLANK_SIDE_MARGIN: return {}
	for existing: Dictionary in _claims.values():
		if existing.kind != &"flank" or existing.target_id != target or not _claim_valid(existing) or not can_cooperate(existing.owner_id, id): continue
		if existing.owner_id == id:
			return existing.duplicate(true) if existing.flank_destination.distance_to(destination) < 0.05 else {}
		if existing.flank_destination.distance_to(destination) < FLANK_DESTINATION_SPACING: return {}
	for member: Dictionary in _flank_members(context, target):
		if member.id != id and member.position.distance_to(destination) < FLANK_DESTINATION_SPACING: return {}
	if opportunity.remaining_slots <= 0: return {}
	var duration: float = task.get("duration", 4.0)
	if not is_finite(duration) or duration <= 0.0: return {}
	var round_id: int = opportunity.round_id
	if round_id == 0:
		_serial += 1
		round_id = _serial
		_flank_rounds[round_id] = {"id": round_id, "target_id": target, "anchor": opportunity.anchor,
			"front_axis": opportunity.front_axis, "faction": context.actor.faction_id, "group": context.actor.communication_group,
			"generation": generation, "expires_at": elapsed + duration}
	var round: Dictionary = _flank_rounds[round_id]
	_serial += 1
	var value := task.duplicate(true)
	value.merge({"id": _serial, "owner_id": id, "target_id": target, "kind": &"flank", "lane_id": task.get("lane_id", &"opposite"),
		"position": context.actor.global_position, "generation": generation, "created_at": elapsed,
		"expires_at": minf(elapsed + duration, round.expires_at), "owner_action": task.get("owner_action", &"cooperate"),
		"flank_round_id": round_id, "flank_anchor": round.anchor, "flank_axis": round.front_axis, "flank_destination": destination}, true)
	_claims[_serial] = value
	revision += 1
	return value.duplicate(true)

func _discard_flank_round(round_id: int) -> void:
	for token in _claims.keys():
		if _claims[token].get("flank_round_id", 0) == round_id: _claims.erase(token)
	_flank_rounds.erase(round_id)
	revision += 1

## Execution maintenance only. A falling population first revokes departures
## that have not crossed; already moved bodies are never teleported back.
func _maintain_flank_rounds() -> void:
	for round_id in _flank_rounds.keys():
		var round: Dictionary = _flank_rounds[round_id]
		var representative = null
		var evidence_moved := false
		for id in _members:
			var member = _context(id)
			if member == null or not is_instance_valid(member.actor) or not _flank_round_matches(round, member): continue
			var evidence: Dictionary = member.cooperation_target_evidence()
			if _flank_evidence_live(member, evidence):
				if evidence.position.distance_to(round.anchor) > 2.0: evidence_moved = true
				if member.cooperation_enabled(): representative = member
		if representative == null or evidence_moved:
			_discard_flank_round(round_id)
			continue
		var members := _flank_members(representative, round.target_id)
		if members.size() < 2:
			_discard_flank_round(round_id)
			continue
		var crossed: Dictionary = {}
		for member: Dictionary in members:
			if _flank_opposite(round, member.position): crossed[member.id] = true
		var claims: Array[Dictionary] = []
		for token in _claims.keys():
			var entry: Dictionary = _claims[token]
			if entry.get("flank_round_id", 0) != round_id: continue
			if not _claim_valid(entry):
				_claims.erase(token)
				revision += 1
			else: claims.append(entry)
		claims.sort_custom(func(a: Dictionary, b: Dictionary):
			if crossed.has(a.owner_id) != crossed.has(b.owner_id): return crossed.has(a.owner_id)
			return int(a.id) < int(b.id))
		var unclaimed_crossed := crossed.duplicate()
		for entry: Dictionary in claims: unclaimed_crossed.erase(entry.owner_id)
		var slots: int = maxi(0, floori(members.size() / 2.0) - unclaimed_crossed.size())
		for index in range(slots, claims.size()):
			_claims.erase(claims[index].id)
			revision += 1

func claim(context, task: Dictionary) -> Dictionary:
	if not context.cooperation_enabled(): return {}
	var id: int = context.actor.get_instance_id()
	if not _members.has(id): register(context)
	var target: int = task.get("target_id", context.cooperation_target_id())
	var kind: StringName = task.get("kind", &"")
	var lane: String = String(task.get("lane_id", ""))
	var point: Vector3 = task.get("position", context.actor.global_position)
	if target == 0 or kind.is_empty() or not point.is_finite(): return {}
	if kind == &"flank": return _claim_flank(context, task)
	if kind == &"inspect_end":
		var report := inspection_evidence(context, target)
		if report.is_empty() or int(report.id) != int(task.get("inspection_id", -1)) or report.checked_ends.has(int(task.get("end", 0))): return {}
		if int(task.get("end", 0)) not in [-1, 1] or task.get("geometry", {}).is_empty() or inspection_end(context, task.geometry) != int(task.end): return {}
	for existing in _claims.values():
		if not _claim_valid(existing) or existing.target_id != target or not can_cooperate(existing.owner_id, id): continue
		if existing.owner_id == id and existing.kind == kind and String(existing.lane_id) == lane: return existing.duplicate(true)
		var collision: bool = existing.kind == kind and not lane.is_empty() and String(existing.lane_id) == lane
		if kind == &"search" and existing.kind == kind:
			collision = existing.position.distance_to(point) < float(task.get("radius", 1.0))
		if kind == &"reload" and existing.kind == kind: collision = true
		if collision: return {}
	_serial += 1
	var value := task.duplicate(true)
	value.merge({"id": _serial, "owner_id": id, "target_id": target, "kind": kind, "lane_id": lane, "position": point,
		"generation": generation, "created_at": elapsed, "expires_at": elapsed + maxf(0.1, float(task.get("duration", 4.0))),
		"owner_action": task.get("owner_action", context.utility_current.get("id", &"cooperate"))}, true)
	if kind == &"inspect_end":
		value.domain = _domain(context.actor)
		value.expires_at = minf(value.expires_at, float(inspection_evidence(context, target).valid_until))
	_claims[_serial] = value
	revision += 1
	return value.duplicate(true)

func update_claim(context, token: Dictionary, state: Dictionary) -> bool:
	var id: int = token.get("id", 0)
	if not _claims.has(id) or token.get("generation", -1) != generation: return false
	if _claims[id].kind == &"flank":
		_maintain_flank_rounds()
		if not _claims.has(id): return false
	var entry: Dictionary = _claims[id]
	if entry.owner_id != context.actor.get_instance_id() or not _claim_valid(entry): return false
	# Status cannot renew evidence or impersonate measured ready fire.
	for key in [&"phase", &"progress", &"position"]:
		if state.has(key):
			if key == &"phase" and entry.get(key) != state[key]: revision += 1
			entry[key] = state[key]
	return true

func release(context, token: Dictionary) -> void:
	var id: int = token.get("id", 0)
	if _claims.has(id) and _claims[id].owner_id == context.actor.get_instance_id():
		_claims.erase(id)
		revision += 1

func search_available(context, point: Vector3, radius: float) -> bool:
	var id: int = context.actor.get_instance_id()
	var footprint := _reservation_footprint(context, point)
	for reservation: Dictionary in _reservations.values():
		if reservation.owner_id == id or not _reservation_valid(reservation) or not can_share_space(id, reservation.owner_id): continue
		for projection: Dictionary in _reservation_projections(reservation):
			var occupied := _reservation_footprint(_context(reservation.owner_id), projection.position)
			if _reservation_geometry_conflict(footprint, occupied): return false
	if not context.cooperation_enabled(): return true
	var target: int = context.cooperation_target_id()
	for item in _claims.values():
		if item.owner_id != id and item.kind == &"search" and item.target_id == target and _claim_valid(item) and can_cooperate(item.owner_id, id) and item.position.distance_to(point) < radius: return false
	return true

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
	var result := {"allowed": false, "support_seconds": 0.0, "provider_id": 0, "request_id": 0}
	if not context.cooperation_enabled(): return result
	var id: int = context.actor.get_instance_id()
	var data: Dictionary = context.cooperation_snapshot()
	for item in data.claims:
		if item.kind == &"reload" and item.owner_id != id: return result
	for member in data.members:
		if member.id != id and member.get("reloading", false): return result
	for support in data.supports + data.threats:
		if support.owner_id == id: continue
		if float(support.support_seconds) > float(result.support_seconds):
			result.support_seconds = support.support_seconds
			result.provider_id = support.owner_id
	result.allowed = float(result.support_seconds) >= maxf(0.01, context.setting(&"cooperation", &"reload_min_support_seconds", 0.5))
	return result

func candidate_seconds(context, candidate: Dictionary) -> float:
	if not context.cooperation_enabled(): return 0.0
	var horizon: float = context.utility_horizon_seconds
	var outcome: Dictionary = candidate.get("outcome", {})
	var explicit: float = maxf(0.0, float(outcome.get("cooperation_seconds", 0.0)))
	var task: Dictionary = candidate.get("cooperation", {})
	var data: Dictionary = context.cooperation_snapshot()
	var id: int = context.actor.get_instance_id()
	var available: float = maxf(0.0, horizon - float(outcome.get("unavailable_seconds", horizon)))
	var self_status: Dictionary = _members.get(id, {}).get("status", {})
	var support_time: float = float(task.get("support_seconds", available if self_status.get("ready", false) else 0.0))
	var start: float = clampf(float(task.get("estimated_start_seconds", 0.0)), 0.0, horizon)
	support_time = maxf(0.0, minf(support_time, horizon - start))
	var candidate_moving := _candidate_moves(context, candidate)
	# An ordinary moving option inherits the currently measured fire state, not
	# permission to keep firing after it starts walking. Explicit arrival plans
	# retain their own delayed, stationary support estimate.
	if task.is_empty() and candidate_moving and not context.fire.fire_while_moving: support_time = 0.0
	# Candidate predictions cannot promise more fire than the current magazine/burst.
	if context.actor.can_use_firearms():
		var shot_window: float = context.fire.burst_window_seconds(candidate.get("support_intent", false) or task.get("kind", &"") == &"support")
		if context.actor.ammo.is_reloading: shot_window = 0.0
		support_time = minf(support_time, shot_window)
	var quality: float = clampf(float(task.get("quality", 1.0)), 0.0, 1.0)
	var gain := explicit
	# A geometrically useful move can benefit while travelling even when the
	# covering magazine will be empty on arrival. Count the measured overlap,
	# never the promise of a claim, and do not discount the route's exposure.
	if task.get("movement_qualified", false):
		var move_start: float = clampf(float(task.get("movement_start_seconds", horizon)), 0.0, horizon)
		var move_end: float = minf(horizon, move_start + maxf(0.0, float(task.get("movement_seconds", 0.0))))
		for support in data.supports:
			if support.owner_id == id or support.get("moving", false) or support.get("lane_id", &"target") != &"target": continue
			var overlap: float = maxf(0.0, minf(move_end, float(support.support_seconds)) - move_start)
			gain = maxf(gain, overlap * quality)
	for request in data.requests:
		if request.beneficiary_id == id: continue
		if task.get("request_id", 0) != 0 and task.request_id != request.request_id: continue
		if String(task.get("lane_id", "target")) != String(request.get("lane_id", "target")): continue
		var stationary_required := _request_requires_stationary(request)
		if stationary_required and candidate_moving: continue
		var covered := 0.0
		for support in data.supports:
			if support.owner_id == id: continue
			if stationary_required and support.get("moving", false): continue
			if String(support.get("lane_id", "target")) == String(task.get("lane_id", "target")):
				covered = maxf(covered, float(support.support_seconds))
		var end: float = minf(start + support_time, minf(horizon, float(request.get("remaining", horizon))))
		var missing: float = maxf(0.0, end - maxf(start, covered))
		gain = maxf(gain, missing * quality)
	if task.get("kind", &"") in [&"advance", &"flank", &"crossfire"] and task.get("position", Vector3.INF).is_finite():
		var evidence: Dictionary = context.cooperation_target_evidence()
		if not evidence.is_empty():
			var axis: Vector3 = task.position - evidence.position
			axis.y = 0.0
			for support in data.supports:
				if support.owner_id == id: continue
				var other: Vector3 = support.position - evidence.position
				other.y = 0.0
				if axis.is_zero_approx() or other.is_zero_approx(): continue
				var angle := rad_to_deg(axis.angle_to(other))
				if angle >= float(context.setting(&"cooperation", &"minimum_angle_degrees", 25.0)):
					var own_window: float = support_time if context.actor.can_use_firearms() else available
					var common_window: float = maxf(0.0, minf(start + own_window, float(support.support_seconds)) - start)
					gain = maxf(gain, common_window * minf(angle / 90.0, 1.0) * quality)
	return clampf(gain, 0.0, horizon) if is_finite(gain) else 0.0

func _candidate_moves(context, candidate: Dictionary) -> bool:
	if not candidate.get("route", {}).is_empty(): return true
	if float(candidate.get("cooperation", {}).get("movement_seconds", 0.0)) > 0.05: return true
	var destination: Dictionary = candidate.get("destination", {})
	var position: Vector3 = destination.get("position", destination.get("hide", Vector3.INF))
	if not position.is_finite(): return false
	var offset: Vector3 = position - context.actor.global_position
	return Vector2(offset.x, offset.z).length() > 0.15

func _request_requires_stationary(request: Dictionary) -> bool:
	return request.get("kind", &"") in [&"advance", &"flank", &"move"]

func support_pressure(context) -> float:
	if not context.cooperation_enabled(): return 0.0
	var data: Dictionary = context.cooperation_snapshot()
	var id: int = context.actor.get_instance_id()
	var need := 0.0
	for request in data.requests:
		if request.beneficiary_id == id: continue
		var covered := 0.0
		for support in data.supports:
			if support.owner_id == id or support.get("lane_id", &"target") != &"target": continue
			if _request_requires_stationary(request) and support.get("moving", false): continue
			covered = maxf(covered, float(support.support_seconds))
		need = maxf(need, maxf(0.0, float(request.get("remaining", 0.0)) - covered))
	return clampf(need / maxf(0.1, context.utility_horizon_seconds), 0.0, 1.0)


# Unified tactical bridge. Offers are published after the caller's read-only
# evaluation batch. None of these functions runs an action, navigates or fires.
func _clear_coordination() -> void:
	_coordination_sources.clear()
	_coordination_source_pool.clear()
	_coordination_receipts.clear()
	_coordination_offers.clear()
	_coordination_plans.clear()
	_coordination_environments.clear()
	_coordination_due.clear()
	_coordination_failures.clear()
	_coordination_counters.clear()
	_coordination_checked.clear()

func _coordination_team(context) -> int:
	if not _reservation_member_valid(context): return 0
	return int(_team_by_member.get(context.actor.get_instance_id(), 0))

func _coordination_key(team_id: int, target_id: int) -> String:
	return "%s:%s:%s" % [generation, team_id, target_id]

func _coordination_source_valid(context, source: Dictionary) -> bool:
	if _coordination_team(context) == 0: return false
	if typeof(source.get("source_id")) != TYPE_INT or source.source_id <= 0: return false
	if typeof(source.get("target_id")) != TYPE_INT or source.target_id < 0: return false
	if not source.get("position") is Vector3 or not source.position.is_finite(): return false
	if not _reservation_text(source.get("source")): return false
	if not _reservation_number(source.get("captured_at")) or not _reservation_number(source.get("valid_until")): return false
	if source.captured_at < 0.0 or source.captured_at > context.evidence_elapsed_seconds or source.valid_until <= context.evidence_elapsed_seconds: return false
	if source.target_id == 0:
		return source.source in [&"noise", &"sound"] and context.noise_search_origin.is_finite() and context.noise_search_origin.distance_squared_to(source.position) < 0.0001
	if source.target_id != context.cooperation_target_id(): return false
	# The Context event bridge is the source authority; this additionally checks
	# against acquired observation values, never the hidden target's transform.
	if source.source == &"visual":
		return context.sees_player and context.last_seen_position.distance_squared_to(source.position) < 0.0001
	if source.source in [&"visual_loss", &"close_cover_exact", &"inspection"]:
		var inspected := inspection_evidence(context, source.target_id)
		return not inspected.is_empty() and int(inspected.id) == source.source_id and inspected.position.distance_squared_to(source.position) < 0.0001
	if source.source in [&"shared_visual", &"observation_memory"]:
		if source.source == &"observation_memory" and source.valid_until > source.captured_at + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0)) + 0.0001: return false
		for report: Dictionary in _reports.values():
			if int(report.id) == source.source_id and report.target_id == source.target_id and report.valid_until > elapsed and _inspection_domain_matches(context, report) and report.position.distance_squared_to(source.position) < 0.0001: return true
	return false

## Input timestamps use Context time. A duplicate source event cannot refresh
## its timestamp or deadline; only a genuinely acquired newer source can do so.
func publish_noise_source(context, position: Vector3) -> void:
	if not context.cooperation_enabled() or not position.is_finite(): return
	_serial += 1
	var captured: float = context.evidence_elapsed_seconds
	publish_coordination_source(context, {"source_id": _serial, "source": &"noise", "target_id": 0,
		"position": position, "captured_at": captured,
		"valid_until": captured + maxf(0.1, context.setting(&"cooperation", &"cover_inspection_seconds", 20.0))})

func publish_coordination_source(context, source: Dictionary) -> void:
	if not _coordination_source_valid(context, source): return
	var actor_id: int = context.actor.get_instance_id()
	var team_id := _coordination_team(context)
	var key := _coordination_key(team_id, source.target_id)
	var receipt_key: Array = [actor_id, source.target_id, StringName(source.source)]
	var receipt: Dictionary = _coordination_receipts.get(receipt_key, {})
	var same_event: bool = not receipt.is_empty() and receipt.source_id == source.source_id
	if same_event and receipt.team_id == team_id: return
	var offset: float = elapsed - context.evidence_elapsed_seconds
	var captured: float = float(receipt.captured_at) if same_event else maxf(0.0, float(source.captured_at) + offset)
	var deadline: float = float(receipt.valid_until) if same_event else float(source.valid_until) + offset
	if deadline <= elapsed: return
	_coordination_receipts[receipt_key] = {"source_id": source.source_id, "captured_at": captured, "valid_until": deadline, "team_id": team_id}
	var previous := _active_coordination_source(key)
	# A newer sight at another location contradicts an older investigation. An
	# older, longer-lived clue at the SAME frozen anchor remains a valid fallback.
	if not previous.is_empty() and captured < previous.captured_at and previous.position.distance_to(source.position) >= COORDINATION_SOURCE_DISTANCE: return
	var new_anchor: bool = previous.is_empty() or previous.position.distance_to(source.position) >= COORDINATION_SOURCE_DISTANCE
	var evidence_id: int = int(previous.get("evidence_id", 0))
	if new_anchor:
		_serial += 1
		evidence_id = _serial
		_drop_coordination_plan(team_id, &"new_evidence")
		_coordination_source_pool[key] = {}
	var anchor: Vector3 = source.position if new_anchor else previous.position
	var axis: Vector3 = _coordination_source_axis(team_id, anchor, source.target_id) if new_anchor else previous.front_axis
	var observed := {"source_id": source.source_id, "source": StringName(source.source),
		"observed_position": source.position, "captured_at": captured, "valid_until": deadline, "observer_id": actor_id}
	# One latest observation per source family, at most three entries per anchor.
	# Vision and investigation deliberately have different original deadlines.
	var family: StringName = &"investigation" if source.source in [&"visual_loss", &"close_cover_exact", &"inspection", &"observation_memory"] else (&"sound" if source.target_id == 0 else &"vision")
	var pool: Dictionary = _coordination_source_pool.get(key, {})
	var old: Dictionary = pool.get(family, {})
	if old.is_empty() or captured > old.captured_at or (captured == old.captured_at and deadline > old.valid_until): pool[family] = observed
	_coordination_source_pool[key] = pool
	_coordination_sources[key] = {"target_id": source.target_id, "position": anchor, "front_axis": axis,
		"flank_clustered": _coordination_clustered(team_id, anchor, axis, source.target_id) if new_anchor else previous.flank_clustered,
		"evidence_id": evidence_id, "generation": generation, "team_id": team_id}
	if new_anchor:
		_coordination_due[team_id] = elapsed
		revision += 1

func _active_coordination_source(key: String) -> Dictionary:
	var frame: Dictionary = _coordination_sources.get(key, {})
	if frame.is_empty(): return {}
	var best: Dictionary = {}
	for item: Dictionary in _coordination_source_pool.get(key, {}).values():
		if item.valid_until <= elapsed: continue
		if best.is_empty() or item.captured_at > best.captured_at or (item.captured_at == best.captured_at and item.valid_until > best.valid_until): best = item
	if best.is_empty(): return {}
	var result := frame.duplicate(true)
	result.merge(best, true)
	return result

## Getter uses board time, makes no new event and never renews a plan. Expired
## short vision can expose a still-valid old clue with its ORIGINAL timestamps.
func coordination_source(context, target_id: int = 0) -> Dictionary:
	var team_id := _coordination_team(context)
	if team_id == 0 or (target_id != 0 and target_id != context.cooperation_target_id()): return {}
	return _active_coordination_source(_coordination_key(team_id, target_id))

func _coordination_source_axis(team_id: int, anchor: Vector3, target_id: int) -> Vector3:
	var center := Vector3.ZERO
	var positions: Array[Vector3] = []
	var ordered: Array = _members.keys()
	ordered.sort()
	for id: int in ordered:
		var context = _context(id)
		if not _reservation_member_valid(context) or _team_by_member.get(id, 0) != team_id: continue
		if target_id != 0 and context.cooperation_target_id() != target_id: continue
		positions.append(context.actor.global_position)
		center += context.actor.global_position
	var direction: Vector3 = center / float(positions.size()) - anchor if not positions.is_empty() else Vector3.ZERO
	direction.y = 0.0
	if direction.length_squared() < 0.0001:
		for point: Vector3 in positions:
			direction = point - anchor
			direction.y = 0.0
			if direction.length_squared() >= 0.0001: break
	return direction.normalized() if direction.length_squared() >= 0.0001 else Vector3.FORWARD

func _coordination_clustered(team_id: int, anchor: Vector3, axis: Vector3, target_id: int) -> bool:
	var directions: Array[Vector3] = []
	for id: int in _members:
		var context = _context(id)
		if not _reservation_member_valid(context) or _team_by_member.get(id, 0) != team_id or context.cooperation_target_id() != target_id: continue
		var direction: Vector3 = context.actor.global_position - anchor
		direction.y = 0.0
		if direction.dot(axis) <= FLANK_SIDE_MARGIN: return false
		direction = direction.normalized()
		for previous: Vector3 in directions:
			if previous.dot(direction) <= FLANK_SEPARATION_COSINE: return false
		directions.append(direction)
	return directions.size() >= 2

func _coordination_roles(context, target_id: int) -> Array:
	var result: Array = []
	if not _reservation_member_valid(context) or not context.cooperation_enabled(): return result
	if not context.is_alerted and not context.noise_search_origin.is_finite(): return result
	if target_id != 0 and context.cooperation_target_id() != target_id: return result
	var mobile: bool = context.actor.can_move() and not context.actor.is_vaulting() and not context.actor.melee_active
	if context.coordinated_cooperation_enabled() and mobile and not context.sees_player and context.can_use_action(&"search") and (context.is_alerted or context.noise_search_origin.is_finite()):
		result.append(&"search_sector")
		if target_id != 0:
			result.append(&"inspect_left")
			result.append(&"inspect_right")
	if target_id != 0 and context.can_use_action(&"cooperate"):
		if mobile and coordination_source(context, target_id).get("flank_clustered", false): result.append(&"flank")
		if context.actor.can_use_firearms() and context.actor.shooting_enabled and not context.actor.is_vaulting() and not context.actor.melee_active:
			result.append(&"front_support")
	return result

func _coordination_offer_valid(context, offer: Dictionary, board_time: bool = false) -> bool:
	if not _reservation_member_valid(context) or not _members[context.actor.get_instance_id()].versions_published: return false
	if int(offer.get("team_config_revision", 0)) != team_configuration_revision(context): return false
	if offer.get("scope") != &"tactical": return false
	for key in [&"offer_key", &"owner_action", &"position_set_key", &"role"]:
		if not _reservation_text(offer.get(key)): return false
	if not context.can_use_action(StringName(offer.owner_action)): return false
	var expected: StringName = &"search" if offer.role in [&"inspect_left", &"inspect_right", &"search_sector"] else &"cooperate"
	if offer.owner_action != expected: return false
	var identity := coordination_identity(context)
	for key in [&"actor_id", &"generation", &"member_generation", &"config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if typeof(offer.get(key)) != TYPE_INT or offer[key] != identity[key]: return false
	if typeof(offer.get("target_id")) != TYPE_INT or typeof(offer.get("evidence_id")) != TYPE_INT: return false
	if not _coordination_roles(context, offer.target_id).has(offer.role): return false
	var source := coordination_source(context, offer.target_id)
	if source.is_empty() or offer.evidence_id != source.evidence_id: return false
	if not offer.get("position") is Vector3 or not offer.position.is_finite(): return false
	var budget: Array = [2048]
	if not _team_planner._values_only(offer, budget, 0) or not _team_planner._summary_valid(offer.get("path_summary")): return false
	if not _reservation_summary_valid(offer.path_summary): return false
	var summary: Dictionary = offer.path_summary
	if offer.role == &"search_sector" and summary.has("sector_key"):
		if not context.has_method("coordination_search_template_valid") or not context.coordination_search_template_valid(String(summary.sector_key), int(summary.get("source_revision", -1)), int(summary.get("template_navigation_revision", -1))): return false
	if not summary.get("staging_position") is Vector3 or not summary.staging_position.is_finite(): return false
	if not _reservation_number(summary.get("staging_seconds")) or summary.staging_seconds < 0.0: return false
	if not _coordination_frame_valid(summary, source, StringName(offer.role), offer.position): return false
	if offer.role in [&"inspect_left", &"inspect_right", &"search_sector"]:
		var observations: Variant = summary.get("observation_points")
		if not observations is Array or observations.is_empty() or observations.size() > 64: return false
		for point in observations:
			if not point is Vector3 or not point.is_finite(): return false
	for key in [&"cost", &"travel_seconds", &"unavailable_seconds", &"exposed_seconds", &"information_loss", &"measured_support_seconds"]:
		if not _reservation_number(offer.get(key)): return false
		if key != &"cost" and offer[key] < 0.0: return false
	if not offer.get("movement_possible") is bool or not offer.get("fire_ready") is bool: return false
	if offer.role != &"front_support" and not offer.movement_possible: return false
	var now: float = elapsed if board_time else context.evidence_elapsed_seconds
	if offer.has("accept_after"):
		if not _reservation_number(offer.accept_after) or not _reservation_number(offer.get("captured_at")): return false
		if offer.accept_after < offer.captured_at or offer.accept_after > offer.captured_at + COORDINATION_MAX_SECONDS: return false
	return _team_planner._fresh(offer, now)

## Atomic publication: malformed arrays preserve the last legitimate batch.
## An empty legitimate batch withdraws offers, not a running valid assignment.
func submit_offers(context, offers: Array) -> bool:
	if not _reservation_member_valid(context) or offers.size() > 6: return false
	var copied: Array = []
	var keys: Dictionary = {}
	for value in offers:
		if not value is Dictionary or not _coordination_offer_valid(context, value) or keys.has(value.offer_key): return false
		keys[value.offer_key] = true
		var offer: Dictionary = value.duplicate(true)
		offer.path_summary = _coordination_physical_summary(context, value.path_summary, value.target_id)
		var offset: float = elapsed - context.evidence_elapsed_seconds
		offer.captured_at = maxf(0.0, float(offer.captured_at) + offset)
		offer.valid_until = float(offer.valid_until) + offset
		if offer.has("accept_after"): offer.accept_after = float(offer.accept_after) + offset
		copied.append(offer)
	_coordination_offers[context.actor.get_instance_id()] = copied
	# Publication does not invoke the planner or bypass its maintenance period.
	return true

func _coordination_team_members(team_id: int) -> Array:
	var result: Array = []
	for id: int in _members:
		if _team_by_member.get(id, 0) == team_id and _reservation_member_valid(_context(id)) and _members[id].versions_published: result.append(id)
	result.sort()
	return result

func _coordination_environment(team_id: int, ids: Array) -> int:
	var signature: Array = []
	for id: int in ids:
		var member: Dictionary = _members[id]
		signature.append([id, member.member_generation, member.environment_revision, member.navigation_revision])
	var previous: Dictionary = _coordination_environments.get(team_id, {})
	if previous.is_empty() or previous.signature != signature:
		_serial += 1
		_coordination_environments[team_id] = {"signature": signature, "revision": _serial}
	return int(_coordination_environments[team_id].revision)

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

func _coordination_plan_source(plan: Dictionary) -> Dictionary:
	var source := _active_coordination_source(_coordination_key(plan.team_id, plan.target_id))
	return source if not source.is_empty() and source.valid_until > elapsed and source.evidence_id == plan.evidence_id else {}

func _coordination_assignment_valid(plan: Dictionary, entry: Dictionary) -> bool:
	var context = _context(int(entry.actor_id))
	if _coordination_plan_source(plan).is_empty() or plan.expires_at <= elapsed or entry.expires_at <= elapsed: return false
	if not _reservation_member_valid(context) or _coordination_team(context) != plan.team_id: return false
	if int(entry.get("team_config_revision", 0)) != team_configuration_revision(context): return false
	if not _coordination_roles(context, plan.target_id).has(entry.role) or not context.can_use_action(entry.owner_action): return false
	var identity := coordination_identity(context)
	for key in [&"member_generation", &"config_revision", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if entry[key] != identity[key]: return false
	if entry.get("failed", false): return false
	var primary: Dictionary = _reservations.get(entry.reservation_id, {})
	var pending: Dictionary = _reservations.get(entry.get("pending_reservation_id", 0), {})
	if primary.is_empty() and (pending.is_empty() or pending.accept_until <= elapsed): return false
	if not entry.accepted and entry.accept_until <= elapsed: return false
	return true

func _assignment_for_owner(owner_id: int) -> Dictionary:
	var plan: Dictionary = _coordination_plans.get(_team_by_member.get(owner_id, 0), {})
	if plan.is_empty(): return {}
	for entry: Dictionary in plan.assignments:
		if entry.actor_id == owner_id and _coordination_assignment_valid(plan, entry): return entry
	return {}

func _assignment_token(context, token: Dictionary) -> Dictionary:
	if not _reservation_member_valid(context): return {}
	var entry := _assignment_for_owner(context.actor.get_instance_id())
	if entry.is_empty(): return {}
	for key in [&"plan_id", &"plan_version", &"assignment_id", &"assignment_revision", &"actor_id", &"generation", &"team_id", &"evidence_id"]:
		if token.get(key) != entry[key]: return {}
	return entry

## A live plan does not require its original preview offers to remain in cache.
func assignment(context) -> Dictionary:
	if not _reservation_member_valid(context): return {}
	var entry := _assignment_for_owner(context.actor.get_instance_id())
	if entry.is_empty(): return {}
	var plan: Dictionary = _coordination_plans[entry.team_id]
	var result := _assignment_snapshot(entry)
	result.phase = plan.phase
	result.phase_id = plan.phase_id
	result.release_at = plan.release_at
	result.stage_until = plan.stage_until
	result.tactic = plan.tactic
	return result

## Internal previews can be large. Exclude them before copying public values;
## all remaining nested arrays/dictionaries still belong to the caller.
func _assignment_snapshot(entry: Dictionary) -> Dictionary:
	var result := entry.duplicate()
	result.erase("raw_offers")
	return result.duplicate(true)

func _reservation_projections(entry: Dictionary) -> Array:
	if entry.get("scope") == &"tactical" and entry.phase == &"pending" and entry.get("selected_offer_key", "") == "":
		return entry.get("alternatives", [])
	return [entry]

func _tactical_reservation_valid(reservation: Dictionary) -> bool:
	var entry := _assignment_for_owner(int(reservation.owner_id))
	return not entry.is_empty() and reservation.reservation_id in [entry.reservation_id, entry.get("pending_reservation_id", 0)] and entry.assignment_id == reservation.get("assignment_id")

func _coordination_reservation(context, entry: Dictionary, plan: Dictionary) -> Dictionary:
	var first: Dictionary = entry.reserved_offers[0]
	var reservation := _reservation_footprint(context, first.position)
	reservation.merge(coordination_identity(context))
	reservation.merge({"reservation_id": entry.reservation_id, "assignment_id": entry.assignment_id,
		"owner_id": entry.actor_id, "owner_action": entry.owner_action, "offer_key": first.offer_key,
		"position_set_key": first.position_set_key, "path_summary": _reservation_summary(first.path_summary),
		"scope": &"tactical", "role": entry.role, "target_id": plan.target_id, "evidence_id": plan.evidence_id,
		"phase": &"pending", "created_at": elapsed, "expires_at": entry.expires_at, "accept_until": entry.accept_until,
		"selected_offer_key": "", "alternatives": entry.reserved_offers.duplicate(true)})
	return reservation

func prepare_assignment(context, identity: Dictionary, offer_key: String) -> Dictionary:
	var entry := _assignment_token(context, identity)
	if entry.is_empty() or not entry.allowed_offer_keys.has(offer_key): return {}
	if entry.accepted and not entry.get("segment_boundary", false): return {}
	var selected: Dictionary = {}
	for option: Dictionary in entry.reserved_offers:
		if option.offer_key == offer_key: selected = option
	if selected.is_empty(): return {}
	var existing_pending: Dictionary = _reservations.get(entry.get("pending_reservation_id", 0), {})
	if not existing_pending.is_empty() and existing_pending.offer_key == offer_key and _reservation_valid(existing_pending):
		return existing_pending.duplicate(true) if _reservation_position_available(context, existing_pending, existing_pending.reservation_id) else {}
	var reservation: Dictionary = _reservations.get(entry.reservation_id, {})
	if reservation.is_empty() or not _reservation_valid(reservation): return {}
	var proposed := reservation.duplicate(true)
	proposed.merge({"position": selected.position, "offer_key": selected.offer_key,
		"position_set_key": selected.position_set_key, "path_summary": _reservation_summary(selected.path_summary),
		"selected_offer_key": selected.offer_key}, true)
	if not _reservation_position_available(context, proposed, int(reservation.reservation_id)): return {}
	if entry.accepted:
		# A different allowed segment gets a separate pending physical lease;
		# the task itself and its original deadline remain exactly the same.
		_serial += 1
		proposed.reservation_id = _serial
		proposed.phase = &"pending"
		proposed.created_at = elapsed
		proposed.accept_until = minf(entry.expires_at, elapsed + COORDINATION_ACCEPT_SECONDS)
		proposed.erase("accepted_at")
		if not existing_pending.is_empty(): _reservations.erase(existing_pending.reservation_id)
		entry.pending_reservation_id = proposed.reservation_id
	_reservations[proposed.reservation_id] = proposed
	return proposed.duplicate(true)

func commit_assignment(context, identity: Dictionary, reservation_token: Dictionary) -> bool:
	var entry := _assignment_token(context, identity)
	if entry.is_empty(): return false
	var expected: int = int(entry.get("pending_reservation_id", entry.reservation_id))
	if expected != reservation_token.get("reservation_id"): return false
	var reservation: Dictionary = _reservations.get(expected, {})
	if reservation.is_empty() or reservation.get("selected_offer_key", "") == "": return false
	if entry.accepted and expected == entry.reservation_id: return validate_reservation(context, reservation_token)
	if not commit_reservation(context, reservation_token): return false
	var initial: bool = not entry.accepted
	entry.accepted = true
	entry.reservation_id = expected
	entry.erase("pending_reservation_id")
	entry.selected_offer_key = reservation.offer_key
	entry.selected_position = reservation.position
	for selected: Dictionary in entry.reserved_offers:
		if selected.offer_key == entry.selected_offer_key:
			entry.staging_position = selected.path_summary.staging_position
			entry.observation_points = selected.path_summary.get("observation_points", []).duplicate()
	if initial: entry.accepted_at = elapsed
	entry.support_prepare_until = minf(entry.expires_at, elapsed + COORDINATION_WAIT_SECONDS)
	entry.last_report_at = elapsed
	entry.ready_for_phase = false
	entry.segment_boundary = false
	return true

func rollback_assignment(context, identity: Dictionary, reservation_token: Dictionary) -> void:
	var entry := _assignment_token(context, identity)
	if entry.is_empty(): return
	var expected: int = int(entry.get("pending_reservation_id", entry.reservation_id))
	if expected != reservation_token.get("reservation_id"): return
	var reservation: Dictionary = _reservation_token(context, reservation_token)
	if reservation.is_empty() or reservation.phase != &"pending": return
	rollback_reservation(context, reservation_token)
	# Canceling preparation before the caller clears the old action leaves its
	# accepted lease intact. A failed begin after clear cannot resurrect it.
	if entry.accepted and expected != entry.reservation_id and _reservations.has(entry.reservation_id):
		entry.erase("pending_reservation_id")
		return
	_reservations.erase(entry.reservation_id)
	entry.erase("pending_reservation_id")
	entry.failed = true
	entry.failure_reason = &"begin_failed"
	_coordination_failures.append({"actor_id": entry.actor_id, "offer_key": reservation_token.offer_key,
		"valid_until": minf(entry.expires_at, elapsed + 2.0), "team_id": entry.team_id,
		"target_id": entry.target_id, "evidence_id": entry.evidence_id})
	if _coordination_failures.size() > 128: _coordination_failures.pop_front()
	_coordination_due[entry.team_id] = elapsed

## Reports describe the action's validated local execution. They cannot change
## geometry, identities, lease durations, Fire state or any other actor's body.
func report_assignment(context, report: Dictionary) -> bool:
	var entry := _assignment_token(context, report)
	if entry.is_empty(): return false
	var plan: Dictionary = _coordination_plans[entry.team_id]
	if report.get("phase_id") != plan.phase_id: return false
	var state: StringName = report.get("state", &"")
	if state not in [&"moving", &"arrived", &"complete", &"unavailable", &"self_preservation"]: return false
	if not entry.accepted and state not in [&"unavailable", &"self_preservation"]: return false
	if not report.get("segment_boundary", false) is bool: return false
	if state in [&"unavailable", &"self_preservation"]:
		entry.failed = true
		entry.failure_reason = state
		_reservations.erase(entry.reservation_id)
		_reservations.erase(entry.get("pending_reservation_id", 0))
		_record_coordination_failure(entry, plan)
		_coordination_due[plan.team_id] = elapsed
		return true
	if report.get("execution_valid", true) != true: return false
	if state == &"arrived":
		if context.actor.global_position.distance_to(entry.staging_position) > 0.35 or not context.actor.can_move() or context.actor.is_vaulting() or context.actor.melee_active: return false
	if state == &"complete":
		if entry.complete: return true
		if entry.role in [&"flank", &"inspect_left", &"inspect_right"] and context.actor.global_position.distance_to(entry.selected_position) > 0.35: return false
		if plan.phase != &"executing" or plan.release_at < 0.0 or elapsed < plan.release_at: return false
		if entry.role in [&"inspect_left", &"inspect_right", &"search_sector"]:
			if not _record_assignment_observations(context, entry, plan, report): return false
			for expected: Vector3 in entry.observation_points:
				if not entry.get("observed_points", {}).has(expected): return false
		entry.complete = true
	if state != &"complete" and plan.phase == &"executing" and plan.release_at >= 0.0 and elapsed >= plan.release_at:
		if not _record_assignment_observations(context, entry, plan, report): return false
	entry.last_report_at = elapsed
	entry.segment_boundary = report.get("segment_boundary", false)
	entry.position = context.actor.global_position
	entry.ready_for_phase = state == &"arrived"
	entry.report_phase_id = plan.phase_id
	return true


## Incremental observations belong to this accepted assignment and version.
## Re-reporting a point never renews its original observation or expiry.
func _record_assignment_observations(context, entry: Dictionary, plan: Dictionary, report: Dictionary) -> bool:
	if entry.role not in [&"inspect_left", &"inspect_right", &"search_sector"]: return true
	var checked: Variant = report.get("checked_points", PackedVector3Array())
	if not checked is PackedVector3Array or checked.size() > 64: return false
	for point: Vector3 in checked:
		if not point.is_finite() or not entry.observation_points.has(point) or not context.perception.can_observe_position(point): return false
	if not entry.has("observed_points"): entry.observed_points = {}
	var newly_checked := PackedVector3Array()
	for point: Vector3 in checked:
		if entry.observed_points.has(point): continue
		entry.observed_points[point] = elapsed
		newly_checked.append(point)
		var grid := Vector3i(roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0))
		_coordination_checked[[plan.team_id, plan.evidence_id, grid]] = {"position": point, "observer_id": entry.actor_id,
			"team_id": plan.team_id, "target_id": plan.target_id, "evidence_id": plan.evidence_id,
			"navigation_revision": entry.navigation_revision, "observed_at": elapsed, "valid_until": minf(float(_coordination_plan_source(plan).valid_until), elapsed + maxf(0.1, context.setting(&"cooperation", &"checked_point_seconds", 3.0)))}
	if plan.target_id != 0 and not newly_checked.is_empty(): publish_checked(context, newly_checked)
	return true

## Negative observations are kept in the task domain, never the shared map.
## In particular targetless sound never becomes a negative player observation.
func coordination_checked_points(context, target_id: int = 0) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var source := coordination_source(context, target_id)
	if source.is_empty(): return result
	var navigation_version: int = int(coordination_identity(context).get("navigation_revision", -1))
	for checked: Dictionary in _coordination_checked.values():
		if checked.team_id == source.team_id and checked.target_id == target_id and checked.evidence_id == source.evidence_id and checked.valid_until > elapsed and checked.get("navigation_revision", -1) == navigation_version: result.append(checked.duplicate(true))
	return result

func _coordination_occupancy(context) -> Array:
	var result: Array = []
	var owner: int = context.actor.get_instance_id()
	for id: int in _members:
		var other = _context(id)
		if not _reservation_member_valid(other) or not can_share_space(owner, id): continue
		var footprint := _reservation_footprint(other, other.actor.global_position)
		result.append({"actor_id": id, "kind": &"body", "position": footprint.position,
			"captured_at": elapsed, "valid_until": elapsed + COORDINATION_PERIOD,
			"path_summary": _coordination_physical_summary(other, {}, other.cooperation_target_id())})
	for reservation: Dictionary in _reservations.values():
		if not _reservation_valid(reservation) or not can_share_space(owner, reservation.owner_id): continue
		for projection: Dictionary in _reservation_projections(reservation):
			var summary := _coordination_physical_summary(_context(reservation.owner_id), projection.get("path_summary", {}), reservation.target_id)
			result.append({"actor_id": reservation.owner_id, "kind": &"reservation", "position": projection.position,
				"reservation_id": reservation.reservation_id, "position_set_key": projection.position_set_key,
				"captured_at": elapsed, "valid_until": reservation.expires_at, "path_summary": summary})
	return result

func _coordination_requests(ids: Array, source: Dictionary) -> Array:
	var result: Array = []
	for id: int in ids:
		var context = _context(id)
		var status: Dictionary = _members[id].status
		var age: float = elapsed - float(status.get("updated_at", -INF))
		if age > 0.35 or status.get("target_id", 0) != source.target_id: continue
		if context.actor.ammo.is_reloading and status.get("reloading", false) and status.has("reload_request_id"):
			var remaining: float = maxf(0.0, float(status.get("reload_seconds", 0.0)) - age)
			if remaining > 0.0:
				result.append({"request_id": status.reload_request_id, "actor_id": id, "kind": &"reload", "actual": true,
					"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": float(status.updated_at),
					"valid_until": minf(elapsed + remaining, float(status.updated_at) + 0.35)})
		var need: Dictionary = status.get("support_request", {})
		if need.get("kind") == &"retreat" and status.get("moving", false) and status.has("support_request_id"):
			var remaining: float = maxf(0.0, float(need.get("duration", 0.0)) - age)
			if remaining > 0.0:
				result.append({"request_id": status.support_request_id, "actor_id": id, "kind": &"retreat", "actual": true,
					"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": float(status.updated_at),
					"valid_until": minf(elapsed + remaining, float(status.updated_at) + 0.35)})
	var plan: Dictionary = _coordination_plans.get(source.team_id, {})
	if not plan.is_empty():
		for entry: Dictionary in plan.assignments:
			if not entry.accepted or entry.complete or not entry.role in [&"flank", &"inspect_left", &"inspect_right", &"search_sector"] or not _coordination_assignment_valid(plan, entry): continue
			var status: Dictionary = _members[entry.actor_id].status
			var moving: bool = elapsed - float(status.get("updated_at", -INF)) <= 0.35 and status.get("moving", false)
			if not moving and elapsed > float(entry.get("support_prepare_until", -INF)): continue
			result.append({"request_id": entry.assignment_id, "actor_id": entry.actor_id, "kind": &"advance", "accepted": true,
				"target_id": source.target_id, "evidence_id": source.evidence_id, "captured_at": entry.accepted_at,
				"valid_until": minf(entry.expires_at, plan.stage_until)})
	return result.slice(0, 32)

func _coordination_frame_valid(summary: Dictionary, source: Dictionary, role: StringName, position: Vector3) -> bool:
	if role not in [&"flank", &"front_support"] or not summary.has("tactical_key"): return true
	var anchor: Variant = summary.get("tactical_anchor")
	var axis: Variant = summary.get("tactical_axis")
	if not anchor is Vector3 or not axis is Vector3 or not anchor.is_finite() or not axis.is_finite(): return false
	if anchor.distance_to(source.position) > 0.001 or axis.distance_to(source.front_axis) > 0.001 or absf(axis.y) > 0.001 or absf(axis.length() - 1.0) > 0.001: return false
	var side: float = (position - anchor).dot(axis)
	return side < -FLANK_SIDE_MARGIN if role == &"flank" else side > FLANK_SIDE_MARGIN

func _coordination_offer_observed(source: Dictionary, offer: Dictionary) -> bool:
	if _coordination_checked.is_empty() or offer.role not in [&"inspect_left", &"inspect_right", &"search_sector"]: return false
	for point: Vector3 in offer.path_summary.observation_points:
		var grid := Vector3i(roundi(point.x * 100.0), roundi(point.y * 100.0), roundi(point.z * 100.0))
		var checked: Dictionary = _coordination_checked.get([source.team_id, source.evidence_id, grid], {})
		if checked.is_empty() or checked.valid_until <= elapsed or checked.target_id != source.target_id or checked.get("navigation_revision", -1) != offer.navigation_revision: return false
	return true

func _coordination_snapshot(team_id: int, source: Dictionary, ids: Array) -> Dictionary:
	var environment := _coordination_environment(team_id, ids)
	var current: Dictionary = _coordination_plans.get(team_id, {})
	var frame: Dictionary = current.get("tactical_frame", {}) if not current.is_empty() else {"anchor": source.position, "axis": source.front_axis}
	var members: Array = []
	var representative = _context(ids[0])
	for id: int in ids:
		var context = _context(id)
		var identity := coordination_identity(context)
		var actual := _coordination_actual(context, source.target_id)
		var offers: Array = []
		for raw: Dictionary in _coordination_offers.get(id, []):
			if raw.target_id != source.target_id or raw.evidence_id != source.evidence_id or not _coordination_offer_valid(context, raw, true): continue
			if _coordination_offer_observed(source, raw): continue
			var normalized := raw.duplicate(true)
			normalized.path_summary = _coordination_physical_summary(context, raw.path_summary, source.target_id)
			# Original per-member versions remain in raw_offers for acceptance.
			normalized.environment_revision = environment
			if normalized.role == &"front_support":
				normalized.fire_ready = actual.fire_ready and raw.fire_ready
				normalized.measured_support_seconds = minf(raw.measured_support_seconds, actual.measured_support_seconds)
				if raw.path_summary.get("holds_front", false) and _members[id].status.get("moving", false): normalized.fire_ready = false
			offers.append(normalized)
		var far: bool = context.cooperation_target_id() == source.target_id and not frame.is_empty() and (context.actor.global_position - frame.anchor).dot(frame.axis) < -FLANK_SIDE_MARGIN
		members.append({"actor_id": id, "member_generation": identity.member_generation, "config_revision": identity.config_revision,
			"navigation_revision": identity.navigation_revision, "position": context.actor.global_position,
			"advanced_enabled": context.cooperation_enabled(), "eligible_roles": _coordination_roles(context, source.target_id),
			"offers": offers, "actual_support": actual, "on_far_side": far})
	var snapshot_value := {"now": elapsed, "generation": generation, "team_id": team_id, "domain": "team:%s" % team_id,
		"target_id": source.target_id, "evidence_id": source.evidence_id, "environment_revision": environment,
		"navigation_revision": int(_members[ids[0]].navigation_revision), "relation_revision": relation_revision,
		"members": members, "occupancy": _coordination_occupancy(representative), "requests": _coordination_requests(ids, source),
		"failures": _coordination_failures.filter(func(entry): return entry.team_id == team_id and entry.target_id == source.target_id and entry.evidence_id == source.evidence_id).duplicate(true), "flank_owner_ids": [], "current_plan": {}}
	if not current.is_empty():
		var projected := current.duplicate()
		projected.erase("assignments")
		projected = projected.duplicate(true)
		projected.assignments = []
		projected.execution_valid = _coordination_plan_source(current).size() > 0 and current.expires_at > elapsed
		projected.segment_boundary = true
		for stored: Dictionary in current.assignments:
			var entry := _assignment_snapshot(stored)
			entry.execution_valid = _coordination_assignment_valid(current, entry)
			var owner = _context(int(entry.actor_id))
			if _reservation_member_valid(owner):
				for reserved: Dictionary in entry.reserved_offers:
					reserved.path_summary = _coordination_physical_summary(owner, reserved.path_summary, current.target_id)
			projected.segment_boundary = projected.segment_boundary and entry.get("segment_boundary", true)
			if entry.role == &"flank" and entry.execution_valid: snapshot_value.flank_owner_ids.append(entry.actor_id)
			projected.assignments.append(entry)
		snapshot_value.current_plan = projected
	return snapshot_value

func _coordination_find_source(team_id: int, ids: Array) -> Dictionary:
	var current: Dictionary = _coordination_plans.get(team_id, {})
	if not current.is_empty(): return _coordination_plan_source(current)
	var best: Dictionary = {}
	for key: String in _coordination_sources:
		if _coordination_sources[key].team_id != team_id: continue
		var source := _active_coordination_source(key)
		if source.is_empty() or (not best.is_empty() and source.captured_at <= best.captured_at): continue
		var offered := false
		for id: int in ids:
			for offer: Dictionary in _coordination_offers.get(id, []):
				if offer.target_id == source.target_id and offer.evidence_id == source.evidence_id and _coordination_offer_valid(_context(id), offer, true):
					offered = true
					break
			if offered: break
		if offered: best = source
	return best

func _coordination_entry(proposal: Dictionary, plan: Dictionary) -> Dictionary:
	var context = _context(int(proposal.actor_id))
	if not _reservation_member_valid(context): return {}
	var raw_offers: Array = []
	for key in proposal.allowed_offer_keys:
		var found := false
		for raw: Dictionary in _coordination_offers.get(proposal.actor_id, []):
			if raw.offer_key == key and _coordination_offer_valid(context, raw, true):
				raw_offers.append(raw.duplicate(true))
				found = true
				break
		if not found: return {}
	if raw_offers.is_empty(): return {}
	var entry := proposal.duplicate(true)
	entry.merge(coordination_identity(context))
	_serial += 1
	entry.assignment_id = _serial
	_serial += 1
	entry.reservation_id = _serial
	entry.assignment_revision = 1
	entry.plan_id = plan.plan_id
	entry.plan_version = plan.plan_version
	entry.target_id = plan.target_id
	entry.evidence_id = plan.evidence_id
	entry.created_at = elapsed
	entry.expires_at = plan.expires_at
	entry.accept_until = minf(plan.expires_at, elapsed + COORDINATION_ACCEPT_SECONDS)
	for raw: Dictionary in raw_offers:
		entry.accept_until = minf(plan.expires_at, maxf(entry.accept_until, float(raw.get("accept_after", elapsed))))
	# Preview expiry gates issuance above. Once assigned, acceptance has its own
	# original fixed window and live body/route validation; it is never renewed.
	entry.accepted = false
	entry.complete = false
	entry.failed = false
	entry.ready_for_phase = false
	entry.segment_boundary = true
	entry.last_report_at = elapsed
	entry.raw_offers = raw_offers
	return entry

func _coordination_plan_duration(proposal: Dictionary) -> float:
	var travel := 0.0
	for entry: Dictionary in proposal.assignments:
		for raw: Dictionary in _coordination_offers.get(entry.actor_id, []):
			if entry.allowed_offer_keys.has(raw.offer_key): travel = maxf(travel, maxf(0.0, float(raw.get("accept_after", elapsed)) - elapsed) + float(raw.travel_seconds))
	return minf(COORDINATION_MAX_SECONDS, maxf(4.0, travel + COORDINATION_WAIT_SECONDS + 2.0))

func _install_coordination_proposal(team_id: int, source: Dictionary, proposal: Dictionary) -> void:
	var previous: Dictionary = _coordination_plans.get(team_id, {})
	if proposal.operation == &"keep": return
	if proposal.operation == &"none":
		if not previous.is_empty(): _drop_coordination_plan(team_id, StringName(proposal.reason))
		return
	var extending: bool = proposal.operation == &"extend" and not previous.is_empty()
	var repairing: bool = proposal.operation in [&"repair", &"extend"] and not previous.is_empty()
	var plan: Dictionary = previous.duplicate(true) if repairing else {}
	if not repairing:
		_serial += 1
		plan = {"plan_id": _serial, "plan_version": 1, "generation": generation, "team_id": team_id,
			"domain": "team:%s" % team_id, "target_id": source.target_id, "evidence_id": source.evidence_id,
			"tactic": proposal.tactic, "phase": &"assigning", "phase_id": 1, "release_at": -1.0,
			"created_at": elapsed, "expires_at": minf(source.valid_until, elapsed + _coordination_plan_duration(proposal)),
			"stage_until": elapsed + COORDINATION_ACCEPT_SECONDS, "assignments": [], "tactical_frame": {}}
		plan.stage_until = minf(plan.stage_until, plan.expires_at)
	elif not extending:
		# Repair never extends the original overall deadline or unaffected leases.
		plan.phase = &"assigning"
		plan.phase_id += 1
		plan.release_at = -1.0
		plan.stage_until = minf(plan.expires_at, elapsed + COORDINATION_ACCEPT_SECONDS)
	plan.required_participants = proposal.required_participants.duplicate()
	if proposal.has("request_id"): plan.request_id = proposal.request_id
	var replaced: Dictionary = {}
	if extending:
		for id: int in proposal.get("removed_actor_ids", []): replaced[id] = 0
	var new_entries: Array = []
	for item: Dictionary in proposal.assignments:
		var entry := _coordination_entry(item, plan)
		if entry.is_empty(): return
		new_entries.append(entry)
		plan.stage_until = minf(plan.expires_at, maxf(plan.stage_until, entry.accept_until))
		if repairing and not extending: replaced[int(item.previous_actor_id)] = int(item.actor_id)
		if item.role == &"flank":
			var summary: Dictionary = entry.raw_offers[0].path_summary
			plan.tactical_frame = {"anchor": summary.tactical_anchor, "axis": summary.tactical_axis, "key": summary.tactical_key}
	var retained: Array = []
	if repairing:
		for entry: Dictionary in plan.assignments:
			if replaced.has(entry.actor_id): continue
			# Retained assignment identity, accepted lease and deadline are unchanged.
			if extending: entry.partner_ids = entry.partner_ids.filter(func(id): return not replaced.has(id))
			else:
				for index in entry.partner_ids.size():
					entry.partner_ids[index] = replaced.get(entry.partner_ids[index], entry.partner_ids[index])
			if not extending: entry.ready_for_phase = false
			retained.append(entry)
	plan.assignments = retained + new_entries
	# Atomic install: every selected preview was validated above. The planner
	# has checked mutual conflicts; transactions recheck current physical facts.
	if not previous.is_empty():
		for old: Dictionary in previous.assignments:
			if not repairing or replaced.has(old.actor_id):
				_reservations.erase(old.reservation_id)
				_reservations.erase(old.get("pending_reservation_id", 0))
	_coordination_plans[team_id] = plan
	for entry: Dictionary in new_entries:
		_reservations[entry.reservation_id] = _coordination_reservation(_context(entry.actor_id), entry, plan)
	revision += 1

func _drop_coordination_plan(team_id: int, _reason: StringName) -> void:
	var plan: Dictionary = _coordination_plans.get(team_id, {})
	if plan.is_empty(): return
	for entry: Dictionary in plan.assignments:
		_reservations.erase(entry.reservation_id)
		_reservations.erase(entry.get("pending_reservation_id", 0))
	_coordination_plans.erase(team_id)
	revision += 1

func _invalidate_coordination_member(owner_id: int, reason: StringName) -> void:
	var plan: Dictionary = _coordination_plans.get(_team_by_member.get(owner_id, 0), {})
	if plan.is_empty(): return
	for entry: Dictionary in plan.assignments:
		if entry.actor_id == owner_id:
			entry.failed = true
			entry.failure_reason = reason
	_coordination_due[plan.team_id] = elapsed

## Failure cooldown is independent of the abandoned plan's expiry. Rebuilding
## a plan or receiving the same location again cannot erase an actual failure.
func _record_coordination_failure(entry: Dictionary, plan: Dictionary) -> void:
	for failure: Dictionary in _coordination_failures:
		if failure.actor_id == entry.actor_id and failure.position_set_key == entry.reserved_position_sets[0] and failure.team_id == plan.team_id and failure.evidence_id == plan.evidence_id and failure.valid_until > elapsed: return
	_coordination_failures.append({"actor_id": entry.actor_id, "position_set_key": entry.reserved_position_sets[0],
		"valid_until": elapsed + 2.0, "team_id": plan.team_id, "target_id": plan.target_id, "evidence_id": plan.evidence_id})
	if _coordination_failures.size() > 128: _coordination_failures.pop_front()

func _advance_coordination_phase(plan: Dictionary) -> void:
	if plan.expires_at <= elapsed or _coordination_plan_source(plan).is_empty():
		for entry: Dictionary in plan.assignments:
			if not entry.complete: _record_coordination_failure(entry, plan)
		_drop_coordination_plan(plan.team_id, &"expired")
		return
	var all_accepted := true
	var all_complete := true
	var movers_complete := true
	var mover_count := 0
	var required_ready := true
	var unready: Array = []
	for entry: Dictionary in plan.assignments:
		if not _coordination_assignment_valid(plan, entry):
			if not entry.failed:
				_record_coordination_failure(entry, plan)
				entry.failed = true
				_coordination_due[plan.team_id] = elapsed
			return
		all_accepted = all_accepted and entry.accepted
		all_complete = all_complete and entry.complete
		if entry.role != &"front_support":
			mover_count += 1
			movers_complete = movers_complete and entry.complete
		if plan.required_participants.has(entry.actor_id):
			var context = _context(entry.actor_id)
			var ready: bool = entry.accepted and entry.get("ready_for_phase", false) and entry.get("report_phase_id", -1) == plan.phase_id and elapsed - float(entry.last_report_at) <= COORDINATION_REPORT_SECONDS and context.actor.global_position.distance_to(entry.get("staging_position", Vector3.INF)) <= 0.35
			if entry.role == &"front_support": ready = ready and _coordination_actual(context, plan.target_id).fire_ready
			required_ready = required_ready and ready
			if not ready: unready.append(entry)
	# Front fire supports the actual maneuver; it need not invent a separate
	# completion movement or wait until the whole lease expires after arrival.
	if all_complete or (plan.tactic == &"flank" and mover_count > 0 and movers_complete):
		_drop_coordination_plan(plan.team_id, &"complete")
		return
	if plan.phase == &"assigning" and all_accepted:
		plan.phase = &"staging"
		plan.phase_id += 1
		var longest := 0.0
		for entry: Dictionary in plan.assignments:
			for offer: Dictionary in entry.raw_offers: longest = maxf(longest, float(offer.path_summary.staging_seconds))
		plan.stage_until = minf(plan.expires_at, elapsed + longest + COORDINATION_WAIT_SECONDS)
		# Non-synchronized support/search tasks start after acceptance; inspect
		# and flank wait on real same-phase entry facts, never preview ready.
		if plan.required_participants.is_empty(): required_ready = true
		else: required_ready = false
	if plan.phase == &"staging" and required_ready:
		plan.phase = &"executing"
		plan.phase_id += 1
		plan.release_at = elapsed
		for entry: Dictionary in plan.assignments:
			entry.support_prepare_until = minf(entry.expires_at, elapsed + COORDINATION_WAIT_SECONDS)
		plan.stage_until = plan.expires_at
		revision += 1
	elif plan.phase != &"executing" and elapsed >= plan.stage_until:
		for entry: Dictionary in unready: _record_coordination_failure(entry, plan)
		_drop_coordination_plan(plan.team_id, &"stage_timeout")

func _advance_coordination() -> void:
	if _coordination_sources.is_empty() and _coordination_plans.is_empty(): return
	for key in _coordination_checked.keys():
		if _coordination_checked[key].valid_until <= elapsed: _coordination_checked.erase(key)
	for index in range(_coordination_failures.size() - 1, -1, -1):
		if _coordination_failures[index].valid_until <= elapsed: _coordination_failures.remove_at(index)
	var active: Dictionary = {}
	for team: Dictionary in _teams.values(): active[team.team_id] = true
	for team_id in _coordination_plans.keys():
		if not active.has(team_id): _drop_coordination_plan(team_id, &"team_changed")
		else: _advance_coordination_phase(_coordination_plans[team_id])
	for key in _coordination_sources.keys():
		if not active.has(_coordination_sources[key].team_id) or _active_coordination_source(key).is_empty():
			_coordination_sources.erase(key)
			_coordination_source_pool.erase(key)
	for registry: Dictionary in [_coordination_environments, _coordination_due, _coordination_counters]:
		for team_id in registry.keys():
			if not active.has(team_id): registry.erase(team_id)
	for key in _coordination_receipts.keys():
		if not _members.has(int(key[0])): _coordination_receipts.erase(key)
	for team_id: int in active:
		if elapsed < float(_coordination_due.get(team_id, 0.0)): continue
		_coordination_due[team_id] = elapsed + COORDINATION_PERIOD
		var ids := _coordination_team_members(team_id)
		if ids.size() < 2 or ids.size() > 32:
			_drop_coordination_plan(team_id, &"unsupported_team_size")
			continue
		var source := _coordination_find_source(team_id, ids)
		if source.is_empty(): continue
		if team_level(_context(ids[0]), 2) != 2:
			_drop_coordination_plan(team_id, &"team_level")
			continue
		var snapshot_value := _coordination_snapshot(team_id, source, ids)
		var proposal: Dictionary = _team_planner.propose(snapshot_value)
		_coordination_counters[team_id] = proposal.get("counters", {}).duplicate(true)
		_install_coordination_proposal(team_id, source, proposal)
