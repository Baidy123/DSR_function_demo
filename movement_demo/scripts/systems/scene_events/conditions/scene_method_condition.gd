@tool
class_name SceneMethodCondition
extends SceneCondition

const Scripts = preload("res://scripts/systems/scene_script_executor.gd")

@export_node_path("Node") var target_path: NodePath
@export var method: StringName
@export var arguments: Array = []
@export var expected := true


func matches(context: SceneActionContext) -> bool:
	if not diagnostics(context).is_empty():
		return false
	var target := context.resolve(target_path)
	var result: Variant = target.callv(method, arguments)
	return typeof(result) == TYPE_BOOL and bool(result) == expected


func diagnostics(context: SceneActionContext) -> PackedStringArray:
	var target := context.resolve(target_path)
	var error: String = Scripts.method_error(target, method, arguments)
	if not error.is_empty():
		return [error]
	for metadata in target.get_method_list():
		if metadata.name != method:
			continue
		var return_metadata: Dictionary = metadata.get("return", {})
		if int(return_metadata.get("type", TYPE_NIL)) != TYPE_BOOL:
			return ["Condition method must declare a bool result: %s" % method]
		return []
	return ["Method metadata missing: %s" % method]
