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


func _escape() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		root.push_input(event, true)
	await _settle()


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
	var defaults: Dictionary = settings.default_values()
	settings.mouse_target_assist_enabled = defaults.mouse_target_assist_enabled
	settings.target_switch_sensitivity = defaults.target_switch_sensitivity
	settings.window_mode = defaults.window_mode
	settings.resolution_index = defaults.resolution_index
	settings.vsync_enabled = defaults.vsync_enabled
	settings.last_save_error = OK

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
	var categories := settings_page.find_child("Categories", true, false)
	var basic := settings_page.find_child("BasicSettings", true, false)
	var combat_settings := settings_page.find_child("CombatSettings", true, false)
	var window_mode := basic.find_child("WindowMode", true, false) if basic != null else null
	var resolution_choice := basic.find_child("Resolution", true, false) if basic != null else null
	var vsync := basic.find_child("VSync", true, false) if basic != null else null
	var mouse_assist := combat_settings.find_child("MouseAssist", true, false) \
		if combat_settings != null else null
	var sensitivity := combat_settings.find_child("Sensitivity", true, false) \
		if combat_settings != null else null
	var save := settings_page.get_node_or_null("SaveSettings")
	var restore := settings_page.get_node_or_null("RestoreDefaults")
	var notice := settings_page.get_node_or_null("Notice")
	check(categories is TabContainer and categories.get_tab_count() == 2,
		"设置页分为基础设置和战斗设置")
	check(window_mode is OptionButton and resolution_choice is OptionButton
		and vsync is CheckButton, "基础设置提供窗口、分辨率和垂直同步")
	check(mouse_assist is CheckButton and sensitivity is OptionButton,
		"战斗设置栏保留鼠标辅助和换锁灵敏度")
	check(save is Button and restore is Button and notice is Label,
		"设置页提供统一保存、恢复默认和状态提示")
	var setup_ready: bool = categories is TabContainer \
		and window_mode is OptionButton and resolution_choice is OptionButton \
		and vsync is CheckButton and mouse_assist is CheckButton \
		and sensitivity is OptionButton and save is Button and notice is Label
	if not setup_ready:
		scene.free()
		_finish()
		return
	check(not basic.is_ancestor_of(mouse_assist)
		and combat_settings.is_ancestor_of(mouse_assist),
		"鼠标辅助只出现在战斗设置栏")
	check(basic.is_ancestor_of(window_mode) and basic.is_ancestor_of(resolution_choice),
		"画面项只出现在基础设置栏")
	check(notice.text.contains("默认设置") and notice.text.contains("尚未保存"),
		"首次运行明确显示默认设置尚未保存")

	var rendered := DisplayServer.get_name() != "headless"
	var mode_before := DisplayServer.window_get_mode()
	var vsync_before := DisplayServer.window_get_vsync_mode()
	var size_before := DisplayServer.window_get_size()
	var content_scale_before := root.content_scale_size
	mouse_assist.button_pressed = false
	mouse_assist.toggled.emit(false)
	sensitivity.select(2)
	sensitivity.item_selected.emit(2)
	window_mode.select(1)
	window_mode.item_selected.emit(1)
	resolution_choice.select(2)
	resolution_choice.item_selected.emit(2)
	vsync.button_pressed = false
	vsync.toggled.emit(false)
	await _settle()
	check(settings.mouse_target_assist_enabled
		and settings.target_switch_sensitivity == 1
		and settings.window_mode == 0
		and settings.resolution_index == 0
		and settings.vsync_enabled,
		"编辑控件不会自动提交设置")
	check(not FileAccess.file_exists(test_config), "编辑控件不会自动写入配置")
	check(root.content_scale_size == content_scale_before,
		"编辑分辨率不会立即改变渲染画布")
	var combat: Node = scene.get_node("Player/Combat")
	check(combat.mouse_target_assist_enabled
		and is_equal_approx(combat.target_switch_travel_ratio, 0.12),
		"编辑战斗设置不会立即影响玩家")
	if rendered:
		check(DisplayServer.window_get_mode() == mode_before
			and DisplayServer.window_get_vsync_mode() == vsync_before
			and DisplayServer.window_get_size() == size_before,
			"编辑画面设置不会立即影响显示服务")
	check(notice.text.contains("未保存"), "未保存改动在设置页明确提示")

	save.pressed.emit()
	await _settle()
	check(not settings.mouse_target_assist_enabled
		and settings.target_switch_sensitivity == 2
		and settings.window_mode == 1
		and settings.resolution_index == 2
		and not settings.vsync_enabled,
		"点击保存后提交全部基础与战斗设置")
	check(FileAccess.file_exists(test_config), "点击保存后写入配置文件")
	check(not combat.mouse_target_assist_enabled
		and is_equal_approx(combat.target_switch_travel_ratio, 0.08),
		"点击保存后同步当前玩家")
	check(notice.text.contains("已保存") and not notice.text.contains("未保存"),
		"保存成功后显示明确状态")
	check(root.content_scale_size == Vector2i(1920, 1080),
		"保存后应用1920×1080渲染画布")
	check(root.get_visible_rect().size == Vector2(1920, 1080),
		"保存后可见画布使用1920×1080坐标")
	if rendered:
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
			"保存后应用无边框全屏")
		check(DisplayServer.window_get_vsync_mode() == DisplayServer.VSYNC_DISABLED,
			"保存后关闭垂直同步")

	window_mode.select(0)
	window_mode.item_selected.emit(0)
	resolution_choice.select(1)
	resolution_choice.item_selected.emit(1)
	save.pressed.emit()
	await _settle()
	check(settings.window_mode == 0 and settings.resolution_index == 1,
		"保存后提交窗口分辨率")
	check(root.content_scale_size == Vector2i(1600, 900),
		"保存后应用1600×900渲染画布")
	check(root.get_visible_rect().size == Vector2(1600, 900),
		"保存后可见画布使用1600×900坐标")
	if rendered:
		check(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
			and DisplayServer.window_get_size() == Vector2i(1600, 900),
			"窗口模式保存后应用1600×900分辨率")

	vsync.button_pressed = true
	vsync.toggled.emit(true)
	await _settle()
	settings_page.get_node("Back").pressed.emit()
	check(not settings_page.visible and content.get_node("Main").visible,
		"返回暂停菜单")
	check(not settings.vsync_enabled and FileAccess.file_exists(test_config),
		"返回时丢弃未保存改动")
	content.get_node("Main/Settings").pressed.emit()
	check(vsync.button_pressed == false, "重新打开设置恢复已保存值")
	sensitivity.select(0)
	sensitivity.item_selected.emit(0)
	await _settle()
	settings_page.get_node("Guide").pressed.emit()
	await _settle()
	menu.get_node("PlayGuide").close_guide()
	await _settle()
	check(settings_page.visible and sensitivity.selected == 0
		and settings.target_switch_sensitivity == 2,
		"引导返回保留待保存战斗设置且不提交")
	resolution_choice.select(2)
	resolution_choice.item_selected.emit(2)
	await _settle()
	await _escape()
	check(content.get_node("Main").visible and settings.resolution_index == 1,
		"Esc 返回并丢弃未保存改动")
	content.get_node("Main/Settings").pressed.emit()

	restore.pressed.emit()
	await _settle()
	check(window_mode.selected == 0 and resolution_choice.selected == 0
		and vsync.button_pressed and mouse_assist.button_pressed
		and sensitivity.selected == 1,
		"恢复默认只修改待保存控件")
	check(settings.window_mode == 0 and settings.resolution_index == 1
		and not settings.vsync_enabled and settings.target_switch_sensitivity == 2,
		"恢复默认在保存前不改变已提交设置")
	save.pressed.emit()
	await _settle()
	check(settings.window_mode == 0 and settings.resolution_index == 0
		and settings.vsync_enabled and settings.mouse_target_assist_enabled
		and settings.target_switch_sensitivity == 1,
		"保存恢复默认后的全部设置")
	check(combat.mouse_target_assist_enabled
		and is_equal_approx(combat.target_switch_travel_ratio, 0.12),
		"保存默认战斗设置后恢复玩家")

	settings.config_path = OS.get_temp_dir().path_join(
		"dsr-settings-missing-%d" % OS.get_process_id()).path_join("settings.cfg")
	var failed_mode_before := DisplayServer.window_get_mode()
	var failed_size_before := DisplayServer.window_get_size()
	var failed_vsync_before := DisplayServer.window_get_vsync_mode()
	mouse_assist.button_pressed = false
	mouse_assist.toggled.emit(false)
	sensitivity.select(2)
	sensitivity.item_selected.emit(2)
	window_mode.select(1)
	window_mode.item_selected.emit(1)
	resolution_choice.select(2)
	resolution_choice.item_selected.emit(2)
	vsync.button_pressed = false
	vsync.toggled.emit(false)
	await _settle()
	save.pressed.emit()
	await _settle()
	check(settings.last_save_error != OK
		and settings.mouse_target_assist_enabled
		and settings.target_switch_sensitivity == 1
		and settings.window_mode == 0
		and settings.resolution_index == 0
		and settings.vsync_enabled,
		"保存失败不提交候选设置")
	check(combat.mouse_target_assist_enabled
		and is_equal_approx(combat.target_switch_travel_ratio, 0.12),
		"保存失败不改变当前战斗设置")
	check(root.content_scale_size == Vector2i(1280, 720),
		"保存失败不改变渲染画布")
	if rendered:
		check(DisplayServer.window_get_mode() == failed_mode_before
			and DisplayServer.window_get_size() == failed_size_before
			and DisplayServer.window_get_vsync_mode() == failed_vsync_before,
			"保存失败不改变显示服务")
	check(notice.text.contains("保存失败") and notice.text.contains("未应用"),
		"保存失败在设置页明确提示")
	settings.config_path = test_config

	root.size = Vector2i(640, 480)
	root.content_scale_size = root.size
	await _settle()
	var viewport := root.get_visible_rect()
	categories.current_tab = 0
	await _settle()
	var basic_visible := true
	for control in [window_mode, resolution_choice, vsync, save, restore,
			settings_page.get_node("Guide"), settings_page.get_node("Back")]:
		basic_visible = basic_visible and viewport.encloses(control.get_global_rect())
	categories.current_tab = 1
	await _settle()
	basic_visible = basic_visible \
		and viewport.encloses(mouse_assist.get_global_rect()) \
		and viewport.encloses(sensitivity.get_global_rect())
	check(basic_visible, "640×480 下两栏设置与操作按钮完整可见")

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
