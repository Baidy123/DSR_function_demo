class_name PlayerEquipmentGrant
extends Node

const Director = preload("res://scripts/systems/scene_director.gd")

## Drag this node into a scene and target it with a RUN_SCRIPT action.
## A weapon fills the specified slot with a full magazine. Leave it empty for supplies only.
@export var weapon: WeaponData
@export_enum("主武器:0", "副武器:1") var weapon_slot: int = 0
@export var ammo_supplies: Array[AmmoSupply] = []
@export var medkit: MedkitData
@export_range(0, 999, 1, "or_greater") var medkit_amount := 0


func begin_scene_action(request: SceneRequest) -> void:
	if request.kind != &"script" or request.node(&"target") != self \
			or request.status != &"running" or not request.is_current():
		return
	var player := _recipient(request)
	var equipment := player.get_node_or_null("Equipment") if player != null else null
	if equipment == null or not equipment.has_method(&"grant_equipment"):
		request.fail("missing_player_equipment")
	elif not equipment.grant_equipment(weapon_slot, weapon, ammo_supplies, medkit, medkit_amount):
		request.fail("invalid_equipment_grant")
	else:
		request.complete()


func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void:
	# The approved grant is synchronous and owns no running animation or timer.
	pass


func _recipient(request: SceneRequest) -> Node:
	var director := Director.for_node(self)
	var explicit_player := request.node(&"player")
	if explicit_player != null:
		if explicit_player.is_in_group(&"player") and Director.for_node(explicit_player) == director:
			return explicit_player
		return null
	var player: Node
	for candidate in get_tree().get_nodes_in_group(&"player"):
		if Director.for_node(candidate) != director:
			continue
		if player != null:
			return null
		player = candidate
	return player
