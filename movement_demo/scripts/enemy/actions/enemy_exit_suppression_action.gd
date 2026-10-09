extends "res://scripts/enemy/actions/enemy_suppression_action.gd"

## Disabled compatibility shell. Old resource/UID references cannot restore exits.
func is_enabled() -> bool:
	return false

func default_mode() -> StringName:
	return &"disabled_exit"
