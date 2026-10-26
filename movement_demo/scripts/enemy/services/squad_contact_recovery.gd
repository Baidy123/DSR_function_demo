extends RefCounted

## Coordinator-owned contact history. No clock, scene access or task authority.
## A replacement guard token is not evidence that a member made progress.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const STALL_SECONDS := 1.25
const RETRY_SECONDS := 1.5
const FAILURE_SECONDS := 4.0
var members: Dictionary = {}
var _last_repair := 0

func observe(tasks: Dictionary, bodies: Dictionary, objective: Dictionary, now: float) -> void:
	if objective.get("phase") != &"contact":
		members.clear()
		return
	for id in members.keys():
		if not bodies.has(id): members.erase(id)
	for id in tasks:
		var body: Dictionary = bodies[id]
		var task: Dictionary = tasks[id]
		var useful_fire: bool = firing(body) and task.get("role") in [&"engage", &"support", &"flank", &"guard"]
		if body.get("occupied", false) or body.get("reloading", false) or useful_fire or task.get("role") in [&"reload", &"shelter", &"cover_peek"]:
			members.erase(id)
			continue
		var record: Dictionary = members.get(id, {})
		if not record.is_empty() and (record.target_id != objective.get("target_id", 0) or Contract.horizontal(record.position, body.position) > 0.25):
			members.erase(id)
			record = {}
		if record.is_empty():
			if task.get("role") != &"guard": continue
			record = {"target_id": objective.get("target_id", 0), "position": body.position,
				"since": now, "next_at": now + STALL_SECONDS, "round": 0, "failures": [], "reason": &"finding_post"}
			members[id] = record

static func firing(body: Dictionary) -> bool:
	return body.get("firearms", false) and body.get("visible", false) and body.get("fire_lane_valid", false) and body.get("can_attack", false) and body.get("rounds", 0) > 0 and not body.get("reloading", false)

func round_for(id: int) -> int:
	return int(members.get(id, {}).get("round", 0))

## One focused pass per newly selected page. Later ordinary passes still
## enumerate healthy members' installed tactics; this is not a permanent lock.
func take_priority_pass() -> bool:
	var pending := false
	for record: Dictionary in members.values():
		pending = pending or record.get("priority", false)
		record.priority = false
	return pending

## Advance only after a complete candidate pass; partial cursors must finish.
## Returns one bounded repair request, while all other members keep working.
func finished(tasks: Dictionary, candidates: Dictionary, bodies: Dictionary, objective: Dictionary, revision: int, now: float, focused: bool = false) -> Dictionary:
	var repairs: Array[Dictionary] = []
	for id in members:
		if not candidates.has(id): continue
		var record: Dictionary = members[id]
		var task: Dictionary = tasks.get(id, {})
		if task.get("role") != &"guard" and task.get("state") != &"blocked": continue
		if now < record.next_at and (not focused or record.round == 0): continue
		if now >= record.next_at:
			record.next_at = now + RETRY_SECONDS
			record.round = int(record.round) % 6 + 1
			record.priority = true
		record.reason = &"finding_post"
		var failures: Array = []
		for offer: Dictionary in candidates.get(id, []):
			if not offer.get("role") in [&"engage", &"support", &"flank"]: continue
			var conflict := obstruction(id, offer, tasks, bodies)
			if conflict.is_empty(): continue
			var record_offer := {"offer": offer.duplicate(true), "reason": conflict.reason,
				"blockers": conflict.blockers, "at": now, "revision": revision, "target": objective.position, "positions": {}}
			for other in conflict.blockers: record_offer.positions[other] = bodies[other].position
			failures.append(record_offer)
			record.reason = conflict.reason
			if failures.size() >= 3: break
		# A different candidate page may be empty. Keep the last concrete
		# blocked approach for its original finite lifetime, never renew its age.
		for previous: Dictionary in record.failures:
			if failures.size() >= 3: break
			if now - float(previous.at) >= FAILURE_SECONDS or previous.revision != revision or Contract.horizontal(previous.target, objective.position) > 1.0: continue
			if failures.any(func(item): return Contract.horizontal(item.offer.position, previous.offer.position) < 0.25): continue
			failures.append(previous)
		record.failures = failures
		if not failures.is_empty():
			record.reason = failures[0].reason
			# A completed focused local pass already tried the gentler option.
			# Its failure may start yielding without waiting for another full scan;
			# the page/cooldown clock itself is never accelerated or renewed.
			if record.round >= 2 or focused: repairs.append({"member": id, "failure": failures[0].duplicate(true)})
	if repairs.is_empty(): return {}
	repairs.sort_custom(func(a, b): return a.member < b.member)
	var selected: Dictionary = repairs[0]
	for repair in repairs:
		if repair.member > _last_repair:
			selected = repair
			break
	_last_repair = selected.member
	return selected

func filter_sites(id: int, sites: Array, bodies: Dictionary, target: Vector3, revision: int, now: float) -> Array:
	var failures: Array = members.get(id, {}).get("failures", [])
	if failures.is_empty(): return sites
	return sites.filter(func(site):
		for failure: Dictionary in failures:
			if now - float(failure.at) >= FAILURE_SECONDS or failure.revision != revision or Contract.horizontal(failure.target, target) > 1.0: continue
			if Contract.horizontal(site.position, failure.offer.position) > 0.25: continue
			var unchanged: bool = failure.blockers.all(func(other): return bodies.has(other) and Contract.horizontal(bodies[other].position, failure.positions[other]) < 0.25)
			if unchanged: return false
		return true)

static func obstruction(id: int, offer: Dictionary, tasks: Dictionary, bodies: Dictionary) -> Dictionary:
	var blocked: Array = []
	var reason: StringName = &"passage_occupied"
	for other in tasks:
		if other == id: continue
		var peer: Dictionary = tasks[other]
		var gap: float = bodies[id].radius + bodies[other].radius + maxf(bodies[id].spacing_margin, bodies[other].spacing_margin)
		var post := Contract.horizontal(offer.position, peer.position) < gap
		var muzzle: bool = peer.get("tactical", {}).get("sustainable_fire", false) and Traffic.distance_to_path(offer.position, PackedVector3Array([peer.position, peer.look_position])) < bodies[id].radius + 0.1
		muzzle = muzzle or offer.get("tactical", {}).get("sustainable_fire", false) and Traffic.distance_to_path(peer.position, PackedVector3Array([offer.position, offer.look_position])) < bodies[other].radius + 0.1
		var passage := Traffic.distance_to_path(bodies[other].position, offer.route) < gap - 0.03 and not Traffic._leaves_crowding(offer.route, bodies[other].position, gap)
		if post or muzzle or passage:
			blocked.append(other)
			if post: reason = &"post_occupied"
			elif muzzle: reason = &"friendly_fire_lane"
	return {} if blocked.is_empty() else {"reason": reason, "blockers": blocked}

func snapshot(id: int, now: float) -> Dictionary:
	var record: Dictionary = members.get(id, {})
	if record.is_empty(): return {}
	return {"age": maxf(0.0, now - float(record.since)), "round": record.round,
		"reason": record.reason, "retry_in": maxf(0.0, float(record.next_at) - now)}
