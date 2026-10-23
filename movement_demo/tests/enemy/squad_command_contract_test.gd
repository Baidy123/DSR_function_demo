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
	print("SQUAD COMMAND CONTRACT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _post(start: Vector3, goal: Vector3, cost: float) -> Dictionary:
	return {"role": &"engage", "action": &"engage", "position": goal, "route": PackedVector3Array([start, goal]), "estimate": cost}
