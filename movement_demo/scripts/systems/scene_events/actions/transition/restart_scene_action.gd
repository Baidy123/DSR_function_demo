@tool
class_name RestartSceneAction
extends SceneAction

@export var mode: StringName


func begin(context: SceneActionContext) -> void:
	var parameters := {"reload": true}
	if not mode.is_empty():
		parameters["mode"] = mode
	context.request(&"transition", null, parameters)
