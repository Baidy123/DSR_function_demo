extends RefCounted

## Environmental inspection, independent of near-body awareness and hidden
## target geometry. Both low and standing hiding space must actually be visible.
static func visible(ctx, feet: Vector3) -> bool:
	if not feet.is_finite() or not is_instance_valid(ctx.actor): return false
	var offset: Vector3 = feet - ctx.actor.global_position
	if offset.length() > ctx.perception.sight_distance: return false
	offset.y = 0.0
	if not offset.is_zero_approx() and (-ctx.actor.global_basis.z).dot(offset.normalized()) < cos(deg_to_rad(ctx.perception.sight_angle_degrees * 0.5)): return false
	return clear_from(ctx, ctx.actor.get_eye_position(), feet)

static func clear_from(ctx, eye: Vector3, feet: Vector3) -> bool:
	# A view of a wall top or standing head does not clear a crouched hideout.
	for height in [0.45, 1.2]:
		if not ctx.cover_selection.has_clear_line(eye, feet + Vector3.UP * height): return false
	return true
