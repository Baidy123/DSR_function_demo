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
var _flank_rounds: Dictionary = {}
var _inspection_reports: Dictionary = {}
const FLANK_SIDE_MARGIN := 0.5
const FLANK_DESTINATION_SPACING := 1.2
# A completed 140-degree flank still fits inside a rotated half-plane. This
# default geometry guard prevents a new round from sending the front after it.
const FLANK_SEPARATION_COSINE := -0.5 # cos(120 degrees), horizontal directions.
const FLANK_GEOMETRY_MEMBER_STEP := 0.5
const FLANK_GEOMETRY_TARGET_STEP := 0.25

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

func reset() -> void:
	generation += 1
	elapsed = 0.0
	_reports.clear()
	_claims.clear()
	_checked.clear()
	_flank_rounds.clear()
	_inspection_reports.clear()
	for member in _members.values():
		member.status = {}
		member.activity = {}
	revision += 1

func register(context) -> bool:
	var id: int = context.actor.get_instance_id()
	var domain: String = _domain(context.actor)
	var changed: bool = _members.has(id) and _members[id].domain != domain
	if changed: unregister(id)
	if not _members.has(id):
		_members[id] = {"context": weakref(context), "domain": domain, "faction": context.actor.faction_id, "group": context.actor.communication_group, "status": {}, "activity": {}}
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

## Ending an action is not ending the body's reload or leaving the team.
## Dependent allies keep their finite leases while the same real need exists.
func clear_execution(id: int) -> void:
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

func _key(domain: String, target: int) -> String:
	return "%s:%s:%s" % [generation, domain, target]

func set_relation(first: StringName, second: StringName, relation: StringName) -> void:
	_relations[[first, second]] = relation
	_relations[[second, first]] = relation
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
		return
	_serial += 1
	_reports[key] = {"target_id": target, "observer_id": observer, "faction": context.actor.faction_id, "group": context.actor.communication_group,
		"position": context.last_seen_position, "observer_position": context.actor.global_position, "aim_position": context.last_seen_aim_position, "direction": context.last_seen_direction, "velocity": context.observed_velocity,
		"captured_at": elapsed, "valid_until": elapsed + maxf(0.1, context.setting(&"cooperation", &"intel_seconds", 5.0)),
		"id": _serial, "generation": generation, "source": &"shared_visual", "shared": true,
		"reloading": reloading, "reload_until": elapsed + context.observed_reload_remaining}
	revision += 1

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
