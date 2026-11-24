extends Node

const Director = preload("res://scripts/systems/scene_director.gd")
const PlayerState = preload("res://scripts/player/player_campaign_state.gd")
const TAVERN_SCENE_PATH := "res://scenes/main.tscn"

const CURRENT_SCHEMA_VERSION := 1
const DEFAULT_SAVE_PATH := "user://campaign_save.cfg"
const TEST_PATH_ENV := "DSR_CAMPAIGN_SAVE_CONFIG"

var save_path := DEFAULT_SAVE_PATH
var last_error: Error = OK
var last_error_code: StringName = &""
var startup_warning_count := 0
var startup_pending := false
var _reset_staged := false
var _debug_reset_in_flight := false


func _ready() -> void:
	var override := OS.get_environment(TEST_PATH_ENV)
	if not override.is_empty():
		save_path = override
	var args := OS.get_cmdline_args()
	if not should_load_saved_state(args, override):
		return
	if _has_option(args, ["--script", "-s"]):
		apply_startup_game(args, override)
	else:
		startup_pending = true
		_restore_startup_scene.call_deferred()


func _restore_startup_scene() -> void:
	# The scene director registers during deferred initialization.
	await get_tree().process_frame
	var scene := get_tree().current_scene
	if scene != null and scene.scene_file_path == _launch_scene_path():
		resume_game(scene)
	startup_pending = false


func _launch_scene_path() -> String:
	return String(ProjectSettings.get_setting("application/run/main_scene", TAVERN_SCENE_PATH))


## Restore the snapshot only once the director's normal scene transition is accepted.
func resume_game(scene: Node) -> SceneRequest:
	var error := _reconcile_stale_reset_artifacts()
	if error != OK:
		_fail(error, &"reset_reconcile_failed")
		_report_startup_load_error()
		return null
	var snapshot := load_game()
	if snapshot.is_empty():
		if last_error != OK: _report_startup_load_error()
		return null
	var director = Director.for_node(scene)
	if director == null:
		_fail(ERR_UNAVAILABLE, &"missing_scene_director")
		_report_startup_load_error()
		return null
	return director.request_action(&"transition", {"source": scene, "parameters": {
		"path": TAVERN_SCENE_PATH, "mode": &"resume_campaign", "save_snapshot": snapshot,
		"return_control_on_failure": true,
	}})


func can_save_game(scene: Node) -> bool:
	var state := _game_state()
	if scene == null or state == null:
		return false
	if scene.scene_file_path == TAVERN_SCENE_PATH:
		return not state.get_flag(&"opening_active") or state.get_flag(&"opening_complete")
	return not state.last_tavern_state.is_empty()


func save_current_game(scene: Node) -> Dictionary:
	if not can_save_game(scene):
		return {"ok": false, "result": &"unavailable"}
	var state := _game_state()
	var in_tavern := scene.scene_file_path == TAVERN_SCENE_PATH
	var snapshot: Dictionary
	if in_tavern:
		var player := get_tree().get_first_node_in_group(&"player")
		snapshot = state.capture_save_state(PlayerState.capture(player))
	else:
		snapshot = state.last_tavern_state.duplicate(true)
	if save_game(snapshot) != OK:
		return {"ok": false, "result": &"save_failed"}
	if in_tavern:
		state.remember_tavern_state(snapshot)
	return {"ok": true, "result": &"tavern_saved" if in_tavern else &"level_saved"}


func request_debug_reset(director: Node) -> bool:
	var debug_settings := get_node_or_null("/root/DebugSettings")
	if _debug_reset_in_flight or not OS.is_debug_build() or debug_settings == null or not debug_settings.enabled:
		return false
	if stage_reset() != OK:
		director.report_action_error("reset", "Unable to stage save deletion")
		return false
	_debug_reset_in_flight = true
	debug_settings.preserve_enabled_once()
	var request: SceneRequest = director.request_action(&"transition", {"parameters": {
		"path": _launch_scene_path(), "mode": &"reset_progress", "return_control_on_failure": true,
	}})
	if request.is_terminal():
		_on_debug_reset_finished(request, weakref(director))
	else:
		request.finished.connect(_on_debug_reset_finished.bind(weakref(director)), CONNECT_ONE_SHOT)
	return request.status not in [&"failed", &"cancelled", &"rejected"]


func _on_debug_reset_finished(request: SceneRequest, director_ref: WeakRef) -> void:
	var completed := request.status == &"completed"
	if not completed:
		get_node("/root/DebugSettings").cancel_preserved_enabled()
	var error := finish_staged_reset() if completed else restore_staged_reset()
	_debug_reset_in_flight = false
	if error == OK:
		return
	var reason := "Unable to remove staged reset save" if completed else "Unable to restore staged reset save"
	var message := "%s: %s" % [reason, error_string(error)]
	var director = director_ref.get_ref()
	if is_instance_valid(director):
		director.report_action_error("reset", message)
	push_warning("reset: %s" % message)


func should_load_saved_state(args: PackedStringArray, override: String) -> bool:
	if override.is_empty() and _has_option(args, ["--script", "-s"]):
		return false
	if not _has_option(args, ["--scene"]):
		return true
	var scene_path := _option_value(args, "--scene")
	if scene_path.is_empty():
		return false
	return scene_path.simplify_path() == _launch_scene_path().simplify_path()


func _has_option(args: PackedStringArray, names: Array[String]) -> bool:
	for argument in args:
		for name in names:
			if argument == name or argument.begins_with(name + "="):
				return true
	return false


func _option_value(args: PackedStringArray, name: String) -> String:
	for index in range(args.size()):
		var argument: String = args[index]
		if argument.begins_with(name + "="):
			return argument.trim_prefix(name + "=")
		if argument == name and index + 1 < args.size():
			return args[index + 1]
	return ""


func apply_startup_game(args: PackedStringArray, override: String) -> Error:
	if not should_load_saved_state(args, override):
		return OK
	var reconcile_error := _reconcile_stale_reset_artifacts()
	if reconcile_error != OK:
		_fail(reconcile_error, &"reset_reconcile_failed")
		_report_startup_load_error()
		return reconcile_error
	var error := apply_saved_game()
	if error != OK:
		_report_startup_load_error()
	return error


func _report_startup_load_error() -> void:
	if startup_warning_count > 0:
		return
	startup_warning_count += 1
	push_warning("Campaign save startup load failed (%s): %s" % [
		last_error_code,
		save_path,
	])


func save_game(snapshot: Dictionary) -> Error:
	if _debug_reset_in_flight or _has_pending_reset_artifact():
		return _fail(ERR_BUSY, &"reset_pending_exists")
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
		var keep_backup := FileAccess.file_exists(backup_path) \
			and _read_snapshot(save_path).is_empty() and not _read_snapshot(backup_path).is_empty()
		if keep_backup:
			error = _remove_file(save_path)
		else:
			error = _remove_file(backup_path)
			if error == OK: error = _rename(save_path, backup_path)
		if error != OK:
			_remove_file(temp_path)
			return _fail(error, &"replace_failed")
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
	var primary_exists := FileAccess.file_exists(save_path)
	var backup_path := save_path + ".bak"
	var backup_exists := FileAccess.file_exists(backup_path)
	if not primary_exists and not backup_exists:
		last_error = OK
		last_error_code = &""
		return {}
	if primary_exists:
		var primary_snapshot := _read_snapshot(save_path)
		if not primary_snapshot.is_empty():
			return primary_snapshot
		var primary_error := last_error
		var primary_error_code := last_error_code
		if backup_exists:
			var backup_snapshot := _read_snapshot(backup_path)
			if not backup_snapshot.is_empty():
				return backup_snapshot
		last_error = primary_error
		last_error_code = primary_error_code
		return {}
	var recovered_snapshot := _read_snapshot(backup_path)
	if recovered_snapshot.is_empty():
		return {}
	_rename(backup_path, save_path)
	return recovered_snapshot


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
	return _ok()


func stage_reset() -> Error:
	if _reset_staged:
		if _has_pending_reset_artifact():
			return _fail(ERR_ALREADY_EXISTS, &"reset_pending_exists")
		_reset_staged = false
	var reconcile_error := _reconcile_stale_reset_artifacts()
	if reconcile_error != OK:
		return _fail(reconcile_error, &"reset_reconcile_failed")
	var pairs := _reset_file_pairs()
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
	_reset_staged = true
	return _ok()


func restore_staged_reset() -> Error:
	if not _reset_staged:
		var reconcile_error := _reconcile_stale_reset_artifacts()
		if reconcile_error != OK:
			return _fail(reconcile_error, &"reset_reconcile_failed")
		return _ok()
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
	_reset_staged = false
	return _ok()


func finish_staged_reset() -> Error:
	if not _reset_staged:
		var reconcile_error := _reconcile_stale_reset_artifacts()
		if reconcile_error != OK:
			return _fail(reconcile_error, &"reset_reconcile_failed")
		return _ok()
	var first_error := OK
	for pair in _reset_file_pairs():
		if not FileAccess.file_exists(pair.pending):
			continue
		var error := _remove_file(pair.pending)
		if error != OK and first_error == OK:
			first_error = error
	if first_error != OK:
		return _fail(first_error, &"reset_finish_failed")
	_reset_staged = false
	return _ok()


func _reconcile_stale_reset_artifacts() -> Error:
	if not _has_pending_reset_artifact():
		return OK
	var first_error := OK
	for path in [
			save_path,
			save_path + ".bak",
			save_path + ".reset-pending",
			save_path + ".bak.reset-pending",
		]:
		var error := _remove_file(path)
		if error != OK and first_error == OK:
			first_error = error
	return first_error


func _has_pending_reset_artifact() -> bool:
	var pairs := _reset_file_pairs()
	for pair in pairs:
		if FileAccess.file_exists(pair.pending):
			return true
	return false


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
	# Kept in schema v1 for saves produced by the original implementation.
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
	var schema_version: Variant = config.get_value("save", "schema_version", null)
	if not schema_version is int:
		last_error_code = &"invalid_state"
		return {}
	if schema_version != CURRENT_SCHEMA_VERSION:
		last_error_code = &"unsupported_version"
		return {}
	for entry in [
			["save", "saved_at_unix"],
			["save", "opening_cinematic_played"],
		]:
		if not config.has_section_key(entry[0], entry[1]):
			last_error_code = &"invalid_state"
			return {}
	var saved_at: Variant = config.get_value("save", "saved_at_unix", null)
	if not saved_at is int or int(saved_at) < 0:
		last_error_code = &"invalid_state"
		return {}
	if not config.get_value("save", "opening_cinematic_played", null) is bool:
		last_error_code = &"invalid_state"
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
