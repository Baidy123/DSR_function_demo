@tool
extends "res://scripts/enemy/config/module_settings.gd"

func _init() -> void:
	section = &"cooperation"

## Shared sight reports retain their original observation time.
@export_range(0.1, 15.0, 0.1) var intel_seconds := 5.0:
	set(value):
		intel_seconds = value
		mark_override(&"intel_seconds")
@export_range(0.1, 5.0, 0.1) var wait_seconds := 1.2:
	set(value):
		wait_seconds = value
		mark_override(&"wait_seconds")
@export_range(0.5, 15.0, 0.1) var plan_seconds := 4.0:
	set(value):
		plan_seconds = value
		mark_override(&"plan_seconds")
@export_range(0.1, 5.0, 0.1) var lane_hold_seconds := 1.2:
	set(value):
		lane_hold_seconds = value
		mark_override(&"lane_hold_seconds")
@export_range(1.0, 8.0, 0.1) var flank_distance := 3.0:
	set(value):
		flank_distance = value
		mark_override(&"flank_distance")
@export_range(15.0, 120.0, 5.0) var flank_angle_degrees := 60.0:
	set(value):
		flank_angle_degrees = value
		mark_override(&"flank_angle_degrees")
@export_range(5.0, 90.0, 5.0) var minimum_angle_degrees := 25.0:
	set(value):
		minimum_angle_degrees = value
		mark_override(&"minimum_angle_degrees")
@export_range(0.05, 0.9, 0.05) var reload_rounds_ratio := 0.35:
	set(value):
		reload_rounds_ratio = value
		mark_override(&"reload_rounds_ratio")
@export_range(0.0, 5.0, 0.1) var reload_min_support_seconds := 0.5:
	set(value):
		reload_min_support_seconds = value
		mark_override(&"reload_min_support_seconds")
@export_range(0.5, 15.0, 0.1) var checked_point_seconds := 3.0:
	set(value):
		checked_point_seconds = value
		mark_override(&"checked_point_seconds")
@export_range(0.25, 3.0, 0.05) var search_claim_radius := 1.0:
	set(value):
		search_claim_radius = value
		mark_override(&"search_claim_radius")
@export_range(1.0, 20.0, 0.5) var search_claim_seconds := 6.0:
	set(value):
		search_claim_seconds = value
		mark_override(&"search_claim_seconds")
