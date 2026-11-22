extends Node

## 用户偏好只保存设置，不保存任务、货币或玩家进度。
signal settings_changed

enum TargetSwitchSensitivity { LOW, NORMAL, HIGH }
enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE_FULLSCREEN }

const DEFAULT_CONFIG_PATH := "user://settings.cfg"
const DEFAULT_MOUSE_TARGET_ASSIST_ENABLED := true
const DEFAULT_TARGET_SWITCH_SENSITIVITY := TargetSwitchSensitivity.NORMAL
const DEFAULT_WINDOW_MODE := WindowMode.WINDOWED
const DEFAULT_VSYNC_ENABLED := true

var config_path := DEFAULT_CONFIG_PATH
var mouse_target_assist_enabled := DEFAULT_MOUSE_TARGET_ASSIST_ENABLED
var target_switch_sensitivity: int = DEFAULT_TARGET_SWITCH_SENSITIVITY
var window_mode: int = DEFAULT_WINDOW_MODE
var vsync_enabled := DEFAULT_VSYNC_ENABLED
var last_save_error := OK


func _ready() -> void:
	var config_override := OS.get_environment("DSR_USER_SETTINGS_CONFIG")
	if not config_override.is_empty():
		config_path = config_override
	if should_load_saved_config(OS.get_cmdline_args(), config_override):
		var error := load_settings()
		if error != OK and error != ERR_FILE_NOT_FOUND:
			push_warning("无法读取用户设置 %s：%s" % [config_path, error_string(error)])
	apply_display_settings()


static func should_load_saved_config(args: PackedStringArray, config_override: String) -> bool:
	return not config_override.is_empty() or not args.has("--script")


func target_switch_travel_ratio() -> float:
	match target_switch_sensitivity:
		TargetSwitchSensitivity.LOW:
			return 0.16
		TargetSwitchSensitivity.HIGH:
			return 0.08
		_:
			return 0.12


func save_settings() -> Error:
	var config := ConfigFile.new()
	config.set_value("input_assist", "mouse_target_assist_enabled", mouse_target_assist_enabled)
	config.set_value("input_assist", "target_switch_sensitivity", target_switch_sensitivity)
	config.set_value("display", "window_mode", window_mode)
	config.set_value("display", "vsync_enabled", vsync_enabled)
	return config.save(config_path)


func load_settings() -> Error:
	if not FileAccess.file_exists(config_path):
		return ERR_FILE_NOT_FOUND
	var config := ConfigFile.new()
	var error := config.load(config_path)
	if error != OK:
		return error
	mouse_target_assist_enabled = _bool_setting(
		config, "input_assist", "mouse_target_assist_enabled",
		DEFAULT_MOUSE_TARGET_ASSIST_ENABLED)
	target_switch_sensitivity = _enum_setting(
		config, "input_assist", "target_switch_sensitivity",
		DEFAULT_TARGET_SWITCH_SENSITIVITY,
		[TargetSwitchSensitivity.LOW, TargetSwitchSensitivity.NORMAL, TargetSwitchSensitivity.HIGH])
	window_mode = _enum_setting(
		config, "display", "window_mode", DEFAULT_WINDOW_MODE,
		[WindowMode.WINDOWED, WindowMode.FULLSCREEN, WindowMode.EXCLUSIVE_FULLSCREEN])
	if window_mode == WindowMode.EXCLUSIVE_FULLSCREEN and not available_window_modes().has(window_mode):
		window_mode = WindowMode.FULLSCREEN
	vsync_enabled = _bool_setting(
		config, "display", "vsync_enabled", DEFAULT_VSYNC_ENABLED)
	return OK


func _bool_setting(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value = config.get_value(section, key, fallback)
	return value if typeof(value) == TYPE_BOOL else fallback


func _enum_setting(
		config: ConfigFile, section: String, key: String, fallback: int, allowed: Array) -> int:
	var value = config.get_value(section, key, fallback)
	return value if typeof(value) == TYPE_INT and allowed.has(value) else fallback


func apply_to_combat(combat: Node) -> void:
	if combat == null:
		return
	combat.mouse_target_assist_enabled = mouse_target_assist_enabled
	combat.target_switch_travel_ratio = target_switch_travel_ratio()


func set_mouse_target_assist_enabled(value: bool) -> Error:
	if mouse_target_assist_enabled == value:
		return OK
	mouse_target_assist_enabled = value
	_apply_gameplay_settings()
	return _save_and_notify()


func set_target_switch_sensitivity(value: int) -> Error:
	var normalized := clampi(value, TargetSwitchSensitivity.LOW, TargetSwitchSensitivity.HIGH)
	if target_switch_sensitivity == normalized:
		return OK
	target_switch_sensitivity = normalized
	_apply_gameplay_settings()
	return _save_and_notify()


func set_window_mode(value: int) -> Error:
	var normalized := clampi(value, WindowMode.WINDOWED, WindowMode.EXCLUSIVE_FULLSCREEN)
	if not available_window_modes().has(normalized):
		normalized = WindowMode.FULLSCREEN
	if window_mode == normalized:
		return OK
	window_mode = normalized
	apply_display_settings()
	return _save_and_notify()


func set_vsync_enabled(value: bool) -> Error:
	if vsync_enabled == value:
		return OK
	vsync_enabled = value
	apply_display_settings()
	return _save_and_notify()


func reset_to_defaults() -> Error:
	mouse_target_assist_enabled = true
	target_switch_sensitivity = TargetSwitchSensitivity.NORMAL
	window_mode = WindowMode.WINDOWED
	vsync_enabled = true
	_apply_gameplay_settings()
	apply_display_settings()
	return _save_and_notify()


func apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(godot_window_mode())
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)


func godot_window_mode() -> DisplayServer.WindowMode:
	match window_mode:
		WindowMode.FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN
		WindowMode.EXCLUSIVE_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_FULLSCREEN if OS.get_name() == "macOS" \
				else DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		_:
			return DisplayServer.WINDOW_MODE_WINDOWED


func available_window_modes() -> Array:
	var modes: Array = [WindowMode.WINDOWED, WindowMode.FULLSCREEN]
	if OS.get_name() != "macOS":
		modes.append(WindowMode.EXCLUSIVE_FULLSCREEN)
	return modes


func _apply_gameplay_settings() -> void:
	if not is_inside_tree():
		return
	for combat in get_tree().get_nodes_in_group(&"user_settings_combat"):
		apply_to_combat(combat)


func _save_and_notify() -> Error:
	last_save_error = save_settings()
	if last_save_error != OK:
		push_warning("无法保存用户设置 %s：%s" % [config_path, error_string(last_save_error)])
	settings_changed.emit()
	return last_save_error
