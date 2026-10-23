extends RefCounted

## Pressure requests and finite cover steps owned by the squad. Members execute
## only assigned routes; personal Utility and hidden target positions stay out.
const Contract = preload("res://scripts/enemy/services/squad_contract.gd")
const Formation = preload("res://scripts/enemy/services/enemy_search_formation.gd")
const Geometry = preload("res://scripts/systems/character_geometry.gd")
var requests: Dictionary = {}
var _cooldown: Dictionary = {}
var _serial := 0
var _preparing: Dictionary = {}

func release(id: int) -> void:
	requests.erase(id)
	_cooldown.erase(id)
	_preparing.erase(id)

func role(id: int) -> StringName:
	return requests.get(id, {}).get("phase", &"")

func advance(bodies: Dictionary, profiles: Dictionary, tasks: Dictionary, objective: Dictionary, now: float) -> bool:
	var changed := false
	for id in bodies:
		var body: Dictionary = bodies[id]
		var threshold: float = profiles.get(id, {}).get("stress_tolerance", 0.4)
		if not requests.has(id):
			if objective.get("phase") == &"patrol" or now < float(_cooldown.get(id, 0.0)): continue
			if body.pressure <= maxf(0.01, threshold) or Contract.executor(profiles.get(id, {}), &"shelter").is_empty(): continue
			_serial += 1
			requests[id] = {"phase": &"shelter", "post": {}, "returning": false, "id": _serial, "started_at": now, "phase_started_at": now}
			changed = true
			continue
		var request: Dictionary = requests[id]
		if request.get("proactive", false) and body.pressure > maxf(0.01, threshold):
			request.proactive = false
			_preparing.erase(id)
			changed = true
		if request.get("proactive", false) and objective.get("phase") != &"contact" and body.pressure <= maxf(0.01, threshold):
			requests.erase(id)
			_cooldown[id] = now + 1.0
			changed = true
			continue
		if request.post.is_empty() and now - float(request.started_at) > 2.0:
			# No feasible cover must not turn a short danger request into a
			# permanent hold. Continue ordinary commanded combat and retry later.
			requests.erase(id)
			_cooldown[id] = now + 1.0
			changed = true
			continue
		var task: Dictionary = tasks.get(id, {})
		if task.get("role") != request.phase and now - float(request.phase_started_at) > 3.0:
			requests.erase(id)
			_cooldown[id] = now + 1.0
			changed = true
			continue
		# A completed hide report must not also complete the next peek while
		# that new full-team task table is still being prepared.
		if task.get("defense_id") != request.id or task.get("role") != request.phase: continue
		if task.get("state") == &"blocked" or task.get("expires_at", INF) <= now:
			requests.erase(id)
			_cooldown[id] = now + 0.5
			changed = true
			continue
		if request.phase == &"cover_peek" and body.pressure > maxf(0.01, threshold):
			request.phase = &"shelter"
			request.phase_started_at = now
			request.returning = true
			changed = true
		elif task.get("state") == &"complete":
			request.phase_started_at = now
			if request.phase == &"shelter" and not request.returning and body.firearms and not Contract.executor(profiles[id], &"cover_peek").is_empty() and request.post.get("peek", Vector3.INF).is_finite():
				request.phase = &"cover_peek"
			elif request.phase == &"cover_peek":
				request.phase = &"shelter"
				request.returning = true
			else:
				requests.erase(id)
				_cooldown[id] = now + 1.0
			changed = true
	return changed

func accept(id: int, task: Dictionary) -> void:
	if task.get("defense_proactive", false) and not requests.has(id):
		requests[id] = {"phase": task.role, "post": {}, "returning": false, "id": task.defense_id,
			"started_at": task.issued_at, "phase_started_at": task.issued_at, "proactive": true}
	if requests.has(id) and task.get("defense_id") == requests[id].id:
		requests[id].post = task.defense_post.duplicate(true)

func prepare_candidates(ctx, profile: Dictionary, body: Dictionary, objective: Dictionary, proactive: bool, deadline: int) -> Dictionary:
	var id: int = ctx.actor.get_instance_id()
	if proactive and (requests.has(id) or float(_cooldown.get(id, 0.0)) > ctx.coordination_now() or not body.firearms or not body.visible or Contract.executor(profile, &"cover_peek").is_empty()): return {"ready": true, "candidates": []}
	if not proactive and not requests.has(id): return {"ready": true, "candidates": []}
	var request: Dictionary = {"phase": &"shelter", "post": {}, "id": -id, "proactive": true} if proactive else requests[id]
	var signature := [objective.objective_id, request.phase, request.id, proactive]
	if _preparing.has(id) and _preparing[id].signature == signature:
		return _continue_candidates(ctx, profile, body, objective, request, _preparing[id], deadline)
	var posts: Array[Dictionary] = []
	if not request.post.is_empty():
		posts.append(request.post)
	else:
		var covers: Array = ctx.actor.get_tree().get_nodes_in_group("cover_region").filter(func(cover): return ctx.navigation_region.is_ancestor_of(cover))
		covers.sort_custom(func(a, b): return body.position.distance_squared_to(a.global_position) < body.position.distance_squared_to(b.global_position))
		for cover in covers.slice(0, 2 if proactive else 4):
			var points: Array = cover.get_candidates(objective.position + Vector3.UP, body.position)
			points.sort_custom(func(a, b): return body.position.distance_squared_to(a.hide) < body.position.distance_squared_to(b.hide))
			for point in points.slice(0, 4 if proactive else 8):
				var hide: Vector3 = point.hide
				hide.y = body.position.y
				if Contract.horizontal(hide, body.position) > 10.0: continue
				var post = {"hide": hide, "peek": Vector3.INF, "crouch": point.get("crouch", false), "cover_id": cover.get_instance_id()}
				if not protected(ctx, post, objective.position): continue
				var peeks: Array = [point.get("stand", hide)] if post.crouch else point.peeks.duplicate()
				peeks.sort_custom(func(a, b): return hide.distance_squared_to(a) < hide.distance_squared_to(b))
				for peek: Vector3 in peeks:
					peek.y = body.position.y
					if proactive and Contract.horizontal(peek, objective.position) < 3.0: continue
					var origin: Vector3 = ctx.actor.get_posture_muzzle_position(false, peek)
					var aim: Vector3 = objective.get("aim_position", Vector3.INF)
					if not aim.is_finite(): aim = objective.position + Vector3.UP
					if not Geometry.can_occupy(ctx.actor, peek, ctx.actor.get_posture_body_height(false), body.radius, true): continue
					if not ctx.cover_selection.has_clear_line(origin, aim): continue
					if origin.distance_to(aim) > float(profile.weapon.get("fire_range", 0.0)): continue
					post.peek = peek
					break
				if not proactive or post.peek.is_finite(): posts.append(post)
	var work := {"signature": signature, "posts": posts, "cursor": 0, "candidates": []}
	_preparing[id] = work
	return _continue_candidates(ctx, profile, body, objective, request, work, deadline)

func _continue_candidates(ctx, profile: Dictionary, body: Dictionary, objective: Dictionary, request: Dictionary, work: Dictionary, deadline: int) -> Dictionary:
	var result: Array = work.candidates
	while work.cursor < work.posts.size() and result.size() < (2 if request.get("proactive", false) else 6):
		if Time.get_ticks_usec() >= deadline: return {"ready": false, "candidates": []}
		var post: Dictionary = work.posts[work.cursor]
		work.cursor += 1
		if not protected(ctx, post, objective.position): continue
		var destination: Vector3 = post.peek if request.phase == &"cover_peek" else post.hide
		if not destination.is_finite(): continue
		var path = Formation.route(ctx, destination)
		if path.is_empty(): continue
		# Geometry opportunities have no executor. All qualified actions may bid.
		result.append({"role": request.phase, "position": destination, "prepared_route": path, "look_position": objective.position,
			"site_key": "defense:%s:%s:%s" % [post.cover_id, request.phase, destination], "objective_id": objective.objective_id,
			"defense_id": request.id, "defense_post": post.duplicate(true), "stress_tolerance": profile.get("stress_tolerance", 0.4),
			"defense_proactive": request.get("proactive", false)})
	_preparing.erase(ctx.actor.get_instance_id())
	return {"ready": true, "candidates": result}

static func protected(ctx, post: Dictionary, threat: Vector3) -> bool:
	var cover = instance_from_id(post.get("cover_id", 0))
	if not is_instance_valid(cover) or not ctx.navigation_region.is_ancestor_of(cover): return false
	var eye: Vector3 = ctx.actor.get_posture_eye_position(post.crouch, post.hide)
	var lateral = (eye - threat).normalized().cross(Vector3.UP) * ctx.coordination_motion_state().radius
	for offset in [Vector3.ZERO, lateral, -lateral]:
		var hit: Dictionary = ctx.cover_selection.environment_ray(threat + Vector3.UP, eye + offset)
		if hit.get("collider") != cover: return false
	return true
