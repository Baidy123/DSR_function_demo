extends RefCounted

var collection_costs: Dictionary = {}

## 选择器不登记具体动作；新模块只需实现统一协议并加入兵种资源。
func assess_options(ai, sees_player: bool) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	ai.context.spatial.advance_evaluation()
	for action in ai.actions.values():
		if not action.is_enabled(): continue
		var started := Time.get_ticks_usec()
		for candidate in action.collect_candidates(sees_player):
			var outcome: Dictionary = candidate.get("outcome", {})
			if candidate.get("id") != action.action_id or outcome.is_empty(): continue
			var breakdown := score_outcome(ai.context, outcome.get("unavailable_seconds", 0.0), outcome.get("exposed_seconds", 0.0), outcome.get("information_loss", 0.0))
			candidate.cost = breakdown.cost
			candidate.breakdown = breakdown
			options.append(candidate)
		collection_costs[action.action_id] = Time.get_ticks_usec() - started
	return options

func choose_option(options: Array, current: Dictionary = {}) -> Dictionary:
	var best: Dictionary = {}
	for candidate in options:
		if not is_finite(candidate.cost): continue
		if best.is_empty() or candidate.cost < best.cost or (is_equal_approx(candidate.cost, best.cost) and same_option(candidate, current)):
			best = candidate
	return best


func score_outcome(context, unavailable_seconds: float, exposed_seconds: float, information_loss: float = 0.0) -> Dictionary:
	return preload("res://scripts/enemy/enemy_utility_score.gd").score_outcome(context, unavailable_seconds, exposed_seconds, information_loss)


func same_option(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	if a.get("id", &"") != b.get("id", &"") or a.get("plan", &"") != b.get("plan", &"") or a.get("mode", &"") != b.get("mode", &""):
		return false
	var first: Dictionary = a.get("destination", {})
	var second: Dictionary = b.get("destination", {})
	if first.is_empty() or second.is_empty():
		return first.is_empty() and second.is_empty()
	var first_point: Vector3 = first.get("position", first.get("hide", Vector3.INF))
	var second_point: Vector3 = second.get("position", second.get("hide", Vector3.INF))
	return first.get("body") == second.get("body") and first_point.is_equal_approx(second_point)

func assess_route(context, path: PackedVector3Array, threat: Vector3, multiplier: float, reload_seconds: float, evaluate_fire: bool = false) -> Dictionary:
	return preload("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new().assess_route(context, path, threat, multiplier, reload_seconds, evaluate_fire)
