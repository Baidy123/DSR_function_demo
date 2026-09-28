extends "res://scripts/enemy/actions/enemy_action.gd"

var ticks := 0
var cancelled := false

func collect_candidates(_visible: bool) -> Array[Dictionary]:
	return [option({}, 0.0, 0.0)]

func tick(_delta: float, _visible: bool) -> Dictionary:
	ticks += 1
	return motion(Vector3.ZERO)

func cancel(reason: StringName = &"switch") -> void:
	cancelled = true
	super.cancel(reason)
