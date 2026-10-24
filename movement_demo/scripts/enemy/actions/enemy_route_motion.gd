extends RefCounted

## Owned by the selected action. Body execution survives cancellation only until safe landing.
var route: Dictionary = {}
var stage := 0
var waypoint := 0
var started := false
var failed := false
var completed := false
var waiting_for_vault := false
var segment_index := 0
const NavigationRoute = preload("res://scripts/enemy/services/enemy_navigation_route.gd")

func reset() -> void:
	route = {}
	stage = 0
	waypoint = 0
	started = false
	failed = false
	completed = false
	waiting_for_vault = false
	segment_index = 0

func begin(value: Dictionary) -> void:
	reset()
	route = value.duplicate(true)

func apply(context, output: Dictionary, delta: float) -> Dictionary:
	if route.is_empty(): return output
	if route.has("segments"): return _apply_segments(context, output, delta)
	var actor = context.actor
	if stage == 1:
		output.direction = Vector3.ZERO
		output.fire = {}
		output.melee = {}
		if actor.is_vaulting():
			started = true
			return output
		if started:
			if context._horizontal_distance_between(actor.global_position, route.vault.exit) > 0.45:
				reset()
				output.running = false
				return output
			stage = 2
			waypoint = 0
		else:
			output.vault = route.vault
			# A failed actual preflight is a failed route, never an every-frame vault request.
			started = true
			return output
	var path: PackedVector3Array = route.before if stage == 0 else route.after
	while waypoint < path.size() and context._horizontal_distance(path[waypoint]) < 0.15:
		waypoint += 1
	if waypoint >= path.size():
		if stage == 0:
			stage = 1
			return apply(context, output, delta)
		reset()
		return output
	var direction: Vector3 = path[waypoint] - actor.global_position
	direction.y = 0.0
	var maximum: float = maxf(0.001, actor.move_speed * actor.get_effective_movement_multiplier(output.get("multiplier", 1.0)) * delta)
	output.direction = direction.normalized() * minf(1.0, direction.length() / maximum)
	output.crouch = false
	return output

func _apply_segments(context, output: Dictionary, delta: float) -> Dictionary:
	var actor = context.actor
	waiting_for_vault = false
	if not NavigationRoute.current(context, route):
		if actor.is_vaulting():
			output.direction = Vector3.ZERO
			output.fire = {}
			output.melee = {}
			return output
		return _fail(context, output)
	while segment_index < route.segments.size():
		var segment: Dictionary = route.segments[segment_index]
		if segment.kind == &"vault":
			output.direction = Vector3.ZERO
			output.fire = {}
			output.melee = {}
			if actor.is_vaulting(): return output
			if started:
				if context.cooperation != null: context.cooperation.release_vault_transit(context)
				if context._horizontal_distance_between(actor.global_position, segment.exit) > 0.45 or absf(actor.global_position.y - segment.exit.y) > 0.3:
					context.routes.reject_link(segment.get("crossing_key", segment.link_key))
					return _fail(context, output)
				segment_index += 1
				waypoint = 0
				started = false
				continue
			if context.cooperation != null and not context.cooperation.acquire_vault_transit(context, segment):
				waiting_for_vault = true
				return output
			output.vault = NavigationRoute.execution_vault(context, segment)
			if output.vault.is_empty(): return _fail(context, output)
			started = true
			return output
		var points: PackedVector3Array = segment.points
		while waypoint < points.size() and context._horizontal_distance(points[waypoint]) < 0.12: waypoint += 1
		if waypoint >= points.size():
			segment_index += 1
			waypoint = 0
			continue
		var direction: Vector3 = points[waypoint] - actor.global_position
		direction.y = 0.0
		var maximum: float = maxf(0.001, actor.move_speed * actor.get_effective_movement_multiplier(output.get("multiplier", 1.0)) * delta)
		output.direction = direction.normalized() * minf(1.0, direction.length() / maximum)
		output.stop_position = points[waypoint]
		output.crouch = false
		return output
	reset()
	completed = true
	output.direction = Vector3.ZERO
	return output

func _fail(context, output: Dictionary) -> Dictionary:
	if context.cooperation != null: context.cooperation.release_vault_transit(context)
	reset()
	failed = true
	output.direction = Vector3.ZERO
	output.running = false
	return output
