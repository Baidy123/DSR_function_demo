@tool
class_name UpdateQuestAction
extends SceneAction

enum Operation { ACCEPT, REFUSE, COMPLETE, FAIL, SET_STATUS }

@export_node_path("Node") var controller_path: NodePath
@export var quest_id: StringName
@export var operation: Operation = Operation.ACCEPT
@export_range(0, 64, 1) var status := 0


func begin(context: SceneActionContext) -> void:
	var controller := context.resolve(controller_path)
	if controller == null or quest_id.is_empty():
		context.fail(&"invalid_quest_target")
		return
	var method: StringName
	var arguments: Array = [quest_id]
	match operation:
		Operation.ACCEPT: method = &"accept"
		Operation.REFUSE: method = &"refuse"
		Operation.COMPLETE: method = &"complete"
		Operation.FAIL: method = &"fail"
		Operation.SET_STATUS:
			method = &"set_status"
			arguments.append(status)
	if not controller.has_method(method):
		context.fail(&"invalid_quest_operation")
		return
	controller.callv(method, arguments)
	context.complete()
