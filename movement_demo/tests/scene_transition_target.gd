extends Node

func _ready() -> void:
	var state := get_node("/root/GameState")
	get_tree().set_meta(&"transition_ready_seen", {"level": state.completed_level,
		"pending": state.take_pending_player_state(), "entry": state.level_entry_player_state.duplicate(true)})
