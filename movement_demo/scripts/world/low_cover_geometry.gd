extends RefCounted

## 纯查询：不切姿态、不搬动身体、不推进计时，也不读取 AI 目标记忆。
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const VAULT_HEIGHT: float = 1.0
const STANDING_HEIGHT: float = 1.75

static func _radius(actor: CollisionObject3D) -> float:
	var collision := actor.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision != null and collision.shape is CapsuleShape3D:
		return collision.shape.radius * maxf(absf(collision.global_basis.x.length()), absf(collision.global_basis.z.length()))
	return 0.35

static func _ray(actor: CollisionObject3D, from: Vector3, to: Vector3, ignore_characters: bool = false) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, actor.collision_mask, Geometry.exclusions(actor, ignore_characters))
	return actor.get_world_3d().direct_space_state.intersect_ray(query)

static func _low(body: Object) -> bool:
	return is_instance_valid(body) and body.has_method("is_low_cover") and body.is_low_cover()

static func aim_cover(actor: CollisionObject3D, direction: Vector3, max_distance: float = 1.5) -> Dictionary:
	direction.y = 0.0
	if direction.length_squared() < 0.001: return {}
	direction = direction.normalized()
	# 固定用假定蹲姿查询，避免实际站起后条件消失而反复起蹲。
	var low_origin: Vector3 = actor.get_posture_muzzle_position(true) if actor.has_method("get_posture_muzzle_position") else actor.global_position + Vector3.UP * 0.72
	var high_origin: Vector3 = actor.get_posture_muzzle_position(false) if actor.has_method("get_posture_muzzle_position") else actor.global_position + Vector3.UP * 1.30
	var low := _ray(actor, low_origin, low_origin + direction * max_distance)
	if low.is_empty() or not _low(low.collider): return {}
	var high := _ray(actor, high_origin, high_origin + direction * max_distance)
	if not high.is_empty(): return {}
	return {"cover": low.collider, "position": low.position}

static func query_vault(actor: CollisionObject3D, direction: Vector3, max_distance: float = 1.5, duration: float = 0.8) -> Dictionary:
	direction.y = 0.0
	if direction.length_squared() < 0.001: return _failure("direction")
	direction = direction.normalized()
	var hit := _ray(actor, actor.global_position + Vector3.UP * 0.5, actor.global_position + Vector3.UP * 0.5 + direction * max_distance)
	if hit.is_empty() or not _low(hit.collider): return _failure("no_low_cover")
	return query_vault_at(actor, hit.collider, actor.global_position, direction, duration, false)

static func query_vault_at(actor: CollisionObject3D, cover: Node3D, from: Vector3, direction: Vector3, duration: float = 0.8, ignore_characters: bool = true) -> Dictionary:
	if not _low(cover) or not cover.vault_enabled: return _failure("not_vaultable")
	var collision := cover.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D: return _failure("shape")
	var basis := collision.global_basis
	if basis.y.normalized().dot(Vector3.UP) < 0.999: return _failure("tilted_cover")
	var point := collision.to_local(from)
	var half: Vector3 = collision.shape.size * 0.5
	direction.y = 0.0
	if direction.length_squared() < 0.001: return _failure("direction")
	direction = direction.normalized()
	var local_direction := basis.inverse() * direction
	var axis: int = 0 if absf(local_direction.x) > absf(local_direction.z) else 2
	var along: int = 2 if axis == 0 else 0
	var scale_axis: float = basis[axis].length()
	var scale_along: float = basis[along].length()
	var radius := _radius(actor)
	var side := signf(point[axis])
	if side == 0.0 or absf(point[axis]) < half[axis]: return _failure("inside_wall")
	var normal: Vector3 = basis[axis].normalized() * side
	if direction.dot(-normal) < cos(deg_to_rad(40.0)): return _failure("approach_angle")
	if absf(point[along]) > half[along] - (radius + 0.03) / scale_along: return _failure("edge")
	var gap: float = (absf(point[axis]) - half[axis]) * scale_axis
	if gap < radius - 0.03 or gap > 1.5: return _failure("entry_distance")
	var thickness: float = half[axis] * 2.0 * scale_axis
	if thickness > 1.2: return _failure("thickness")
	var top: float = cover.get_top_height()
	if top - from.y > 1.3 or top - from.y < 0.45: return _failure("height")
	var exit_local := point
	exit_local[axis] = -side * (half[axis] + (radius + 0.15) / scale_axis)
	var landing := collision.to_global(exit_local)
	var ground := _ray(actor, Vector3(landing.x, top + 0.1, landing.z), Vector3(landing.x, from.y - 0.45, landing.z), ignore_characters)
	if ground.is_empty() or ground.normal.dot(Vector3.UP) < 0.8: return _failure("landing_ground")
	landing = ground.position
	if absf(landing.y - from.y) > 0.35: return _failure("landing_height")
	var start_ground := _ray(actor, from + Vector3.UP * 0.1, from - Vector3.UP * 0.15, ignore_characters)
	if start_ground.is_empty() or start_ground.normal.dot(Vector3.UP) < 0.8: return _failure("entry_ground")
	if not Geometry.can_occupy(actor, landing, STANDING_HEIGHT, radius, ignore_characters): return _failure("landing_space")
	var lift: float = top + 0.06
	var points := PackedVector3Array([from, Vector3(from.x, lift, from.z), Vector3(landing.x, lift, landing.z), landing])
	for index in 3:
		if not Geometry.can_sweep(actor, points[index], points[index + 1], VAULT_HEIGHT, radius, ignore_characters): return _failure("blocked_arc")
	var distance := from.distance_to(points[1]) + points[1].distance_to(points[2]) + points[2].distance_to(landing)
	return {"valid": true, "reason": "", "cover": cover, "entry": from, "exit": landing, "points": points,
		"duration": maxf(maxf(duration, 0.2), distance / 8.0), "height": VAULT_HEIGHT}

static func sample_vault(plan: Dictionary, progress: float) -> Vector3:
	var points: PackedVector3Array = plan.get("points", PackedVector3Array())
	if points.size() != 4: return plan.get("entry", Vector3.ZERO)
	var t := clampf(progress, 0.0, 1.0)
	if t < 0.3: return points[0].lerp(points[1], smoothstep(0.0, 1.0, t / 0.3))
	if t < 0.7: return points[1].lerp(points[2], smoothstep(0.0, 1.0, (t - 0.3) / 0.4))
	return points[2].lerp(points[3], smoothstep(0.0, 1.0, (t - 0.7) / 0.3))

static func proximity_cover(actor: CollisionObject3D, target: CollisionObject3D, max_distance: float = 2.0) -> Dictionary:
	if not is_instance_valid(target) or not target.has_method("is_crouching") or not target.is_crouching(): return {}
	if actor.global_position.distance_to(target.global_position) > max_distance: return {}
	if absf(actor.global_position.y - target.global_position.y) > 0.35: return {}
	var from := actor.global_position + Vector3.UP * 0.5
	var to := target.global_position + Vector3.UP * 0.5
	var hit := _ray(actor, from, to, true)
	if hit.is_empty() or not _low(hit.collider): return {}
	var cover: Node3D = hit.collider
	var collision := cover.get_node("CollisionShape3D") as CollisionShape3D
	var a := collision.to_local(actor.global_position)
	var b := collision.to_local(target.global_position)
	var half: Vector3 = collision.shape.size * 0.5
	var same_wall := false
	for axis in [0, 2]:
		var other: int = 2 if axis == 0 else 0
		var scale_axis: float = collision.global_basis[axis].length()
		if a[axis] * b[axis] >= 0.0: continue
		if absf(a[axis]) < half[axis] or absf(b[axis]) < half[axis]: continue
		if absf(a[other]) > half[other] or absf(b[other]) > half[other]: continue
		if maxf(absf(a[axis]) - half[axis], absf(b[axis]) - half[axis]) * scale_axis > 1.1: continue
		same_wall = true
	if not same_wall: return {}
	var excluded := Geometry.exclusions(actor, true)
	excluded.append(cover.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, actor.collision_mask, excluded)
	if not actor.get_world_3d().direct_space_state.intersect_ray(query).is_empty(): return {}
	return {"cover": cover, "position": target.global_position}

static func _failure(reason: String) -> Dictionary:
	return {"valid": false, "reason": reason}
