@tool
class_name SceneQuestCondition
extends SceneCondition

@export_node_path("Node") var controller_path: NodePath
@export var quest_id: StringName
@export_enum("Not Started", "In Progress", "Refused", "Completed", "Missed") var expected_status := 0


func matches(context: SceneActionContext) -> bool:
	var controller := context.resolve(controller_path)
	return controller != null and controller.has_method(&"status_of") \
		and int(controller.call(&"status_of", quest_id)) == expected_status


func diagnostics(context: SceneActionContext) -> PackedStringArray:
	if quest_id.is_empty():
		return ["Quest condition needs a quest id"]
	var controller := context.resolve(controller_path)
	if controller == null or not controller.has_method(&"status_of"):
		return ["Quest controller must expose status_of"]
	return []
