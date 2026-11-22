extends CanvasLayer

## 只展示菜单和回传意图；暂停所有权由 SceneDirector 管理。
signal pause_requested
signal resume_requested
signal quit_requested

@onready var _main: VBoxContainer = $Backdrop/Center/Panel/Content/Main
@onready var _settings: VBoxContainer = $Backdrop/Center/Panel/Content/Settings
@onready var _quit: VBoxContainer = $Backdrop/Center/Panel/Content/Quit
@onready var _title: Label = $Backdrop/Center/Panel/Content/Title
@onready var _guide: CanvasLayer = $PlayGuide
@onready var _mouse_assist: CheckButton = $Backdrop/Center/Panel/Content/Settings/MouseAssistRow/MouseAssist
@onready var _sensitivity: OptionButton = $Backdrop/Center/Panel/Content/Settings/SensitivityRow/Sensitivity
@onready var _window_mode: OptionButton = $Backdrop/Center/Panel/Content/Settings/WindowModeRow/WindowMode
@onready var _vsync: CheckButton = $Backdrop/Center/Panel/Content/Settings/VSyncRow/VSync
@onready var _restore_defaults: Button = $Backdrop/Center/Panel/Content/Settings/RestoreDefaults
@onready var _notice: Label = $Backdrop/Center/Panel/Content/Settings/Notice

func _ready() -> void:
	_main.get_node("Resume").pressed.connect(func(): resume_requested.emit())
	_main.get_node("Settings").pressed.connect(_show_settings)
	_main.get_node("Exit").pressed.connect(_show_quit)
	_settings.get_node("Guide").pressed.connect(_show_guide)
	_settings.get_node("Back").pressed.connect(_show_main)
	_mouse_assist.toggled.connect(_on_mouse_assist_toggled)
	_sensitivity.item_selected.connect(_on_sensitivity_selected)
	_window_mode.item_selected.connect(_on_window_mode_selected)
	_vsync.toggled.connect(_on_vsync_toggled)
	_restore_defaults.pressed.connect(_restore_settings)
	_quit.get_node("Cancel").pressed.connect(_show_main)
	_quit.get_node("Confirm").pressed.connect(func(): quit_requested.emit())
	_guide.finished.connect(_show_settings)
	_guide.get_node("Backdrop/Panel/Content/Close").text = "返回设置"
	_guide.get_node("Backdrop/Panel/Content/Hint").text = "游戏已暂停 · 滚轮查看说明 · Esc 返回设置"
	close_menu()

func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"ui_cancel"): return
	if not visible:
		pause_requested.emit()
		if not visible: return
	elif _guide.visible:
		_guide.close_guide()
	elif _settings.visible or _quit.visible:
		_show_main()
	else:
		resume_requested.emit()
	get_viewport().set_input_as_handled()

func open_menu() -> void:
	show()
	_show_main()

func close_menu() -> void:
	_guide.cancel()
	hide()
	if not is_inside_tree(): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused): focused.release_focus()

func _show_main() -> void:
	_show_page(_main, "游戏暂停", _main.get_node("Resume"))

func _show_settings() -> void:
	_sync_settings_controls()
	_show_page(_settings, "设置", _settings.get_node("Guide"))

func _show_quit() -> void:
	_show_page(_quit, "退出游戏", _quit.get_node("Cancel"))

func _show_page(page: Control, title: String, focus: Button) -> void:
	_main.visible = page == _main
	_settings.visible = page == _settings
	_quit.visible = page == _quit
	_title.text = title
	focus.grab_focus()

func _show_guide() -> void:
	_guide.begin()


func _user_settings() -> Node:
	return get_node_or_null("/root/UserSettings")


func _sync_settings_controls() -> void:
	var user_settings := _user_settings()
	var available := user_settings != null
	for control in [_mouse_assist, _sensitivity, _window_mode, _vsync, _restore_defaults]:
		control.disabled = not available
	if not available:
		return
	_mouse_assist.set_pressed_no_signal(user_settings.mouse_target_assist_enabled)
	_sensitivity.select(user_settings.target_switch_sensitivity)
	_sync_window_modes(user_settings.available_window_modes())
	_window_mode.select(user_settings.window_mode)
	_vsync.set_pressed_no_signal(user_settings.vsync_enabled)
	_update_toggle_labels()
	_update_settings_notice()


func _on_mouse_assist_toggled(enabled: bool) -> void:
	var user_settings := _user_settings()
	if user_settings != null:
		user_settings.set_mouse_target_assist_enabled(enabled)
	_update_toggle_labels()
	_update_settings_notice()


func _on_sensitivity_selected(index: int) -> void:
	var user_settings := _user_settings()
	if user_settings != null:
		user_settings.set_target_switch_sensitivity(index)
	_update_settings_notice()


func _on_window_mode_selected(index: int) -> void:
	var user_settings := _user_settings()
	if user_settings != null:
		user_settings.set_window_mode(_window_mode.get_item_id(index))
	_update_settings_notice()


func _on_vsync_toggled(enabled: bool) -> void:
	var user_settings := _user_settings()
	if user_settings != null:
		user_settings.set_vsync_enabled(enabled)
	_update_toggle_labels()
	_update_settings_notice()


func _restore_settings() -> void:
	var user_settings := _user_settings()
	if user_settings == null:
		return
	user_settings.reset_to_defaults()
	_sync_settings_controls()


func _update_toggle_labels() -> void:
	_mouse_assist.text = "开启" if _mouse_assist.button_pressed else "关闭"
	_vsync.text = "开启" if _vsync.button_pressed else "关闭"


func _update_settings_notice() -> void:
	var user_settings := _user_settings()
	var saved: bool = user_settings != null and user_settings.last_save_error == OK
	_notice.text = "更改会立即应用并保存" if saved else "已应用，但设置未保存"
	_notice.add_theme_color_override(
		"font_color", Color(0.6, 0.7, 0.75, 1) if saved else Color(1.0, 0.65, 0.55, 1.0))


func _sync_window_modes(modes: Array) -> void:
	if _window_mode.item_count == modes.size():
		var unchanged := true
		for index in range(modes.size()):
			unchanged = unchanged and _window_mode.get_item_id(index) == int(modes[index])
		if unchanged:
			return
	_window_mode.clear()
	for mode in modes:
		_window_mode.add_item(_window_mode_label(int(mode)), int(mode))


func _window_mode_label(mode: int) -> String:
	match mode:
		1:
			return "无边框全屏"
		2:
			return "独占全屏"
		_:
			return "窗口"
