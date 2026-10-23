extends RefCounted

## Sole squad authority. Area clock, immutable battle profiles, one objective,
## atomic full-member task tables. No personal Utility or fallback authority.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Planner = preload("res://scripts/enemy/services/enemy_team_planner.gd")
const Formation = preload("res://scripts/enemy/services/enemy_search_formation.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const Search = preload("res://scripts/enemy/services/squad_search.gd")
const Combat = preload("res://scripts/enemy/services/squad_combat_tactics.gd")
const Support = preload("res://scripts/enemy/services/squad_support.gd")
var _support = Support.new()
var _search = Search.new()
const Defense = preload("res://scripts/enemy/services/squad_defense.gd")
var _defense = Defense.new()
var _environment: WeakRef
var _members: Dictionary = {}
var _profiles: Dictionary = {}
var _template: Dictionary = {}
var _tasks: Dictionary = {}
var _objective: Dictionary = {}
var _covered: Dictionary = {}
var _patrol_visits: Dictionary = {}
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
var frame_costs := {"observation": 0, "planning": 0, "stage": &"idle"}
var _version = 0
var _epoch = 0
var _due = 0.0
var _attempt = 0
var _reason: StringName = &"initializing"
var _last_replan: StringName = &"initializing"
var _last_map_revision = -1
var _observations: Dictionary = {}
var _observation_at := 0.0
var _barriers: Dictionary = {}
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
	_search = Search.new()
	_defense = Defense.new()
	_support = Support.new()
	_tasks.clear()
	_profiles.clear()
	_template.clear()
	_objective.clear()
	_covered.clear()
	_patrol_visits.clear()
	_feedback.clear()
	_progress.clear()
	_preparation.clear()
	_failed_sites.clear()
	_bodies.clear()
	_barriers.clear()
	barrier_wait_count = 0
	barrier_release_count = 0
	traffic_wait_count = 0
	yield_count = 0
	_attempt = 0
	_due = 0.0
	_last_map_revision = -1
	_observations.clear()
	_observation_at = 0.0
	if environment != null: environment.release_squad_reservations(self)

func release_member(id: int) -> void:
	_search.coverage.release(id)
	_observations.erase(id)
	_defense.release(id)
	_support.release(id)
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
	if environment == null: return
	if int(configuration.get("level", 0)) == 0:
		_observe_map()
		last_advance_usec = Time.get_ticks_usec() - start
		return
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
	var observation_start := Time.get_ticks_usec()
	_observe_map()
	frame_costs.observation = Time.get_ticks_usec() - observation_start
	_update_objective()
	if _defense.advance(_bodies, _profiles, _tasks, _objective, elapsed):
		_preparation.clear()
		_due = 0.0
	if _objective.phase == &"search":
		var revision: int = _search.revision
		_search.advance(_bodies.keys().map(func(id): return _context(id)), _profiles, elapsed)
		if revision != _search.revision:
			_preparation.clear()
			_due = 0.0
		_objective.search_center = _search.center
		_objective.search_revision = _search.revision
	_update_progress()
	for id in _support.advance(_tasks, _bodies, _profiles, _context, elapsed):
		_tasks[id].state = &"blocked"
		_tasks[id].reason = &"support_unavailable"
		_failed_sites[[id, _tasks[id].site_key]] = elapsed + Support.RETRY_SECONDS
		_preparation.clear()
		_due = 0.0
	if elapsed >= _due:
		_due = elapsed + Contract.PERIOD
		var planning_start := Time.get_ticks_usec()
		_plan()
		frame_costs.planning = Time.get_ticks_usec() - planning_start
	else: frame_costs.planning = 0
	last_advance_usec = Time.get_ticks_usec() - start

func _observe_map() -> void:
	var delta := minf(0.1, maxf(0.0, elapsed - _observation_at))
	_observation_at = elapsed
	var prepared := false
	for id in _members:
		var ctx = _context(id)
		if ctx == null or not is_instance_valid(ctx.actor) or ctx.actor.is_dead or not ctx.is_arena_active(): continue
		if not prepared:
			_search.coverage.advance(ctx, elapsed, Time.get_ticks_usec() + 500)
			prepared = true
		var task: Dictionary = _tasks.get(id, {})
		_search.coverage.observe(ctx, task, elapsed, delta, Time.get_ticks_usec() + 250)
		if task.get("role") != &"search" or not task.get("accepted", false) or task.get("state") in [&"blocked", &"complete", &"occupied"]: continue
		if task.get("coverage_version", _search.coverage.map_version) != _search.coverage.map_version: continue
		# Critical inspections require an actual check at their released post.
		# Travel still contributes to the map ledger; sweep steps finish in motion.
		if task.has("barrier_id") and not _barriers.get(task.barrier_id, {}).get("released", false): continue
		if task.get("observation_mode") != &"sweep" and Contract.horizontal(ctx.actor.global_position, task.position) > 0.18: continue
		var progress: Dictionary = _observations.get(id, {})
		if not Contract.same_task(progress.get("token", {}), task) or progress.get("map_revision", -1) != ctx.coordination_search_revision():
			progress = {"token": task.duplicate(true), "duration": {}, "last_at": -INF, "map_revision": ctx.coordination_search_revision()}
			_observations[id] = progress
		if elapsed <= float(progress.last_at): continue
		progress.last_at = elapsed
		var samples: PackedVector3Array = task.get("observation_samples", PackedVector3Array([task.look_position]))
		var observation_deadline := Time.get_ticks_usec() + 650
		for count in samples.size():
			if Time.get_ticks_usec() >= observation_deadline: break
			var index: int = progress.get("cursor", 0) % samples.size()
			progress.cursor = index + 1
			if ctx.actor.is_vaulting() or ctx.actor.melee_active: break
			if not preload("res://scripts/enemy/services/enemy_visual_observation.gd").visible(ctx, samples[index]): continue
			progress.duration[index] = float(progress.duration.get(index, 0.0)) + delta
			_search.coverage.credit(task.get("coverage_key", ""), samples[index], id, task.task_id, elapsed, delta, ctx)

func observation_progress(context, token: Dictionary) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	var task: Dictionary = _tasks.get(id, {})
	if not Contract.same_task(token, task): return {}
	var progress: Dictionary = _observations.get(id, {})
	if not Contract.same_task(progress.get("token", {}), task): return {}
	if progress.get("map_revision", -1) != context.coordination_search_revision() or task.get("coverage_version", _search.coverage.map_version) != _search.coverage.map_version: return {}
	var parameters: Dictionary = _profiles.get(id, {}).get("actions", {}).get(task.action, {}).get("parameters", {})
	var pause := maxf(0.25, float(parameters.get("search_pause_seconds", 0.5)))
	var samples: PackedVector3Array = task.get("observation_samples", PackedVector3Array([task.look_position]))
	var ratio := 1.0
	var focus: Vector3 = task.look_position
	for index in samples.size():
		var part := float(progress.duration.get(index, 0.0)) / pause
		if part < ratio:
			ratio = part
			focus = samples[index]
	var arrived := Contract.horizontal(context.actor.global_position, task.position) <= 0.18
	return {"progress": minf(1.0, ratio), "complete": ratio >= 1.0 and (arrived or task.get("observation_mode") == &"sweep"), "look_position": focus}

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
	if not changed:
		if phase == &"contact" and not newest.is_empty():
			# A new usable aim point at the same feet must not stay frozen as INF.
			_objective.aim_position = newest.get("aim_position", Vector3.INF)
			# Small legal target movement can invalidate one melee post without
			# replacing the objective or the still useful ranged firing tasks.
			for id in _tasks:
				if _profiles.get(id, {}).get("firearms", true) or not _tasks[id].role in [&"engage", &"flank"]: continue
				if Combat.melee_post_valid(_context(id), _profiles[id], _tasks[id].position, newest.position, 0.08): continue
				# Finish the bounded in-flight team plan before taking another
				# sub-metre sample. Restarting for every walking frame starves it.
				if _preparation.is_empty() and _objective.position.distance_to(newest.position) > 0.02:
					_objective.position = newest.position
					_objective.captured_at = newest.captured_at
					_failed_sites.clear()
				_tasks[id].state = &"blocked"
				_tasks[id].reason = &"attack_post_invalid"
				_due = 0.0
		return
	var previous = _objective
	_objective = newest.duplicate(true) if not newest.is_empty() else previous.duplicate(true)
	_objective.merge({"phase": phase, "objective_id": environment.allocate_coordination_id(),
		"position": _objective.get("position", _bodies.values()[0].position),
		"target_id": _objective.get("target_id", 0), "uncertainty": 0.0}, true)
	_covered.clear()
	_patrol_visits.clear()
	_failed_sites.clear()
	_barriers.clear()
	_attempt = 0
	_preparation.clear()
	_due = 0.0
	_last_replan = &"objective_changed"
	if phase == &"search": _search.begin(_objective, _profiles, elapsed)
	# Explicit supersession keeps every live body owned while a new full
	# plan is prepared; stale search reports can no longer mark coverage.
	for id in _tasks:
		if _tasks[id].role in [&"shelter", &"cover_peek"] and not _defense.role(id).is_empty(): continue
		# During visible target motion, retain valid combat work while preparing
		# its replacement. Replanning itself is not a loss of firing permission.
		if previous.get("phase") == &"contact" and phase == &"contact" and _tasks[id].role in [&"engage", &"support", &"flank", &"reload"]:
			continue
		_tasks[id] = _holding(id, &"objective_changed")
	environment.release_squad_reservations(self)

func _holding(id: int, reason: StringName) -> Dictionary:
	var profile: Dictionary = _profiles.get(id, {})
	var body: Dictionary = _bodies.get(id, {})
	var position: Vector3 = body.get("position", Vector3.ZERO)
	var action = Contract.executor(profile, &"guard")
	if _objective.get("phase") == &"contact":
		var engage = Contract.executor(profile, &"engage")
		if not engage.is_empty() and profile.actions[engage].roles.has(&"guard"): action = engage
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
	frame_costs.stage = &"candidates"
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
		var defense_role = _defense.role(id)
		if task.has("overwatch_for"):
			var has_inspector := false
			for other in _tasks:
				if other != id and _tasks[other].get("role") == &"search" and Support.covers(task, _tasks[other]) and _tasks[other].state != &"complete": has_inspector = true
			must_replan = must_replan or not has_inspector
		if task.has("overwatch_for") and Contract.horizontal(_bodies[id].position, task.position) < 0.18:
			var peer = _context(id)
			if not preload("res://scripts/enemy/services/enemy_visual_observation.gd").clear_from(peer, peer.actor.get_eye_position(), task.look_position):
				task.state = &"blocked"
				task.reason = &"overwatch_obstructed"
		must_replan = must_replan or not defense_role.is_empty() and task.role != defense_role
		must_replan = must_replan or task.role == &"guard" or task.state == &"blocked" or (task.state == &"complete" and not _waiting_for_search_peers(id)) or task.expires_at <= elapsed or task.objective_id != _objective.objective_id
		must_replan = must_replan or task.has("barrier_id") and not _barriers.has(task.barrier_id)
		must_replan = must_replan or task.get("coverage_version", _search.coverage.map_version) != _search.coverage.map_version
		if _objective.phase == &"contact":
			if not _bodies[id].firearms and not _bodies[id].occupied and task.role in [&"engage", &"flank"]:
				var remaining := Traffic.remaining(_bodies[id].position, task.route)
				var length: float = _context(id).cover_selection._path_length_from_path(remaining)
				var executor := Combat.contact_executor(_profiles[id], _bodies[id], task.role, length, _objective.position)
				must_replan = must_replan or not executor.is_empty() and executor != task.action
			must_replan = must_replan or (_bodies[id].visible == false and task.role in [&"engage", &"support", &"flank"] and task.state == &"executing" and Contract.horizontal(_bodies[id].position, task.position) < 0.15)
			must_replan = must_replan or (_bodies[id].firearms and _bodies[id].visible and not _bodies[id].fire_lane_valid and task.role in [&"engage", &"support", &"flank"] and Contract.horizontal(_bodies[id].position, task.position) < 0.15)
			must_replan = must_replan or not defense_role.is_empty() and task.role != defense_role
			must_replan = must_replan or _bodies[id].firearms and _bodies[id].visible and Contract.horizontal(_bodies[id].position, _objective.position) < 3.0 and Contract.horizontal(task.position, _objective.position) < 3.0
		must_replan = must_replan or defense_role.is_empty() and _bodies[id].can_reload and _bodies[id].rounds == 0 and task.role != &"reload"
	if not must_replan: return
	if _preparation.has("solution"):
		_finish_plan(Time.get_ticks_usec() + 2500)
		return
	if _preparation.is_empty():
		var sites = Formation.sites(context, _objective, _bodies.size(), _attempt)
		if _objective.phase == &"patrol" and not sites.is_empty() and sites.all(func(site): return _patrol_visits.has(site.site_key)):
			_patrol_visits.clear()
		_preparation = {"members": _bodies.keys(), "index": 0, "candidates": {}, "sites": sites, "map_revision": map_revision,
			"objective_id": _objective.objective_id, "started_at": elapsed}
	var id = _preparation.members[_preparation.index]
	if not _bodies.has(id):
		_preparation.clear()
		return
	var deadline = Time.get_ticks_usec() + 2500
	if not _preparation.has("work"): _preparation.work = _member_work(id)
	var work: Dictionary = _preparation.work
	var candidates: Array[Dictionary] = work.candidates
	if not work.defense_ready:
		var defense := _defense.prepare_candidates(_context(id), _profiles[id], _bodies[id], _objective, work.proactive, deadline)
		if not defense.ready:
			_due = elapsed
			return
		candidates.append_array(defense.candidates)
		work.defense_ready = true
	while work.cursor < work.sites.size() and candidates.size() < 6:
		if Time.get_ticks_usec() >= deadline:
			_due = elapsed
			return
		var site: Dictionary = work.sites[work.cursor]
		work.cursor += 1
		if _recent_inspection(site, map_revision) or _failed_sites.get([id, site.site_key], -INF) > elapsed: continue
		if _objective.phase == &"patrol" and _patrol_visits.has(site.site_key): continue
		if _objective.phase == &"contact" and not site.has("role"): site.role = _contact_role(id)
		# A physical box has four bounded bypass alternatives. Test them on
		# successive budget slots instead of hiding all four inside one query.
		if not site.has("detour_variant"): site.detour_variant = 0
		var candidate = Formation.candidate(_context(id), _profiles.get(id, {}), _bodies[id], site, _objective, _tasks[id])
		if candidate.get("retry_detour", false):
			var retry := site.duplicate(true)
			retry.detour_variant += 1
			work.sites.append(retry)
			continue
		if not candidate.is_empty():
			if candidate.has("overwatch_for"):
				candidate.supported_sites = Support.covered_sites(_context(id), candidate, _preparation.sites)
				if candidate.supported_sites.is_empty(): continue
			if candidate.has("coverage_key"):
				_search.routes.extend(_context(id), candidate, _search.coverage, work.sites, deadline)
			candidates.append(candidate)
	_preparation.erase("work")
	# Every member can keep a validated holding post while a teammate reloads
	# or completes the remaining search points; one impossible route must not
	# prevent all other work from being committed.
	var hold = _holding(id, &"no_reachable_post")
	hold.estimate = 40.0
	candidates.append(hold)
	_preparation.candidates[id] = candidates
	_preparation.index += 1
	if _preparation.index < _preparation.members.size():
		_due = elapsed # Continue bounded preparation on the next area tick.
		return
	_preparation.solution = _planner.begin({"members": _bodies, "profiles": _profiles, "template": _template,
		"objective": _objective, "candidates": _preparation.candidates, "synchronize_search": _synchronize_search()})
	_finish_plan(deadline)

func _recent_inspection(site: Dictionary, map_revision: int) -> bool:
	if site.has("coverage_key"): return false
	var record: Dictionary = _covered.get(site.site_key, {})
	if record.is_empty() or record.get("map_revision", -1) != map_revision: return false
	# A hint changes priorities, not the fact that this exact hiding patch was
	# just inspected. Different faces/geometry and genuinely old checks compete.
	return record.position.distance_to(site.look_position) < 0.25 and elapsed - float(record.observed_at) < _search.coverage.REVISIT_SECONDS

func _finish_plan(deadline: int) -> void:
	frame_costs.stage = &"combinations"
	var result := _planner.advance(_preparation.solution, deadline)
	if not result.ready:
		_due = elapsed
		return
	planning_count += 1
	_reason = result.reason
	_preparation.clear()
	if result.complete and result.tasks.values().any(func(task): return task.role != &"guard"):
		frame_costs.stage = &"commit"
		if not _commit(result.tasks, result.traffic):
			_last_replan = &"commit_revalidation_failed"
			_attempt += 1
	else:
		_attempt += 1
		# Exhaust the first bounded geometry alternatives on subsequent area
		# ticks before backing off; failed preparation is not useful waiting.
		if _attempt <= 3: _due = elapsed
		# Unreachable remaining sites do not prevent the next patrol round.
		# Clearing visits never marks those sites as physically visited.
		if _objective.phase == &"patrol": _patrol_visits.clear()
		_last_replan = result.reason
		frame_costs.stage = &"repair"
		if not _repair_traffic(result.get("attempted", {})):
			for task in _tasks.values():
				task.reason = &"retry_other_posts"
				task.check_at = elapsed + Contract.PERIOD

func _member_work(id: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var body: Dictionary = _bodies[id]
	var context = _context(id)
	var sites: Array = _preparation.sites.duplicate(true)
	if _objective.phase == &"contact": sites = Combat.sites(context, _profiles[id], body, _objective, _bodies, _profiles)
	if _objective.phase == &"search":
		# A completed route can continue into its prepared future, after checking
		# current coverage and revalidating navigation through normal candidates.
		var future: Array = _tasks[id].get("future_steps", [])
		for index in range(future.size() - 1, -1, -1):
			var step: Dictionary = future[index]
			if step.get("coverage_version") == _search.coverage.map_version and not _search.coverage.unfinished(step.coverage_key, elapsed).is_empty(): sites.push_front(step.duplicate(true))
		sites.append_array(_search.sites(body.position, elapsed, id))
		var recovery_site := _support.recovery_site(id, body, _objective, elapsed, context)
		if not recovery_site.is_empty(): sites.push_front(recovery_site)
	if _objective.phase == &"contact" and body.visible and (not body.firearms or body.fire_lane_valid and Contract.horizontal(body.position, _objective.position) >= 3.0):
		sites.push_front({"position": body.position, "look_position": _objective.position, "site_key": "contact:%s" % id})
	var needs_reload: bool = body.reloading or body.rounds == 0 and body.can_reload
	if needs_reload: sites = [{"position": body.position, "look_position": _objective.position, "site_key": "reload:%s" % id}]
	var previous: Dictionary = _tasks[id]
	var defense_role = _defense.role(id)
	if _objective.phase == &"search" and previous.has("overwatch_for") and previous.state != &"blocked" and previous.expires_at > elapsed and previous.get("search_revision") == _objective.get("search_revision") and not needs_reload:
		var inspecting := false
		for other in _tasks:
			if other != id and Support.covers(previous, _tasks[other]) and _tasks[other].state != &"complete": inspecting = true
		if inspecting:
			var continuing := previous.duplicate(true)
			continuing.route = Traffic.remaining(body.position, previous.route)
			continuing.estimate = 0.0
			candidates.append(continuing)
	if _objective.phase == &"contact" and defense_role.is_empty() and not needs_reload and previous.role in [&"engage", &"support", &"flank"] and previous.state != &"blocked" and previous.expires_at > elapsed:
		var valid: bool = body.visible and body.fire_lane_valid and Contract.horizontal(body.position, _objective.position) >= 3.0 if body.firearms else Combat.melee_post_valid(context, _profiles[id], previous.position, _objective.position, 0.08)
		if valid and not body.firearms and not body.occupied:
			var length: float = context.cover_selection._path_length_from_path(Traffic.remaining(body.position, previous.route))
			valid = Combat.contact_executor(_profiles[id], body, previous.role, length, _objective.position) == previous.action
		if valid:
			var continuing := previous.duplicate(true)
			continuing.route = Traffic.remaining(body.position, previous.route)
			continuing.objective_id = _objective.objective_id
			continuing.look_position = _objective.position
			continuing.estimate = 0.0
			candidates.append(continuing)
	if _objective.phase == &"contact" and defense_role.is_empty() and not needs_reload:
		# Defaults remain preferences. A qualified visible member can replace a
		# blind support slot; unseen members continue to a real firing position.
		var roles: Array[StringName] = [_contact_role(id)]
		for role: StringName in [&"engage", &"support", &"flank"]:
			if role == &"support" and (not body.visible or body.rounds <= 0): continue
			if not roles.has(role) and not Contract.executor(_profiles[id], role).is_empty(): roles.append(role)
		var expanded: Array = []
		# Spatial alternatives must enter the bounded pool before multiple role
		# labels of the same point consume every slot.
		for role in roles:
			for site in sites:
				var variant: Dictionary = site.duplicate(true)
				variant.role = role
				variant.role_cost = 0.0 if role == _contact_role(id) else 0.35
				expanded.append(variant)
		sites = expanded
	if not defense_role.is_empty():
		sites.clear()
	var holding_peers = previous.state == &"complete" and _waiting_for_search_peers(id)
	if defense_role.is_empty() and previous.role in [&"patrol", &"search"] and not needs_reload and (not previous.state in [&"blocked", &"complete"] or holding_peers) and previous.expires_at > elapsed and previous.get("coverage_version", _search.coverage.map_version) == _search.coverage.map_version:
		# Keep unfinished legs and completed posts still needed by this group.
		var continuing = previous.duplicate(true)
		continuing.route = Traffic.remaining(body.position, previous.route)
		if previous.role == &"search" and Traffic.approach(continuing).is_empty(): continuing.staging_position = body.position
		continuing.estimate = 0.0
		candidates.append(continuing)
	if defense_role.is_empty() and previous.has("resume_task") and previous.state == &"complete" and _passage_cleared(previous):
		var resume: Dictionary = previous.resume_task
		var path = Formation.route(context, resume.position)
		if not path.is_empty():
			resume = resume.duplicate(true)
			resume.route = path
			resume.estimate = 0.0
			candidates.append(resume)
	return {"candidates": candidates, "sites": sites, "cursor": 0,
		"defense_ready": defense_role.is_empty() and (_objective.phase != &"contact" or needs_reload), "proactive": defense_role.is_empty()}

func _contact_role(id: int) -> StringName:
	if not _defense.role(id).is_empty(): return _defense.role(id)
	var role: StringName = _template.get("contact_roles", {}).get(id, &"engage")
	if _bodies.size() == 1: role = &"engage"
	if not Contract.executor(_profiles[id], &"support").is_empty():
		for other in _bodies:
			if other != id and (_bodies[other].reloading or _bodies[other].rounds == 0 and _bodies[other].can_reload or not _defense.role(other).is_empty()): return &"support"
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
	var traffic = Traffic.plan(routes, _bodies, _synchronize_search())
	if not traffic.valid: return false
	if not Support.acyclic(routes, traffic): return false
	var table = {}
	for id in routes:
		if not _bodies.has(id) or not _profiles.has(id): return false
		var proposal: Dictionary = routes[id]
		if not _context(id).validate_command_post(proposal, _profiles[id]): return false
		var old: Dictionary = _tasks.get(id, {})
		var same_staging: bool = proposal.role != &"search" or old.get("staging_position", Vector3.INF) == proposal.get("staging_position", Vector3.INF)
		if same_staging and old.get("search_revision", 0) == proposal.get("search_revision", 0) and old.get("objective_id") == proposal.objective_id and old.get("role") == proposal.role and old.get("action") == proposal.action and old.get("position", Vector3.INF).distance_to(proposal.position) < 0.05 and old.expires_at > elapsed and (not old.state in [&"blocked", &"complete"] or old.state == &"complete" and _waiting_for_search_peers(id)):
			table[id] = old.duplicate(true)
		else:
			table[id] = _new_task(id, proposal)
			table[id].version = _version + 1
			table[id].expires_at = elapsed + maxf(Contract.TASK_SECONDS, float(proposal.get("travel_seconds", 0.0)) + 4.0)
		table[id].waiting_for = traffic.get("dependencies", {}).get(id, []).duplicate()
		table[id].preparation_waiting_for = traffic.get("preparation_dependencies", {}).get(id, []).duplicate()
		if not traffic.get("synchronized_members", []).has(id): table[id].erase("barrier_id")
		table[id].map_revision = _last_map_revision
	if not environment.commit_squad_reservations(self, table): return false
	for key in _barriers.keys():
		for id in _barriers[key].members:
			if not table.has(id) or not Contract.same_task(table[id], _tasks.get(id, {})):
				_barriers.erase(key)
				break
	_version += 1
	_tasks = table
	_support.install(table, _profiles, elapsed)
	_search.coverage.reserve(table)
	for id in table: _defense.accept(id, table[id])
	for participants in traffic.get("synchronized_groups", []): _install_barrier(participants)
	for id in table:
		_progress[id] = {"position": _bodies[id].position, "at": elapsed}
	_last_replan = &"complete_plan"
	return true

func _synchronize_search() -> bool:
	return int(configuration.get("level", 0)) == 2 and _objective.get("phase") == &"search"

func _waiting_for_search_peers(id: int) -> bool:
	var barrier: Dictionary = _barriers.get(_tasks[id].get("barrier_id", 0), {})
	if barrier.is_empty(): return false
	for other in barrier.members:
		if other != id and _tasks.has(other) and _tasks[other].state != &"complete": return true
	return false

func _install_barrier(participants: Array) -> void:
	if not _synchronize_search() or participants.size() < 2: return
	for barrier in _barriers.values():
		if barrier.members.size() == participants.size() and participants.all(func(id): return barrier.members.has(id)): return
	# Every searcher in this step participates, including a follower in the
	# same lane. Reloading or unrelated fire providers are not participants.
	var key = environment.allocate_coordination_id()
	_barriers[key] = {"members": participants, "ready": {}, "waited": {}, "released": false, "started_at": elapsed}
	for id in participants: _tasks[id].barrier_id = key

func _update_progress() -> void:
	for id in _tasks:
		var task: Dictionary = _tasks[id]
		var body: Dictionary = _bodies[id]
		var old: Dictionary = _progress.get(id, {"position": body.position, "at": elapsed})
		if Contract.horizontal(old.position, body.position) > 0.08:
			old = {"position": body.position, "at": elapsed}
		_progress[id] = old
		if task.get("reason") in [&"staging_barrier", &"step_replanning", &"formation_gap", &"support_preparing", &"support_replanning"]:
			_progress[id].at = elapsed
			continue
		if Contract.horizontal(body.position, task.position) <= 0.12 or body.occupied: continue
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
					var via: Vector3 = Vector3.INF
					if _synchronize_search() and table[other].role == &"search":
						if _barriers.get(table[other].get("barrier_id", 0), {}).get("released", false): table[other].staging_position = _bodies[other].position
						via = table[other].staging_position
					var path = Formation.route(_context(other), table[other].position, via)
					if not path.is_empty(): table[other].route = path
				var traffic = Traffic.plan(table, _bodies, _synchronize_search())
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
	# A stale executor tick cannot revive a post the coordinator invalidated
	# earlier in this area tick. Only a newly committed task clears failure.
	if task.state == &"blocked" and report.state != &"blocked": return false
	# Observed completion is monotonic until the coordinator replaces the task.
	# A later idle tick or a passing body must not restart the finished leg.
	if task.state == &"complete" and report.state in [&"executing", &"waiting"]: return true
	if report.state == &"complete" and not task.accepted: return false
	if report.state == &"complete" and task.role in [&"patrol", &"move"] and Contract.horizontal(context.actor.global_position, task.position) > 0.18: return false
	if report.state == &"complete" and task.role in [&"shelter", &"cover_peek"] and Contract.horizontal(context.actor.global_position, task.position) > 0.18: return false
	if report.state == &"complete" and task.role == &"search":
		if not observation_progress(context, task).get("complete", false): return false
	_feedback[id] = report.duplicate(true)
	task.state = report.state
	task.reason = report.get("reason", &"")
	task.progress = report.get("progress", 0.0)
	if report.state == &"complete":
		if task.role == &"search":
			_covered[task.site_key] = {"position": task.look_position, "observed_at": elapsed, "member_id": id,
				"map_revision": context.coordination_search_revision()}
			if _waiting_for_search_peers(id): task.reason = &"search_peers"
		elif task.role == &"patrol":
			_patrol_visits[task.site_key] = {"position": task.position, "visited_at": elapsed, "member_id": id}
		_due = 0.0
	elif report.state == &"blocked":
		_failed_sites[[id, task.site_key]] = elapsed + 4.0
		if task.role == &"search": _search.reject(task.site_key, elapsed)
		_due = 0.0
	return true

func motion_permission(context, token: Dictionary) -> Dictionary:
	var id: int = context.actor.get_instance_id()
	if not Contract.same_task(token, _tasks.get(id, {})): return {"allowed": false, "reason": &"replaced", "waiting_for": []}
	var bodies = {}
	for member in _tasks:
		var peer = _context(member)
		if peer != null and is_instance_valid(peer.actor) and not peer.actor.is_dead: bodies[member] = peer.member_runtime_snapshot()
	var task: Dictionary = _tasks[id]
	var motion_tasks = _tasks
	var support_permission := _support.permission(id, task, bodies[id].position)
	if not support_permission.is_empty(): return support_permission
	var hurry := false
	for peer in _feedback:
		if peer != id and Contract.same_task(_feedback[peer], _tasks.get(peer, {})) and _feedback[peer].get("state") == &"waiting" and _feedback[peer].get("waiting_for", []).has(id): hurry = true
	var dependencies: Array = task.waiting_for
	# Unrelated fire providers also share the preparation traffic transaction.
	# Using departure dependencies for them while inspectors use arrival
	# dependencies can create a wait cycle absent from either validated plan.
	var preparing: Array = []
	for pending in _barriers.values():
		if not pending.released: preparing.append_array(pending.members)
	if not preparing.is_empty():
		motion_tasks = _tasks.duplicate(true)
		for member in preparing:
			motion_tasks[member].route = Traffic.approach(_tasks[member])
			motion_tasks[member].position = _tasks[member].staging_position
		dependencies = task.get("preparation_waiting_for", [])
	var barrier_id = task.get("barrier_id", 0)
	if barrier_id != 0 and not _barriers.has(barrier_id):
		return {"allowed": false, "reason": &"step_replanning", "waiting_for": [], "members": bodies.keys()}
	if _barriers.has(barrier_id):
		var barrier: Dictionary = _barriers[barrier_id]
		if not barrier.released:
			barrier.ready.clear()
			for member in barrier.members:
				if bodies.has(member) and _tasks[member].accepted and _tasks[member].state != &"blocked" and _tasks[member].expires_at > elapsed and not bodies[member].occupied and not bodies[member].reloading and Contract.horizontal(bodies[member].position, _tasks[member].staging_position) <= 0.12:
					barrier.ready[member] = true
			if barrier.ready.size() == barrier.members.size():
				barrier.released = true
				barrier_release_count += 1
		if not barrier.released and Contract.horizontal(bodies[id].position, task.staging_position) <= 0.12:
			if not barrier.waited.has(id):
				barrier.waited[id] = true
				barrier_wait_count += 1
			var awaiting = barrier.members.filter(func(member): return not barrier.ready.has(member))
			return {"allowed": false, "waiting_for": awaiting, "reason": &"staging_barrier", "members": bodies.keys()}
		if not barrier.released:
			hurry = hurry or not barrier.ready.is_empty()
	var waiting: Array = Traffic.blockers(id, motion_tasks, bodies)
	for other in dependencies:
		if not _tasks.has(other) or not bodies.has(other): continue
		var path = Traffic.prefix(Traffic.remaining(bodies[id].position, motion_tasks[id].route), 1.4)
		# A scheduled follower must not enter its next crossing before the
		# predecessor passes it. Comparing two short prefixes lets the follower
		# park inside a later section of the predecessor's route and deadlock.
		# Only this member's next 1.4m is gated, only for assigned predecessors.
		var other_path = Traffic.remaining(bodies[other].position, motion_tasks[other].route)
		var clearance: float = bodies[id].radius + bodies[other].radius + maxf(bodies[id].spacing_margin, bodies[other].spacing_margin)
		if Traffic.conflicts(path, other_path, clearance) and not waiting.has(other): waiting.append(other)
	if not waiting.is_empty(): traffic_wait_count += 1
	var cohesion := Traffic.cohesion(id, _tasks, bodies) if _synchronize_search() else {"speed_scale": 1.0}
	if waiting.is_empty() and float(cohesion.speed_scale) <= 0.01:
		return {"allowed": false, "waiting_for": cohesion.get("waiting_for", []), "reason": &"formation_gap", "speed_scale": 0.0}
	return {"allowed": waiting.is_empty(), "waiting_for": waiting, "reason": &"occupied_corridor" if not waiting.is_empty() else &"", "members": bodies.keys(), "speed_scale": cohesion.speed_scale, "hurry": hurry}

func debug_member_snapshot(context) -> Dictionary:
	var task = assignment(context)
	var future := PackedVector3Array()
	for step in task.get("future_steps", []): future.append_array(step.route)
	return {"source": &"squad" if not task.is_empty() else &"personal", "task": task,
		"coverage_owner": get_instance_id(),
		"next_route": future, "observation_direction": -context.actor.global_basis.z,
		"objective": _objective.duplicate(true), "template": _template.duplicate(true),
		"profile": _profiles.get(context.actor.get_instance_id(), {}).duplicate(true),
		"support": _support.snapshot(context.actor.get_instance_id()),
		"defense": _defense.requests.get(context.actor.get_instance_id(), {}).duplicate(true), "pressure": context.recent_damage_pressure + context.nearby_shot_pressure,
		"route": Traffic.remaining(context.actor.global_position, task.get("route", PackedVector3Array())) if not task.is_empty() and task.state != &"complete" else PackedVector3Array(), "target_position": task.get("position", Vector3.INF),
		"staging_position": task.get("staging_position", Vector3.INF), "goal": task.get("position", Vector3.INF),
		"waiting_for": _feedback.get(context.actor.get_instance_id(), {}).get("waiting_for", []).duplicate(),
		"phase": _objective.get("phase", &"patrol"), "state": task.get("state", &"pending"),
		"reason": task.get("reason", _reason), "planning_reason": _reason, "last_replan": _last_replan,
		"plan_version": _version, "covered": _covered.duplicate(true), "search": _search.snapshot(elapsed), "patrol_visits": _patrol_visits.duplicate(true), "barriers": _barriers.duplicate(true)}

func coverage_debug_snapshot() -> Dictionary:
	return _search.snapshot(elapsed, true)

func member_ids() -> Array:
	return _tasks.keys()

func support_demand(context) -> float:
	var task := assignment(context)
	if task.get("role") != &"support" or task.expires_at <= elapsed or not context.sees_player: return 0.0
	for id in _support.beneficiaries(context.actor.get_instance_id(), _tasks):
		if id == context.actor.get_instance_id(): continue
		var peer = _context(id)
		if peer == null or peer.actor.is_dead: continue
		if not environment.can_share_intel(id, context.actor.get_instance_id()): continue
		if peer.actor.ammo.is_reloading or not _defense.role(id).is_empty(): return 1.0
		var moving: Dictionary = _tasks[id]
		if moving.role in [&"engage", &"flank"] and moving.state != &"blocked" and peer.actor.get_local_movement_velocity().length() > 0.1 and Contract.horizontal(peer.actor.global_position, moving.position) > 0.5: return 1.0
	return 0.0
