@tool
extends Node

@export var profile: EnemyUnitProfile:
	set(value):
		profile = value
		notify_property_list_changed()

func supports_firearms() -> bool:
	return profile != null and profile.capabilities.has(&"firearms")



func _ready() -> void:
	if not Engine.is_editor_hint() and profile != null:
		profile = profile.duplicate(true)
