@tool
class_name SceneItemCondition
extends SceneCondition

@export_node_path("Node") var state_path: NodePath = ^"/root/GameState"
@export var item_id: StringName
@export_range(0, 999999, 1) var minimum_count := 1


func matches(context: SceneActionContext) -> bool:
	var state := context.resolve(state_path)
	return state != null and state.has_method(&"get_item_count") \
		and int(state.call(&"get_item_count", item_id)) >= minimum_count


func diagnostics(context: SceneActionContext) -> PackedStringArray:
	if item_id.is_empty():
		return ["Item condition needs an item id"]
	var state := context.resolve(state_path)
	if state == null or not state.has_method(&"get_item_count"):
		return ["Item state must expose get_item_count"]
	return []
