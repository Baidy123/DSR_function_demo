@tool
class_name ChangeSceneAction
extends SceneAction

@export_file("*.tscn") var scene_path := ""
@export var mode: StringName


func begin(context: SceneActionContext) -> void:
	if scene_path.is_empty():
		context.fail(&"missing_scene_path")
		return
	var parameters := {"path": scene_path}
	if not mode.is_empty():
		parameters["mode"] = mode
	context.request(&"transition", null, parameters)
