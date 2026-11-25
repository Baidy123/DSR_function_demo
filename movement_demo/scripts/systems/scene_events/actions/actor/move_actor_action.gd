@tool
class_name MoveActorAction
extends SceneAction

@export_node_path("Node3D") var actor_path: NodePath
@export_node_path("Node3D") var target_path: NodePath
@export_node_path("TavernRoute") var route_path: NodePath
@export var vanish_at_end := false
## Zero keeps the actor's authored speed for this execution.
@export_range(0.0, 20.0, 0.05) var speed_override := 0.0


func begin(context: SceneActionContext) -> void:
	var actor := context.resolve(actor_path)
	if actor == null or not actor.has_method(&"begin_scene_action") \
			or not actor.has_method(&"cancel_scene_action"):
		context.fail(&"invalid_actor")
		return
	if target_path.is_empty() == route_path.is_empty():
		context.fail(&"move_needs_one_target_or_route")
		return
	var parameters := {"vanish_at_end": vanish_at_end}
	if not target_path.is_empty():
		var target := context.resolve(target_path) as Node3D
		if target == null:
			context.fail(&"missing_move_target")
			return
		parameters["points"] = [target.global_position]
	else:
		var route := context.resolve(route_path) as TavernRoute
		if route == null:
			context.fail(&"missing_move_route")
			return
		if route.world_points().is_empty():
			context.fail(&"route_empty")
			return
		parameters["route_path"] = actor.get_path_to(route)
	if speed_override > 0.0 and _has_property(actor, &"walk_speed"):
		context.state[&"original_walk_speed"] = actor.get(&"walk_speed")
		actor.set(&"walk_speed", speed_override)
	var scene_request := context.request(&"script", actor, parameters, {"source": actor})
	if context.is_terminal() or scene_request == null:
		_restore_speed(context, actor)
	else:
		context.finished.connect(_on_finished.bind(context, actor), CONNECT_ONE_SHOT)


func _on_finished(_status: StringName, _reason: StringName,
		context: SceneActionContext, actor: Node) -> void:
	_restore_speed(context, actor)


func _restore_speed(context: SceneActionContext, actor: Node) -> void:
	if context.state.has(&"original_walk_speed") and is_instance_valid(actor):
		actor.set(&"walk_speed", context.state[&"original_walk_speed"])
		context.state.erase(&"original_walk_speed")


func _has_property(target: Object, property_name: StringName) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
