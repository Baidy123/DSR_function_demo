extends Node

const State = preload("res://scripts/systems/presentation/presentation_state.gd")
@export var presentation_path: NodePath = ^"../Presentation"
@export var dialogue_ui_path: NodePath = ^"../../DialogueUI"
var state = State.new()
@onready var presentation = get_node_or_null(presentation_path)


func _ready() -> void:
	var ui := get_node_or_null(dialogue_ui_path)
	if ui != null:
		ui.dialogue_started.connect(_on_started)
		ui.dialogue_ended.connect(_on_ended)


func _on_started(source: Node) -> void:
	if source != get_parent(): return
	state.in_dialogue = true
	if presentation != null: presentation.apply_state(state)


func _on_ended(source: Node) -> void:
	if source != get_parent(): return
	state.in_dialogue = false
	if presentation != null: presentation.apply_state(state)
