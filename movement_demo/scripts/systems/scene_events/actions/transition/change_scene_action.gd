@tool
class_name ChangeSceneAction
extends SceneAction

@export_file("*.tscn") var scene_path := ""
@export var mode: StringName
@export var return_control_on_failure := false


func begin(context: SceneActionContext) -> void:
	if scene_path.is_empty():
		context.fail(&"missing_scene_path")
		return
	var parameters := {"path": scene_path}
	if not mode.is_empty():
		parameters["mode"] = mode
	if return_control_on_failure:
		parameters["return_control_on_failure"] = true
	context.request(&"transition", null, parameters)
