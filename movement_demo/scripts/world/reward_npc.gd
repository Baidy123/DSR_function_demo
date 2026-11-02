extends "res://scripts/world/npc.gd"

## 酒馆结算奖励 NPC：有未领取奖励时直接打开三选一，否则回退到普通对话。

@export var reward_controller_path: NodePath = ^"../EncounterController"

@onready var reward_controller: Node = get_node_or_null(reward_controller_path)


func _ready() -> void:
	super._ready()
	interaction_requested.connect(_on_interaction_requested)


func _on_interaction_requested(player: Node3D) -> void:
	if reward_controller == null or not reward_controller.has_method(&"open_reward_for_player"):
		return
	if reward_controller.open_reward_for_player(player):
		get_viewport().set_input_as_handled()
