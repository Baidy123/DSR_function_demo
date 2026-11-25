@tool
class_name SceneNodeCondition
extends SceneCondition

enum Query { EXISTS, VISIBLE, ENABLED, IN_GROUP }

@export_node_path("Node") var target_path: NodePath
@export var query: Query = Query.EXISTS
@export var expected := true
@export var group: StringName


func matches(context: SceneActionContext) -> bool:
	var target := context.resolve(target_path)
	var result := target != null
	if target != null:
		match query:
			Query.VISIBLE:
				result = bool(target.get(&"visible")) if _has_property(target, &"visible") else false
			Query.ENABLED:
				if _has_property(target, &"enabled"):
					result = bool(target.get(&"enabled"))
				elif _has_property(target, &"disabled"):
					result = not bool(target.get(&"disabled"))
				else:
					result = target.process_mode != Node.PROCESS_MODE_DISABLED
			Query.IN_GROUP:
				result = not group.is_empty() and target.is_in_group(group)
	return result == expected


func diagnostics(_context: SceneActionContext) -> PackedStringArray:
	if target_path.is_empty():
		return ["Node condition needs a target path"]
	if query == Query.IN_GROUP and group.is_empty():
		return ["Node group condition needs a group"]
	return []


func _has_property(target: Object, property_name: StringName) -> bool:
	for property in target.get_property_list():
		if property.name == property_name:
			return true
	return false
