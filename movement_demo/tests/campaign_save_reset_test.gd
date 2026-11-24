extends SceneTree

const LEVEL_ONE := preload("res://scenes/world/levels/lvl_1.tscn")
const Director := preload("res://scripts/systems/scene_director.gd")
const MAIN_SCENE_PATH := "res://scenes/access_denied/hub/tavern_exterior.tscn"
const WATCHDOG_SECONDS := 20.0


class FailingMaintenanceService extends "res://scripts/systems/campaign_save_service.gd":
	var fail_restore := false
	var fail_finish := false

	func _rename(from_path: String, to_path: String) -> Error:
		if fail_restore and from_path.ends_with(".reset-pending") and to_path == save_path:
			return ERR_CANT_CREATE
		return super._rename(from_path, to_path)

	func _remove_file(path: String) -> Error:
		if fail_finish and path.ends_with(".reset-pending"):
			return ERR_CANT_CREATE
		return super._remove_file(path)

var checks := 0
var failures := 0
var _finished := false
var _settings_path := ""


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	create_timer(WATCHDOG_SECONDS, true, false, true).timeout.connect(_on_watchdog)
	var state := root.get_node("GameState")
	var service := root.get_node("CampaignSaveService")
	service.save_path = OS.get_temp_dir().path_join(
		"dsr-reset-save-%d.cfg" % OS.get_process_id())
	_remove_save_artifacts(service.save_path)
	var settings := root.get_node("UserSettings")
	_settings_path = OS.get_temp_dir().path_join(
		"dsr-reset-settings-%d.cfg" % OS.get_process_id())
	if FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)
	settings.config_path = _settings_path
	check(settings.commit_settings(
		settings.mouse_target_assist_enabled,
		settings.target_switch_sensitivity,
		settings.window_mode,
		settings.resolution_index,
		settings.vsync_enabled) == OK,
		"重置测试准备用户设置文件")
	var saved_settings := FileAccess.get_file_as_string(_settings_path)
	state.reset_game_progress()
	state.money = 100
	state.available_level = 3
	state.help_choice = "accepted"
	state.items = {&"coin": {"display_name": "硬币", "count": 1}}
	state.flags = {&"music_playing": true}
	state.set_flag(&"opening_complete")
	check(service.save_game(state.capture_save_state({})) == OK,
		"重置测试准备有效存档")

	var scene: Node = LEVEL_ONE.instantiate()
	root.add_child(scene)
	current_scene = scene
	for _frame in range(3):
		await process_frame
	scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var director := Director.for_node(scene)
	var loaded_paths: Array[String] = []
	director.scene_loader = func(path: String, _reload: bool) -> Error:
		loaded_paths.append(path)
		return OK
	var health := scene.get_node("Player/Health")
	health.debug_invincible = true
	await process_frame
	var button := health.get_node_or_null("Debug/Controls/ResetProgress") as Button
	check(button != null and not button.disabled, "Debug 控制栏提供可用重置按钮")
	var confirm := health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(confirm != null, "重置进度需要确认对话框")
	if button == null or confirm == null:
		_finish(scene, service.save_path)
		return
	var saved_mode: int = settings.window_mode
	var saved_sensitivity: int = settings.target_switch_sensitivity
	button.pressed.emit()
	check(state.money == 100 and FileAccess.file_exists(service.save_path),
		"确认前不重置游戏进度")
	confirm.confirmed.emit()
	await process_frame
	check(state.money == 0 and state.available_level == 1
			and state.items.is_empty() and state.flags.is_empty()
			and not state.get_flag(&"opening_complete"),
		"重置清空全部游戏进度")
	check(not FileAccess.file_exists(service.save_path),
		"重置删除正式存档")
	check(settings.window_mode == saved_mode
			and settings.target_switch_sensitivity == saved_sensitivity,
		"重置保留用户设置")
	check(loaded_paths == [MAIN_SCENE_PATH],
		"重置加载主场景返回初始酒馆")
	check(FileAccess.file_exists(_settings_path)
			and FileAccess.get_file_as_string(_settings_path) == saved_settings,
		"重置保留 settings.cfg 内容")
	check(root.get_node("DebugSettings").enabled,
		"重置保留 Debug 总开关状态")
	scene.free()
	current_scene = null
	await process_frame

	state.reset_game_progress()
	state.money = 100
	state.available_level = 3
	state.items = {&"coin": {"display_name": "硬币", "count": 1}}
	state.flags = {&"music_playing": true}
	state.set_flag(&"opening_complete")
	check(service.save_game(state.capture_save_state({})) == OK,
		"失败恢复测试准备有效存档")

	var failed_scene: Node = LEVEL_ONE.instantiate()
	root.add_child(failed_scene)
	current_scene = failed_scene
	for _frame in range(3):
		await process_frame
	failed_scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var failed_director := Director.for_node(failed_scene)
	failed_director.scene_loader = func(_path: String, _reload: bool) -> Error:
		return ERR_FILE_CANT_OPEN
	var failed_health := failed_scene.get_node("Player/Health")
	failed_health.debug_invincible = true
	await process_frame
	var failed_button := failed_health.get_node_or_null("Debug/Controls/ResetProgress") as Button
	var failed_confirm := failed_health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(failed_button != null and failed_confirm != null,
		"失败恢复场景提供重置确认入口")
	if failed_button == null or failed_confirm == null:
		_finish(failed_scene, service.save_path)
		return
	failed_confirm.confirmed.emit()
	for _frame in range(3):
		await process_frame
	check(state.money == 100 and FileAccess.file_exists(service.save_path),
		"重置加载失败恢复旧状态和存档")
	check(failed_director.state == &"running",
		"重置加载失败归还场景控制")
	failed_scene.free()
	current_scene = null
	await process_frame

	state.reset_game_progress()
	state.money = 100
	state.available_level = 3
	state.set_flag(&"opening_complete")
	check(service.save_game(state.capture_save_state({})) == OK,
		"备份重置测试准备有效存档")
	var backup_path: String = service.save_path + ".bak"
	var backup_pending: String = backup_path + ".reset-pending"
	check(DirAccess.rename_absolute(service.save_path, backup_path) == OK
			and FileAccess.file_exists(backup_path),
		"备份重置测试构造备份存档")
	var backup_scene: Node = LEVEL_ONE.instantiate()
	root.add_child(backup_scene)
	current_scene = backup_scene
	for _frame in range(3):
		await process_frame
	backup_scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var backup_director := Director.for_node(backup_scene)
	backup_director.scene_loader = func(_path: String, _reload: bool) -> Error: return OK
	var backup_health := backup_scene.get_node("Player/Health")
	backup_health.debug_invincible = true
	await process_frame
	var backup_confirm := backup_health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(backup_confirm != null, "备份重置场景提供确认入口")
	if backup_confirm == null:
		_finish(backup_scene, service.save_path)
		return
	backup_confirm.confirmed.emit()
	for _frame in range(3):
		await process_frame
	check(state.money == 0 and not FileAccess.file_exists(service.save_path)
			and not FileAccess.file_exists(backup_path)
			and not FileAccess.file_exists(backup_pending),
		"重置删除只存在备份的旧存档")
	backup_scene.free()
	current_scene = null
	await process_frame

	_remove_save_artifacts(service.save_path)
	var original_service := root.get_node("CampaignSaveService")
	original_service.name = "CampaignSaveServiceOriginal"
	var failing_service = FailingMaintenanceService.new()
	failing_service.name = "CampaignSaveService"
	failing_service.save_path = service.save_path
	root.add_child(failing_service)

	state.reset_game_progress()
	state.money = 100
	check(failing_service.save_game(state.capture_save_state({})) == OK,
		"恢复失败测试准备有效存档")
	var restore_scene: Node = LEVEL_ONE.instantiate()
	root.add_child(restore_scene)
	current_scene = restore_scene
	for _frame in range(3):
		await process_frame
	restore_scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var restore_director := Director.for_node(restore_scene)
	restore_director.scene_loader = func(_path: String, _reload: bool) -> Error:
		return ERR_FILE_CANT_OPEN
	var restore_errors: Array[Dictionary] = []
	restore_director.action_failed.connect(func(rule: String, reason: String) -> void:
		restore_errors.append({"rule": rule, "reason": reason}))
	var restore_health := restore_scene.get_node("Player/Health")
	restore_health.debug_invincible = true
	await process_frame
	var restore_confirm := restore_health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(restore_confirm != null, "恢复失败测试提供确认入口")
	if restore_confirm == null:
		_finish(restore_scene, failing_service.save_path)
		return
	failing_service.fail_restore = true
	restore_confirm.confirmed.emit()
	for _frame in range(3):
		await process_frame
	check(_has_reset_error(restore_errors, "restore"),
		"恢复暂存存档失败产生可观察错误")
	restore_scene.free()
	current_scene = null
	await process_frame
	_remove_save_artifacts(failing_service.save_path)

	state.reset_game_progress()
	state.money = 100
	failing_service.fail_restore = false
	check(failing_service.save_game(state.capture_save_state({})) == OK,
		"删除失败测试准备有效存档")
	var finish_scene: Node = LEVEL_ONE.instantiate()
	root.add_child(finish_scene)
	current_scene = finish_scene
	for _frame in range(3):
		await process_frame
	finish_scene.get_node("LevelFlow/PlayGuide/Backdrop/Panel/Content/Close").pressed.emit()
	var finish_director := Director.for_node(finish_scene)
	finish_director.scene_loader = func(_path: String, _reload: bool) -> Error: return OK
	var finish_errors: Array[Dictionary] = []
	finish_director.action_failed.connect(func(rule: String, reason: String) -> void:
		finish_errors.append({"rule": rule, "reason": reason}))
	var finish_health := finish_scene.get_node("Player/Health")
	finish_health.debug_invincible = true
	await process_frame
	var finish_confirm := finish_health.get_node_or_null("ResetProgressConfirm") as ConfirmationDialog
	check(finish_confirm != null, "删除失败测试提供确认入口")
	if finish_confirm == null:
		_finish(finish_scene, failing_service.save_path)
		return
	failing_service.fail_finish = true
	finish_confirm.confirmed.emit()
	for _frame in range(3):
		await process_frame
	check(_has_reset_error(finish_errors, "remove"),
		"删除暂存存档失败产生可观察错误")
	check(state.money == 0, "提交后删除失败不恢复旧游戏进度")
	_finish(finish_scene, failing_service.save_path)


func _has_reset_error(errors: Array[Dictionary], reason_fragment: String) -> bool:
	for error in errors:
		if error.get("rule") == "reset" \
				and String(error.get("reason", "")).to_lower().contains(reason_fragment):
			return true
	return false


func _remove_save_artifacts(save_path: String) -> void:
	for path in [save_path, save_path + ".tmp", save_path + ".bak",
			save_path + ".reset-pending", save_path + ".bak.reset-pending"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _on_watchdog() -> void:
	if _finished:
		return
	_finished = true
	paused = false
	push_error("campaign save reset test exceeded %.0f seconds" % WATCHDOG_SECONDS)
	quit(1)


func _finish(scene: Node, save_path: String) -> void:
	if _finished:
		return
	_finished = true
	paused = false
	_remove_save_artifacts(save_path)
	if not _settings_path.is_empty() and FileAccess.file_exists(_settings_path):
		DirAccess.remove_absolute(_settings_path)
	if is_instance_valid(scene):
		scene.free()
	current_scene = null
	print("CAMPAIGN SAVE RESET: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
