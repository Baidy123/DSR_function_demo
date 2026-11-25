@tool
class_name RunProviderAction
extends SceneAction

enum RequestKind { SCRIPT, SHOP }

@export_node_path("Node") var target_path: NodePath
@export_node_path("Node3D") var player_path: NodePath
@export var request_kind: RequestKind = RequestKind.SCRIPT
@export var parameters: Dictionary = {}


func begin(context: SceneActionContext) -> void:
	var target := context.resolve(target_path)
	if target == null or not target.has_method(&"begin_scene_action") \
			or not target.has_method(&"cancel_scene_action"):
		context.fail(&"invalid_scene_action_provider")
		return
	var provider_parameters := parameters.duplicate(true)
	var options := {"source": target}
	var kind := &"script"
	if request_kind == RequestKind.SHOP:
		kind = &"shop"
		var player := context.resolve(player_path) as Node3D
		if player == null:
			context.fail(&"missing_provider_player")
			return
		options["player"] = player
	else:
		provider_parameters["mode"] = &"provider"
	context.request(kind, target, provider_parameters, options)
