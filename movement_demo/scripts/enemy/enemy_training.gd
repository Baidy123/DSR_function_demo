@tool
extends Node

@export var profile: EnemyTrainingProfile:
	set(value):
		profile = value
		notify_property_list_changed()

func _ready() -> void:
	if not Engine.is_editor_hint() and profile != null:
		profile = profile.duplicate(true)
