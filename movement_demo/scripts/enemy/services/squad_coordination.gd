extends RefCounted

## Sole squad authority. Area clock, immutable battle profiles, one objective,
## atomic full-member task tables. No personal Utility or fallback authority.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Planner = preload("res://scripts/enemy/services/enemy_team_planner.gd")
const Formation = preload("res://scripts/enemy/services/enemy_search_formation.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
var _environment: WeakRef
var _members: Dictionary = {}
var _profiles: Dictionary = {}
var _template: Dictionary = {}
var _tasks: Dictionary = {}
var _objective: Dictionary = {}
var _covered: Dictionary = {}
var _feedback: Dictionary = {}
var _bodies: Dictionary = {}
var _progress: Dictionary = {}
var _failed_sites: Dictionary = {}
var _preparation: Dictionary = {}
var _planner = Planner.new()
var configuration: Dictionary = {}
var configuration_revision = 0
var planning_count = 0
var last_advance_usec = 0
var _version = 0
var _epoch = 0
var _due = 0.0
var _attempt = 0
var _reason: StringName = &"initializing"
var _last_replan: StringName = &"initializing"
var _last_map_revision = -1
var _barriers: Dictionary = {}
var _barrier_objective = 0
var barrier_wait_count = 0
var barrier_release_count = 0
var traffic_wait_count = 0
var yield_count = 0
var environment:
	get: return _environment.get_ref() if _environment != null else null
var elapsed: float:
	get: return environment.elapsed if environment != null else 0.0
var generation: int:
	get: return _epoch

func bind_environment(board) -> void:
	_environment = weakref(board)

func configure_profile(value: Dictionary) -> void:
	if configuration == value: return
	configuration = value.duplicate(true)
	configuration_revision += 1
	reset()

func sync_members(members: Dictionary, _teams: Dictionary = {}, _mapping: Dictionary = {}) -> void:
	for id in _members:
		if not members.has(id): release_member(id)
	_members = members.duplicate()
	_due = 0.0

func registered_member_count() -> int:
	return _members.size()

func reset() -> void:
	_epoch += 1
	_tasks.clear()
	_profiles.clear()
	_template.clear()
	_objective.clear()
	_covered.clear()
	_feedback.clear()
	_progress.clear()
	_preparation.clear()
	_failed_sites.clear()
	_bodies.clear()
	_barriers.clear()
	_barrier_objective = 0
	barrier_wait_count = 0
	barrier_release_count = 0
	traffic_wait_count = 0
	yield_count = 0
	_attempt = 0
	_due = 0.0
	_last_map_revision = -1
	if environment != null: environment.release_squad_reservations(self)

func release_member(id: int) -> void:
	_tasks.erase(id)
	_profiles.erase(id)
	_feedback.erase(id)
	_progress.erase(id)
	_bodies.erase(id)
	_preparation.clear()
	for task in _tasks.values(): task.waiting_for.erase(id)
	for key in _barriers.keys():
		if _barriers[key].members.has(id): _barriers.erase(key)
	if environment != null: environment.release_squad_reservations(self, id)
	_due = 0.0
	_last_replan = &"membership_changed"

func invalidate_member(_id: int) -> void:
	# Environment changes require route revalidation, never a training reread.
	_preparation.clear()
	_due = 0.0
	_last_replan = &"environment_changed"

func _context(id: int):
	var member: Dictionary = _members.get(id, {})
	return member.context.get_ref() if not member.is_empty() else null

func report_visual(context, acquired: bool) -> void:
	if environment == null: return
	environment.store_visual(context, acquired)
	if acquired: _due = 0.0

func report_inspection(context, clue: Dictionary) -> void:
	if environment != null: environment.store_inspection(context, clue)

func shared_visual(context) -> Dictionary:
	return environment.read_visual(context, context.cooperation_target_id()) if environment != null else {}

func shared_inspection(context) -> Dictionary:
	return environment.inspection_evidence(context, context.cooperation_target_id()) if environment != null else {}

func has_visual_contact(context) -> bool:
	return environment != null and environment.has_visual_contact(context, context.cooperation_target_id())

func report_noise(context, position: Vector3) -> void:
	if environment == null or not position.is_finite(): return
	environment.store_noise(context, position)
	_due = 0.0

func shared_noise(context) -> Dictionary:
	return environment.read_noise(context) if environment != null else {}

func report_checked(context, points: PackedVector3Array) -> void:
	if environment != null: environment.publish_checked(context, points)

func shared_checked(context) -> Array[Dictionary]:
	return environment.checked_points(context) if environment != null else []

func advance() -> void:
	var start = Time.get_ticks_usec()
	if environment == null or int(configuration.get("level", 0)) == 0: return
	_bodies.clear()
	var added = false
	for id in _members:
		var context = _context(id)
		if context == null or not is_instance_valid(context.actor) or context.actor.is_dead or not context.is_arena_active(): continue
		_bodies[id] = context.member_runtime_snapshot()
		if not _profiles.has(id):
			var profile: Dictionary = context.member_capability_snapshot()
			if profile.get("ready", false):
				_profiles[id] = profile
				added = true
		if not _tasks.has(id): _tasks[id] = _holding(id, &"assembly_pending")
	for id in _tasks.keys():
		if not _bodies.has(id): release_member(id)
	if _bodies.is_empty(): return
	if added or _template.is_empty():
		_template = Contract.template(_profiles, environment.allocate_coordination_id())
		_preparation.clear()
		_due = 0.0
	_update_objective()
	_update_progress()
	if elapsed >= _due:
		_due = elapsed + Contract.PERIOD
		_plan()
	last_advance_usec = Time.get_ticks_usec() - start

func _update_objective() -> void:
	var newest: Dictionary = {}
	var contact = false
	for id in _bodies:
		var context = _context(id)
		var report: Dictionary = environment.planning_observation(context)
		if not report.is_empty() and (newest.is_empty() or report.captured_at > newest.captured_at): newest = report
		contact = contact or has_visual_contact(context)
	var phase: StringName = &"contact" if contact else (&"search" if not newest.is_empty() or _objective.get("target_id", 0) != 0 else &"patrol")
	var changed: bool = _objective.is_empty() or _objective.phase != phase
	if phase == &"contact" and not newest.is_empty():
		changed = changed or _objective.get("position", Vector3.INF).distance_to(newest.position) > 1.0
	if phase == &"search" and not newest.is_empty():
		changed = changed or float(newest.captured_at) > float(_objective.get("captured_at", -INF)) + 0.01
	if not changed: return
	var previous = _objective
	_objective = newest.duplicate(true) if not newest.is_empty() else previous.duplicate(true)
	_objective.merge({"phase": phase, "objective_id": environment.allocate_coordination_id(),
		"position": _objective.get("position", _bodies.values()[0].position),
		"target_id": _objective.get("target_id", 0), "uncertainty": 0.0}, true)
	_covered.clear()
	_failed_sites.clear()
	_barriers.clear()
	_attempt = 0
	_preparation.clear()
	_due = 0.0
	_last_replan = &"objective_changed"
	# Explicit supersession keeps every live body owned while a new full
	# plan is prepared; stale search reports can no longer mark coverage.
	for id in _tasks: _tasks[id] = _holding(id, &"objective_changed")
	environment.release_squad_reservations(self)

func _holding(id: int, reason: StringName) -> Dictionary:
	var profile: Dictionary = _profiles.get(id, {})
	var body: Dictionary = _bodies.get(id, {})
	var position: Vector3 = body.get("position", Vector3.ZERO)
	var action = Contract.executor(profile, &"guard")
	var proposal = {"action": action, "role": &"guard", "position": position,
		"route": PackedVector3Array([position]), "look_position": _objective.get("position", position + Vector3.FORWARD),
		"objective_id": _objective.get("objective_id", 0), "site_key": "hold:%s" % id}
	var result = _new_task(id, proposal)
	result.reason = reason
	result.check_at = elapsed + Contract.PERIOD
	return result

func _new_task(id: int, proposal: Dictionary) -> Dictionary:
	return Contract.task({"generation": generation, "version": _version, "member_id": id,
		"task_id": environment.allocate_coordination_id(), "profile_id": _profiles.get(id, {}).get("profile_id", "")}, proposal, elapsed)

func _plan() -> void:
	if _profiles.is_empty():
		_reason = &"members_not_assembled"
		return
	var context = _context(_bodies.keys()[0])
	var map_revision: int = context.coordination_search_revision()
	if map_revision != _last_map_revision:
		_last_map_revision = map_revision
		_preparation.clear()
	var must_replan = _preparation.size() > 0
	for id in _tasks:
		var task: Dictionary = _tasks[id]
		must_replan = must_replan or task.role == &"guard" or task.state in [&"blocked", &"complete"] or task.expires_at <= elapsed or task.objective_id != _objective.objective_id
		if _objective.phase == &"contact":
			must_replan = must_replan or (_bodies[id].visible == false and task.role in [&"engage", &"support", &"flank"] and task.state == &"executing" and Contract.horizontal(_bodies[id].position, task.position) < 0.15)
			must_replan = must_replan or task.role != &"reload" and task.role != _contact_role(id)
			must_replan = must_replan or _bodies[id].firearms and _bodies[id].visible and Contract.horizontal(_bodies[id].position, _objective.position) < 3.0 and Contract.horizontal(task.position, _objective.position) < 3.0
		must_replan = must_replan or _bodies[id].can_reload and _bodies[id].rounds == 0 and task.role != &"reload"
	if not must_replan: return
	if _preparation.is_empty():
		var sites = Formation.sites(context, _objective, _bodies.size(), _attempt)
		_preparation = {"members": _bodies.keys(), "index": 0, "candidates": {}, "sites": sites, "map_revision": map_revision,
			"objective_id": _objective.objective_id, "started_at": elapsed}
	var id = _preparation.members[_preparation.index]
	if not _bodies.has(id):
		_preparation.clear()
		return
	var candidates: Array[Dictionary] = []
	var body: Dictionary = _bodies[id]
	var member_context = _context(id)
	var sites: Array = _preparation.sites.duplicate(true)
	if _objective.phase == &"contact" and body.visible and (not body.firearms or Contract.horizontal(body.position, _objective.position) >= 3.0):
		sites.push_front({"position": body.position, "look_position": _objective.position, "site_key": "contact:%s" % id})
	if body.reloading or body.rounds == 0 and body.can_reload:
		sites = [{"position": body.position, "look_position": _objective.position, "site_key": "reload:%s" % id}]
	var previous: Dictionary = _tasks[id]
	if previous.has("resume_task") and previous.state == &"complete" and _passage_cleared(previous):
		var resume: Dictionary = previous.resume_task
		var path = Formation.route(member_context, resume.position)
		if not path.is_empty():
			resume = resume.duplicate(true)
			resume.route = path
			resume.estimate = 0.0
			candidates.append(resume)
	for site in sites:
		if _covered.has(site.site_key) or _failed_sites.get([id, site.site_key], -INF) > elapsed: continue
		if _objective.phase == &"contact": site.role = _contact_role(id)
		var candidate = Formation.candidate(member_context, _profiles.get(id, {}), body, site, _objective, _tasks[id])
		if not candidate.is_empty(): candidates.append(candidate)
		if candidates.size() >= 6: break
	if candidates.is_empty():
		var hold = _holding(id, &"no_reachable_post")
		hold.estimate = 40.0
		candidates.append(hold)
	_preparation.candidates[id] = candidates
	_preparation.index += 1
	if _preparation.index < _preparation.members.size():
		_due = elapsed # Continue bounded preparation on the next area tick.
		return
	var result = _planner.propose({"members": _bodies, "profiles": _profiles, "template": _template,
		"objective": _objective, "candidates": _preparation.candidates})
	planning_count += 1
	_reason = result.reason
	_preparation.clear()
	if result.complete and result.tasks.values().any(func(task): return task.role != &"guard"):
		if not _commit(result.tasks, result.traffic):
			_last_replan = &"commit_revalidation_failed"
			_attempt += 1
	else:
		_attempt += 1
		_last_replan = result.reason
		if not _repair_traffic(result.get("attempted", {})):
			for task in _tasks.values():
				task.reason = &"retry_other_posts"
				task.check_at = elapsed + Contract.PERIOD

func _contact_role(id: int) -> StringName:
	var role: StringName = _template.get("contact_roles", {}).get(id, &"engage")
	if _bodies.size() == 1: role = &"engage"
	if not Contract.executor(_profiles[id], &"support").is_empty():
		for other in _bodies:
			if other != id and (_bodies[other].reloading or _bodies[other].rounds == 0 and _bodies[other].can_reload): return &"support"
	return role

func _passage_cleared(task: Dictionary) -> bool:
	var other = task.get("yield_for", 0)
	if not _tasks.has(other) or not _bodies.has(other): return true
	var path = Traffic.remaining(_bodies[other].position, _tasks[other].route)
	var radius: float = _bodies[other].radius * 2.0 + _bodies[other].spacing_margin
	return Traffic.distance_to_path(task.resume_position, path) >= radius

func _commit(proposals: Dictionary, _traffic: Dictionary) -> bool:
	# Recheck membership, map and actual occupancy immediately before one
	# transaction replaces the table and public position reservations.
	if proposals.size() != _bodies.size(): return false
	# Preparation spans area ticks. Refresh start points and solve traffic
	# again against the current bodies before publishing either resource.
	var routes = proposals.duplicate(true)
	for id in routes:
		var peer = _context(id)
		if peer == null or peer.actor.is_dead: return false
		_bodies[id] = peer.member_runtime_snapshot()
		routes[id].route = Traffic.remaining(_bodies[id].position, routes[id].route)
		if not peer.validate_command_post(routes[id], _profiles.get(id, {})): return false
	var traffic = Traffic.schedule(routes, _bodies)
	if not traffic.valid: return false
	var table = {}
	for id in routes:
		if not _bodies.has(id) or not _profiles.has(id): return false
		var proposal: Dictionary = routes[id]
		if not _context(id).validate_command_post(proposal, _profiles[id]): return false
		var old: Dictionary = _tasks.get(id, {})
		if old.get("objective_id") == proposal.objective_id and old.get("role") == proposal.role and old.get("action") == proposal.action and old.get("position", Vector3.INF).distance_to(proposal.position) < 0.05 and old.expires_at > elapsed and not old.state in [&"blocked", &"complete"]:
			table[id] = old.duplicate(true)
		else:
			table[id] = _new_task(id, proposal)
			table[id].version = _version + 1
			table[id].expires_at = elapsed + maxf(Contract.TASK_SECONDS, float(proposal.get("travel_seconds", 0.0)) + 4.0)
		table[id].waiting_for = traffic.get("dependencies", {}).get(id, []).duplicate()
		table[id].map_revision = _last_map_revision
	if not environment.commit_squad_reservations(self, table): return false
	for key in _barriers.keys():
		for id in _barriers[key].members:
			if not table.has(id) or not Contract.same_task(table[id], _tasks.get(id, {})):
				_barriers.erase(key)
				break
	_version += 1
	_tasks = table
	_install_barrier()
	for id in table:
		_progress[id] = {"position": _bodies[id].position, "at": elapsed}
	_last_replan = &"complete_plan"
	return true

func _install_barrier() -> void:
	if int(configuration.get("level", 0)) != 2 or _objective.phase != &"search" or _barrier_objective == _objective.objective_id: return
	# Only the first observer at each of two different cover exits takes part.
	# Followers and unrelated fire providers remain asynchronous.
	var exits = {}
	for id in _tasks:
		var task: Dictionary = _tasks[id]
		if task.role != &"search" or not task.get("staging_position", Vector3.INF).is_finite(): continue
		var side = task.get("side", 0)
		if not exits.has(side) or task.travel_seconds < _tasks[exits[side]].travel_seconds: exits[side] = id
	if exits.size() < 2: return
	var participants: Array = exits.values()
	for id in participants:
		for other in participants:
			if id != other and _tasks[id].waiting_for.has(other): return
	var key = environment.allocate_coordination_id()
	_barriers[key] = {"members": participants, "ready": {}, "waited": {}, "released": false, "started_at": elapsed}
	for id in participants: _tasks[id].barrier_id = key
	_barrier_objective = _objective.objective_id

func _update_progress() -> void:
	for id in _tasks:
		var task: Dictionary = _tasks[id]
		var body: Dictionary = _bodies[id]
		var old: Dictionary = _progress.get(id, {"position": body.position, "at": elapsed})
		if Contract.horizontal(old.position, body.position) > 0.08:
			old = {"position": body.position, "at": elapsed}
		_progress[id] = old
		if Contract.horizontal(body.position, task.position) <= 0.12 or body.occupied or task.get("reason") == &"staging_barrier": continue
		var passing = false
		for other in _feedback.get(id, {}).get("waiting_for", []):
			if _bodies.has(other) and Vector2(_bodies[other].velocity.x, _bodies[other].velocity.z).length() > 0.1: passing = true
		if passing:
			_progress[id].at = elapsed
			continue
		if elapsed - float(old.at) > 1.25:
			task.state = &"blocked"
			task.reason = &"no_motion_progress"
			_failed_sites[[id, task.site_key]] = elapsed + 4.0
			_due = 0.0
			_last_replan = &"no_motion_progress"

func _repair_traffic(attempted: Dictionary = {}) -> bool:
	# Joint yield/return plan: the blocker moves to a validated temporary post;
	# all other destinations and their dependencies are reconsidered together.
	var base = attempted if attempted.size() == _tasks.size() else _tasks
	for id in base:
		var blocked = Traffic.blockers(id, base, _bodies)
		for blocker in blocked:
			if not _profiles.has(blocker) or _bodies[blocker].occupied: continue
			for site in Formation.yield_sites(_context(blocker), _bodies[blocker]):
				var table = base.duplicate(true)
				var action = Contract.executor(_profiles[blocker], &"move")
				if action.is_empty(): continue
				var previous: Dictionary = table[blocker]
				table[blocker] = {"action": action, "role": &"move", "position": site.position, "route": site.route,
					"look_position": _objective.position, "objective_id": _objective.objective_id, "site_key": site.site_key,
					"resume_position": previous.get("resume_position", previous.position), "resume_task": previous.get("resume_task", previous).duplicate(true),
					"yield_for": id, "return_when": &"passage_cleared", "estimate": 0.0}
				for other in table:
					if other == blocker: continue
					var path = Formation.route(_context(other), table[other].position)
					if not path.is_empty(): table[other].route = path
				var traffic = Traffic.schedule(table, _bodies)
				if traffic.valid and _commit(table, traffic):
					_last_replan = &"joint_yield"
					yield_count += 1
					return true
	return false

func assignment(context) -> Dictionary:
	return _tasks.get(context.actor.get_instance_id(), {}).duplicate(true)

func accept(context, token: Dictionary) -> bool:
	var id: int = context.actor.get_instance_id()
	if not Contract.same_task(token, _tasks.get(id, {})): return false
	if int(_tasks[id].get("map_revision", context.coordination_search_revision())) != context.coordination_search_revision(): return false
	if not context.validate_command_post(_tasks[id], _profiles.get(id, {})): return false
	_tasks[id].accepted = true
	_tasks[id].state = &"executing"
	return true

func report(context, report: Dictionary) -> bool:
	var id: int = context.actor.get_instance_id()
	if not Contract.same_task(report, _tasks.get(id, {})): return false
	if not Contract.STATES.has(report.get("state")): return false
	var task: Dictionary = _tasks[id]
	if report.state == &"complete" and not task.accepted: return false
	if report.state == &"complete" and task.role == &"search":
		if not report.get("observed", false) or not context.command_observation_valid(task): return false
	_feedback[id] = report.duplicate(true)
	task.state = report.state
	task.reason = report.get("reason", &"")
	task.progress = report.get("progress", 0.0)
	if report.state == &"complete":
		if task.role == &"search":
			_covered[task.site_key] = {"position": task.look_position, "observed_at": elapsed, "member_id": id}
		_due = 0.0
	elif report.state == &"blocked":
		_failed_sites[[id, task.site_key]] = elapsed + 4.0
		_due = 0.0
	return true

func motion_permission(context, token: Dictionary) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	if not Contract.same_task(token, _tasks.get(id, {})): return {"allowed": false, "reason": &"replaced", "waiting_for": []}
	var bodies = {}
	for member in _tasks:
		var peer = _context(member)
		if peer != null and is_instance_valid(peer.actor) and not peer.actor.is_dead: bodies[member] = peer.member_runtime_snapshot()
	var blockers = Traffic.blockers(id, _tasks, bodies)
	var task: Dictionary = _tasks[id]
	var waiting: Array = blockers.duplicate()
	var barrier_id = task.get("barrier_id", 0)
	if _barriers.has(barrier_id):
		var barrier: Dictionary = _barriers[barrier_id]
		for member in barrier.members:
			if bodies.has(member) and _tasks[member].accepted and Contract.horizontal(bodies[member].position, _tasks[member].staging_position) <= 0.12:
				barrier.ready[member] = true
		if barrier.ready.size() == barrier.members.size() and not barrier.released:
			barrier.released = true
			barrier_release_count += 1
		if not barrier.released and Contract.horizontal(bodies[id].position, task.staging_position) <= 0.12:
			if not barrier.waited.has(id):
				barrier.waited[id] = true
				barrier_wait_count += 1
			var awaiting = barrier.members.filter(func(member): return not barrier.ready.has(member))
			return {"allowed": false, "waiting_for": awaiting, "reason": &"staging_barrier", "members": bodies.keys()}
	for other in task.waiting_for:
		if not _tasks.has(other) or not bodies.has(other): continue
		var path = Traffic.remaining(bodies[id].position, task.route)
		var clearance: float = bodies[id].radius + bodies[other].radius + maxf(bodies[id].spacing_margin, bodies[other].spacing_margin)
		if Traffic.distance_to_path(bodies[other].position, path) < clearance and not waiting.has(other): waiting.append(other)
	if not waiting.is_empty(): traffic_wait_count += 1
	return {"allowed": waiting.is_empty(), "waiting_for": waiting, "reason": &"occupied_corridor" if not waiting.is_empty() else &"", "members": bodies.keys()}

func debug_member_snapshot(context) -> Dictionary:
	var task = assignment(context)
	return {"source": &"squad" if not task.is_empty() else &"personal", "task": task,
		"objective": _objective.duplicate(true), "template": _template.duplicate(true),
		"profile": _profiles.get(context.actor.get_instance_id(), {}).duplicate(true),
		"route": Traffic.remaining(context.actor.global_position, task.get("route", PackedVector3Array())) if not task.is_empty() and task.state != &"complete" else PackedVector3Array(), "target_position": task.get("position", Vector3.INF),
		"staging_position": task.get("staging_position", Vector3.INF), "goal": task.get("position", Vector3.INF),
		"waiting_for": _feedback.get(context.actor.get_instance_id(), {}).get("waiting_for", []).duplicate(),
		"phase": _objective.get("phase", &"patrol"), "state": task.get("state", &"pending"),
		"reason": task.get("reason", _reason), "planning_reason": _reason, "last_replan": _last_replan,
		"plan_version": _version, "covered": _covered.duplicate(true), "barriers": _barriers.duplicate(true)}

func member_ids() -> Array:
	return _tasks.keys()

func support_demand(context) -> float:
	var task := assignment(context)
	if task.get("role") != &"support" or not context.sees_player: return 0.0
	for id in _tasks:
		if id == context.actor.get_instance_id(): continue
		var peer = _context(id)
		if peer == null or peer.actor.is_dead: continue
		if not environment.can_share_intel(id, context.actor.get_instance_id()): continue
		if peer.actor.ammo.is_reloading: return 1.0
	return 0.0
