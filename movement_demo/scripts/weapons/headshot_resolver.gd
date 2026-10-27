extends RefCounted

## 仅处理已完成射线的命中：每枪每目标一次抽样、冻结伤害和防护结果。
## 不查询物理、不选择目标、不持有武器资源，也不消费弹药或推进AI。
static func resolve(hits: Dictionary, damage_per_hit: float, settings: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	for target in hits:
		if not is_instance_valid(target): continue
		var opening := _opening_snapshot(target)
		var chance := _chance(settings, opening)
		var critical := chance > 0.0 and (chance >= 1.0 or rng.randf() < chance)
		var execution: bool = critical and settings.instant_kill and target.has_method("receive_headshot_hit") and target.has_method("is_headshot_protected") and not target.is_headshot_protected()
		results.append({"target": target, "pellets": int(hits[target]), "critical": critical,
			"opening_generation": opening.get("generation", -1),
			"life_generation": opening.get("life_generation", -1),
			"damage": maxf(0.0, damage_per_hit) * int(hits[target]) * (float(settings.multiplier) if critical and not execution else 1.0),
			"reaction": {"execution": execution, "stagger_seconds": settings.stagger_seconds,
				"movement_multiplier": settings.movement_multiplier, "accuracy_cap": settings.accuracy_cap,
				"stagger_refresh_mode": settings.stagger_refresh_mode}})
	return results


static func get_target_chance(settings: Dictionary, target: Object) -> float:
	return _chance(settings, _opening_snapshot(target))


static func _opening_snapshot(target: Object) -> Dictionary:
	if is_instance_valid(target) and target.has_method("get_melee_stun_state"):
		return target.get_melee_stun_state()
	return {}


static func _chance(settings: Dictionary, opening: Dictionary) -> float:
	if not settings.enabled: return 0.0
	var threshold: float = settings.accuracy_threshold
	if opening.get("opening_available", false):
		threshold = minf(threshold, float(opening.accuracy_threshold))
	return WeaponData.headshot_probability(float(settings.stability), threshold)


## 保留旧目标伤害接口；训练靶／测试靶没有敌人防护接口，仅获得倍率反馈。
static func apply(result: Dictionary, source: Vector3, effects: Dictionary) -> StringName:
	if result.get("applied", false): return &""
	result["applied"] = true # 同一冻结结果只交付一次，包括同步受击回调中的重入。
	var target = result.target
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return &""
	# 本枪较早目标的回调可能复位后续目标，旧命中不能伤害新生命。
	var life_generation: int = result.get("life_generation", -1)
	if life_generation >= 0 and int(target.get_melee_stun_state().life_generation) != life_generation: return &""
	# 任何有效玩家枪击都消费一次；先消费再回调，且代际防止清掉复位后的新状态。
	if is_finite(result.damage) and result.damage >= 0.0 and target.has_method("consume_melee_opening"):
		target.consume_melee_opening(int(result.opening_generation))
	if result.critical and target.has_method("receive_headshot_hit"):
		return target.receive_headshot_hit(result.damage, source, effects, result.reaction)
	if target.has_method("receive_weapon_hit"):
		target.receive_weapon_hit(result.damage, source, effects)
	elif target.has_method("receive_hit"):
		target.receive_hit(result.damage, source)
	return &"headshot" if result.critical else &""
