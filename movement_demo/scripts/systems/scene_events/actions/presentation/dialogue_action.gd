@tool
class_name DialogueAction
extends SceneAction

@export_node_path("Node") var target_path: NodePath
@export_node_path("Node") var player_path: NodePath
@export_node_path("Node") var source_path: NodePath
@export var dialogue: Resource
@export var start := "start"
@export var pause_world := true
@export var face_source := false
@export var camera_cues: Dictionary = {}
@export var seat_cues: Dictionary = {}


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
	var resolved_camera_cues: Variant = _resolve_camera_cues(context, target)
	if resolved_camera_cues == null:
		context.fail(&"missing_dialogue_camera_cue_target")
		return
	var resolved_seat_cues: Variant = _resolve_seat_cues(context, target)
	if resolved_seat_cues == null:
		context.fail(&"missing_dialogue_seat_cue_target")
		return
	var parameters := {
		"resource": dialogue,
		"start": start,
		"face_source": face_source,
		"camera_cues": resolved_camera_cues,
		"seat_cues": resolved_seat_cues,
	}
	var options := {"pause_world": pause_world}
	var player := context.resolve(player_path)
	if player == null:
		context.fail(&"missing_dialogue_player")
		return
	options["player"] = player
	if not source_path.is_empty():
		var source := context.resolve(source_path)
		if source == null:
			context.fail(&"missing_dialogue_source")
			return
		options["source"] = source
	context.request(&"dialogue", target, parameters, options)


func _resolve_camera_cues(context: SceneActionContext, target: Node) -> Variant:
	var resolved := {}
	for cue in camera_cues:
		var node := context.resolve(NodePath(camera_cues[cue]))
		if node == null:
			return null
		resolved[cue] = target.get_path_to(node)
	return resolved


func _resolve_seat_cues(context: SceneActionContext, target: Node) -> Variant:
	var resolved := {}
	for cue in seat_cues:
		var paths: Array[NodePath] = []
		for source_path_value in seat_cues[cue]:
			var node := context.resolve(NodePath(source_path_value))
			if node == null:
				return null
			paths.append(target.get_path_to(node))
		resolved[cue] = paths
	return resolved
