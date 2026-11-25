@tool
class_name SceneWaveCondition
extends SceneCondition

@export_node_path("Node") var wave_path: NodePath
@export var expected_status: StringName = &"cleared"


func matches(context: SceneActionContext) -> bool:
	var wave := context.resolve(wave_path)
	return wave != null and is_instance_valid(context.director) \
		and context.director.has_method(&"wave_status") \
		and StringName(context.director.call(&"wave_status", wave)) == expected_status


func diagnostics(context: SceneActionContext) -> PackedStringArray:
	if context.resolve(wave_path) == null:
		return ["Wave condition target is missing"]
	if not is_instance_valid(context.director) or not context.director.has_method(&"wave_status"):
		return ["Scene director must expose wave_status"]
	return []
