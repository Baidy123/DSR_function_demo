@tool
extends EditorPlugin

var inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	inspector = preload("res://addons/scene_event_inspector/inspector.gd").new()
	inspector.configure(get_undo_redo())
	add_inspector_plugin(inspector)


func _exit_tree() -> void:
	if inspector != null:
		remove_inspector_plugin(inspector)
		inspector = null
