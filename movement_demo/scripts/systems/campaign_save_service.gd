extends Node

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_SAVE_PATH := "user://campaign_save.cfg"
const TEST_PATH_ENV := "DSR_CAMPAIGN_SAVE_CONFIG"

var save_path := DEFAULT_SAVE_PATH
var last_error: Error = OK
var last_error_code: StringName = &""


func _ready() -> void:
	var override := OS.get_environment(TEST_PATH_ENV)
	if not override.is_empty():
		save_path = override
	var args := OS.get_cmdline_args()
	if not should_load_saved_state(args, override):
		return
	apply_saved_game()


func should_load_saved_state(args: PackedStringArray, override: String) -> bool:
	return not override.is_empty() or not args.has("--script")


func save_game(snapshot: Dictionary) -> Error:
	var state = _game_state()
	if state == null or not state.validate_save_state(snapshot):
		return _fail(ERR_INVALID_DATA, &"invalid_state")
	var temp_path := save_path + ".tmp"
	var backup_path := save_path + ".bak"
	_remove_file(temp_path)
	var error := _encode(snapshot).save(temp_path)
	if error != OK:
		return _fail(error, &"write_failed")
	var verify := ConfigFile.new()
	if verify.load(temp_path) != OK or _decode(verify).is_empty():
		_remove_file(temp_path)
		return _fail(ERR_FILE_CORRUPT, &"verify_failed")
	if FileAccess.file_exists(save_path):
		if _remove_file(backup_path) != OK:
			_remove_file(temp_path)
			return _fail(ERR_CANT_CREATE, &"replace_failed")
		if _rename(save_path, backup_path) != OK:
			_remove_file(temp_path)
			return _fail(ERR_CANT_CREATE, &"replace_failed")
	if _rename(temp_path, save_path) != OK:
		var rollback_error := OK
		if FileAccess.file_exists(backup_path):
			rollback_error = _rename(backup_path, save_path)
		_remove_file(temp_path)
		if rollback_error != OK:
			return _fail(rollback_error, &"rollback_failed")
		return _fail(ERR_CANT_CREATE, &"replace_failed")
	_remove_file(backup_path)
	return _ok()


func load_game() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		var backup_path := save_path + ".bak"
		if FileAccess.file_exists(backup_path):
			var backup_snapshot := _read_snapshot(backup_path)
			if backup_snapshot.is_empty():
				return {}
			_rename(backup_path, save_path)
			return backup_snapshot
		last_error = OK
		last_error_code = &""
		return {}
	return _read_snapshot(save_path)


func _read_snapshot(path: String) -> Dictionary:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		last_error = error
		last_error_code = &"read_failed"
		return {}
	var snapshot := _decode(config)
	if snapshot.is_empty():
		last_error = ERR_FILE_CORRUPT
		return {}
	last_error = OK
	last_error_code = &""
	return snapshot


func apply_saved_game() -> Error:
	var snapshot := load_game()
	if snapshot.is_empty():
		return last_error
	var state = _game_state()
	if state == null or not state.apply_save_state(snapshot, true):
		return _fail(ERR_INVALID_DATA, &"apply_failed")
	state.opening_cinematic_played = true
	return _ok()


func stage_reset() -> Error:
	var pairs := _reset_file_pairs()
	for pair in pairs:
		if FileAccess.file_exists(pair.pending):
			return _fail(ERR_ALREADY_EXISTS, &"reset_pending_exists")
	var staged: Array[Dictionary] = []
	for pair in pairs:
		if not FileAccess.file_exists(pair.original):
			continue
		var error := _rename(pair.original, pair.pending)
		if error != OK:
			var rollback_error := _restore_staged_files(staged)
			if rollback_error != OK:
				return _fail(rollback_error, &"rollback_failed")
			return _fail(error, &"reset_stage_failed")
		staged.append(pair)
	return _ok()


func restore_staged_reset() -> Error:
	var first_error := OK
	for pair in _reset_file_pairs():
		if not FileAccess.file_exists(pair.pending):
			continue
		var error := OK
		if FileAccess.file_exists(pair.original):
			error = ERR_ALREADY_EXISTS
		else:
			error = _rename(pair.pending, pair.original)
		if error != OK and first_error == OK:
			first_error = error
	if first_error != OK:
		return _fail(first_error, &"reset_restore_failed")
	return _ok()


func finish_staged_reset() -> Error:
	var first_error := OK
	for pair in _reset_file_pairs():
		if not FileAccess.file_exists(pair.pending):
			continue
		var error := _remove_file(pair.pending)
		if error != OK and first_error == OK:
			first_error = error
	if first_error != OK:
		return _fail(first_error, &"reset_finish_failed")
	return _ok()


func _reset_file_pairs() -> Array[Dictionary]:
	return [
		{"original": save_path, "pending": save_path + ".reset-pending"},
		{"original": save_path + ".bak", "pending": save_path + ".bak.reset-pending"},
	]


func _restore_staged_files(staged: Array[Dictionary]) -> Error:
	var first_error := OK
	for index in range(staged.size() - 1, -1, -1):
		var pair: Dictionary = staged[index]
		var error := _rename(pair.pending, pair.original)
		if error != OK and first_error == OK:
			first_error = error
	return first_error


func _encode(snapshot: Dictionary) -> ConfigFile:
	var config := ConfigFile.new()
	config.set_value("save", "schema_version", CURRENT_SCHEMA_VERSION)
	config.set_value("save", "saved_at_unix", int(Time.get_unix_time_from_system()))
	config.set_value("save", "opening_cinematic_played", true)
	for key in ["completed_level", "available_level", "claimed_reward_levels",
			"task_a_returned", "money", "rewarded_task_ids",
			"purchased_shop_item_ids", "campaign_checkpoint",
			"level_entry_player_state"]:
		config.set_value("campaign", key, snapshot.get(key))
	for key in ["talked_to_a", "help_choice", "music_quest_choice",
			"music_quest_turnin"]:
		config.set_value("dialogue", key, snapshot.get(key))
	for key in ["items", "flags", "shop_flag_keys"]:
		config.set_value("world", key, snapshot.get(key))
	config.set_value("player", "player_state", snapshot.get("player_state", {}))
	return config


func _decode(config: ConfigFile) -> Dictionary:
	if int(config.get_value("save", "schema_version", -1)) != CURRENT_SCHEMA_VERSION:
		last_error_code = &"unsupported_version"
		return {}
	for entry in [
			["campaign", "completed_level"],
			["campaign", "available_level"],
			["campaign", "claimed_reward_levels"],
			["campaign", "task_a_returned"],
			["campaign", "money"],
			["campaign", "rewarded_task_ids"],
			["campaign", "purchased_shop_item_ids"],
			["campaign", "campaign_checkpoint"],
			["campaign", "level_entry_player_state"],
			["dialogue", "talked_to_a"],
			["dialogue", "help_choice"],
			["dialogue", "music_quest_choice"],
			["dialogue", "music_quest_turnin"],
			["world", "items"],
			["world", "flags"],
			["world", "shop_flag_keys"],
			["player", "player_state"],
		]:
		if not config.has_section_key(entry[0], entry[1]):
			last_error_code = &"invalid_state"
			return {}
	var snapshot := {
		"completed_level": config.get_value("campaign", "completed_level", 0),
		"available_level": config.get_value("campaign", "available_level", 1),
		"claimed_reward_levels": config.get_value("campaign", "claimed_reward_levels", {}),
		"task_a_returned": config.get_value("campaign", "task_a_returned", ""),
		"money": config.get_value("campaign", "money", 0),
		"rewarded_task_ids": config.get_value("campaign", "rewarded_task_ids", {}),
		"purchased_shop_item_ids": config.get_value("campaign", "purchased_shop_item_ids", {}),
		"campaign_checkpoint": config.get_value("campaign", "campaign_checkpoint", {}),
		"level_entry_player_state": config.get_value("campaign", "level_entry_player_state", {}),
		"talked_to_a": config.get_value("dialogue", "talked_to_a", false),
		"help_choice": config.get_value("dialogue", "help_choice", ""),
		"music_quest_choice": config.get_value("dialogue", "music_quest_choice", ""),
		"music_quest_turnin": config.get_value("dialogue", "music_quest_turnin", ""),
		"items": config.get_value("world", "items", {}),
		"flags": config.get_value("world", "flags", {}),
		"shop_flag_keys": config.get_value("world", "shop_flag_keys", {}),
		"player_state": config.get_value("player", "player_state", {}),
	}
	if not _game_state().validate_save_state(snapshot):
		last_error_code = &"invalid_state"
		return {}
	return snapshot


func _game_state() -> Node:
	if is_inside_tree():
		return get_node_or_null("/root/GameState")
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameState")


func _rename(from_path: String, to_path: String) -> Error:
	return DirAccess.rename_absolute(from_path, to_path)


func _remove_file(path: String) -> Error:
	if not FileAccess.file_exists(path):
		return OK
	return DirAccess.remove_absolute(path)


func _fail(error: Error, code: StringName) -> Error:
	last_error = error
	last_error_code = code
	return error


func _ok() -> Error:
	last_error = OK
	last_error_code = &""
	return OK
