@tool
class_name CompleteSceneAction
extends SceneAction


func begin(context: SceneActionContext) -> void:
	context.request(&"completion")
