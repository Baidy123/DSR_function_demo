extends RefCounted

## 仅处理已完成射线的命中：每枪每目标一次抽样、冻结伤害和防护结果。
## 不查询物理、不选择目标、不持有武器资源，也不消费弹药或推进AI。
static func resolve(hits: Dictionary, damage_per_hit: float, settings: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var chance: float = settings.chance
	for target in hits:
		if not is_instance_valid(target): continue
		var critical := chance > 0.0 and (chance >= 1.0 or rng.randf() < chance)
		var execution: bool = critical and settings.instant_kill and target.has_method("receive_headshot_hit") and target.has_method("is_headshot_protected") and not target.is_headshot_protected()
		results.append({"target": target, "pellets": int(hits[target]), "critical": critical,
			"damage": maxf(0.0, damage_per_hit) * int(hits[target]) * (float(settings.multiplier) if critical and not execution else 1.0),
			"reaction": {"execution": execution, "stagger_seconds": settings.stagger_seconds,
				"movement_multiplier": settings.movement_multiplier, "accuracy_cap": settings.accuracy_cap,
				"stagger_refresh_mode": settings.stagger_refresh_mode}})
	return results


## 保留旧目标伤害接口；训练靶／测试靶没有敌人防护接口，仅获得倍率反馈。
static func apply(result: Dictionary, source: Vector3, effects: Dictionary) -> StringName:
	var target = result.target
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return &""
	if result.critical and target.has_method("receive_headshot_hit"):
		return target.receive_headshot_hit(result.damage, source, effects, result.reaction)
	if target.has_method("receive_weapon_hit"):
		target.receive_weapon_hit(result.damage, source, effects)
	elif target.has_method("receive_hit"):
		target.receive_hit(result.damage, source)
	return &"headshot" if result.critical else &""
