@tool
extends "res://scripts/enemy/config/module_settings.gd"
class_name EnemyCooperationSettings

enum Level { INTEL_ONLY, TACTICAL, COORDINATED }

## Levels 1/2 both command the squad; optional actions still require training.
@export_enum("仅视野共享", "战术配合", "强配合") var level: int = Level.INTEL_ONLY:
	set(value):
		level = clampi(value, Level.INTEL_ONLY, Level.COORDINATED)
		mark_override(&"level")

func _init() -> void:
	section = &"cooperation"

## Expiry limits precise shared evidence, never completes a search objective.
@export_range(0.1, 15.0, 0.1) var intel_seconds := 5.0:
	set(value):
		intel_seconds = value
		mark_override(&"intel_seconds")
@export_range(0.5, 15.0, 0.1) var checked_point_seconds := 3.0:
	set(value):
		checked_point_seconds = value
		mark_override(&"checked_point_seconds")
## Personal inspection evidence. Commanded searches own a persistent objective.
@export_range(1.0, 40.0, 0.5) var cover_inspection_seconds := 20.0:
	set(value):
		cover_inspection_seconds = value
		mark_override(&"cover_inspection_seconds")
@export_range(0.0, 1.0, 0.05) var spacing_margin := 0.45:
	set(value):
		spacing_margin = value
		mark_override(&"spacing_margin")

## Commanded flanking and catching up to waiting teammates; frozen per battle.
@export_range(1.0, 3.0, 0.1) var run_speed_multiplier := 2.0:
	set(value):
		run_speed_multiplier = value
		mark_override(&"run_speed_multiplier")
