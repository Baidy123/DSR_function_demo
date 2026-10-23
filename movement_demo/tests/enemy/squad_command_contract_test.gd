extends SceneTree

## Small pure boundary check alongside the saved-map runtime, not a mock of
## perception, acceptance, or body movement in the gameplay tests.
const Planner = preload("res://scripts/enemy/services/enemy_team_planner.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
var checks = 0
var failures = 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _initialize() -> void:
	var bodies = {}
	var profiles = {}
	for id in [1, 2, 3]:
		bodies[id] = {"position": Vector3(float(id - 1) * 3.0, 0, 0), "radius": 0.35, "spacing_margin": 0.45}
		profiles[id] = {"profile_id": str(id), "actions": {&"engage": {"roles": [&"engage", &"guard", &"move"], "basis": "contract_fixture"}}}
	var candidates = {
		1: [_post(bodies[1].position, bodies[2].position, 1.0), _post(bodies[1].position, Vector3(0, 0, 3), 4.0)],
		2: [_post(bodies[2].position, bodies[1].position, 1.0), _post(bodies[2].position, Vector3(3, 0, 3), 4.0)],
		3: [_post(bodies[3].position, Vector3(6, 0, 3), 1.0)]}
	var cyclic = {1: candidates[1][0], 2: candidates[2][0], 3: candidates[3][0]}
	check(not Traffic.schedule(cyclic, bodies).valid, "A complete swap cycle is rejected despite distinct destinations")
	var snapshot = {"members": bodies, "profiles": profiles, "template": Contract.template(profiles, 1), "candidates": candidates}
	var planner = Planner.new()
	var result = planner.propose(snapshot)
	check(result.complete and result.tasks.size() == 3 and result.traffic.order.size() == 3, "Global alternatives resolve the entire team instead of accepting one greedy departure")
	check(result.cost > 3.0 and result.trials <= Planner.MAX_COMBINATIONS, "The cheapest blocked layout is rejected within the finite search budget")
	var pending := planner.begin(snapshot)
	check(not planner.advance(pending, 0).ready and planner.advance(pending, 9223372036854775807).tasks == result.tasks, "An exhausted budget preserves the exact pending whole-team search")
	var isolated = result.duplicate(true)
	isolated.tasks.clear()
	check(planner.propose(snapshot).tasks.size() == 3, "Proposal consumers cannot mutate planner inputs or later outputs")
	var forbidden = candidates.duplicate(true)
	for candidate in forbidden[1]: candidate.role = &"support"
	snapshot.candidates = forbidden
	check(not planner.propose(snapshot).complete, "The actual template excludes an untrained role even when its geometry is legal")
	var crowded = PackedVector3Array([Vector3.ZERO, Vector3(-0.5, 0, 0), Vector3(0, 0, 3)])
	check(not Traffic._leaves_crowding(crowded, Vector3(-0.7, 0, 0), 1.15), "Escaping initial crowding cannot first cross a neighbour's body")
	var pair = {1: bodies[1], 3: bodies[3]}
	var staged = {
		1: {"role": &"search", "position": Vector3(3, 0, 3), "staging_position": Vector3(3, 0, 0), "look_position": Vector3(3, 0, 4), "route": PackedVector3Array([Vector3.ZERO, Vector3(3, 0, 0), Vector3(3, 0, 3)])},
		3: {"role": &"search", "position": Vector3(6, 0, 3), "staging_position": Vector3(3, 0, 0), "look_position": Vector3(6, 0, 4), "route": PackedVector3Array([Vector3(6, 0, 0), Vector3(3, 0, 0), Vector3(6, 0, 3)])}}
	for task in staged.values(): task.sync_key = "shared_cover"
	check(Traffic.schedule(staged, pair).valid and not Traffic.plan(staged, pair, true).valid, "Distinct final posts cannot conceal colliding preparation posts")
	staged[3].staging_position = Vector3(6, 0, 1.5)
	staged[3].route = PackedVector3Array([Vector3(6, 0, 0), staged[3].staging_position, staged[3].position])
	check(Traffic.plan(staged, pair, true).valid, "Separate preparation and departure routes allow a real shared rendezvous")
	staged[1].look_position = staged[3].position
	check(not Traffic.plan(staged, pair, true).valid, "A parked teammate cannot block a required observation line")
	for task in staged.values(): task.sync_key = ""
	check(Traffic.plan(staged, pair, true).get("synchronized_members", []).is_empty(), "Independent area routes do not acquire an unrelated cover barrier")
	var bent = Traffic.prefix(PackedVector3Array([Vector3.ZERO, Vector3(0.2, 0, 0), Vector3(0.2, 0, 5)]), 1.4)
	check(bent.size() == 3 and absf(bent[-1].z - 1.2) < 0.001, "Local traffic horizon follows bends without reserving the full long route")
	var column_bodies := {1: {"position": Vector3(6, 0, 0)}, 2: {"position": Vector3.ZERO}}
	var column := {1: {"role": &"search", "route": PackedVector3Array([Vector3(6, 0, 0), Vector3(10, 0, 0)])},
		2: {"role": &"search", "route": PackedVector3Array([Vector3.ZERO, Vector3(8, 0, 0)])}}
	check(Traffic.cohesion(1, column, column_bodies).speed_scale < 1.0 and Traffic.cohesion(2, column, column_bodies).speed_scale == 1.0, "Continuous column slows its leader while the following member catches up")
	column_bodies[2].position = Vector3(3, 0, 0)
	check(Traffic.cohesion(1, column, column_bodies).speed_scale == 1.0, "A closed formation gap releases the leader without a point barrier")
	column[2].role = &"reload"
	column_bodies[2].position = Vector3(-3, 0, 0)
	check(Traffic.cohesion(1, column, column_bodies).speed_scale == 1.0, "Reloading members do not acquire an unrelated movement barrier")
	_search_roles(planner, bodies)
	_combat_roles(planner)
	_support_contract()
	print("SQUAD COMMAND CONTRACT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _post(start: Vector3, goal: Vector3, cost: float) -> Dictionary:
	return {"role": &"engage", "action": &"engage", "position": goal, "route": PackedVector3Array([start, goal]), "estimate": cost}

func _search_roles(planner, bodies: Dictionary) -> void:
	var profiles := {}
	var candidates := {}
	for id in bodies:
		profiles[id] = {"profile_id": str(id), "actions": {&"fixture": {"roles": [&"search", &"support", &"guard"], "basis": "installed_fixture"}}}
		var inspect := _post(bodies[id].position, bodies[id].position + Vector3(0, 0, 3), 1.0)
		inspect.merge({"action": &"fixture", "role": &"search", "sync_key": "cover:fixture", "side": -1}, true)
		var hold := _post(bodies[id].position, bodies[id].position, 40.0)
		hold.merge({"action": &"fixture", "role": &"guard"}, true)
		candidates[id] = [inspect, hold]
	var opposite: Dictionary = candidates[2][0].duplicate(true)
	opposite.position = Vector3(3, 0, -3)
	opposite.route = PackedVector3Array([bodies[2].position, opposite.position])
	opposite.side = 1
	opposite.estimate = 5.0
	candidates[2].append(opposite)
	var watch := _post(bodies[3].position, Vector3(6, 0, -3), 4.0)
	watch.merge({"action": &"fixture", "role": &"support", "overwatch_for": "cover:fixture", "side": 1}, true)
	candidates[3].append(watch)
	var snapshot := {"members": bodies, "profiles": profiles, "template": Contract.template(profiles, 1), "candidates": candidates, "objective": {"phase": &"search"}}
	var result: Dictionary = planner.propose(snapshot)
	check(result.complete and result.tasks[2].get("side") == 1 and result.tasks[3].has("overwatch_for"), "A longer opposite entrance plus overwatch beats three cheap same-side inspections")
	candidates[2].erase(opposite)
	result = planner.propose(snapshot)
	check(result.complete and result.tasks.values().filter(func(task): return task.role == &"search").size() == 1, "An unavailable opposite entrance reduces inspectors instead of stacking them")
	for id in candidates: candidates[id] = candidates[id].filter(func(task): return task.role != &"search")
	result = planner.propose(snapshot)
	check(result.complete and result.tasks.values().all(func(task): return not task.has("overwatch_for")), "No remaining inspector means no orphaned overwatch assignment")

func _combat_roles(planner) -> void:
	var bodies := {}
	var profiles := {}
	var candidates := {}
	for id in [1, 2]:
		var position := Vector3(-1 if id == 1 else 1, 0, -6)
		bodies[id] = {"position": position, "radius": 0.35, "spacing_margin": 0.45, "visible": true, "fire_lane_valid": true, "can_attack": true, "rounds": 5}
		profiles[id] = {"profile_id": str(id), "firearms": true, "actions": {&"engage": {"roles": [&"engage"], "basis": "installed_fixture"}}}
		var hold := _post(position, position, 0.0)
		hold.look_position = Vector3.ZERO
		hold.tactical = {"sustainable_fire": true}
		candidates[id] = [hold]
	var lateral := _post(bodies[2].position, Vector3(5, 0, -1), 3.0)
	lateral.look_position = Vector3.ZERO
	lateral.tactical = {"sustainable_fire": true}
	candidates[2].append(lateral)
	var snapshot := {"members": bodies, "profiles": profiles, "template": Contract.template(profiles, 1), "candidates": candidates, "objective": {"phase": &"contact", "position": Vector3.ZERO}}
	var result: Dictionary = planner.propose(snapshot)
	check(result.complete and result.tasks[2].position == lateral.position and result.tasks[1].position == bodies[1].position, "A useful crossfire angle justifies one lateral move while retaining the other firing post")
	candidates[2].erase(lateral)
	result = planner.propose(snapshot)
	check(result.complete and result.tasks[1].position == bodies[1].position and result.tasks[2].position == bodies[2].position, "A narrow layout keeps legal fire when no lateral post exists")
	profiles[1].firearms = false
	bodies[1].position = Vector3(0, 0, -4)
	var approach := _post(bodies[1].position, Vector3(0, 0, -1.2), 1.0)
	approach.look_position = Vector3.ZERO
	candidates[1] = [approach]
	var rear := _post(bodies[2].position, Vector3(3, 0, -5), 1.5)
	rear.look_position = Vector3.ZERO
	rear.tactical = {"sustainable_fire": true}
	var exposed := _post(bodies[2].position, Vector3(3, 0, 2), 1.0)
	exposed.look_position = Vector3.ZERO
	exposed.tactical = {"sustainable_fire": true}
	candidates[2] = [exposed, rear]
	result = planner.propose(snapshot)
	check(result.complete and result.tasks[2].position == rear.position, "Mixed plan prefers the rear-side gun position relative to the real melee approach")

func _support_contract() -> void:
	var Support = preload("res://scripts/enemy/services/squad_support.gd")
	var tasks := {}
	var profiles := {1: {"firearms": false}, 2: {"firearms": true, "actions": {&"support": {"roles": [&"support"]}}}}
	for id in [1, 2]:
		var proposal := {"role": &"search" if id == 1 else &"support", "position": Vector3(id, 0, 0), "look_position": Vector3.ZERO,
			"route": PackedVector3Array([Vector3(id, 0, -3), Vector3(id, 0, 0)]), "objective_id": 1, "site_key": str(id), "sync_key": "group" if id == 1 else ""}
		if id == 2: proposal.overwatch_for = "group"
		tasks[id] = Contract.task({"generation": 1, "task_id": id, "version": 1, "member_id": id, "profile_id": str(id)}, proposal, 0.0)
	check(not Support.acyclic(tasks, {"dependencies": {2: [1]}}), "A support provider cannot depend on the inspector waiting for that provider")
	check(Support.acyclic(tasks, {"dependencies": {1: [2]}}), "A valid provider-first crossing remains a complete support plan")
	check(not Support.acyclic(tasks, {"dependencies": {}, "preparation_dependencies": {2: [1]}}), "A preparation-phase traffic cycle cannot hide behind a legal departure order")
	tasks[2].supported_sites = ["opposite_region"]
	check(not Support.covers(tasks[2], tasks[1]), "A shared cover group does not grant support to an unseen responsibility region")
	tasks[2].supported_sites = [tasks[1].site_key]
	var support = Support.new()
	support.install(tasks, profiles, 0.0)
	check(support.links.has(1) and support.beneficiaries(2, tasks) == [1], "Support links bind concrete current task identities in both directions")
	var copy: Dictionary = support.snapshot(1)
	copy.providers.clear()
	check(support.links[1].providers.has(2), "Diagnostic callers cannot erase the live support relationship")
	tasks[1].version += 1
	check(support.beneficiaries(2, tasks).is_empty() and support.permission(1, tasks[1], Vector3.ZERO).is_empty(), "Replaced task identities cannot reuse stale support or waiting permission")
	support.install(tasks, profiles, 1.0)
	support.release(2)
	check(support.beneficiaries(2, tasks).is_empty() and support.links[1].providers.is_empty(), "Member departure removes both provider and beneficiary dependencies")
	support.recovery[1] = {"task": tasks[1].duplicate(true), "until": 4.0}
	var start := Vector3(1, 0, -3)
	var step: Dictionary = support.recovery_site(1, {"position": start}, {"objective_id": 1}, 1.0)
	check(step.sync_key == tasks[1].sync_key and step.via == start and step.look_position == tasks[1].look_position and start.distance_to(step.position) <= 1.401 and not Support.covers(tasks[2], step), "Independent recovery retains the strong rendezvous and observation target while removing failed support")
