@tool
class_name SceneFlagCondition
extends SceneCondition

@export_node_path("Node") var state_path: NodePath = ^"/root/GameState"
@export var flag: StringName
@export var expected := true


func matches(context: SceneActionContext) -> bool:
	var state := context.resolve(state_path)
	return state != null and state.has_method(&"get_flag") \
		and bool(state.call(&"get_flag", flag, false)) == expected


func diagnostics(context: SceneActionContext) -> PackedStringArray:
	if flag.is_empty():
		return ["Flag condition needs a flag key"]
	var state := context.resolve(state_path)
	if state == null or not state.has_method(&"get_flag"):
		return ["Flag state must expose get_flag"]
	return []
