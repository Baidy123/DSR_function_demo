extends SceneTree

const SETTINGS_SCRIPT := "res://scripts/systems/user_settings.gd"

var test_config := ""
var checks := 0
var failures := 0


func _initialize() -> void:
	test_config = OS.get_temp_dir().path_join(
		"dsr-user-settings-test-%d.cfg" % OS.get_process_id())
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	_remove_test_config()
	check(ProjectSettings.has_setting("autoload/UserSettings"),
		"项目注册用户设置自动加载")
	var settings_script = load(SETTINGS_SCRIPT)
	check(settings_script != null, "用户设置服务脚本可以加载")
	if settings_script == null:
		_finish()
		return
	check(settings_script.should_load_saved_config(PackedStringArray(), ""),
		"正式游戏启动加载用户设置")
	check(not settings_script.should_load_saved_config(PackedStringArray(["--script"]), ""),
		"测试脚本默认忽略开发者本机设置")
	check(settings_script.should_load_saved_config(
		PackedStringArray(["--script"]), test_config),
		"测试可显式指定隔离设置文件")

	var settings = settings_script.new()
	check(settings.window_mode == 0, "默认使用窗口模式")
	check(settings.vsync_enabled, "默认开启垂直同步")
	check(settings.mouse_target_assist_enabled, "默认战斗设置开启鼠标辅助")
	check(settings.target_switch_sensitivity == 1, "默认战斗设置使用标准灵敏度")
	var persisted_state_ready: bool = settings.get("has_saved_settings") != null
	check(persisted_state_ready, "设置服务记录是否已有保存配置")
	if persisted_state_ready:
		check(not settings.has_saved_settings, "新实例默认标记为尚未保存")
	var resolution_ready: bool = settings.get("resolution_index") != null \
		and settings.has_method("resolution") \
		and settings.has_method("available_resolutions")
	check(resolution_ready, "设置服务提供基础分辨率")
	if resolution_ready:
		check(settings.resolution_index == 0 and settings.resolution() == Vector2i(1280, 720),
			"默认分辨率为1280×720")
		check(settings.available_resolutions().size() == 3, "提供三档基础分辨率")
	check(settings.available_window_modes().has(0)
		and settings.available_window_modes().has(1), "提供窗口与无边框全屏")
	if OS.get_name() == "macOS":
		check(not settings.available_window_modes().has(2), "macOS 隐藏独占全屏")
	else:
		check(settings.available_window_modes().has(2), "支持的平台保留独占全屏")
	check(not settings.has_method("set_mouse_target_assist_enabled"),
		"战斗设置修改不再触发自动保存")
	check(not settings.has_method("set_window_mode"),
		"基础设置修改不再触发自动保存")

	settings.config_path = test_config
	var aim_ready: bool = settings.has_method("commit_aim_control")
	check(aim_ready, "设置服务提供独立的瞄准方式保存入口")
	if aim_ready:
		check(settings.commit_aim_control(2) == OK and settings.get_aim_control() == 2,
			"鼠标瞄准保存后立即生效")
		var config_override := OS.get_environment("DSR_USER_SETTINGS_CONFIG")
		OS.set_environment("DSR_USER_SETTINGS_CONFIG", test_config)
		var aim_only = settings_script.new()
		root.add_child(aim_only)
		OS.set_environment("DSR_USER_SETTINGS_CONFIG", config_override)
		check(aim_only.get_aim_control() == 2 and not aim_only.has_saved_settings,
			"启动重读瞄准方式不启用未保存的显示和辅助设置")
		aim_only.free()
	var commit_ready: bool = settings.has_method("commit_settings")
	check(commit_ready, "设置服务提供显式保存入口")
	if commit_ready:
		check(settings.commit_settings(true, 2, 1, 2, false) == OK,
			"保存设置写入文件并提交全部候选值")
		check(FileAccess.file_exists(test_config), "保存设置创建用户配置文件")
		check(settings.mouse_target_assist_enabled
			and settings.target_switch_sensitivity == 2
			and settings.window_mode == 1
			and settings.resolution_index == 2
			and not settings.vsync_enabled,
			"保存后设置服务采用候选值")
		if persisted_state_ready:
			check(settings.has_saved_settings, "保存成功后标记为已持久化")
		var restored = settings_script.new()
		restored.config_path = test_config
		check(restored.load_settings() == OK, "保存后的设置可以重新读取")
		if aim_ready:
			check(restored.get_aim_control() == 2, "保存其他设置保留已选的鼠标瞄准")
		check(restored.mouse_target_assist_enabled
			and restored.target_switch_sensitivity == 2
			and restored.window_mode == 1
			and restored.resolution_index == 2
			and not restored.vsync_enabled,
			"重载恢复基础与战斗设置")
		if persisted_state_ready:
			check(restored.has_saved_settings, "重载成功标记为已持久化")
		restored.free()

		if aim_ready:
			check(settings.commit_aim_control(1) == OK, "可以持久化切回自动锁定")
			var current_config := ConfigFile.new()
			check(current_config.load(test_config) == OK
				and current_config.get_value("display", "resolution_index") == 2,
				"切换瞄准方式保留现有显示设置")

		var invalid_config := ConfigFile.new()
		invalid_config.set_value("display", "window_mode", 999)
		invalid_config.set_value("display", "resolution_index", 99)
		invalid_config.set_value("display", "vsync_enabled", "false")
		invalid_config.set_value("input_assist", "mouse_target_assist_enabled", "false")
		invalid_config.set_value("input_assist", "target_switch_sensitivity", 99)
		check(invalid_config.save(test_config) == OK, "测试写入错误类型与越界值")
		var invalid = settings_script.new()
		invalid.config_path = test_config
		check(invalid.load_settings() == OK, "错误值仍可读取并回退")
		if aim_ready:
			check(invalid.get_aim_control() == 1, "没有瞄准方式字段的旧配置默认自动锁定")
		check(invalid.mouse_target_assist_enabled
			and invalid.target_switch_sensitivity == 1
			and invalid.window_mode == 0
			and invalid.resolution_index == 0
			and invalid.vsync_enabled,
			"错误类型、越界枚举与缺失键全部回退默认值")
		invalid.free()

		var player = load("res://scenes/player/player.tscn").instantiate()
		root.add_child(player)
		await process_frame
		var combat = player.get_node("Combat")
		var live_settings := root.get_node_or_null("UserSettings")
		check(live_settings != null, "设置服务可从项目根节点访问")
		if live_settings != null:
			live_settings.config_path = test_config
			check(live_settings.commit_settings(false, 2, 1, 2, false) == OK,
				"运行中的设置服务保存候选值")
			check(not combat.mouse_target_assist_enabled
				and is_equal_approx(combat.target_switch_travel_ratio, 0.08),
				"保存战斗设置后同步当前玩家")
			live_settings.commit_settings(true, 1, 0, 0, true)
			live_settings.config_path = live_settings.DEFAULT_CONFIG_PATH
		player.queue_free()
		await process_frame

		var missing = settings_script.new()
		missing.config_path = test_config + ".missing"
		check(missing.load_settings() == ERR_FILE_NOT_FOUND,
			"缺失配置文件返回可忽略的未找到状态")
		check(missing.mouse_target_assist_enabled
			and missing.target_switch_sensitivity == 1
			and missing.window_mode == 0
			and missing.resolution_index == 0
			and missing.vsync_enabled,
			"缺失配置文件保持默认值")
		if persisted_state_ready:
			check(not missing.has_saved_settings, "缺失配置不标记为已保存")
		missing.free()

		var failure = settings_script.new()
		failure.config_path = OS.get_temp_dir().path_join(
			"dsr-settings-missing-%d" % OS.get_process_id()).path_join("settings.cfg")
		var window_before: int = failure.window_mode
		if aim_ready:
			check(failure.commit_aim_control(2) != OK and failure.get_aim_control() == 1,
				"无法写入时保留当前瞄准方式")
		check(failure.commit_settings(false, 0, 1, 2, false) != OK,
			"写入失败返回错误")
		check(failure.window_mode == window_before
			and failure.mouse_target_assist_enabled,
			"写入失败不提交候选值")
		failure.free()
	settings.free()
	_finish()


func _remove_test_config() -> void:
	if FileAccess.file_exists(test_config):
		DirAccess.remove_absolute(test_config)


func _finish() -> void:
	_remove_test_config()
	print("USER SETTINGS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
