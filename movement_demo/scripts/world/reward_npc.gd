extends "res://scripts/world/npc.gd"

## 酒馆蓝色商店 NPC：交互时打开货币商店，失败则回退到普通对话。

@export var shop_controller_path: NodePath = ^"../ShopController"

@onready var shop_controller: Node = get_node_or_null(shop_controller_path)


func _ready() -> void:
	super._ready()
	interaction_requested.connect(_on_interaction_requested)


func _on_interaction_requested(player: Node3D) -> void:
	if shop_controller == null or not shop_controller.has_method(&"open_shop_for_player"):
		return
	if shop_controller.open_shop_for_player(player):
		get_viewport().set_input_as_handled()
