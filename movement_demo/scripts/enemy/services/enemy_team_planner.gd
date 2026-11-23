extends RefCounted

## Whole-team assignment over coordinator-requested, locally validated posts.
## No personal candidates, Utility scores, scene access or tactical authority.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const Combat = preload("res://scripts/enemy/services/squad_combat_tactics.gd")
const Support = preload("res://scripts/enemy/services/squad_support.gd")
const Scoring = preload("res://scripts/enemy/services/squad_scoring.gd")
const MAX_COMBINATIONS := 256

func propose(snapshot: Dictionary) -> Dictionary:
	return advance(begin(snapshot), 9223372036854775807)

func begin(snapshot: Dictionary) -> Dictionary:
	snapshot = snapshot.duplicate(true)
	snapshot.scoring = Scoring.weights(snapshot.get("scoring", {}))
	var ids: Array = snapshot.members.keys()
	snapshot.overwatch_groups = {}
	for id in ids:
		for candidate in snapshot.candidates.get(id, []):
			if candidate.has("overwatch_for") and Contract.qualified(snapshot.profiles[id], candidate.action, &"support"):
				snapshot.overwatch_groups[candidate.overwatch_for] = true
	ids.sort_custom(func(a, b): return snapshot.candidates.get(a, []).size() < snapshot.candidates.get(b, []).size())
	for candidates in snapshot.candidates.values():
		for candidate: Dictionary in candidates:
			candidate.planning_cost = Scoring.candidate_cost(candidate, snapshot.scoring)
		candidates.sort_custom(func(a, b): return float(a.planning_cost) < float(b.planning_cost))
	# 原动作允许负偏好分。剪枝必须计入剩余成员的最低分，不能把
	# 当前前缀较贵、但后续收益更大的完整方案提前丢掉。
	var remaining_minimum: Array[float] = []
	remaining_minimum.resize(ids.size() + 1)
	remaining_minimum[ids.size()] = 0.0
	for index in range(ids.size() - 1, -1, -1):
		var options: Array = snapshot.candidates.get(ids[index], [])
		remaining_minimum[index] = remaining_minimum[index + 1] + (float(options[0].planning_cost) if not options.is_empty() else 0.0)
	var holding := {}
	for id in ids:
		for candidate: Dictionary in snapshot.candidates.get(id, []):
			if candidate.role == &"guard":
				holding[id] = candidate
				break
	# Crowded large squads can exhaust every DFS trial on incompatible cheap
	# posts before reaching a safe holding alternative. Establish a feasible
	# full table first, then keep the original global comparison and limits.
	var seed := {"tasks": holding, "started": false, "index": 0, "candidate": 0} if holding.size() == ids.size() else {}
	return {"snapshot": snapshot, "ids": ids, "stack": [{"index": 0, "selected": {}, "cost": 0.0}],
		"remaining_minimum": remaining_minimum, "seed": seed,
		"trials": 0, "nodes": 0, "best": {}, "attempted": {}, "cost": INF, "traffic": {}, "reason": &"no_complete_layout"}

## Resume the same full-team search when the area budget is exhausted. Bodies
## and all route conflicts are rechecked by the coordinator before commitment.
func advance(work: Dictionary, deadline: int) -> Dictionary:
	var snapshot: Dictionary = work.snapshot
	var ids: Array = work.ids
	if not _seed_layout(work, deadline): return {"ready": false}
	while not work.stack.is_empty() and work.trials < MAX_COMBINATIONS and work.nodes < 2048:
		if Time.get_ticks_usec() >= deadline: return {"ready": false}
		var node: Dictionary = work.stack.pop_back()
		work.nodes += 1
		if node.cost + work.remaining_minimum[node.index] >= work.cost: continue
		if node.index == ids.size():
			work.trials += 1
			var cost: float = node.cost + _team_cost(snapshot, node.selected)
			if cost >= work.cost: continue
			var traffic = Traffic.plan(node.selected, snapshot.members, snapshot.get("synchronize_search", false))
			if work.attempted.is_empty(): work.attempted = node.selected.duplicate(true)
			if not traffic.valid: continue
			if not Support.acyclic(node.selected, traffic): continue
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
			work.stack.append({"index": node.index + 1, "selected": selected, "cost": node.cost + float(candidate.planning_cost)})
	if work.best.is_empty() and work.has("holding_fallback"):
		work.best = work.holding_fallback.tasks
		work.traffic = work.holding_fallback.traffic
		work.cost = work.holding_fallback.cost
		work.reason = &"complete_layout"
	return {"tasks": work.best, "traffic": work.traffic, "cost": work.cost,
		"ready": true, "trials": work.trials, "reason": work.reason, "attempted": work.attempted, "complete": work.best.size() == ids.size() and not ids.is_empty()}

func _seed_layout(work: Dictionary, deadline: int) -> bool:
	var seed: Dictionary = work.seed
	if seed.is_empty(): return true
	while work.trials < MAX_COMBINATIONS and work.nodes < 2048:
		if Time.get_ticks_usec() >= deadline: return false
		if not seed.started:
			seed.started = true
			_consider_seed(work, seed.tasks)
			continue
		if seed.index >= work.ids.size(): break
		var id = work.ids[seed.index]
		var options: Array = work.snapshot.candidates.get(id, [])
		if seed.candidate >= options.size():
			seed.index += 1
			seed.candidate = 0
			continue
		var candidate: Dictionary = options[seed.candidate]
		seed.candidate += 1
		if candidate.role == &"guard": continue
		var tasks: Dictionary = seed.tasks.duplicate()
		tasks[id] = candidate
		_consider_seed(work, tasks)
	work.seed = {}
	return true

func _consider_seed(work: Dictionary, tasks: Dictionary) -> void:
	work.trials += 1
	work.nodes += 1
	var selected := {}
	var cost := 0.0
	for id in work.ids:
		if not _eligible(work.snapshot, id, tasks[id], selected): return
		selected[id] = tasks[id]
		cost += float(tasks[id].planning_cost)
	cost += _team_cost(work.snapshot, selected)
	if cost >= work.cost: return
	var traffic := Traffic.plan(selected, work.snapshot.members, work.snapshot.get("synchronize_search", false))
	# Keep a real attempted departure for the coordinator's joint yielding;
	# the all-holding baseline has no corridor conflict for it to repair.
	if work.attempted.is_empty() and selected.values().any(func(task): return task.role != &"guard"):
		work.attempted = selected.duplicate(true)
	if not traffic.valid or not Support.acyclic(selected, traffic): return
	if selected.values().all(func(task): return task.role == &"guard"):
		# This is a safe fallback, not a bound that can prune equally priced
		# departures when the action-cost weight is zero.
		work.holding_fallback = {"tasks": selected.duplicate(true), "traffic": traffic, "cost": cost}
		return
	work.best = selected.duplicate(true)
	work.seed.tasks = selected
	work.cost = cost
	work.traffic = traffic
	work.reason = &"complete_layout"

func _team_cost(snapshot: Dictionary, tasks: Dictionary) -> float:
	if snapshot.get("objective", {}).get("phase") == &"search":
		var entrances := {}
		var watchers := {}
		for task in tasks.values():
			if task.has("overwatch_for"):
				if not tasks.values().any(func(peer): return peer.role == &"search" and Support.covers(task, peer)): return INF
				watchers[task.overwatch_for] = int(watchers.get(task.overwatch_for, 0)) + 1
			var key: String = task.get("sync_key", "")
			if key.is_empty(): continue
			var side: int = task.get("side", 0)
			var group: Dictionary = entrances.get(key, {})
			group[side] = int(group.get(side, 0)) + 1
			entrances[key] = group
		var repeated := 0.0
		for key in watchers:
			# A fire provider must support a concrete active investigation.
			# Once its inspectors leave, its old post competes as no duty at all.
			if not entrances.has(key): return INF
			repeated += maxf(0.0, float(watchers[key]) - 1.0) * 8.0
		for key in entrances:
			if snapshot.overwatch_groups.has(key) and not watchers.has(key): repeated += 6.0
		return repeated * Scoring.weight(snapshot.get("scoring", {}), &"score_search_support_weight")
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
	return (8.0 if available and not retained else 0.0) * Scoring.weight(snapshot.get("scoring", {}), &"score_fire_continuity_weight") + Combat.team_cost(snapshot, tasks)

func _eligible(snapshot: Dictionary, id: int, candidate: Dictionary, selected: Dictionary) -> bool:
	# The scene-independent template is an input constraint, not a label.
	var qualified = false
	for slot in snapshot.template.roles.get(candidate.role, []):
		if slot.member_id == id and slot.action == candidate.action: qualified = true
	if not qualified: return false
	if candidate.role == &"flank":
		var flankers := 0
		for peer in selected.values():
			if peer.role == &"flank": flankers += 1
		if flankers >= maxi(1, snapshot.members.size() / 2): return false
	var clear = true
	for other in selected:
		var peer: Dictionary = selected[other]
		# Alternative ranks are observation choices, not a queue of bodies
		# assigned to inspect the same entrance one after another.
		if candidate.get("role") == &"search" and not candidate.get("sync_key", "").is_empty() and candidate.get("sync_key") == peer.get("sync_key") and candidate.get("side") == peer.get("side"): return false
		if candidate.has("overwatch_for") and candidate.get("overwatch_for") == peer.get("overwatch_for") and candidate.get("side") == peer.get("side"): return false
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
