extends SceneTree

## Opt-in real-render integration:
## DSR_CAMPAIGN_SAVE_CONFIG=/tmp/dsr-reset-rendered-$$.cfg \
## DSR_USER_SETTINGS_CONFIG=/tmp/dsr-reset-rendered-settings-$$.cfg \
## Godot --path movement_demo --script res://tests/campaign_save_reset_rendered_test.gd

const LEVEL_ONE := preload("res://scenes/world/levels/lvl_1.tscn")
const Director := preload("res://scripts/systems/scene_director.gd")
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const WATCHDOG_SECONDS := 30.0

var checks := 0
var failures := 0
var _finished := false


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	check(DisplayServer.get_name() != "headless", "渲染测试使用真实显示后端")
	var state := root.get_node("GameState")
	var service := root.get_node("CampaignSaveService")
	var settings := root.get_node("UserSettings")
	var debug_settings := root.get_node("DebugSettings")
	check(service.save_path.begins_with("/tmp/dsr-reset-rendered-"),
		"渲染测试使用隔离的游戏存档")
	check(settings.config_path.begins_with("/tmp/dsr-reset-rendered-settings-"),
		"渲染测试使用隔离的用户设置")
	_remove_save_artifacts(service.save_path)
	settings.config_path = service.save_path + ".settings"
	if FileAccess.file_exists(settings.config_path):
		DirAccess.remove_absolute(settings.config_path)
	check(settings.commit_settings(
		settings.mouse_target_assist_enabled,
		settings.target_switch_sensitivity,
		settings.window_mode,
		settings.resolution_index,
		settings.vsync_enabled) == OK,
		"渲染测试写入用户设置")
	var saved_settings := FileAccess.get_file_as_string(settings.config_path)

	state.reset_game_progress()
	state.money = 100
	state.available_level = 3
	state.items = {&"coin": {"display_name": "硬币", "count": 1}}
	state.flags = {&"music_playing": true}
	state.opening_cinematic_played = true
	check(service.save_game(state.capture_save_state({})) == OK,
		"渲染测试准备有效游戏存档")

	var scene: Node = LEVEL_ONE.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(5):
		await process_frame
	scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var director := Director.for_node(scene)
	check(not director.scene_loader.is_valid(),
		"渲染测试使用真实场景切换而非注入 loader")
	var health := scene.get_node("Player/Health")
	health.debug_invincible = true
	await process_frame
	var button := health.get_node_or_null("Debug/Controls/ResetProgress") as Button
	var confirm := health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(button != null and confirm != null, "渲染测试找到重置确认控件")
	if button == null or confirm == null:
		_finish(service, settings)
		return
	var old_scene_id := scene.get_instance_id()
	button.pressed.emit()
	for _frame in range(3):
		await process_frame
	check(confirm.visible,
		"点击重置按钮后确认对话框真实可见")
	var ok_button := confirm.get_ok_button()
	check(ok_button != null and ok_button.visible,
		"确认对话框提供可见的确认按钮")
	if ok_button == null:
		_finish(service, settings)
		return
	ok_button.pressed.emit()

	var replaced := false
	for _frame in range(180):
		await process_frame
		if current_scene != null \
				and current_scene.get_instance_id() != old_scene_id \
				and current_scene.scene_file_path == MAIN_SCENE_PATH:
			replaced = true
			break
	for _frame in range(5):
		await process_frame
	check(replaced, "接受重置后用真实切换替换为初始酒馆场景")
	check(current_scene != null and current_scene.scene_file_path == MAIN_SCENE_PATH,
		"重置后的当前场景是主酒馆")
	check(state.money == 0 and state.available_level == 1
			and state.items.is_empty() and state.flags.is_empty()
			and not state.opening_cinematic_played,
		"真实重置清空游戏进度并恢复开场资格")
	check(not FileAccess.file_exists(service.save_path)
			and not FileAccess.file_exists(service.save_path + ".bak")
			and not FileAccess.file_exists(service.save_path + ".reset-pending")
			and not FileAccess.file_exists(service.save_path + ".bak.reset-pending"),
		"真实重置删除正式、备份和暂存存档")
	check(FileAccess.file_exists(settings.config_path)
			and FileAccess.get_file_as_string(settings.config_path) == saved_settings,
		"真实重置保留 settings.cfg")
	check(debug_settings.enabled, "真实重置保留 Debug 总开关")
	if current_scene != null:
		var new_health := current_scene.get_node_or_null("Player/Health")
		var new_reset := new_health.get_node_or_null("Debug/Controls/ResetProgress") as Button \
			if new_health != null else null
		check(new_reset != null and not new_reset.disabled,
			"替换后的酒馆继续提供可用重置按钮")
	_finish(service, settings)


func _remove_save_artifacts(save_path: String) -> void:
	for path in [save_path, save_path + ".tmp", save_path + ".bak",
			save_path + ".reset-pending", save_path + ".bak.reset-pending"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	push_error("rendered campaign save reset test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(service: Node, settings: Node) -> void:
	if _finished:
		return
	_finished = true
	_remove_save_artifacts(service.save_path + ".settings")
	_remove_save_artifacts(service.save_path)
	if FileAccess.file_exists(settings.config_path):
		DirAccess.remove_absolute(settings.config_path)
	root.get_node("DebugSettings").set_enabled(false)
	if current_scene != null:
		current_scene.queue_free()
		current_scene = null
	print("CAMPAIGN SAVE RESET RENDERED: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
