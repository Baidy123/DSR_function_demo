extends RefCounted

## Coordinator-owned planning geometry, never an executor or target observer.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const ARRIVAL_MARGIN := 0.16

static func melee_post_valid(context, profile: Dictionary, point: Vector3, target: Vector3, margin: float = 0.0) -> bool:
	var weapon: Dictionary = profile.get("weapon", {})
	if not weapon.get("melee_enabled", false) or not point.is_finite() or not target.is_finite(): return false
	if absf(point.y - target.y) > float(weapon.get("melee_height_tolerance", 0.5)): return false
	if Contract.horizontal(point, target) > float(weapon.get("melee_range", 0.0)) - margin: return false
	return context.cover_selection.has_clear_line(point + Vector3.UP * 0.8, target + Vector3.UP * 0.8)

static func melee_position(context, profile: Dictionary, body: Dictionary, seed_point: Vector3, target: Vector3) -> Vector3:
	# Preserve a current reachable attack, including its normal cooldown/turn.
	if Contract.horizontal(seed_point, body.position) < 0.1 and melee_post_valid(context, profile, body.position, target, ARRIVAL_MARGIN): return body.position
	var away := seed_point - target
	away.y = 0.0
	if away.is_zero_approx(): away = body.position - target
	var reach := float(profile.weapon.get("melee_range", 0.0)) - ARRIVAL_MARGIN
	if reach <= body.radius: return Vector3.INF
	var raw: Vector3 = target + away.normalized() * reach
	var point := NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), raw)
	if absf(point.y - body.position.y) > 0.5: return Vector3.INF
	point.y = body.position.y
	return point if melee_post_valid(context, profile, point, target, ARRIVAL_MARGIN * 0.5) else Vector3.INF
