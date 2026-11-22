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
	check(settings_script.has_method("should_load_saved_config"),
		"设置服务区分正式运行与测试脚本")
	if settings_script.has_method("should_load_saved_config"):
		check(not settings_script.should_load_saved_config(PackedStringArray(["--script"]), ""),
			"测试脚本默认忽略开发者本机设置")
		check(settings_script.should_load_saved_config(PackedStringArray(), ""),
			"正式游戏启动加载用户设置")
		check(settings_script.should_load_saved_config(
			PackedStringArray(["--script"]), test_config),
			"测试可显式指定隔离设置文件")

	var settings = settings_script.new()
	check(settings.mouse_target_assist_enabled, "默认开启鼠标辅助锁定")
	check(settings.target_switch_sensitivity == 1, "默认换锁灵敏度为标准档")
	check(settings.window_mode == 0, "默认使用窗口模式")
	check(settings.vsync_enabled, "默认开启垂直同步")
	check(settings.has_method("target_switch_travel_ratio"), "设置服务提供换锁行程换算")
	if settings.has_method("target_switch_travel_ratio"):
		settings.target_switch_sensitivity = 0
		check(is_equal_approx(settings.target_switch_travel_ratio(), 0.16), "低灵敏度需要更长鼠标行程")
		settings.target_switch_sensitivity = 1
		check(is_equal_approx(settings.target_switch_travel_ratio(), 0.12), "标准灵敏度沿用当前鼠标行程")
		settings.target_switch_sensitivity = 2
		check(is_equal_approx(settings.target_switch_travel_ratio(), 0.08), "高灵敏度缩短鼠标行程")
	check(settings.has_method("godot_window_mode"), "设置服务提供窗口模式映射")
	if settings.has_method("godot_window_mode"):
		settings.window_mode = 0
		check(settings.godot_window_mode() == DisplayServer.WINDOW_MODE_WINDOWED,
			"窗口档映射为窗口模式")
		settings.window_mode = 1
		check(settings.godot_window_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
			"全屏档映射为无边框全屏")
		settings.window_mode = 2
		if OS.get_name() == "macOS":
			check(settings.godot_window_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN,
				"独占档在 macOS 回退为无边框全屏")
		else:
			check(settings.godot_window_mode() == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
				"独占档映射为独占全屏")
	check(settings.has_method("available_window_modes"), "设置服务提供平台可用窗口模式")
	if settings.has_method("available_window_modes"):
		var modes: Array = settings.available_window_modes()
		check(modes.has(0) and modes.has(1), "所有平台都提供窗口和无边框全屏")
		if OS.get_name() == "macOS":
			check(not modes.has(2), "macOS 不提供不可兑现的独占全屏选项")
		else:
			check(modes.has(2), "支持独占全屏的平台保留该选项")
	var persistence_ready: bool = settings.get("config_path") != null \
		and settings.has_method("save_settings") \
		and settings.has_method("load_settings")
	check(persistence_ready, "设置服务提供独立配置文件读写")
	if persistence_ready:
		settings.config_path = test_config
		settings.mouse_target_assist_enabled = false
		settings.target_switch_sensitivity = 2
		settings.window_mode = 2
		settings.vsync_enabled = false
		check(settings.save_settings() == OK and FileAccess.file_exists(test_config),
			"更改后的设置写入用户配置文件")
		var restored = settings_script.new()
		restored.config_path = test_config
		restored.load_settings()
		check(not restored.mouse_target_assist_enabled and restored.target_switch_sensitivity == 2,
			"重载恢复鼠标辅助与换锁灵敏度")
		var expected_window_mode := 1 if OS.get_name() == "macOS" else 2
		check(restored.window_mode == expected_window_mode and not restored.vsync_enabled,
			"重载恢复平台可用的窗口模式与垂直同步")
		restored.free()
		var invalid_config := ConfigFile.new()
		invalid_config.set_value("input_assist", "mouse_target_assist_enabled", "false")
		invalid_config.set_value("input_assist", "target_switch_sensitivity", 99)
		invalid_config.set_value("display", "window_mode", 999)
		check(invalid_config.save(test_config) == OK, "测试写入错误类型与越界值")
		var invalid = settings_script.new()
		invalid.config_path = test_config
		check(invalid.load_settings() == OK, "错误值仍可读取并回退")
		check(invalid.mouse_target_assist_enabled
			and invalid.target_switch_sensitivity == 1
			and invalid.window_mode == 0
			and invalid.vsync_enabled,
			"错误类型、越界枚举与缺失键全部回退默认值")
		invalid.free()
		var missing = settings_script.new()
		missing.config_path = test_config + ".missing"
		check(missing.load_settings() == ERR_FILE_NOT_FOUND,
			"缺失配置文件返回可忽略的未找到状态")
		check(missing.mouse_target_assist_enabled
			and missing.target_switch_sensitivity == 1
			and missing.window_mode == 0
			and missing.vsync_enabled,
			"缺失配置文件保持默认值")
		missing.free()
	var player = load("res://scenes/player/player.tscn").instantiate()
	root.add_child(player)
	await process_frame
	var combat = player.get_node("Combat")
	var combat_apply_ready: bool = settings.has_method("apply_to_combat")
	check(combat_apply_ready, "设置服务可应用到真实玩家战斗组件")
	if combat_apply_ready:
		settings.apply_to_combat(combat)
		check(not combat.mouse_target_assist_enabled,
			"运行时应用鼠标辅助开关")
		check(is_equal_approx(combat.target_switch_travel_ratio, 0.08),
			"运行时应用高灵敏度换算后的鼠标行程")
	player.queue_free()
	await process_frame
	var live_settings := root.get_node_or_null("UserSettings")
	check(live_settings != null, "设置服务可从项目根节点访问")
	if live_settings != null:
		live_settings.config_path = test_config
		live_settings.mouse_target_assist_enabled = false
		live_settings.target_switch_sensitivity = 2
		var auto_player = load("res://scenes/player/player.tscn").instantiate()
		root.add_child(auto_player)
		await process_frame
		var auto_combat = auto_player.get_node("Combat")
		check(not auto_combat.mouse_target_assist_enabled
			and is_equal_approx(auto_combat.target_switch_travel_ratio, 0.08),
			"新加载玩家自动采用当前用户设置")
		auto_player.queue_free()
		await process_frame
		live_settings.reset_to_defaults()
		live_settings.config_path = live_settings.DEFAULT_CONFIG_PATH
	settings.free()
	_finish()


func _remove_test_config() -> void:
	var absolute := ProjectSettings.globalize_path(test_config)
	if FileAccess.file_exists(test_config):
		DirAccess.remove_absolute(absolute)


func _finish() -> void:
	_remove_test_config()
	print("USER SETTINGS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
