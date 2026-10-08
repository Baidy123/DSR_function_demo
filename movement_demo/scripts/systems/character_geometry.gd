extends RefCounted

## 只读身体空间查询。姿态、移动、生命与动作计时由各角色自己管理。
const STANDING_HEIGHT: float = 1.75
const CROUCH_HEIGHT: float = 1.0

static func exclusions(actor: CollisionObject3D, ignore_characters: bool = false) -> Array[RID]:
	var result: Array[RID] = [actor.get_rid()]
	if ignore_characters:
		for group in [&"combat_target", &"player"]:
			for other in actor.get_tree().get_nodes_in_group(group):
				if other is CollisionObject3D and not result.has(other.get_rid()):
					result.append(other.get_rid())
	return result

static func capsule_query(actor: CollisionObject3D, feet: Vector3, height: float, radius: float, ignore_characters: bool = false) -> PhysicsShapeQueryParameters3D:
	var shape := CapsuleShape3D.new()
	shape.radius = maxf(0.01, radius - 0.005)
	shape.height = maxf(shape.radius * 2.0, height - 0.02)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, feet + Vector3.UP * (height * 0.5 + 0.01))
	query.collision_mask = actor.collision_mask
	query.exclude = exclusions(actor, ignore_characters)
	query.margin = 0.001
	return query

static func can_occupy(actor: CollisionObject3D, feet: Vector3, height: float, radius: float, ignore_characters: bool = false) -> bool:
	if not is_instance_valid(actor) or not actor.is_inside_tree() or not feet.is_finite(): return false
	if height < radius * 2.0 or radius <= 0.0: return false
	return actor.get_world_3d().direct_space_state.intersect_shape(capsule_query(actor, feet, height, radius, ignore_characters), 1).is_empty()

static func can_sweep(actor: CollisionObject3D, from: Vector3, to: Vector3, height: float, radius: float, ignore_characters: bool = false) -> bool:
	if not can_occupy(actor, from, height, radius, ignore_characters): return false
	var query := capsule_query(actor, from, height, radius, ignore_characters)
	query.motion = to - from
	var fractions := actor.get_world_3d().direct_space_state.cast_motion(query)
	return fractions.size() == 2 and fractions[0] >= 0.9999 and can_occupy(actor, to, height, radius, ignore_characters)
