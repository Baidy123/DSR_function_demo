extends RefCounted

## Whole-team assignment over coordinator-requested, locally validated posts.
## No personal candidates, Utility scores, scene access or tactical authority.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const MAX_COMBINATIONS := 256

func propose(snapshot: Dictionary) -> Dictionary:
	var ids: Array = snapshot.members.keys()
	ids.sort_custom(func(a, b): return snapshot.candidates.get(a, []).size() < snapshot.candidates.get(b, []).size())
	var work = {"trials": 0, "nodes": 0, "best": {}, "attempted": {}, "cost": INF, "traffic": {}, "reason": &"no_complete_layout"}
	_assign(snapshot, ids, 0, {}, 0.0, work)
	return {"tasks": work.best, "traffic": work.traffic, "cost": work.cost,
		"trials": work.trials, "reason": work.reason, "attempted": work.attempted, "complete": work.best.size() == ids.size() and not ids.is_empty()}

func _assign(snapshot: Dictionary, ids: Array, index: int, selected: Dictionary, cost: float, work: Dictionary) -> void:
	work.nodes += 1
	if work.trials >= MAX_COMBINATIONS or work.nodes > 2048 or cost >= float(work.cost): return
	if index == ids.size():
		work.trials += 1
		var traffic = Traffic.schedule(selected, snapshot.members)
		if work.attempted.is_empty(): work.attempted = selected.duplicate(true)
		if not traffic.valid: return
		work.best = selected.duplicate(true)
		work.cost = cost
		work.traffic = traffic
		work.reason = &"complete_layout"
		return
	var id = ids[index]
	for candidate in snapshot.candidates.get(id, []):
		# The scene-independent template is an input constraint, not a label.
		var qualified = false
		for slot in snapshot.template.roles.get(candidate.role, []):
			if slot.member_id == id and slot.action == candidate.action: qualified = true
		if not qualified: continue
		var clear = true
		for other in selected:
			var gap: float = snapshot.members[id].radius + snapshot.members[other].radius + maxf(snapshot.members[id].spacing_margin, snapshot.members[other].spacing_margin)
			if Contract.horizontal(candidate.position, selected[other].position) < gap:
				clear = false
				break
		if not clear: continue
		selected[id] = candidate
		_assign(snapshot, ids, index + 1, selected, cost + float(candidate.estimate), work)
		selected.erase(id)
