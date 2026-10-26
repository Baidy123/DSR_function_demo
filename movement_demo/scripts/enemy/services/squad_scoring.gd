extends RefCounted

## 队伍评分的纯值接口：只改变候选排序和整队软代价，不授予动作、路线或开火权限。
## estimate 始终保留执行器的原估计；每次规划重新算分，续接任务不会重复打折。
const DEFAULTS := {
	&"score_cover_preference": 1.35,
	&"score_action_cost_weight": 1.0,
	&"score_fire_continuity_weight": 1.0,
	&"score_crossfire_weight": 1.0,
	&"score_melee_support_weight": 1.0,
	&"score_search_support_weight": 1.0,
}

static func sanitize(key: StringName, value: float) -> float:
	return clampf(value, 0.1 if key == &"score_cover_preference" else 0.0, 5.0) if is_finite(value) else float(DEFAULTS[key])

static func weights(values: Dictionary) -> Dictionary:
	var result := {}
	for key in DEFAULTS:
		result[key] = sanitize(key, float(values.get(key, DEFAULTS[key])))
	return result

static func weight(values: Dictionary, key: StringName) -> float:
	return float(values.get(key, DEFAULTS[key]))

static func candidate_cost(offer: Dictionary, values: Dictionary) -> float:
	# 原执行器可用负分表达翻越等训练偏好，不能在接口层抹掉这些收益。
	var cost := float(offer.estimate) * weight(values, &"score_action_cost_weight")
	if offer.get("role") in [&"shelter", &"cover_peek"] and offer.has("defense_post"):
		var preference := weight(values, &"score_cover_preference")
		cost = cost / preference if cost >= 0.0 else cost * preference
	return cost
