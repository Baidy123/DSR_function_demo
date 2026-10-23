extends RefCounted

## Whole-team assignment over coordinator-requested, locally validated posts.
## No personal candidates, Utility scores, scene access or tactical authority.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const MAX_COMBINATIONS := 256

func propose(snapshot: Dictionary) -> Dictionary:
	return advance(begin(snapshot), 9223372036854775807)

func begin(snapshot: Dictionary) -> Dictionary:
	snapshot = snapshot.duplicate(true)
	var ids: Array = snapshot.members.keys()
	ids.sort_custom(func(a, b): return snapshot.candidates.get(a, []).size() < snapshot.candidates.get(b, []).size())
	for candidates in snapshot.candidates.values(): candidates.sort_custom(func(a, b): return float(a.estimate) < float(b.estimate))
	return {"snapshot": snapshot, "ids": ids, "stack": [{"index": 0, "selected": {}, "cost": 0.0}],
		"trials": 0, "nodes": 0, "best": {}, "attempted": {}, "cost": INF, "traffic": {}, "reason": &"no_complete_layout"}

## Resume the same full-team search when the area budget is exhausted. Bodies
## and all route conflicts are rechecked by the coordinator before commitment.
func advance(work: Dictionary, deadline: int) -> Dictionary:
	var snapshot: Dictionary = work.snapshot
	var ids: Array = work.ids
	while not work.stack.is_empty() and work.trials < MAX_COMBINATIONS and work.nodes < 2048:
		if Time.get_ticks_usec() >= deadline: return {"ready": false}
		var node: Dictionary = work.stack.pop_back()
		work.nodes += 1
		if node.cost >= work.cost: continue
		if node.index == ids.size():
			work.trials += 1
			var cost: float = node.cost + _team_cost(snapshot, node.selected)
			if cost >= work.cost: continue
			var traffic = Traffic.plan(node.selected, snapshot.members, snapshot.get("synchronize_search", false))
			if work.attempted.is_empty(): work.attempted = node.selected.duplicate(true)
			if not traffic.valid: continue
			work.best = node.selected.duplicate(true)
			work.cost = cost
			work.traffic = traffic
			work.reason = &"complete_layout"
			continue
		var id = ids[node.index]
		var candidates: Array = snapshot.candidates.get(id, [])
		for index in range(candidates.size() - 1, -1, -1):
			var candidate: Dictionary = candidates[index]
			if not _eligible(snapshot, id, candidate, node.selected): continue
			var selected: Dictionary = node.selected.duplicate()
			selected[id] = candidate
			work.stack.append({"index": node.index + 1, "selected": selected, "cost": node.cost + float(candidate.estimate)})
	return {"tasks": work.best, "traffic": work.traffic, "cost": work.cost,
		"ready": true, "trials": work.trials, "reason": work.reason, "attempted": work.attempted, "complete": work.best.size() == ids.size() and not ids.is_empty()}

func _team_cost(snapshot: Dictionary, tasks: Dictionary) -> float:
	if snapshot.get("objective", {}).get("phase") == &"search":
		var entrances := {}
		for task in tasks.values():
			var key: String = task.get("sync_key", "")
			if key.is_empty(): continue
			var side: int = task.get("side", 0)
			var group: Dictionary = entrances.get(key, {})
			group[side] = int(group.get(side, 0)) + 1
			entrances[key] = group
		var repeated := 0.0
		for group in entrances.values():
			for count in group.values(): repeated += maxf(0.0, float(count) - 2.0) * 5.0
		return repeated
	if snapshot.get("objective", {}).get("phase") != &"contact": return 0.0
	var available := false
	var retained := false
	for id in tasks:
		var body: Dictionary = snapshot.members[id]
		if not body.get("visible", false) or not body.get("can_attack", false) or body.get("rounds", 0) <= 0: continue
		available = true
		if tasks[id].role in [&"engage", &"support", &"flank", &"cover_peek"]: retained = true
	# Keep useful fire while other members investigate or shelter. Pressure can
	# still require everyone to retreat when no qualified firing plan exists.
	return 8.0 if available and not retained else 0.0

func _eligible(snapshot: Dictionary, id: int, candidate: Dictionary, selected: Dictionary) -> bool:
	# The scene-independent template is an input constraint, not a label.
	var qualified = false
	for slot in snapshot.template.roles.get(candidate.role, []):
		if slot.member_id == id and slot.action == candidate.action: qualified = true
	if not qualified: return false
	var clear = true
	for other in selected:
		var gap: float = snapshot.members[id].radius + snapshot.members[other].radius + maxf(snapshot.members[id].spacing_margin, snapshot.members[other].spacing_margin)
		if Contract.horizontal(candidate.position, selected[other].position) < gap:
			clear = false
			break
		if candidate.has("coverage_key") and candidate.get("coverage_key") == selected[other].get("coverage_key"):
			clear = false
			break
		# A final body cannot occupy an ally's proposed live muzzle corridor.
		if candidate.get("tactical", {}).get("sustainable_fire", false) and candidate.has("look_position"):
			if Traffic.distance_to_path(selected[other].position, PackedVector3Array([candidate.position, candidate.look_position])) < snapshot.members[other].radius + 0.1:
				clear = false
				break
		if selected[other].get("tactical", {}).get("sustainable_fire", false) and selected[other].has("look_position"):
			if Traffic.distance_to_path(candidate.position, PackedVector3Array([selected[other].position, selected[other].look_position])) < snapshot.members[id].radius + 0.1:
				clear = false
				break
	return clear
