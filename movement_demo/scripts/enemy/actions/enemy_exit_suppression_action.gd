extends "res://scripts/enemy/actions/enemy_suppression_action.gd"

## Old resources retain this script UID; assembly uses one unified runtime action.
func default_mode() -> StringName:
	return &"exit_sweep"
