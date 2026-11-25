@tool
class_name SceneAction
extends Resource


func begin(context: SceneActionContext) -> void:
	context.fail(&"action_not_implemented")


func advance(_context: SceneActionContext, _delta: float) -> void:
	pass


func cancel(_context: SceneActionContext, _reason: StringName) -> void:
	pass


func diagnostics(_host: Node) -> PackedStringArray:
	return []


func summary(_host: Node) -> String:
	return get_class()
