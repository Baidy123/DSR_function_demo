extends RefCounted

## Owned by the selected action. Body execution survives cancellation only until safe landing.
var route: Dictionary = {}
var stage := 0
var waypoint := 0
var started := false

func reset() -> void:
	route = {}
	stage = 0
	waypoint = 0
	started = false

func begin(value: Dictionary) -> void:
	reset()
	route = value.duplicate(true)

func apply(context, output: Dictionary, delta: float) -> Dictionary:
	if route.is_empty(): return output
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
