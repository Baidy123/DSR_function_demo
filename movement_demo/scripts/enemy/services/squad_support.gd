extends RefCounted

## Task-scoped support facts. Only the owning coordinator replaces tasks.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Visual = preload("res://scripts/enemy/services/enemy_visual_observation.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const WAIT_SECONDS := 2.0
const RETRY_SECONDS := 4.0
var links := {}
var independent_until := {}
var recovery := {}
var fire_links := {}
var wait_clock := {}

static func covered_sites(context, watch: Dictionary, sites: Array) -> Array:
	var result: Array = []
	var eye: Vector3 = context.actor.get_posture_eye_position(false, watch.position)
	var facing: Vector3 = watch.look_position - watch.position
	facing.y = 0.0
	for site in sites:
		if site.get("sync_key", "") != watch.overwatch_for or site.has("overwatch_for"): continue
		var offset: Vector3 = site.look_position - watch.position
		if offset.length() > context.perception.sight_distance: continue
		offset.y = 0.0
		if not offset.is_zero_approx() and facing.normalized().dot(offset.normalized()) < cos(deg_to_rad(context.perception.sight_angle_degrees * 0.5)): continue
		if Visual.clear_from(context, eye, site.look_position): result.append(site.site_key)
	return result

static func covers(watch: Dictionary, inspection: Dictionary) -> bool:
	if inspection.get("support_mode") == &"independent": return false
	return watch.get("overwatch_for", "!") == inspection.get("sync_key", "") and (not watch.has("supported_sites") or watch.supported_sites.has(inspection.get("site_key", "")))

static func acyclic(tasks: Dictionary, traffic: Dictionary) -> bool:
	for phase in ["dependencies", "preparation_dependencies"]:
		if not _acyclic_phase(tasks, traffic.get(phase, {})): return false
	return true

static func _acyclic_phase(tasks: Dictionary, source: Dictionary) -> bool:
	var dependencies := source.duplicate(true)
	for id in tasks:
		if tasks[id].role != &"search" or tasks[id].get("sync_key", "").is_empty(): continue
		if not dependencies.has(id): dependencies[id] = []
		for other in tasks:
			if other != id and covers(tasks[other], tasks[id]) and not dependencies[id].has(other): dependencies[id].append(other)
	var done: Array = []
	for iteration in tasks.size():
		for id in tasks:
			if not done.has(id) and dependencies.get(id, []).all(func(peer): return done.has(peer)): done.append(id)
	return done.size() == tasks.size()

func release(id: int) -> void:
	links.erase(id)
	recovery.erase(id)
	fire_links.erase(id)
	wait_clock.erase(id)
	for link in fire_links.values(): link.beneficiaries.erase(id)
	for link in links.values(): link.providers.erase(id)
	for key in independent_until.keys():
		if key[0] == id: independent_until.erase(key)

func install(tasks: Dictionary, profiles: Dictionary, now: float) -> void:
	var next := {}
	fire_links.clear()
	for id in tasks:
		if tasks[id].role != &"support": continue
		var beneficiaries := {}
		for other in tasks:
			if other == id or tasks[other].objective_id != tasks[id].objective_id: continue
			if tasks[id].has("overwatch_for") and not covers(tasks[id], tasks[other]): continue
			beneficiaries[other] = tasks[other].duplicate(true)
		fire_links[id] = {"task": tasks[id].duplicate(true), "beneficiaries": beneficiaries}
	for id in tasks:
		var task: Dictionary = tasks[id]
		if task.role != &"search" or task.state == &"complete" or task.get("sync_key", "").is_empty(): continue
		if independent_until.get([id, task.site_key], -INF) > now: continue
		var providers := {}
		for other in tasks:
			var watch: Dictionary = tasks[other]
			if other == id or not covers(watch, task): continue
			if not profiles.get(other, {}).get("firearms", false) or Contract.executor(profiles[other], &"support").is_empty(): continue
			providers[other] = watch.duplicate(true)
		if providers.is_empty(): continue
		var old: Dictionary = links.get(id, {})
		var unchanged: bool = Contract.same_task(old.get("task", {}), task) and old.get("providers", {}).keys() == providers.keys()
		if unchanged:
			for other in providers:
				if not Contract.same_task(old.providers[other], providers[other]): unchanged = false
		next[id] = old if unchanged else {"task": task.duplicate(true), "providers": providers, "region": task.look_position,
			"phase": &"preparing", "waiting_since": -1.0, "deadline": INF, "ready": [], "reason": &"support_preparing"}
	links = next
	for key in independent_until.keys():
		if independent_until[key] <= now: independent_until.erase(key)
	for id in recovery.keys():
		if not tasks.has(id) or recovery[id].until <= now or recovery[id].task.objective_id != tasks[id].objective_id: recovery.erase(id)

func recovery_site(id: int, body: Dictionary, objective: Dictionary, now: float, context = null) -> Dictionary:
	var entry: Dictionary = recovery.get(id, {})
	if entry.is_empty() or entry.until <= now or entry.task.objective_id != objective.objective_id: return {}
	var path := Traffic.remaining(body.position, entry.task.route)
	path = Traffic.prefix(path, 1.4)
	if path.is_empty() or Contract.horizontal(body.position, path[-1]) < 0.2: return {}
	var region: Vector3 = entry.task.look_position
	# Keep watching the intended hideout when it is visible from this shorter
	# leg. Otherwise inspect only the reachable local patch; never claim that
	# a short move has cleared the still-occluded original responsibility.
	if context != null and not Visual.clear_from(context, context.actor.get_posture_eye_position(false, path[-1]), region): region = path[-1]
	return {"position": path[-1], "look_position": region, "site_key": "independent:%s" % entry.task.task_id,
		"support_mode": &"independent", "observation_mode": &"inspect",
		# Independence removes the failed fire dependency, not the strong
		# team's rendezvous. A new short leg starts at the current physical post.
		"sync_key": entry.task.get("sync_key", ""), "side": entry.task.get("side", 0), "via": body.position}

func ready(context, task: Dictionary, body: Dictionary, region: Vector3, profile: Dictionary) -> bool:
	if not task.get("accepted", false) or task.get("state") in [&"blocked", &"complete"]: return false
	if task.get("expires_at", -INF) <= context.coordination_now(): return false
	if Contract.horizontal(body.position, task.position) > 0.18 or not body.firearms or body.occupied or body.reloading or not body.can_attack or body.rounds <= 0: return false
	if body.pressure > float(profile.get("stress_tolerance", 0.4)): return false
	if not Visual.visible(context, region): return false
	var origin: Vector3 = context.actor.get_shot_origin()
	var aim := region + Vector3.UP
	return origin.distance_to(aim) <= float(profile.weapon.get("fire_range", 0.0)) and context.fire.has_clear_firing_lane(origin, aim - origin, origin.distance_to(aim)) and context.cooperation_line_safe(origin, aim)

## Called from the original area tick. Returns invalidated beneficiaries;
## no body, accepted/observed flag or task table is written by this component.
func advance(tasks: Dictionary, bodies: Dictionary, profiles: Dictionary, lookup: Callable, now: float) -> Array[int]:
	var invalid: Array[int] = []
	for id in fire_links.keys():
		if not Contract.same_task(fire_links[id].task, tasks.get(id, {})):
			fire_links.erase(id)
			continue
		for other in fire_links[id].beneficiaries.keys():
			if not Contract.same_task(fire_links[id].beneficiaries[other], tasks.get(other, {})) or tasks[other].state == &"complete": fire_links[id].beneficiaries.erase(other)
	for id in wait_clock.keys():
		if not tasks.has(id) or tasks[id].objective_id != wait_clock[id].objective_id or tasks[id].state == &"complete": wait_clock.erase(id)
	for id in recovery.keys():
		if recovery[id].until <= now or not tasks.has(id) or tasks[id].objective_id != recovery[id].task.objective_id: recovery.erase(id)
	for id in links.keys():
		var link: Dictionary = links[id]
		if not tasks.has(id) or not Contract.same_task(link.task, tasks[id]) or tasks[id].state == &"complete":
			links.erase(id)
			continue
		if link.phase == &"invalid": continue
		link.ready.clear()
		var unavailable := true
		for other in link.providers.keys():
			if not tasks.has(other) or not bodies.has(other) or not Contract.same_task(link.providers[other], tasks[other]):
				link.providers.erase(other)
				continue
			if bodies[other].firearms and not bodies[other].occupied and not bodies[other].reloading and bodies[other].can_attack and bodies[other].rounds > 0 and bodies[other].pressure <= float(profiles[other].get("stress_tolerance", 0.4)): unavailable = false
			if ready(lookup.call(other), tasks[other], bodies[other], link.region, profiles[other]): link.ready.append(other)
		if not link.ready.is_empty():
			link.phase = &"covering"
			link.had_ready = true
			link.waiting_since = -1.0
			link.deadline = INF
			link.reason = &""
			wait_clock.erase(id)
			continue
		link.phase = &"preparing"
		link.reason = &"support_preparing"
		var staging: Vector3 = tasks[id].get("staging_position", Vector3.INF)
		# The dependent may reach its protected preparation point before waiting.
		# Once released, loss of support gets the same finite recovery window.
		var waiting: bool = Contract.horizontal(bodies[id].position, staging) < 0.18 or tasks[id].get("reason") == &"support_preparing" or link.get("had_ready", false)
		if link.providers.is_empty() or waiting and link.waiting_since < 0.0:
			var clock: Dictionary = wait_clock.get(id, {})
			if clock.is_empty() or clock.objective_id != tasks[id].objective_id or Contract.horizontal(clock.position, bodies[id].position) > 0.5:
				clock = {"at": now, "position": bodies[id].position, "objective_id": tasks[id].objective_id}
				wait_clock[id] = clock
			link.waiting_since = clock.at
			link.deadline = clock.at + WAIT_SECONDS
		if unavailable and not link.has("unavailable_since"): link.unavailable_since = now
		if not unavailable: link.erase("unavailable_since")
		if unavailable and now - float(link.get("unavailable_since", now)) >= 0.35 or link.providers.is_empty() or now >= float(link.deadline):
			independent_until[[id, tasks[id].site_key]] = now + RETRY_SECONDS
			recovery[id] = {"task": tasks[id].duplicate(true), "until": now + RETRY_SECONDS}
			link.phase = &"invalid"
			link.reason = &"support_unavailable"
			invalid.append(id)
	return invalid

func permission(id: int, task: Dictionary, position: Vector3) -> Dictionary:
	var link: Dictionary = links.get(id, {})
	if link.is_empty() or not Contract.same_task(link.task, task): return {}
	if link.phase == &"invalid": return {"allowed": false, "reason": &"support_replanning", "waiting_for": []}
	if Contract.horizontal(position, task.get("staging_position", Vector3.INF)) > 0.18: return {}
	if not link.ready.is_empty(): return {}
	return {"allowed": false, "reason": &"support_preparing", "waiting_for": link.providers.keys()}

func snapshot(id: int) -> Dictionary:
	return links.get(id, fire_links.get(id, {})).duplicate(true)

func beneficiaries(id: int, tasks: Dictionary) -> Array:
	var link: Dictionary = fire_links.get(id, {})
	if link.is_empty() or not Contract.same_task(link.task, tasks.get(id, {})): return []
	if tasks[id].state in [&"blocked", &"complete"]: return []
	return link.beneficiaries.keys().filter(func(peer): return Contract.same_task(link.beneficiaries[peer], tasks.get(peer, {})) and not tasks[peer].state in [&"blocked", &"complete"])
