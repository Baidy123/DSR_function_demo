extends "res://scripts/enemy/actions/enemy_action.gd"

func collect_candidates(visible: bool) -> Array[Dictionary]:
	return [option({}, context.utility_horizon_seconds, 0.0)] if visible else []

func validate(_candidate: Dictionary, visible: bool) -> bool:
	return is_enabled() and visible

func valid(visible: bool) -> bool:
	return _running and visible and is_enabled()

func begin(candidate: Dictionary, visible: bool) -> bool:
	super.begin(candidate, visible)
	context.state = context.State.APPROACH
	return true

func tick(_delta: float, visible: bool) -> Dictionary:
	if agent.target_position.distance_to(context.last_known_position) > 0.25:
		agent.target_position = context.last_known_position
	var next: Vector3 = agent.get_next_path_position()
	if (visible and context._horizontal_distance(context.last_known_position) <= float(_setting(&"stopping_distance", 1.3))) or agent.is_navigation_finished():
		return motion(Vector3.ZERO)
	var direction: Vector3 = next - actor.global_position
	direction.y = 0.0
	return motion(direction.normalized())
