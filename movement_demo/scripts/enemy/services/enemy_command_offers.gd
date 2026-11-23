extends RefCounted

## AI-owned adapter. Actions prepare alternatives; only the squad commits them.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Scoring = preload("res://scripts/enemy/services/squad_scoring.gd")

static func dispatch(actions: Dictionary, request: Dictionary) -> void:
	var query: Dictionary = request.query
	var profile: Dictionary = query.profile
	if request.kind == &"validate":
		var offer: Dictionary = request.offer
		var action = actions.get(offer.get("action"))
		request.result = {"valid": false, "reason": &"executor_unavailable"}
		if action != null and profile.get("actions", {}).has(offer.get("action")):
			request.result = action.validate_command_offer(query, offer)
		return
	var work: Dictionary = request.cursor.duplicate(true)
	if work.is_empty():
		var ids: Array = profile.get("actions", {}).keys()
		ids.sort()
		work = {"ids": ids, "index": 0, "done": [], "cursors": {}, "offers": [], "reasons": {}}
	while work.done.size() < work.ids.size() and Time.get_ticks_usec() < request.deadline:
		var id: StringName = work.ids[work.index]
		work.index = (int(work.index) + 1) % work.ids.size()
		if work.done.has(id): continue
		if not actions.has(id):
			work.done.append(id)
			work.reasons[id] = &"executor_unavailable"
			continue
		var batch: Dictionary = actions[id].prepare_command_offers(query, work.cursors.get(id, {}), request.deadline)
		if not Contract.pure_value(batch):
			work.done.append(id)
			work.reasons[id] = &"non_value_offer"
			continue
		work.cursors[id] = batch.get("next_cursor", {})
		work.reasons[id] = batch.get("reason", &"")
		for offer: Dictionary in batch.get("offers", []):
			if offer.get("action") != id or not Contract.qualified(profile, id, offer.get("role", &"")): continue
			offer.profile_id = profile.profile_id
			offer.offer_revision = query.get("revision", [])
			offer.offer_id = [id, offer.role, offer.get("site_key", ""), offer.get("stage", &"")]
			work.offers.append(offer)
		if batch.get("done", true): work.done.append(id)
	request.result = {"done": work.done.size() == work.ids.size(), "cursor": work,
		"offers": bounded(work.offers, 8, query.get("scoring", {})), "reasons": work.reasons.duplicate(true)}

## Reserve a place for each executor before filling with spatial alternatives.
## An early executor cannot fill the pool and prevent the others being queried.
static func bounded(offers: Array, limit: int = 8, scoring: Dictionary = {}) -> Array[Dictionary]:
	var sorted := offers.duplicate()
	sorted.sort_custom(func(a, b): return Scoring.candidate_cost(a, scoring) < Scoring.candidate_cost(b, scoring))
	var result: Array[Dictionary] = []
	var seen := {}
	for offer: Dictionary in sorted:
		var key: Array = [offer.action, offer.role]
		if seen.has(key): continue
		seen[key] = true
		result.append(offer)
		if result.size() >= limit: return result
	for offer: Dictionary in sorted:
		if result.any(func(peer): return peer.position.distance_to(offer.position) < 0.1): continue
		result.append(offer)
		if result.size() >= limit: break
	return result
