@tool
class_name CallInteractionAction
extends SceneAction

@export_node_path("Node") var interaction_path: NodePath
@export_node_path("Node3D") var player_path: NodePath


func begin(context: SceneActionContext) -> void:
	var interaction := context.resolve(interaction_path)
	var player := context.resolve(player_path) as Node3D
	if interaction == null or player == null or not interaction.has_method(&"execute_scene_interaction"):
		context.fail(&"invalid_interaction")
		return
	if interaction.has_method(&"can_interact") and not interaction.call(&"can_interact", player):
		context.fail(&"interaction_blocked")
		return
	context.request(&"interact", interaction, {}, {"source": interaction, "player": player})
