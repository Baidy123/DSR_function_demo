extends RefCounted

## Pure, bounded proposals. The board owns authorization, IDs, clocks, deadlines,
## reservations and execution truth; this helper never calls an actor or a world.
const ROLES := [&"inspect_left", &"inspect_right", &"front_support", &"flank", &"search_sector", &"independent_position"]
const MAX_MEMBERS := 32
const MAX_INPUT_OFFERS := 32
const MAX_OFFERS := 6
const MAX_ALTERNATIVES := 3
const MAX_ROLE_MEMBERS := 6
const MAX_PAIR_TRIALS := 36
const MAX_CONFLICT_CHECKS := 2048
const MAX_VALUE_ITEMS := 24000

func propose(snapshot: Dictionary, limits: Dictionary = {}) -> Dictionary:
	var work := {"snapshot": snapshot, "members": {}, "bundles": [], "occupancy": [],
		"failures": [], "requests": [], "pair_limit": _limit(limits, "max_pair_trials", MAX_PAIR_TRIALS),
		"conflict_limit": _limit(limits, "max_conflict_checks", MAX_CONFLICT_CHECKS),
		"alternatives": maxi(1, _limit(limits, "max_alternatives", MAX_ALTERNATIVES)),
		"offers_limit": maxi(1, _limit(limits, "max_offers_per_member", MAX_OFFERS)),
		"role_members": maxi(1, _limit(limits, "max_role_members", MAX_ROLE_MEMBERS)),
		"counters": {"pair_trials": 0, "conflict_checks": 0, "offers_seen": 0,
			"offers_accepted": 0, "offers_rejected": 0, "conflict_limit_reached": false}}
	var budget := [MAX_VALUE_ITEMS]
	if not _values_only(snapshot, budget, 0) or not _values_only(limits, budget, 0) or not _header_valid(snapshot):
		return _result(work, &"none", &"invalid_snapshot")
	if not _collect_members(work): return _result(work, &"none", &"invalid_members")
	if not _collect_occupancy(work): return _result(work, &"none", &"invalid_occupancy")
	if not _collect_requests(work): return _result(work, &"none", &"invalid_requests")
	var current: Dictionary = snapshot.get("current_plan", {})
	if not current.is_empty():
		if not _current_header_valid(current, snapshot): return _result(work, &"none", &"invalid_current_plan")
		if current.get("tactic") == &"support" and _active_request(work, current.get("request_id")).is_empty(): return _result(work, &"none", &"support_request_ended")
		var continuity := _current_assignments(work, current)
		if continuity.assignments.is_empty(): return _result(work, &"none", &"invalid_assignments")
		if not continuity.assignments.is_empty():
			if continuity.invalid.is_empty():
				if current.get("execution_valid", true) == false: return _result(work, &"none", &"plan_execution_invalid", current.get("tactic", &""))
				# A missing offer or a cheaper unrelated option is not execution failure.
				return _with_basic(work, _result(work, &"keep", &"execution_valid", current.get("tactic", &"")), continuity.assignments)
			var repair := _repair(work, current, continuity)
			return _with_basic(work, repair, continuity.protected + repair.assignments)
	var selected := _new_plan(work)
	return _with_basic(work, selected, selected.assignments)

func _limit(limits: Dictionary, key: String, ceiling: int) -> int:
	var value: Variant = limits.get(key, ceiling)
	return clampi(value, 0, ceiling) if typeof(value) == TYPE_INT else ceiling

func _values_only(value: Variant, remaining: Array, depth: int) -> bool:
	remaining[0] -= 1
	if remaining[0] < 0 or depth > 12: return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_STRING, TYPE_STRING_NAME: return true
		TYPE_FLOAT: return is_finite(value)
		TYPE_VECTOR2, TYPE_VECTOR3: return value.is_finite()
		TYPE_VECTOR2I, TYPE_VECTOR3I: return true
		TYPE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			for child in value:
				if not _values_only(child, remaining, depth + 1): return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not _values_only(key, remaining, depth + 1) or not _values_only(value[key], remaining, depth + 1): return false
			return true
	return false

func _text(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not String(value).is_empty()

func _number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT

func _nonnegative_integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and value >= 0

func _header_valid(snapshot: Dictionary) -> bool:
	for key in [&"generation", &"team_id", &"target_id", &"evidence_id", &"environment_revision", &"navigation_revision", &"relation_revision"]:
		if not _nonnegative_integer(snapshot.get(key)): return false
	return (_number(snapshot.get("now")) and snapshot.now >= 0.0 and snapshot.team_id > 0
		and _text(snapshot.get("domain")) and snapshot.get("members") is Array
		and snapshot.members.size() <= MAX_MEMBERS
		and snapshot.get("occupancy", []) is Array and snapshot.get("occupancy", []).size() <= 128
		and snapshot.get("requests", []) is Array and snapshot.get("requests", []).size() <= 32
		and snapshot.get("failures", []) is Array and snapshot.get("failures", []).size() <= 128
		and snapshot.get("flank_owner_ids", []) is Array and snapshot.get("flank_owner_ids", []).size() <= MAX_MEMBERS
		and snapshot.get("current_plan", {}) is Dictionary)

func _fresh(value: Dictionary, now: float) -> bool:
	return (_number(value.get("captured_at")) and _number(value.get("valid_until"))
		and value.captured_at <= now and value.captured_at >= 0.0 and value.valid_until > now
		and value.valid_until >= value.captured_at)

func _collect_members(work: Dictionary) -> bool:
	for actor_id in work.snapshot.get("flank_owner_ids", []):
		if not _nonnegative_integer(actor_id) or actor_id == 0: return false
	var ordered: Array = work.snapshot.members.duplicate()
	for member in ordered:
		if not member is Dictionary or not _nonnegative_integer(member.get("actor_id")) or member.actor_id == 0: return false
		if not _nonnegative_integer(member.get("member_generation")) or not _nonnegative_integer(member.get("config_revision")): return false
		if member.has("navigation_revision") and not _nonnegative_integer(member.navigation_revision): return false
		if not member.get("position") is Vector3 or not member.get("advanced_enabled") is bool: return false
		if not member.get("eligible_roles", []) is Array or not member.get("offers", []) is Array: return false
		if member.get("offers", []).size() > MAX_INPUT_OFFERS: return false
		for role in member.get("eligible_roles", []):
			if not _text(role) or not ROLES.has(StringName(role)): return false
	ordered.sort_custom(func(a, b): return a.actor_id < b.actor_id)
	for member in ordered:
		if work.members.has(member.actor_id): return false
		work.members[member.actor_id] = member
	for failure in work.snapshot.get("failures", []):
		if failure is Dictionary and _nonnegative_integer(failure.get("actor_id", 0)) and _number(failure.get("valid_until")) and failure.valid_until > work.snapshot.now:
			work.failures.append(failure)
	for member in ordered:
		var by_role := {}
		var keys := {}
		for offer in member.get("offers", []):
			if offer is Dictionary and _text(offer.get("offer_key")):
				keys[offer.offer_key] = int(keys.get(offer.offer_key, 0)) + 1
		for offer in member.get("offers", []):
			work.counters.offers_seen += 1
			if not offer is Dictionary or not _offer_valid(work, member, offer) or keys.get(offer.get("offer_key"), 0) != 1:
				work.counters.offers_rejected += 1
				continue
			var role := StringName(offer.role)
			if not by_role.has(role): by_role[role] = []
			by_role[role].append(offer)
		for role in by_role: by_role[role].sort_custom(_offer_less)
		# One turn per role before a second alternative: six basic offers cannot
		# crowd out the member's other end or front/flank offer.
		var selected: Array = []
		var offset := 0
		while selected.size() < work.offers_limit:
			var changed := false
			for role in ROLES:
				if by_role.has(role) and offset < by_role[role].size() and selected.size() < work.offers_limit:
					selected.append(by_role[role][offset])
					changed = true
			if not changed: break
			offset += 1
		work.counters.offers_accepted += selected.size()
		var groups := {}
		for offer in selected:
			var key := [offer.owner_action, offer.role, offer.position_set_key, offer.get("request_id", 0)]
			if not groups.has(key):
				groups[key] = {"actor_id": member.actor_id, "owner_action": offer.owner_action,
					"role": StringName(offer.role), "position_set_key": offer.position_set_key, "offers": [], "cost": offer.cost}
			if groups[key].offers.size() < work.alternatives: groups[key].offers.append(offer)
		for group in groups.values(): work.bundles.append(group)
	work.bundles.sort_custom(_bundle_less)
	return true

func _offer_valid(work: Dictionary, member: Dictionary, offer: Dictionary) -> bool:
	var snapshot: Dictionary = work.snapshot
	for key in [&"offer_key", &"owner_action", &"position_set_key"]:
		if not _text(offer.get(key)): return false
	if not _text(offer.get("role")) or not ROLES.has(StringName(offer.role)) or not offer.get("position") is Vector3: return false
	if not _summary_valid(offer.get("path_summary", {})) or not _number(offer.get("cost")): return false
	if not offer.get("movement_possible") is bool or not offer.get("fire_ready") is bool: return false
	if offer.has("request_id") and not (_text(offer.request_id) or (_nonnegative_integer(offer.request_id) and offer.request_id > 0)): return false
	for key in [&"travel_seconds", &"unavailable_seconds", &"exposed_seconds", &"information_loss", &"measured_support_seconds"]:
		if not _number(offer.get(key)) or offer[key] < 0.0: return false
	for key in [&"target_id", &"evidence_id", &"environment_revision", &"relation_revision"]:
		if offer.get(key) != snapshot[key]:
			# A basic position carries no enemy information and may be targetless.
			if not (offer.get("scope") == &"basic" and key in [&"target_id", &"evidence_id"] and offer.get(key) == 0): return false
	if offer.get("actor_id") != member.actor_id or offer.get("member_generation") != member.member_generation or offer.get("config_revision") != member.config_revision: return false
	if offer.get("navigation_revision") != member.get("navigation_revision", snapshot.navigation_revision): return false
	if not _fresh(offer, snapshot.now): return false
	var role := StringName(offer.role)
	if role == &"independent_position":
		if offer.get("scope") != &"basic": return false
	else:
		if offer.get("scope") != &"tactical" or not member.advanced_enabled or not member.get("eligible_roles", []).has(role): return false
		if snapshot.target_id == 0 and snapshot.evidence_id == 0: return false
		if role in [&"inspect_left", &"inspect_right", &"flank", &"search_sector"] and not offer.movement_possible: return false
	if role == &"search_sector":
		var summary: Dictionary = offer.path_summary
		if not _text(summary.get("grid_key")) or not _nonnegative_integer(summary.get("search_round_id")) or summary.search_round_id == 0: return false
		if not summary.get("sample_ids") is Array or summary.sample_ids.is_empty() or summary.sample_ids.size() > 64: return false
	if role in [&"inspect_left", &"inspect_right", &"flank"] and not _text(offer.path_summary.get("tactical_key")): return false
	for failure in work.failures:
		if int(failure.get("actor_id", 0)) not in [0, member.actor_id]: continue
		if failure.get("offer_key") == offer.offer_key or failure.get("position_set_key") == offer.position_set_key: return false
	return true

func _summary_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in [&"blocked_position_sets", &"sample_ids"]:
		if not value.get(key, []) is Array or value.get(key, []).size() > 64: return false
		for item in value.get(key, []):
			if not _text(item) and not _nonnegative_integer(item): return false
	if value.has("body_radius") and (not _number(value.body_radius) or value.body_radius < 0.0): return false
	if value.has("side") and (typeof(value.side) != TYPE_INT or value.side not in [-1, 0, 1]): return false
	for key in [&"holds_front", &"exclusive_corridor"]:
		if value.has(key) and not value[key] is bool: return false
	return true

func _offer_less(a: Dictionary, b: Dictionary) -> bool:
	return a.cost < b.cost if a.cost != b.cost else String(a.offer_key) < String(b.offer_key)

func _bundle_less(a: Dictionary, b: Dictionary) -> bool:
	if a.cost != b.cost: return a.cost < b.cost
	if a.actor_id != b.actor_id: return a.actor_id < b.actor_id
	if a.role != b.role: return String(a.role) < String(b.role)
	if a.owner_action != b.owner_action: return String(a.owner_action) < String(b.owner_action)
	return String(a.position_set_key) < String(b.position_set_key)

func _collect_occupancy(work: Dictionary) -> bool:
	var seen := {}
	for entry in work.snapshot.get("occupancy", []):
		if not entry is Dictionary or not entry.get("position") is Vector3 or not _summary_valid(entry.get("path_summary", {})): return false
		if not _nonnegative_integer(entry.get("actor_id")) or not _number(entry.get("captured_at")) or not _number(entry.get("valid_until")): return false
		if not _fresh(entry, work.snapshot.now): continue
		# Deduplicate the same reservation projection; distinct actual body and
		# destination positions remain collision constraints, never extra flank slots.
		var identity := [entry.get("reservation_id", 0), entry.actor_id, entry.position, entry.get("position_set_key", "")]
		if seen.has(identity): continue
		seen[identity] = true
		work.occupancy.append(entry)
	return true

func _collect_requests(work: Dictionary) -> bool:
	var seen := {}
	for request in work.snapshot.get("requests", []):
		if not request is Dictionary: continue
		var request_id: Variant = request.get("request_id")
		if not (_text(request_id) or (_nonnegative_integer(request_id) and request_id > 0)): continue
		if seen.has(request_id): return false
		if not work.members.has(request.get("actor_id")) or not _fresh(request, work.snapshot.now): continue
		if request.get("target_id") != work.snapshot.target_id or request.get("evidence_id") != work.snapshot.evidence_id: continue
		var kind := StringName(request.get("kind", ""))
		if kind in [&"reload", &"retreat"]:
			if request.get("actual", false) != true: continue
		elif kind == &"advance":
			if request.get("accepted", false) != true: continue
		else: continue
		seen[request.request_id] = true
		work.requests.append(request)
	work.requests.sort_custom(func(a, b): return str(a.request_id) < str(b.request_id))
	return true

func _pool(work: Dictionary, role: StringName) -> Array:
	var result: Array = []
	var owners: Array = []
	var by_actor := {}
	# Best bundle per member first; duplicate alternatives never consume another
	# member's role slot. The board can rotate its bounded member snapshot later.
	for bundle in work.bundles:
		if bundle.role != role: continue
		if not by_actor.has(bundle.actor_id):
			if owners.size() >= work.role_members: continue
			owners.append(bundle.actor_id)
			by_actor[bundle.actor_id] = []
		by_actor[bundle.actor_id].append(bundle)
	for offset in MAX_OFFERS:
		for actor_id in owners:
			if offset < by_actor[actor_id].size(): result.append(by_actor[actor_id][offset])
	return result

func _trial(work: Dictionary) -> bool:
	if work.counters.pair_trials >= work.pair_limit: return false
	work.counters.pair_trials += 1
	return true

func _conflict(work: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	if work.counters.conflict_checks >= work.conflict_limit:
		work.counters.conflict_limit_reached = true
		return true
	work.counters.conflict_checks += 1
	if a.get("position_set_key", "") == b.get("position_set_key", "") and _text(a.get("position_set_key")): return true
	var left: Dictionary = a.get("path_summary", {})
	var right: Dictionary = b.get("path_summary", {})
	var clearance: float = maxf(0.0, float(left.get("body_radius", 0.35))) + maxf(0.0, float(right.get("body_radius", 0.35))) + 0.1
	if a.position.distance_squared_to(b.position) < clearance * clearance: return true
	var corridor: Variant = left.get("corridor_key", "")
	if _text(corridor) and corridor == right.get("corridor_key") and (left.get("exclusive_corridor", false) or right.get("exclusive_corridor", false)): return true
	if left.get("blocked_position_sets", []).has(b.get("position_set_key")) or right.get("blocked_position_sets", []).has(a.get("position_set_key")): return true
	if a.get("role") == &"search_sector" and b.get("role") == &"search_sector":
		if left.get("grid_key") != right.get("grid_key") or left.get("search_round_id") != right.get("search_round_id"): return true
		for sample in left.get("sample_ids", []):
			if right.get("sample_ids", []).has(sample): return true
	return false

func _compatible(work: Dictionary, a: Dictionary, b: Dictionary) -> bool:
	if a.actor_id == b.actor_id: return false
	for first in a.offers:
		for second in b.offers:
			if _conflict(work, first, second): return false
	return true

func _free(work: Dictionary, bundle: Dictionary, released: Array = []) -> bool:
	for offer in bundle.offers:
		for occupied in work.occupancy:
			if occupied.actor_id == bundle.actor_id: continue
			if occupied.get("kind") != &"body" and released.has(occupied.actor_id): continue
			if _conflict(work, offer, occupied): return false
	return true

func _flank_allowed(work: Dictionary, bundles: Array) -> bool:
	var available := 0
	var owners := {}
	for member in work.members.values():
		if member.advanced_enabled and (member.get("eligible_roles", []).has(&"flank") or member.get("eligible_roles", []).has(&"front_support")): available += 1
		if member.get("on_far_side", false): owners[member.actor_id] = true
	for actor_id in work.snapshot.get("flank_owner_ids", []): owners[actor_id] = true
	for bundle in bundles:
		if bundle.role == &"flank": owners[bundle.actor_id] = true
	return owners.size() <= floori(float(available) / 2.0)

func _front_holds(work: Dictionary, bundle: Dictionary) -> bool:
	var actual: Variant = work.members[bundle.actor_id].get("actual_support", {})
	if not actual is Dictionary or not _fresh(actual, work.snapshot.now): return false
	if actual.get("fire_ready", false) != true or not _number(actual.get("measured_support_seconds")) or actual.measured_support_seconds <= 0.0: return false
	for offer in bundle.offers:
		if not offer.get("fire_ready", false) or float(offer.get("measured_support_seconds", 0.0)) <= 0.0 or not offer.path_summary.get("holds_front", false): return false
	return true

func _opposite(front: Dictionary, flank: Dictionary) -> bool:
	for a in front.offers:
		for b in flank.offers:
			if int(a.path_summary.get("side", 0)) * int(b.path_summary.get("side", 0)) != -1: return false
	return true

func _same_tactical_key(a: Dictionary, b: Dictionary) -> bool:
	for first in a.offers:
		for second in b.offers:
			var key: Variant = first.get("path_summary", {}).get("tactical_key")
			if not _text(key) or key != second.get("path_summary", {}).get("tactical_key"): return false
	return true

func _queue(tactic: StringName, left: Array, right: Array) -> Dictionary:
	return {"tactic": tactic, "left": left, "right": right, "diagonal": 0, "offset": 0}

func _next_pair(queue: Dictionary) -> Array:
	while queue.diagonal < queue.left.size() + queue.right.size() - 1:
		var first: int = queue.offset
		var second: int = queue.diagonal - first
		queue.offset += 1
		if queue.offset > queue.diagonal:
			queue.diagonal += 1
			queue.offset = 0
		if first < queue.left.size() and second < queue.right.size(): return [queue.left[first], queue.right[second]]
	return []

func _new_plan(work: Dictionary) -> Dictionary:
	if work.members.size() < 2: return _result(work, &"none", &"solo")
	var advanced := 0
	for member in work.members.values():
		if member.advanced_enabled and not member.get("eligible_roles", []).is_empty(): advanced += 1
	var front := _pool(work, &"front_support")
	var search := _pool(work, &"search_sector")
	var queues: Array = []
	if advanced >= 2:
		queues.append(_queue(&"inspect", _pool(work, &"inspect_left"), _pool(work, &"inspect_right")))
		queues.append(_queue(&"flank", front, _pool(work, &"flank")))
		queues.append(_queue(&"search", search, search))
	queues.append(_queue(&"support", front, work.requests.slice(0, MAX_ROLE_MEMBERS)))
	queues = queues.filter(func(entry): return not entry.left.is_empty() and not entry.right.is_empty())
	var best := {}
	# Reserve a small part of the SAME 36 trials for extra non-conflicting members.
	var core_limit: int = mini(work.pair_limit, maxi(1, floori(float(work.pair_limit) * 0.75)))
	var cursor := 0
	while not queues.is_empty() and work.counters.pair_trials < core_limit:
		cursor %= queues.size()
		var queue: Dictionary = queues[cursor]
		var pair := _next_pair(queue)
		if pair.is_empty():
			queues.remove_at(cursor)
			continue
		cursor += 1
		if not _trial(work): break
		var proposed := _pair_plan(work, queue.tactic, pair)
		if proposed.is_empty(): continue
		if best.is_empty() or proposed.cost < best.cost or (proposed.cost == best.cost and proposed.key < best.key): best = proposed
	if best.is_empty() and advanced >= 2:
		# A single legal entrance is a finite one-person sector, never a fake pair.
		for bundle in search:
			if not _trial(work): break
			if _free(work, bundle):
				best = {"tactic": &"search", "bundles": [bundle], "cost": bundle.cost, "key": "single_search", "beneficiary_id": 0}
				break
	if best.is_empty(): return _result(work, &"none", &"no_complete_combination")
	if best.tactic in [&"flank", &"search"]:
		var more := _pool(work, &"flank" if best.tactic == &"flank" else &"search_sector")
		for bundle in more:
			if best.bundles.any(func(other): return other.actor_id == bundle.actor_id): continue
			if not _trial(work): break
			if not _free(work, bundle): continue
			if best.tactic == &"flank" and (not _flank_allowed(work, best.bundles + [bundle]) or not _opposite(best.bundles[0], bundle) or not _same_tactical_key(best.bundles[0], bundle)): continue
			if best.bundles.any(func(other): return not _compatible(work, bundle, other)): continue
			best.bundles.append(bundle)
	var assignments: Array = []
	var actors: Array = best.bundles.map(func(bundle): return bundle.actor_id)
	for bundle in best.bundles:
		var partners: Array = actors.filter(func(actor_id): return actor_id != bundle.actor_id)
		assignments.append(_assignment(bundle, partners, best.get("beneficiary_id", 0)))
	var result := _result(work, &"replace", &"complementary_offers", best.tactic)
	result.assignments = assignments
	result.changed_actor_ids = actors
	result.required_participants = actors if best.tactic in [&"inspect", &"flank"] else []
	if best.has("request_id"): result.request_id = best.request_id
	return result

func _pair_plan(work: Dictionary, tactic: StringName, pair: Array) -> Dictionary:
	var a: Dictionary = pair[0]
	var b: Dictionary = pair[1]
	if not _free(work, a): return {}
	if tactic == &"support":
		if a.actor_id == b.actor_id or not _front_holds(work, a): return {}
		for offer in a.offers:
			if offer.has("request_id") and offer.request_id != b.request_id: return {}
		return {"tactic": tactic, "bundles": [a], "cost": a.cost,
			"key": String(tactic) + ":" + str(a.actor_id) + ":" + str(b.request_id),
			"beneficiary_id": b.actor_id, "request_id": b.request_id}
	if not _free(work, b) or not _compatible(work, a, b): return {}
	if tactic in [&"inspect", &"flank"] and not _same_tactical_key(a, b): return {}
	if tactic == &"flank" and (not _front_holds(work, a) or not _opposite(a, b) or not _flank_allowed(work, [a, b])): return {}
	return {"tactic": tactic, "bundles": [a, b], "cost": a.cost + b.cost,
		"key": String(tactic) + ":" + str(a.actor_id) + ":" + str(b.actor_id), "beneficiary_id": 0}

func _assignment(bundle: Dictionary, partners: Array, beneficiary_id: int = 0) -> Dictionary:
	return {"actor_id": bundle.actor_id, "owner_action": bundle.owner_action, "role": bundle.role,
		"allowed_offer_keys": bundle.offers.map(func(offer): return offer.offer_key),
		"reserved_position_sets": [bundle.position_set_key], "partner_ids": partners.duplicate(),
		"beneficiary_id": beneficiary_id, "reserved_offers": bundle.offers.map(_reserved_offer)}

func _reserved_offer(offer: Dictionary) -> Dictionary:
	return {"offer_key": offer.offer_key, "position_set_key": offer.position_set_key,
		"position": offer.position, "role": offer.role, "path_summary": offer.path_summary.duplicate(true),
		"fire_ready": offer.get("fire_ready", false), "measured_support_seconds": offer.get("measured_support_seconds", 0.0)}

func _current_header_valid(plan: Dictionary, snapshot: Dictionary) -> bool:
	for key in [&"generation", &"team_id", &"domain", &"target_id", &"evidence_id"]:
		if plan.get(key) != snapshot[key]: return false
	return (_number(plan.get("expires_at")) and plan.expires_at > snapshot.now
		and _text(plan.get("tactic")) and plan.tactic in [&"inspect", &"flank", &"support", &"search"]
		and plan.get("execution_valid") is bool and plan.get("segment_boundary") is bool
		and plan.get("required_participants") is Array
		and plan.get("assignments") is Array and plan.assignments.size() <= MAX_MEMBERS)

func _current_assignments(work: Dictionary, plan: Dictionary) -> Dictionary:
	var result := {"assignments": [], "protected": [], "invalid": []}
	var owners := {}
	for assignment in plan.assignments:
		if not assignment is Dictionary or not _nonnegative_integer(assignment.get("actor_id")) or assignment.actor_id == 0 or owners.has(assignment.actor_id): return {"assignments": [], "protected": [], "invalid": []}
		if not _text(assignment.get("role")) or not _text(assignment.get("owner_action")): return {"assignments": [], "protected": [], "invalid": []}
		if not ROLES.has(StringName(assignment.role)) or assignment.role == &"independent_position": return {"assignments": [], "protected": [], "invalid": []}
		if not assignment.get("reserved_position_sets", []) is Array or not assignment.get("partner_ids", []) is Array: return {"assignments": [], "protected": [], "invalid": []}
		if not assignment.get("allowed_offer_keys") is Array or not assignment.get("reserved_offers") is Array or _protected_bundle(assignment).is_empty(): return {"assignments": [], "protected": [], "invalid": []}
		if assignment.allowed_offer_keys.size() > MAX_ALTERNATIVES or assignment.reserved_position_sets.size() > MAX_ALTERNATIVES: return {"assignments": [], "protected": [], "invalid": []}
		if not assignment.get("execution_valid") is bool: return {"assignments": [], "protected": [], "invalid": []}
		if assignment.has("expires_at") and not _number(assignment.expires_at): return {"assignments": [], "protected": [], "invalid": []}
		owners[assignment.get("actor_id")] = true
		result.assignments.append(assignment)
		var member: Dictionary = work.members.get(assignment.get("actor_id"), {})
		var valid: bool = not member.is_empty() and member.advanced_enabled and member.get("eligible_roles", []).has(assignment.get("role"))
		valid = valid and assignment.execution_valid
		if assignment.has("expires_at"): valid = valid and assignment.expires_at > work.snapshot.now
		if assignment.has("member_generation"): valid = valid and not member.is_empty() and assignment.member_generation == member.member_generation
		if valid: result.protected.append(assignment)
		else: result.invalid.append(assignment)
	var participants := {}
	for actor_id in plan.required_participants:
		if not _nonnegative_integer(actor_id) or not owners.has(actor_id) or participants.has(actor_id): return {"assignments": [], "protected": [], "invalid": []}
		participants[actor_id] = true
	return result

func _protected_bundle(assignment: Dictionary) -> Dictionary:
	var positions: Array = []
	var keys := {}
	var sets := {}
	# This is an explicit frozen assignment contract, NOT a volatile local cache
	# or a guess that the global occupancy projection happens to be complete.
	for reserved in assignment.get("reserved_offers", []):
		if not reserved is Dictionary or not reserved.get("position") is Vector3 or not _summary_valid(reserved.get("path_summary")): return {}
		if not _text(reserved.get("offer_key")) or keys.has(reserved.offer_key) or not assignment.allowed_offer_keys.has(reserved.offer_key): return {}
		if not _text(reserved.get("position_set_key")) or not assignment.reserved_position_sets.has(reserved.position_set_key): return {}
		if not reserved.get("fire_ready") is bool or not _number(reserved.get("measured_support_seconds")): return {}
		keys[reserved.offer_key] = true
		sets[reserved.position_set_key] = true
		var copy: Dictionary = reserved.duplicate(true)
		copy.role = assignment.role
		positions.append(copy)
	if keys.size() != assignment.allowed_offer_keys.size() or sets.size() != assignment.reserved_position_sets.size(): return {}
	return {"actor_id": assignment.actor_id, "role": assignment.role, "offers": positions, "locked": true} if not positions.is_empty() else {}

func _active_request(work: Dictionary, request_id: Variant) -> Dictionary:
	for request in work.requests:
		if request.request_id == request_id: return request
	return {}

func _repair(work: Dictionary, current: Dictionary, continuity: Dictionary) -> Dictionary:
	var patch: Array = []
	var chosen: Array = []
	var changed: Array = []
	var reserved: Array = continuity.protected.map(func(assignment): return assignment.actor_id)
	var released: Array = continuity.invalid.map(func(assignment): return assignment.get("actor_id", 0))
	var request := _active_request(work, current.get("request_id")) if current.get("tactic") == &"support" else {}
	if current.get("tactic") == &"support" and request.is_empty(): return _result(work, &"none", &"support_request_ended", &"support")
	for assignment in continuity.protected:
		var locked := _protected_bundle(assignment)
		if locked.is_empty(): return _result(work, &"none", &"repair_snapshot_incomplete", current.get("tactic", &""))
		if current.tactic == &"flank" and locked.role == &"front_support" and not _front_holds(work, locked): return _result(work, &"none", &"front_support_unavailable", &"flank")
		chosen.append(locked)
	for old in continuity.invalid:
		var pool := _pool(work, StringName(old.get("role", "")))
		pool.sort_custom(func(a, b):
			if (a.actor_id == old.actor_id) != (b.actor_id == old.actor_id): return a.actor_id == old.actor_id
			return _bundle_less(a, b))
		var replacement := {}
		for bundle in pool:
			if reserved.has(bundle.actor_id): continue
			if not _trial(work): break
			if not _free(work, bundle, released) or chosen.any(func(other): return not _compatible(work, bundle, other)): continue
			if current.get("tactic") in [&"inspect", &"flank"] and chosen.any(func(other): return not _same_tactical_key(bundle, other)): continue
			if bundle.role == &"front_support" and not _front_holds(work, bundle): continue
			if current.get("tactic") == &"support":
				if int(old.get("beneficiary_id", 0)) != request.actor_id or _pair_plan(work, &"support", [bundle, request]).is_empty(): continue
			if current.get("tactic") == &"flank":
				var bad_side := false
				for other in chosen:
					if bundle.role == &"front_support" and other.role == &"flank" and not _opposite(bundle, other): bad_side = true
					if bundle.role == &"flank" and other.role == &"front_support" and not _opposite(other, bundle): bad_side = true
				if bad_side: continue
			if bundle.role == &"flank":
				var flank_roles: Array = continuity.protected + chosen + [bundle]
				if not _flank_allowed(work, flank_roles): continue
			replacement = bundle
			break
		if replacement.is_empty(): return _result(work, &"none", &"repair_unavailable", current.get("tactic", &""))
		chosen.append(replacement)
		reserved.append(replacement.actor_id)
		for actor_id in [old.actor_id, replacement.actor_id]:
			if not changed.has(actor_id): changed.append(actor_id)
		var assignment := _assignment(replacement, old.get("partner_ids", []), int(old.get("beneficiary_id", 0)))
		assignment.previous_actor_id = old.actor_id
		patch.append(assignment)
	var result := _result(work, &"repair", &"replace_failed_slots", current.get("tactic", &""))
	result.assignments = patch
	result.changed_actor_ids = changed
	result.required_participants = current.get("required_participants", []).duplicate()
	if current.get("tactic") == &"support": result.request_id = request.request_id
	for assignment in patch:
		var old_index: int = result.required_participants.find(assignment.previous_actor_id)
		if old_index >= 0: result.required_participants[old_index] = assignment.actor_id
		if current.get("tactic") in [&"inspect", &"flank"]:
			assignment.partner_ids = reserved.filter(func(actor_id): return actor_id != assignment.actor_id)
	return result

func _with_basic(work: Dictionary, result: Dictionary, assignments: Array) -> Dictionary:
	var taken: Array = assignments.map(func(assignment): return assignment.get("actor_id", 0))
	var selected: Array = []
	for assignment in assignments:
		var reserved := _protected_bundle(assignment)
		if reserved.is_empty():
			result.counters = work.counters.duplicate(true)
			return result
		selected.append_array(reserved.offers)
	for member in work.members.values():
		if taken.has(member.actor_id): continue
		var offers: Array = []
		for bundle in work.bundles:
			if bundle.actor_id == member.actor_id and bundle.role == &"independent_position": offers.append_array(bundle.offers)
		offers.sort_custom(_offer_less)
		var permitted: Array = []
		for offer in offers:
			var bundle := {"actor_id": member.actor_id, "offers": [offer]}
			if not _free(work, bundle): continue
			if selected.any(func(other): return _conflict(work, offer, other)): continue
			permitted.append(offer)
			if permitted.size() >= work.alternatives: break
		if not permitted.is_empty():
			selected.append_array(permitted)
			result.basic_choices.append({"actor_id": member.actor_id,
				"allowed_offer_keys": permitted.map(func(offer): return offer.offer_key)})
	# No tactical assignment or executable reservation is manufactured for basic choices.
	result.counters = work.counters.duplicate(true)
	return result

func _result(work: Dictionary, operation: StringName, reason: StringName, tactic: StringName = &"") -> Dictionary:
	return {"operation": operation, "reason": reason, "tactic": tactic, "assignments": [],
		"changed_actor_ids": [], "required_participants": [], "basic_choices": [],
		"counters": work.counters.duplicate(true)}
