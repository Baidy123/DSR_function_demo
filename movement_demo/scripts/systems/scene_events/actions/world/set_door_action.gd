@tool
class_name SetDoorAction
extends SceneAction

@export_node_path("Node") var door_path: NodePath
@export var open := true


func begin(context: SceneActionContext) -> void:
	var door := context.resolve(door_path)
	if door == null or not door.has_method(&"begin_scene_action") \
			or not door.has_method(&"cancel_scene_action"):
		context.fail(&"invalid_door_provider")
		return
	context.request(&"script", door, {"open": open}, {"source": door})
