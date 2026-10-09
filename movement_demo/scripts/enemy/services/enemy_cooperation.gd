extends RefCounted

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

func reset() -> void:
	generation += 1
	elapsed = 0.0
	_reports.clear()
	_claims.clear()
	_checked.clear()
	for member in _members.values(): member.status = {}
	revision += 1

func register(context) -> bool:
	var id: int = context.actor.get_instance_id()
	var domain: String = _domain(context.actor)
	var changed: bool = _members.has(id) and _members[id].domain != domain
	if changed: unregister(id)
	if not _members.has(id):
		_members[id] = {"context": weakref(context), "domain": domain, "faction": context.actor.faction_id, "group": context.actor.communication_group, "status": {}}
		revision += 1
	return changed

func unregister(id: int) -> void:
	release_member(id)
	_members.erase(id)
	revision += 1

func release_member(id: int) -> void:
	for token in _claims.keys():
		if _claims[token].owner_id == id or _claims[token].get("beneficiary_id", 0) == id: _claims.erase(token)
	if _members.has(id): _members[id].status = {}
	revision += 1

func _context(id: int):
	return _members[id].context.get_ref() if _members.has(id) else null

func _claim_valid(entry: Dictionary) -> bool:
	var owner = _context(entry.owner_id)
	return entry.expires_at > elapsed and owner != null and is_instance_valid(owner.actor) and owner.actor.is_inside_tree() and owner.cooperation_enabled() and owner.can_use_action(entry.owner_action) and owner.cooperation_target_id() == entry.target_id

func _domain(actor) -> String:
	return JSON.stringify([String(actor.faction_id), String(actor.communication_group)])

func _key(domain: String, target: int) -> String:
	return "%s:%s:%s" % [generation, domain, target]

func set_relation(first: StringName, second: StringName, relation: StringName) -> void:
	_relations[[first, second]] = relation
	_relations[[second, first]] = relation
	_claims.clear()
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
		if context == null or not is_instance_valid(context.actor) or context.actor.is_dead or _domain(context.actor) != _members[id].domain: return false
	var first: Dictionary = _members[sender_id]
	var second: Dictionary = _members[receiver_id]
	return first.group == second.group and (first.faction == second.faction or _relations.get([first.faction, second.faction], &"") == &"allied")

func can_cooperate(first_id: int, second_id: int) -> bool:
	return can_share_intel(first_id, second_id)

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
	var key := _key(_members[observer].domain, target)
	var old: Dictionary = _reports.get(key, {})
	var reloading: bool = context.observed_reload_remaining > 0.0
	if not old.is_empty() and old.observer_id == observer and elapsed - float(old.captured_at) < 0.2 and old.position.distance_to(context.last_seen_position) < 0.1 and old.reloading == reloading:
		return
	_serial += 1
	_reports[key] = {"target_id": target, "observer_id": observer, "faction": context.actor.faction_id, "group": context.actor.communication_group,
		"position": context.last_seen_position, "aim_position": context.last_seen_aim_position, "direction": context.last_seen_direction, "velocity": context.observed_velocity,
		"captured_at": elapsed, "valid_until": elapsed + maxf(0.1, context.setting(&"cooperation", &"intel_seconds", 5.0)),
		"id": _serial, "generation": generation, "source": &"shared_visual", "shared": true,
		"reloading": reloading, "reload_until": elapsed + context.observed_reload_remaining}
	revision += 1

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
	if old.get("ready", false) != entry.get("ready", false) or old.get("reloading", false) != entry.get("reloading", false): revision += 1

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
		member.support_seconds = maxf(0.0, float(member.get("support_seconds", 0.0)) - maxf(0.0, elapsed - float(member.updated_at)))
		if member.support_seconds <= 0.0: member.ready = false
		if member.get("ready", false) and (other.actor.ammo.is_reloading or other.actor.ammo.magazine_rounds <= 0 or not other.actor.shooting_enabled or other.actor.is_vaulting() or other.actor.melee_active):
			member.ready = false
			member.support_seconds = 0.0
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
		if claim.kind == &"advance" and claim.owner_id != id:
			var request := copy.duplicate(true)
			request.request_id = claim.id
			request.beneficiary_id = claim.owner_id
			request.lane_id = &"target"
			result.requests.append(request)
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

func claim(context, task: Dictionary) -> Dictionary:
	if not context.cooperation_enabled(): return {}
	var id: int = context.actor.get_instance_id()
	if not _members.has(id): register(context)
	var target: int = task.get("target_id", context.cooperation_target_id())
	var kind: StringName = task.get("kind", &"")
	var lane: String = String(task.get("lane_id", ""))
	var point: Vector3 = task.get("position", context.actor.global_position)
	if target == 0 or kind.is_empty() or not point.is_finite(): return {}
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
	_claims[_serial] = value
	revision += 1
	return value.duplicate(true)

func update_claim(context, token: Dictionary, state: Dictionary) -> bool:
	var id: int = token.get("id", 0)
	if not _claims.has(id) or token.get("generation", -1) != generation: return false
	var entry: Dictionary = _claims[id]
	if entry.owner_id != context.actor.get_instance_id() or entry.expires_at <= elapsed or not context.cooperation_enabled() or not context.can_use_action(entry.owner_action) or entry.target_id != context.cooperation_target_id(): return false
	# Status cannot renew evidence or impersonate measured ready fire.
	for key in [&"phase", &"progress", &"position"]:
		if state.has(key): entry[key] = state[key]
	return true

func release(context, token: Dictionary) -> void:
	var id: int = token.get("id", 0)
	if _claims.has(id) and _claims[id].owner_id == context.actor.get_instance_id():
		_claims.erase(id)
		revision += 1

func search_available(context, point: Vector3, radius: float) -> bool:
	if not context.cooperation_enabled(): return true
	var id: int = context.actor.get_instance_id()
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
	# Candidate predictions cannot promise more fire than the current magazine/burst.
	if context.actor.can_use_firearms():
		var rounds: int = context.actor.ammo.magazine_rounds
		var burst_left: int = maxi(0, context.fire.burst_shot_count - context.fire.fire_burst_shots)
		var shot_window: float = mini(rounds, burst_left) * maxf(0.05, context.actor.weapon.shot_interval)
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
		var covered := 0.0
		for support in data.supports:
			if support.owner_id == id: continue
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

func support_pressure(context) -> float:
	if not context.cooperation_enabled(): return 0.0
	var data: Dictionary = context.cooperation_snapshot()
	var id: int = context.actor.get_instance_id()
	var need := 0.0
	for request in data.requests:
		if request.beneficiary_id == id: continue
		var covered := 0.0
		for support in data.supports:
			if support.owner_id != id and support.get("lane_id", &"target") == &"target": covered = maxf(covered, float(support.support_seconds))
		need = maxf(need, maxf(0.0, float(request.get("remaining", 0.0)) - covered))
	return clampf(need / maxf(0.1, context.utility_horizon_seconds), 0.0, 1.0)
