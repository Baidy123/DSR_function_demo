extends RefCounted

const ImpactEffects = preload("res://scripts/systems/effects/impact_effects.gd")


## 单位为度的固定落点加各颗独立的圆盘扰动；不旋转、平移或缩放整个图样。
static func sample_offsets(weapon: ShotgunSettings, stability: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var jitter := weapon.get_jitter_degrees(stability)
	for point in weapon.get_pattern_points():
		var angle := rng.randf_range(0.0, TAU)
		var radius := sqrt(rng.randf()) * jitter
		result.append(point * clampf(weapon.pattern_angle_degrees, 0.0, 15.0) + Vector2(cos(angle), sin(angle)) * radius)
	return result


static func directions(forward: Vector3, offsets: PackedVector2Array) -> PackedVector3Array:
	var axis := forward.normalized() if forward.is_finite() and not forward.is_zero_approx() else Vector3.FORWARD
	var reference := Vector3.UP if absf(axis.y) < 0.999 else Vector3.RIGHT
	var right := axis.cross(reference).normalized()
	var up := right.cross(axis).normalized()
	var result := PackedVector3Array()
	for offset in offsets:
		result.append((axis + right * tan(deg_to_rad(offset.x)) + up * tan(deg_to_rad(offset.y))).normalized())
	return result


## 先查询整枪所有弹丸，再由调用者结算伤害，防止前面的目标死亡后后续弹丸穿到后面。
## 只处理弹道与命中特效快照，不消费弹药、不控制角色、AI 或伤害。
static func trace(shooter: CollisionObject3D, weapon: WeaponData, origin: Vector3,
		forward: Vector3, stability: float, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var effects := ImpactEffects.find_for(shooter)
	for direction in directions(forward, sample_offsets(weapon.get_shotgun_settings(), stability, rng)):
		var endpoint: Vector3 = origin + direction * maxf(0.0, weapon.fire_range)
		var query := PhysicsRayQueryParameters3D.create(origin, endpoint, 1, [shooter.get_rid()])
		query.hit_from_inside = true
		var hit := shooter.get_world_3d().direct_space_state.intersect_ray(query)
		result.append({"collider": hit.get("collider"), "endpoint": hit.get("position", endpoint),
			"direction": direction, "impact": effects.capture_hit(hit, direction, shooter) if effects != null else null})
	return result


static func count_hits(pellets: Array[Dictionary], target_group: StringName) -> Dictionary:
	var counts := {}
	for pellet in pellets:
		var target = pellet.collider
		if is_instance_valid(target) and target.is_in_group(target_group):
			counts[target] = int(counts.get(target, 0)) + 1
	return counts


## 为一次近弹通知选出最近且无遮挡的真实弹道；同枪已命中的目标由调用者排除。
static func near_miss_endpoint(receiver: Node3D, origin: Vector3, pellets: Array[Dictionary], radius: float) -> Vector3:
	if not is_finite(radius) or radius <= 0.0: return Vector3.INF
	var chest: Vector3 = receiver.get_torso_position() if receiver.has_method("get_torso_position") else receiver.global_position
	var nearest := radius * radius
	var endpoint := Vector3.INF
	for pellet in pellets:
		var point := Geometry3D.get_closest_point_to_segment(chest, origin, pellet.endpoint)
		var distance := chest.distance_squared_to(point)
		if distance > nearest: continue
		if distance > 0.000001:
			var exclusions: Array[RID] = []
			if receiver is CollisionObject3D: exclusions.append(receiver.get_rid())
			var query := PhysicsRayQueryParameters3D.create(chest, point, 1, exclusions)
			query.hit_from_inside = true
			if not receiver.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): continue
		nearest = distance
		endpoint = pellet.endpoint
	return endpoint
