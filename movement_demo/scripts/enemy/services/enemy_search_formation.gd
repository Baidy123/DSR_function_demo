extends RefCounted

## Stateless coordinator geometry. Goals come from the squad; members only
## validate actual navigation/capsules. No action selection or body control.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const CoverGeometry = preload("res://scripts/enemy/services/enemy_cover_inspection_geometry.gd")
const BodyGeometry = preload("res://scripts/systems/character_geometry.gd")
const Traffic = preload("res://scripts/enemy/services/squad_traffic.gd")
const Combat = preload("res://scripts/enemy/services/squad_combat_tactics.gd")

static func sites(context, objective: Dictionary, count: int, attempt: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var center: Vector3 = objective.get("search_center", objective.get("position", context.actor.global_position))
	var phase: StringName = objective.get("phase", &"patrol")
	if phase == &"search":
		var clue = objective.duplicate(true)
		clue.position = center
		clue.id = objective.get("objective_id", 0)
		if not clue.has("cover"):
			clue.merge(CoverGeometry.nearby_investigation_cover(context, clue))
		var geometry = CoverGeometry.describe(context, clue, false)
		if geometry.is_empty():
			# Search can remember a point beside a wall without a motion vector
			# leading into that wall. Inspect nearby static cover as a hypothesis.
			for cover in context.actor.get_tree().get_nodes_in_group("cover_region"):
				var nearby = clue.duplicate(true)
				nearby.cover = weakref(cover)
				nearby.erase("inference_position")
				geometry = CoverGeometry.describe(context, nearby, false)
				if not geometry.is_empty(): break
		if not geometry.is_empty():
			result = _cover_sites(geometry, count, attempt)
		else:
			# A brief loss in open ground still has a concrete last-seen clue.
			# Investigate it before nearby map cells pull everybody elsewhere.
			var toward_observer: Vector3 = objective.get("observer_position", context.actor.global_position) - center
			toward_observer.y = 0.0
			if toward_observer.is_zero_approx(): toward_observer = Vector3.BACK
			for angle_offset in [-0.65, 0.0, 0.65]:
				var point: Vector3 = center + toward_observer.normalized().rotated(Vector3.UP, angle_offset) * 2.5
				var projected := NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), point)
				projected.y = context.actor.global_position.y
				if Contract.horizontal(point, projected) < 0.4:
					result.append({"position": projected, "look_position": center, "site_key": "clue:%s:%s" % [objective.get("objective_id", 0), angle_offset]})
		return result
	if phase == &"patrol": center = context._spawn_position
	var radial: Vector3 = context.actor.global_position - center
	radial.y = 0.0
	if radial.is_zero_approx(): radial = Vector3.BACK
	var angle = atan2(radial.z, radial.x)
	if phase == &"patrol": angle = 0.0
	var radius = 5.0 if phase == &"contact" else 2.0 + float(attempt / 3) * 1.5
	if phase == &"patrol": radius = 3.0
	for i in 12:
		var direction = Vector3(cos(angle + TAU * i / 12.0), 0, sin(angle + TAU * i / 12.0))
		var point = center + direction * radius
		var projected = NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), point)
		if Contract.horizontal(point, projected) > 0.4: continue
		projected.y = context.actor.global_position.y
		result.append({"position": projected, "look_position": center if phase == &"contact" else projected + direction,
			"site_key": "%s:%s:%s" % [phase, 0 if phase == &"patrol" else attempt / 3, i]})
	return result

static func _cover_sites(geometry: Dictionary, count: int, attempt: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var transform: Transform3D = geometry.cover_transform
	var along: Vector3 = transform.basis.x if geometry.along_x else transform.basis.z
	var across: Vector3 = transform.basis.z if geometry.along_x else transform.basis.x
	var axis: Vector3 = -across.normalized() * geometry.front_sign
	var half_length: float = geometry.half_along * along.length()
	var depth: float = geometry.half_across * across.length() + geometry.radius + 0.25
	var rear: Vector3 = transform.origin + axis * depth
	rear.y = geometry.ends.values()[0].peek.y
	var group := "cover:%s" % geometry.cover_id
	# Interleave both ends and duties before the bounded candidate list fills.
	# Wider posts remain hypotheses even when an inner entrance is obstructed.
	for rank in maxi(2, count):
		var watch: Array[Dictionary] = []
		for side in [-1, 1]:
			var outward: Vector3 = along.normalized() * side
			var peek: Vector3 = rear + outward * (half_length + geometry.radius + 0.25)
			var entry: Vector3 = peek - axis * depth * 2.0
			var focus: Vector3 = rear + axis * (0.6 + float(rank) * 0.6)
			if rank > 0: focus += outward * maxf(0.0, half_length - 1.0)
			# The approach inspects the near side first. Only after physically
			# reaching the entry should attention turn into the rear inspection.
			var approach_focus: Vector3 = focus - axis * (2.0 * (depth + 0.6 + float(rank) * 0.6))
			if geometry.ends.has(side):
				var offset: Vector3 = outward * float(rank) * 1.4
				var lateral: Vector3 = (entry - geometry.observer_position).normalized() * float(attempt % 3) * 0.35
				lateral.y = 0.0
				result.append({"position": peek + offset + lateral, "via": entry + offset + lateral,
					"look_position": focus, "approach_look_position": approach_focus,
					"site_key": "%s:%s:%s" % [group, side, rank], "sync_key": group, "side": side})
			var offset: Vector3 = outward * (2.2 + rank * 1.4)
			watch.append({"role": &"support", "position": peek + offset + axis * (0.4 + rank * 1.6),
				"via": entry + offset, "look_position": rear + outward * maxf(0.0, half_length - 1.0) + axis * 1.8,
				"site_key": "watch:%s:%s:%s" % [geometry.cover_id, side, rank], "overwatch_for": group, "side": side})
		result.append_array(watch)
	return result

static func valid_route(context, path: PackedVector3Array) -> bool:
	if path.is_empty(): return false
	var radius: float = context.coordination_motion_state().radius
	return CoverGeometry._walkable_path(context, path, radius) and BodyGeometry.can_occupy(context.actor, path[-1], context.actor.get_body_height(), radius, true)

static func route(context, destination: Vector3, via: Vector3 = Vector3.INF, detour_variant: int = -1) -> PackedVector3Array:
	var path = PackedVector3Array([context.actor.global_position])
	var from: Vector3 = context.actor.global_position
	for point: Vector3 in ([via, destination] if via.is_finite() else [destination]):
		var leg: PackedVector3Array = context.cover_selection._path_to(from, point)
		if leg.is_empty(): return PackedVector3Array()
		for vertex in leg:
			vertex.y = context.actor.global_position.y
			if path[-1].distance_to(vertex) > 0.01: path.append(vertex)
		from = point
	var radius: float = context.coordination_motion_state().radius
	if not CoverGeometry._walkable_path(context, path, radius):
		if via.is_finite(): return PackedVector3Array()
		path = _obstacle_detour(context, path, radius, detour_variant)
		if path.is_empty(): return path
	if not BodyGeometry.can_occupy(context.actor, destination, context.actor.get_body_height(), radius, true): return PackedVector3Array()
	return path

static func _obstacle_detour(context, blocked: PackedVector3Array, radius: float, variant: int = -1) -> PackedVector3Array:
	# A newly placed wall need not be in the baked navigation mesh. Test four
	# bounded routes around its real box, with the same capsule/nav validation.
	var obstacle = null
	for index in range(1, blocked.size()):
		var hit = context.cover_selection.environment_ray(blocked[index - 1] + Vector3.UP * 0.8, blocked[index] + Vector3.UP * 0.8)
		if not hit.is_empty():
			obstacle = hit.collider
			break
	if not is_instance_valid(obstacle): return PackedVector3Array()
	var shape = obstacle.get_node_or_null("CollisionShape3D")
	if shape == null:
		for child in obstacle.get_children():
			if child is CollisionShape3D:
				shape = child
				break
	if shape == null or not shape.shape is BoxShape3D: return PackedVector3Array()
	var half: Vector3 = shape.shape.size * 0.5
	var margin_x: float = (radius + 0.25) / shape.global_basis.x.length()
	var margin_z: float = (radius + 0.25) / shape.global_basis.z.length()
	var corners: Array[Vector3] = []
	for sign_pair in [Vector2(-1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(1, -1)]:
		var point: Vector3 = shape.to_global(Vector3(sign_pair.x * (half.x + margin_x), 0, sign_pair.y * (half.z + margin_z)))
		point.y = context.actor.global_position.y
		corners.append(point)
	var best = PackedVector3Array()
	var best_length = INF
	for index in 4:
		if variant >= 0 and index != variant: continue
		var a = corners[index]
		var b = corners[(index + 1) % 4]
		if Contract.horizontal(blocked[0], b) < Contract.horizontal(blocked[0], a):
			var swap = a
			a = b
			b = swap
		var path = PackedVector3Array([blocked[0]])
		for point in [a, b, blocked[-1]]:
			var leg: PackedVector3Array = context.cover_selection._path_to(path[-1], point)
			if leg.is_empty():
				path.clear()
				break
			for vertex in leg:
				vertex.y = context.actor.global_position.y
				if path[-1].distance_to(vertex) > 0.01: path.append(vertex)
		if path.is_empty() or not CoverGeometry._walkable_path(context, path, radius): continue
		var length: float = context.cover_selection._path_length_from_path(path)
		if length < best_length:
			best = path
			best_length = length
	return best

static func candidate(context, profile: Dictionary, body: Dictionary, site: Dictionary, objective: Dictionary, previous: Dictionary, action: StringName) -> Dictionary:
	context.cover_selection.begin_geometry_evaluation()
	context.fire.begin_geometry_evaluation()
	var result := _candidate(context, profile, body, site, objective, previous, action)
	context.fire.end_geometry_evaluation()
	context.cover_selection.end_geometry_evaluation()
	return result

static func _candidate(context, profile: Dictionary, body: Dictionary, site: Dictionary, objective: Dictionary, previous: Dictionary, action: StringName) -> Dictionary:
	var phase: StringName = objective.get("phase", &"patrol")
	var role: StringName = &"search" if phase == &"search" else (&"engage" if phase == &"contact" else &"patrol")
	role = site.get("role", role)
	if site.has("overwatch_for") and (not profile.firearms or not body.can_attack or body.reloading or body.rounds <= 0 or Contract.executor(profile, &"support").is_empty()): return {}
	if not site.has("defense_post") and (body.reloading or body.can_reload and body.rounds == 0): role = &"reload"
	if not Contract.qualified(profile, action, role): return {}
	var point: Vector3 = site.position
	if role == &"search" and site.has("coverage_key"):
		# Inspect from an offset post when it can see the whole target patch;
		# sampling cells are observation responsibilities, not mandatory footsteps.
		var away: Vector3 = body.position - site.look_position
		away.y = 0.0
		if not away.is_zero_approx():
			var raw: Vector3 = site.position + away.normalized() * 1.25
			var projected := NavigationServer3D.region_get_closest_point(context.navigation_region.get_rid(), raw)
			projected.y = body.position.y
			if Contract.horizontal(raw, projected) < 0.4 and BodyGeometry.can_occupy(context.actor, projected, context.actor.get_body_height(), body.radius, true):
				var clear := true
				for sample: Vector3 in site.observation_samples:
					if not preload("res://scripts/enemy/services/enemy_visual_observation.gd").clear_from(context, projected + Vector3.UP * context.actor.get_body_height() * 0.85, sample): clear = false
				if clear: point = projected
	if role == &"search" or site.has("overwatch_for"):
		var eye = point + Vector3.UP * context.actor.get_body_height() * 0.85
		if not context.cover_selection.has_clear_line(eye, site.look_position + Vector3.UP * 0.7): return {}
		if site.has("overwatch_for"):
			if not preload("res://scripts/enemy/services/enemy_visual_observation.gd").clear_from(context, eye, site.look_position): return {}
			var muzzle: Vector3 = context.actor.get_posture_muzzle_position(false, point)
			var aim: Vector3 = site.look_position + Vector3.UP
			if muzzle.distance_to(aim) > profile.weapon.fire_range or not context.fire.has_clear_firing_lane(muzzle, aim - muzzle, muzzle.distance_to(aim)): return {}
	if role == &"patrol" and Contract.horizontal(point, body.position) < 0.75: return {}
	if phase == &"contact" and role in [&"engage", &"support", &"flank"]:
		if profile.firearms:
			if body.visible and not body.get("fire_lane_valid", true) and Contract.horizontal(body.position, point) < 0.2: return {}
			var origin: Vector3 = context.actor.get_posture_muzzle_position(false, point)
			var aim: Vector3 = objective.get("aim_position", objective.position + Vector3.UP)
			# Seeing a target does not imply the observer's current muzzle has a
			# usable shot. Estimate future posts from known feet in that case;
			# actual fire still requires a fresh personal visible aim point.
			if not aim.is_finite(): aim = objective.position + Vector3.UP
			if origin.distance_to(aim) > profile.weapon.fire_range or not context.fire.has_clear_firing_lane(origin, aim - origin, origin.distance_to(aim)): return {}
		else:
			# Melee members receive actual contact-range posts from the same
			# known target, never a ranged support label.
			point = Combat.melee_position(context, profile, body, point, objective.position)
			if not point.is_finite(): return {}
	var detour_variant: int = site.get("detour_variant", -1)
	var path: PackedVector3Array = site.get("prepared_route", PackedVector3Array())
	if path.is_empty(): path = route(context, point, site.get("via", Vector3.INF), detour_variant)
	if path.is_empty():
		return {"retry_detour": true} if detour_variant >= 0 and detour_variant < 3 and not site.get("via", Vector3.INF).is_finite() else {}
	if role == &"flank" and profile.firearms and Traffic.distance_to_path(objective.position, path) < 1.5:
		var approach: Vector3 = body.position - objective.position
		approach.y = 0.0
		var detour = PackedVector3Array()
		for side in [-1.0, 1.0]:
			var via: Vector3 = objective.position + approach.normalized().rotated(Vector3.UP, side * PI * 0.5) * 5.0
			var alternative = route(context, point, via)
			if not alternative.is_empty() and Traffic.distance_to_path(objective.position, alternative) >= 1.5:
				if detour.is_empty() or context.cover_selection._path_length_from_path(alternative) < context.cover_selection._path_length_from_path(detour): detour = alternative
		if detour.is_empty(): return {}
		path = detour
	var length: float = context.cover_selection._path_length_from_path(path)
	var parameters: Dictionary = profile.actions[action].parameters
	var speed = maxf(0.1, float(parameters.get("focused_search_speed_multiplier", 1.0))) if role == &"search" else 1.0
	var run_speed: float = profile.get("run_speed_multiplier", 2.0)
	var travel_speed: float = maxf(speed, run_speed) if role == &"flank" or site.has("overwatch_for") else speed
	var seconds: float = maxf(0.0, length - 1.4) / maxf(0.1, body.move_speed * travel_speed) + minf(1.4, length) / maxf(0.1, body.move_speed * speed)
	var estimate: float = seconds + (0.0 if previous.get("position", Vector3.INF).distance_to(point) < 0.2 else 0.6)
	if role == &"guard" and phase != &"patrol": estimate += 8.0
	if role == &"search" and site.has("coverage_key"):
		estimate += 2.0 + float(site.get("clue_distance", 0.0)) * 0.7 + (12.0 if site.get("revisit", false) else 0.0)
		estimate += maxf(0.0, 2.25 - float(site.get("expected_area", 0.0)))
	if role in [&"engage", &"support", &"flank"] and body.visible and Contract.horizontal(point, body.position) < 0.2: estimate = 0.0
	if role == &"flank" and not body.visible:
		var approach = (body.position - objective.position).normalized()
		var flank = (point - objective.position).normalized()
		estimate += maxf(0.0, approach.dot(flank)) * 4.0
	var tactical := {}
	if site.has("overwatch_for"):
		tactical = {"sustainable_fire": true}
	if phase == &"contact" and role in [&"engage", &"support", &"flank"]:
		var threat: Vector3 = objective.position + Vector3.UP
		var exposure := 0.0
		for fraction in [0.0, 0.5, 1.0]:
			var sample: Vector3 = path[mini(path.size() - 1, roundi((path.size() - 1) * fraction))]
			if context.cover_selection.has_clear_line(threat, sample + Vector3.UP): exposure += 1.0 / 3.0
		var protected_low: bool = not context.cover_selection.has_clear_line(threat, point + Vector3.UP * 0.45)
		var ammunition := float(body.rounds) / maxf(1.0, float(profile.weapon.get("magazine_capacity", 1)))
		var sustained: bool = profile.firearms and body.can_attack and not body.reloading and body.rounds > 0
		tactical = {"exposure": exposure, "protected": protected_low, "sustainable_fire": sustained,
			"travel": seconds, "reload": body.get("reload_remaining", 0.0), "pressure": body.pressure,
			"ammunition": ammunition, "advance": maxf(0.0, Contract.horizontal(body.position, objective.position) - Contract.horizontal(point, objective.position))}
		estimate += float(site.get("role_cost", 0.0)) + exposure * (2.0 + minf(seconds, 3.0)) + body.pressure * exposure
		if not protected_low: estimate += 1.0
		if not sustained: estimate += 2.0
		if role == &"support" and not body.visible: estimate += 3.0
	var result := {"action": action, "role": role, "position": point, "route": path,
		"look_position": site.get("look_position", objective.get("position", point)),
		"staging_position": site.get("via", point if role == &"search" else Vector3.INF), "site_key": site.get("site_key", str(point)),
		"estimate": estimate, "tactical": tactical, "travel_seconds": seconds, "speed_multiplier": speed, "run_speed_multiplier": run_speed, "objective_id": objective.get("objective_id", 0),
		"evidence_id": objective.get("id", 0), "target_id": objective.get("target_id", 0), "side": site.get("side", 0),
		"sync_key": site.get("sync_key", ""), "search_revision": objective.get("search_revision", 0)}
	for key in Contract.SEARCH_STEP_FIELDS:
		if site.has(key): result[key] = site[key]
	for key in ["defense_id", "defense_post", "stress_tolerance", "defense_proactive"]:
		if site.has(key): result[key] = site[key]
	if site.has("overwatch_for"): result.overwatch_for = site.overwatch_for
	if phase == &"contact" and not profile.firearms and role in [&"engage", &"flank"]: result.contact_post = true
	if role == &"search" and objective.get("source") in [&"visual", &"shared_visual"]:
		# Reuse the frozen, time-limited pursuit setting on long approach legs.
		# Hints and arrival cannot renew the original visual evidence timestamp.
		result.pursuit_until = float(objective.get("captured_at", -INF)) + float(parameters.get("combat_pursuit_seconds", 0.0))
		result.pursuit_multiplier = float(parameters.get("combat_pursuit_speed_multiplier", speed))
	return result

static func yield_sites(context, body: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for radius in [1.4, 2.4]:
		for i in 8:
			var point: Vector3 = body.position + Vector3(cos(TAU * i / 8.0), 0, sin(TAU * i / 8.0)) * radius
			var path = route(context, point)
			if not path.is_empty(): result.append({"position": point, "route": path, "site_key": "yield:%s" % point})
	return result
