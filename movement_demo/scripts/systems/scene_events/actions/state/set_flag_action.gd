@tool
class_name SetFlagAction
extends SceneAction

@export_node_path("Node") var state_path: NodePath = ^"/root/GameState"
@export var flag: StringName
@export var value := true


func begin(context: SceneActionContext) -> void:
	var state := context.resolve(state_path)
	if state == null or not state.has_method(&"set_flag") or flag.is_empty():
		context.fail(&"invalid_flag_target")
		return
	state.call(&"set_flag", flag, value)
	context.complete()
