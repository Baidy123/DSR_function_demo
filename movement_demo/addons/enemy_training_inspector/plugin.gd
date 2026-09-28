@tool
extends EditorPlugin

var inspector: EditorInspectorPlugin

func _enter_tree() -> void:
	inspector = preload("res://addons/enemy_training_inspector/inspector.gd").new()
	inspector.undo_redo = get_undo_redo()
	add_inspector_plugin(inspector)

func _exit_tree() -> void:
	remove_inspector_plugin(inspector)
	inspector = null
