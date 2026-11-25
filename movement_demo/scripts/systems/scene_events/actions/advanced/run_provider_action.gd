@tool
class_name RunProviderAction
extends SceneAction

@export_node_path("Node") var target_path: NodePath
@export var parameters: Dictionary = {}


func begin(context: SceneActionContext) -> void:
	var target := context.resolve(target_path)
	if target == null or not target.has_method(&"begin_scene_action") \
			or not target.has_method(&"cancel_scene_action"):
		context.fail(&"invalid_scene_action_provider")
		return
	var provider_parameters := parameters.duplicate(true)
	provider_parameters["mode"] = &"provider"
	context.request(&"script", target, provider_parameters, {"source": target})
