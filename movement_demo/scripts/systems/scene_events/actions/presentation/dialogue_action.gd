@tool
class_name DialogueAction
extends SceneAction

@export_node_path("Node") var target_path: NodePath
@export_node_path("Node") var player_path: NodePath
@export var dialogue: Resource
@export var start := "start"
@export var pause_world := true


func begin(context: SceneActionContext) -> void:
	var target := context.resolve(target_path)
	if target == null:
		context.fail(&"missing_dialogue_target")
		return
	if dialogue == null or not dialogue.has_method(&"get_next_dialogue_line"):
		context.fail(&"invalid_dialogue_resource")
		return
	if player_path.is_empty():
		context.fail(&"missing_dialogue_player")
		return
	var options := {"pause_world": pause_world}
	var player := context.resolve(player_path)
	if player == null:
		context.fail(&"missing_dialogue_player")
		return
	options["player"] = player
	context.request(&"dialogue", target, {"resource": dialogue, "start": start}, options)
