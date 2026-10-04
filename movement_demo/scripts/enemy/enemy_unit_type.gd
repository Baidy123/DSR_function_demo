@tool
extends Node

@export var profile: EnemyUnitProfile:
	set(value):
		profile = value
		notify_property_list_changed()

func supports_firearms() -> bool:
	return profile != null and profile.capabilities.has(&"firearms")


## 专用近战武器的装备资格；与枪械附带的基础挥击能力分开。
func supports_melee_weapons() -> bool:
	return profile != null and profile.capabilities.has(&"melee_weapons")



func _ready() -> void:
	if not Engine.is_editor_hint() and profile != null:
		profile = profile.duplicate(true)
