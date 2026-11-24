extends CanvasLayer

## 只展示菜单和回传意图；暂停所有权由 SceneDirector 管理。
signal pause_requested
signal resume_requested
signal quit_requested
signal save_game_requested
signal load_game_requested

@onready var _main: VBoxContainer = $Backdrop/Center/Panel/Content/Main
@onready var _settings: VBoxContainer = $Backdrop/Center/Panel/Content/Settings
@onready var _quit: VBoxContainer = $Backdrop/Center/Panel/Content/Quit
@onready var _title: Label = $Backdrop/Center/Panel/Content/Title
@onready var _guide: CanvasLayer = $PlayGuide
@onready var _aim_control: OptionButton = _settings.get_node("Categories/CombatSettings/AimControl/Choice")
@onready var _game_state = get_node("/root/GameState")
@onready var _categories: TabContainer = $Backdrop/Center/Panel/Content/Settings/Categories
@onready var _window_mode: OptionButton = $Backdrop/Center/Panel/Content/Settings/Categories/BasicSettings/WindowModeRow/WindowMode
@onready var _resolution: OptionButton = $Backdrop/Center/Panel/Content/Settings/Categories/BasicSettings/ResolutionRow/Resolution
@onready var _vsync: CheckButton = $Backdrop/Center/Panel/Content/Settings/Categories/BasicSettings/VSyncRow/VSync
@onready var _mouse_assist: CheckButton = $Backdrop/Center/Panel/Content/Settings/Categories/CombatSettings/MouseAssistRow/MouseAssist
@onready var _sensitivity: OptionButton = $Backdrop/Center/Panel/Content/Settings/Categories/CombatSettings/SensitivityRow/Sensitivity
@onready var _save: Button = $Backdrop/Center/Panel/Content/Settings/SaveSettings
@onready var _save_game: Button = _main.get_node("SaveGame")
@onready var _load_game: Button = _main.get_node("LoadGame")
@onready var _game_save_notice: Label = _main.get_node("GameSaveNotice")
@onready var _restore_defaults: Button = $Backdrop/Center/Panel/Content/Settings/RestoreDefaults
@onready var _notice: Label = $Backdrop/Center/Panel/Content/Settings/Notice

var _settings_dirty := false


func _ready() -> void:
	_main.get_node("Resume").pressed.connect(func(): resume_requested.emit())
	_main.get_node("Settings").pressed.connect(_show_settings)
	_main.get_node("Exit").pressed.connect(_show_quit)
	_main.get_node("Guide").pressed.connect(_show_guide)
	_settings.get_node("Back").pressed.connect(_discard_settings_and_show_main)
	_aim_control.item_selected.connect(_select_aim_control)
	_window_mode.item_selected.connect(_on_setting_changed)
	_resolution.item_selected.connect(_on_setting_changed)
	_vsync.toggled.connect(_on_setting_changed)
	_mouse_assist.toggled.connect(_on_setting_changed)
	_sensitivity.item_selected.connect(_on_setting_changed)
	_save.pressed.connect(_save_settings)
	_restore_defaults.pressed.connect(_restore_settings)
	_save_game.pressed.connect(func() -> void: save_game_requested.emit())
	_load_game.pressed.connect(func() -> void: load_game_requested.emit())
	_quit.get_node("Cancel").pressed.connect(_show_main)
	_quit.get_node("Confirm").pressed.connect(func(): quit_requested.emit())
	_guide.finished.connect(_show_main)
	_guide.get_node("Backdrop/Panel/Content/Close").text = "返回暂停菜单"
	_guide.get_node("Backdrop/Panel/Content/Hint").text = "游戏已暂停 · 滚轮查看说明 · Esc 返回暂停菜单"
	_categories.set_tab_title(0, "基础设置")
	_categories.set_tab_title(1, "战斗设置")
	close_menu()


func set_game_save_available(value: bool) -> void:
	_save_game.disabled = not value
	_game_save_notice.text = "" if value else "没有可保存的酒馆进度"
	_game_save_notice.visible = not value


func set_game_load_available(value: bool) -> void:
	_load_game.disabled = not value
	_load_game.tooltip_text = "恢复最近保存的进度并返回酒馆" if value else "没有可加载的存档"


func show_game_save_result(result: StringName) -> void:
	_game_save_notice.show()
	match result:
		&"tavern_saved":
			_game_save_notice.text = "酒馆进度已保存"
		&"level_saved":
			_game_save_notice.text = "已保存离开酒馆时的进度"
		&"unavailable":
			_game_save_notice.text = "没有可保存的酒馆进度"
		&"load_failed":
			_game_save_notice.text = "加载已保存游戏失败"
		_:
			_game_save_notice.text = "游戏进度保存失败"


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_echo() or not event.is_action_pressed(&"ui_cancel"): return
	if not visible:
		pause_requested.emit()
		if not visible: return
	elif _guide.visible:
		_guide.close_guide()
	elif _settings.visible or _quit.visible:
		_discard_settings_and_show_main()
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
	_aim_control.select(_aim_control.get_item_index(_game_state.player_aim_control_override))
	_sync_settings_controls()
	_show_page(_settings, "设置", _settings.get_node("Back"))


func _select_aim_control(index: int) -> void:
	_game_state.player_aim_control_override = _aim_control.get_item_id(index)


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


func _discard_settings_and_show_main() -> void:
	_sync_settings_controls()
	_show_main()


func _user_settings() -> Node:
	return get_node_or_null("/root/UserSettings")


func _sync_settings_controls() -> void:
	var user_settings := _user_settings()
	var available := user_settings != null
	for control in [_window_mode, _resolution, _vsync, _mouse_assist,
			_sensitivity, _save, _restore_defaults]:
		control.disabled = not available
	if not available:
		return
	_sync_window_modes(user_settings.available_window_modes())
	_sync_resolutions(user_settings.available_resolutions())
	_window_mode.select(user_settings.window_mode)
	_resolution.select(user_settings.resolution_index)
	_vsync.set_pressed_no_signal(user_settings.vsync_enabled)
	_mouse_assist.set_pressed_no_signal(user_settings.mouse_target_assist_enabled)
	_sensitivity.select(user_settings.target_switch_sensitivity)
	_settings_dirty = false
	_update_toggle_labels()
	_update_settings_notice()


func _on_setting_changed(_value = null) -> void:
	_settings_dirty = true
	_update_toggle_labels()
	_update_settings_notice()


func _save_settings() -> void:
	var user_settings := _user_settings()
	if user_settings == null:
		return
	var error: Error = user_settings.commit_settings(
		_mouse_assist.button_pressed,
		_sensitivity.get_item_id(_sensitivity.selected),
		_window_mode.get_item_id(_window_mode.selected),
		_resolution.selected,
		_vsync.button_pressed)
	_settings_dirty = false
	_update_toggle_labels()
	_update_settings_notice()
	if error != OK:
		_notice.text = "保存失败，设置未应用"
	else:
		_notice.text = "设置已保存"


func _restore_settings() -> void:
	var user_settings := _user_settings()
	if user_settings == null:
		return
	var defaults: Dictionary = user_settings.default_values()
	_window_mode.select(user_settings.available_window_modes().find(defaults.window_mode))
	_resolution.select(defaults.resolution_index)
	_vsync.set_pressed_no_signal(defaults.vsync_enabled)
	_mouse_assist.set_pressed_no_signal(defaults.mouse_target_assist_enabled)
	_sensitivity.select(defaults.target_switch_sensitivity)
	_settings_dirty = true
	_update_toggle_labels()
	_update_settings_notice()


func _update_toggle_labels() -> void:
	_mouse_assist.text = "开启" if _mouse_assist.button_pressed else "关闭"
	_vsync.text = "开启" if _vsync.button_pressed else "关闭"


func _update_settings_notice() -> void:
	var user_settings := _user_settings()
	var saved: bool = user_settings != null and user_settings.last_save_error == OK
	if _settings_dirty:
		_notice.text = "有未保存的更改"
		_notice.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35, 1.0))
	elif not saved:
		_notice.text = "保存失败，设置未应用"
		_notice.add_theme_color_override("font_color", Color(1.0, 0.65, 0.55, 1.0))
	elif not user_settings.has_saved_settings:
		_notice.text = "默认设置，尚未保存"
		_notice.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35, 1.0))
	else:
		_notice.text = "设置已保存"
		_notice.add_theme_color_override("font_color", Color(0.6, 0.7, 0.75, 1.0))


func _sync_window_modes(modes: Array) -> void:
	if _option_ids_match(_window_mode, modes):
		return
	_window_mode.clear()
	for mode in modes:
		_window_mode.add_item(_window_mode_label(int(mode)), int(mode))


func _sync_resolutions(resolutions: Array) -> void:
	if _resolution.item_count == resolutions.size():
		var unchanged := true
		for index in range(resolutions.size()):
			var size: Vector2i = resolutions[index]
			unchanged = unchanged and _resolution.get_item_id(index) == index \
				and _resolution.get_item_text(index) == "%d×%d" % [size.x, size.y]
		if unchanged:
			return
	_resolution.clear()
	for index in range(resolutions.size()):
		var size: Vector2i = resolutions[index]
		_resolution.add_item("%d×%d" % [size.x, size.y], index)


func _option_ids_match(option: OptionButton, ids: Array) -> bool:
	if option.item_count != ids.size():
		return false
	for index in range(ids.size()):
		if option.get_item_id(index) != int(ids[index]):
			return false
	return true


func _window_mode_label(mode: int) -> String:
	match mode:
		1:
			return "无边框全屏"
		2:
			return "独占全屏"
		_:
			return "窗口"
