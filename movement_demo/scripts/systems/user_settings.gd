extends Node

## 用户偏好只保存设置，不保存任务、货币或玩家进度。
signal settings_changed

enum TargetSwitchSensitivity { LOW, NORMAL, HIGH }
enum WindowMode { WINDOWED, FULLSCREEN, EXCLUSIVE_FULLSCREEN }

const DEFAULT_CONFIG_PATH := "user://settings.cfg"
const RESOLUTIONS := [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const DEFAULT_MOUSE_TARGET_ASSIST_ENABLED := true
const DEFAULT_TARGET_SWITCH_SENSITIVITY := TargetSwitchSensitivity.NORMAL
const DEFAULT_WINDOW_MODE := WindowMode.WINDOWED
const DEFAULT_RESOLUTION_INDEX := 0
const DEFAULT_VSYNC_ENABLED := true

var config_path := DEFAULT_CONFIG_PATH
var mouse_target_assist_enabled := DEFAULT_MOUSE_TARGET_ASSIST_ENABLED
var target_switch_sensitivity: int = DEFAULT_TARGET_SWITCH_SENSITIVITY
var window_mode: int = DEFAULT_WINDOW_MODE
var resolution_index: int = DEFAULT_RESOLUTION_INDEX
var vsync_enabled := DEFAULT_VSYNC_ENABLED
var last_save_error := OK
var has_saved_settings := false


func _ready() -> void:
	if DisplayServer.get_name() != "headless":
		get_window().size_changed.connect(_apply_3d_resolution)
	var config_override := OS.get_environment("DSR_USER_SETTINGS_CONFIG")
	if not config_override.is_empty():
		config_path = config_override
	if should_load_saved_config(OS.get_cmdline_args(), config_override):
		var error := load_settings()
		if error == OK:
			apply_display_settings()
		elif error != ERR_FILE_NOT_FOUND:
			push_warning("无法读取用户设置 %s：%s" % [config_path, error_string(error)])


static func should_load_saved_config(args: PackedStringArray, config_override: String) -> bool:
	return not config_override.is_empty() or not args.has("--script")


func available_resolutions() -> Array:
	return RESOLUTIONS.duplicate()


func resolution() -> Vector2i:
	return RESOLUTIONS[resolution_index]


func target_switch_travel_ratio() -> float:
	match target_switch_sensitivity:
		TargetSwitchSensitivity.LOW:
			return 0.16
		TargetSwitchSensitivity.HIGH:
			return 0.08
		_:
			return 0.12


func default_values() -> Dictionary:
	return {
		"mouse_target_assist_enabled": DEFAULT_MOUSE_TARGET_ASSIST_ENABLED,
		"target_switch_sensitivity": DEFAULT_TARGET_SWITCH_SENSITIVITY,
		"window_mode": DEFAULT_WINDOW_MODE,
		"resolution_index": DEFAULT_RESOLUTION_INDEX,
		"vsync_enabled": DEFAULT_VSYNC_ENABLED,
	}


func commit_settings(
		mouse_assist: bool,
		sensitivity: int,
		mode: int,
		resolution_choice: int,
		vsync: bool) -> Error:
	var normalized_mode := clampi(mode, WindowMode.WINDOWED, WindowMode.EXCLUSIVE_FULLSCREEN)
	if not available_window_modes().has(normalized_mode):
		normalized_mode = WindowMode.FULLSCREEN
	var normalized_sensitivity := clampi(
		sensitivity, TargetSwitchSensitivity.LOW, TargetSwitchSensitivity.HIGH)
	var normalized_resolution := clampi(
		resolution_choice, 0, RESOLUTIONS.size() - 1)
	var error := _write_settings(
		mouse_assist, normalized_sensitivity, normalized_mode, normalized_resolution, vsync)
	last_save_error = error
	if error != OK:
		push_warning("无法保存用户设置 %s：%s" % [config_path, error_string(error)])
		return error
	mouse_target_assist_enabled = mouse_assist
	target_switch_sensitivity = normalized_sensitivity
	window_mode = normalized_mode
	resolution_index = normalized_resolution
	vsync_enabled = vsync
	has_saved_settings = true
	apply_display_settings()
	_apply_gameplay_settings()
	settings_changed.emit()
	return OK


func load_settings() -> Error:
	has_saved_settings = false
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
	if not available_window_modes().has(window_mode):
		window_mode = WindowMode.FULLSCREEN
	resolution_index = _enum_setting(
		config, "display", "resolution_index", DEFAULT_RESOLUTION_INDEX,
		range(RESOLUTIONS.size()))
	vsync_enabled = _bool_setting(
		config, "display", "vsync_enabled", DEFAULT_VSYNC_ENABLED)
	last_save_error = OK
	has_saved_settings = true
	return OK


func apply_to_combat(combat: Node) -> void:
	if combat == null:
		return
	combat.mouse_target_assist_enabled = mouse_target_assist_enabled
	combat.target_switch_travel_ratio = target_switch_travel_ratio()


func apply_display_settings() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(godot_window_mode())
	if window_mode == WindowMode.WINDOWED:
		DisplayServer.window_set_size(resolution())
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	_apply_3d_resolution()


func _apply_3d_resolution() -> void:
	if not has_saved_settings:
		return
	var window := get_window()
	if window_mode == WindowMode.WINDOWED:
		window.scaling_3d_scale = 1.0
		return
	var output_size := DisplayServer.window_get_size()
	if output_size.x <= 0 or output_size.y <= 0:
		return
	var target := resolution()
	# The viewport keeps its aspect ratio within the native fullscreen output.
	window.scaling_3d_scale = minf(1.0, maxf(
		float(target.x) / output_size.x, float(target.y) / output_size.y))


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


func _write_settings(
		mouse_assist: bool,
		sensitivity: int,
		mode: int,
		resolution_choice: int,
		vsync: bool) -> Error:
	var config := ConfigFile.new()
	config.set_value("input_assist", "mouse_target_assist_enabled", mouse_assist)
	config.set_value("input_assist", "target_switch_sensitivity", sensitivity)
	config.set_value("display", "window_mode", mode)
	config.set_value("display", "resolution_index", resolution_choice)
	config.set_value("display", "vsync_enabled", vsync)
	return config.save(config_path)


func _bool_setting(config: ConfigFile, section: String, key: String, fallback: bool) -> bool:
	var value = config.get_value(section, key, fallback)
	return value if typeof(value) == TYPE_BOOL else fallback


func _enum_setting(
		config: ConfigFile, section: String, key: String, fallback: int, allowed: Array) -> int:
	var value = config.get_value(section, key, fallback)
	return value if typeof(value) == TYPE_INT and allowed.has(value) else fallback


func _apply_gameplay_settings() -> void:
	if not is_inside_tree():
		return
	for combat in get_tree().get_nodes_in_group(&"user_settings_combat"):
		apply_to_combat(combat)
