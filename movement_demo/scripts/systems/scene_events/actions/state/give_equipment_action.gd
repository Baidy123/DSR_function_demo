@tool
class_name GiveEquipmentAction
extends SceneAction

@export_node_path("PlayerEquipmentGrant") var grant_path: NodePath
@export_node_path("Node") var player_path: NodePath


func begin(context: SceneActionContext) -> void:
	var grant := context.resolve(grant_path)
	if grant == null or not grant.has_method(&"begin_scene_action") \
			or not grant.has_method(&"cancel_scene_action"):
		context.fail(&"invalid_equipment_grant")
		return
	var options := {"source": grant}
	if not player_path.is_empty():
		var player := context.resolve(player_path)
		if player == null:
			context.fail(&"missing_equipment_player")
			return
		options["player"] = player
	context.request(&"script", grant, {}, options)
