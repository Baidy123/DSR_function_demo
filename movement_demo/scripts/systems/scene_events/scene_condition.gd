@tool
class_name SceneCondition
extends Resource


func matches(_context: SceneActionContext) -> bool:
	return true


func diagnostics(_context: SceneActionContext) -> PackedStringArray:
	return []
