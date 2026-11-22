extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")

var test_config := ""
var checks := 0
var failures := 0


func _initialize() -> void:
	test_config = OS.get_temp_dir().path_join(
		"dsr-settings-menu-test-%d.cfg" % OS.get_process_id())
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _settle(frames: int = 3) -> void:
	for _frame in range(frames):
		await process_frame


func _run() -> void:
	_remove_test_config()
	root.size = Vector2i(1152, 720)
	root.content_scale_size = root.size
	var settings := root.get_node_or_null("UserSettings")
	check(settings != null, "设置菜单使用项目用户设置服务")
	if settings == null:
		_finish()
		return
	settings.config_path = test_config
	settings.mouse_target_assist_enabled = true
	settings.target_switch_sensitivity = 1
	settings.window_mode = 0
	settings.vsync_enabled = true

	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await _settle()
	var director = Director.for_node(scene)
	director.request_pause_menu()
	var menu = director.get_node_or_null("PauseMenu")
	check(menu != null and menu.visible, "可从暂停菜单打开设置")
	if menu == null:
		scene.free()
		_finish()
		return
	var content := menu.get_node("Backdrop/Center/Panel/Content")
	content.get_node("Main/Settings").pressed.emit()
	var settings_page := content.get_node("Settings")
	check(settings_page.visible, "设置分类页保持现有导航")
	var mouse_assist := settings_page.find_child("MouseAssist", true, false)
	var sensitivity := settings_page.find_child("Sensitivity", true, false)
	var window_mode := settings_page.find_child("WindowMode", true, false)
	var vsync := settings_page.find_child("VSync", true, false)
	var restore := settings_page.get_node_or_null("RestoreDefaults")
	check(mouse_assist is CheckButton, "设置页提供鼠标辅助开关")
	check(sensitivity is OptionButton, "设置页提供换锁灵敏度档位")
	check(window_mode is OptionButton, "设置页提供窗口模式")
	check(vsync is CheckButton, "设置页提供垂直同步开关")
	check(restore is Button, "设置页提供恢复默认设置")
	if mouse_assist is not CheckButton or sensitivity is not OptionButton \
			or window_mode is not OptionButton or vsync is not CheckButton \
			or restore is not Button:
		scene.free()
		_finish()
		return

	check(mouse_assist.button_pressed and sensitivity.selected == 1,
		"设置控件打开时显示当前鼠标偏好")
	check(window_mode.selected == 0 and vsync.button_pressed,
		"设置控件打开时显示当前画面偏好")
	if OS.get_name() == "macOS":
		check(window_mode.item_count == 2, "macOS 窗口菜单隐藏不可用的独占全屏")
	else:
		check(window_mode.item_count == 3, "支持独占全屏的平台显示三种窗口模式")
	mouse_assist.button_pressed = false
	mouse_assist.toggled.emit(false)
	sensitivity.select(2)
	sensitivity.item_selected.emit(2)
	window_mode.select(1)
	window_mode.item_selected.emit(1)
	vsync.button_pressed = false
	vsync.toggled.emit(false)
	await _settle()
	check(mouse_assist.text == "关闭" and vsync.text == "关闭",
		"关闭状态在开关文字中明确显示")
	var combat = scene.get_node("Player/Combat")
	check(not combat.mouse_target_assist_enabled
		and is_equal_approx(combat.target_switch_travel_ratio, 0.08),
		"鼠标设置立即应用到当前玩家")
	check(not settings.mouse_target_assist_enabled
		and settings.target_switch_sensitivity == 2,
		"鼠标设置在运行时状态中更新")
	check(settings.window_mode == 1 and not settings.vsync_enabled,
		"画面设置在运行时状态中更新")
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
			"无边框全屏档实际应用窗口模式")
		check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,
			"关闭垂直同步实际应用显示服务")
	var restored = settings.get_script().new()
	restored.config_path = test_config
	restored.load_settings()
	check(not restored.mouse_target_assist_enabled
		and restored.target_switch_sensitivity == 2
		and restored.window_mode == 1
		and not restored.vsync_enabled,
		"设置菜单更改写入独立配置文件")
	restored.free()

	restore.pressed.emit()
	await _settle()
	check(settings.mouse_target_assist_enabled
		and settings.target_switch_sensitivity == 1
		and settings.window_mode == 0
		and settings.vsync_enabled,
		"恢复默认重置全部首批设置")
	check(mouse_assist.button_pressed and sensitivity.selected == 1
		and window_mode.selected == 0 and vsync.button_pressed,
		"恢复默认同步刷新设置控件")
	check(combat.mouse_target_assist_enabled
		and is_equal_approx(combat.target_switch_travel_ratio, 0.12),
		"恢复默认立即应用到当前玩家")
	if rendered:
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED,
			"恢复默认实际回到窗口模式")
		check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_ENABLED,
			"恢复默认实际开启垂直同步")
	var notice := settings_page.get_node("Notice")
	settings.config_path = OS.get_temp_dir().path_join(
		"dsr-settings-missing-%d" % OS.get_process_id()).path_join("settings.cfg")
	mouse_assist.button_pressed = false
	mouse_assist.toggled.emit(false)
	await _settle()
	var save_state_ready: bool = settings.get("last_save_error") != null
	check(save_state_ready, "设置服务提供保存错误状态")
	if save_state_ready:
		check(settings.last_save_error != OK, "保存失败保留可查询错误状态")
	check(notice.text.contains("未保存"), "保存失败在设置页明确提示")
	settings.config_path = test_config
	restore.pressed.emit()
	await _settle()

	root.size = Vector2i(640, 480)
	root.content_scale_size = root.size
	await _settle()
	var viewport := root.get_visible_rect()
	var all_visible := true
	for control in [mouse_assist, sensitivity, window_mode, vsync, restore,
			settings_page.get_node("Guide"), settings_page.get_node("Back")]:
		all_visible = all_visible and viewport.encloses(control.get_global_rect())
		if not viewport.encloses(control.get_global_rect()):
			print("BOUNDS FAIL ", control.name, " ", control.get_global_rect(), " viewport ", viewport)
	check(all_visible, "640×480 下设置控件完整可见")

	scene.free()
	current_scene = null
	await _settle()
	settings.config_path = settings.DEFAULT_CONFIG_PATH
	_finish()


func _remove_test_config() -> void:
	if FileAccess.file_exists(test_config):
		DirAccess.remove_absolute(test_config)


func _finish() -> void:
	_remove_test_config()
	print("SETTINGS MENU: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
