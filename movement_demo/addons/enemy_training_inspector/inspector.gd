@tool
extends EditorInspectorPlugin

var undo_redo: EditorUndoRedoManager

func _can_handle(object: Object) -> bool:
	return object is EnemyUnitProfile or object is EnemyTrainingProfile or object.get_script() == preload("res://scripts/enemy/enemy_training.gd")

func _parse_begin(object: Object) -> void:
	if object is EnemyUnitProfile:
		var validation = preload("res://addons/enemy_training_inspector/unit_validation.gd").new()
		validation.unit = object
		add_custom_control(validation)
		return
	var panel = preload("res://addons/enemy_training_inspector/tactics_panel.gd").new()
	panel.configure(object, undo_redo)
	add_custom_control(panel)
