extends RefCounted

static func score_outcome(ai, unavailable_seconds: float, exposed_seconds: float, information_loss: float = 0.0) -> Dictionary:
	var horizon: float = maxf(0.1, ai.utility_horizon_seconds)
	var unavailable: float = clampf(unavailable_seconds, 0.0, horizon)
	# 近距离威胁的每秒暴露最高为2；时间窗仍相同，不抹掉该空间风险。
	var exposure: float = clampf(exposed_seconds, 0.0, horizon * 2.0)
	var information: float = clampf(information_loss, 0.0, horizon)
	var fire_cost: float = unavailable * maxf(0.0, ai.utility_fire_weight)
	var risk_cost: float = exposure * ai._reload_risk_aversion()
	var information_cost: float = information * maxf(0.0, ai.utility_information_weight)
	return {"cost": fire_cost + risk_cost + information_cost, "unavailable_seconds": unavailable,
		"exposed_seconds": exposure, "information_loss": information, "fire_cost": fire_cost,
		"risk_cost": risk_cost, "information_cost": information_cost}
