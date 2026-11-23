extends SceneTree

const ServiceScript := preload("res://scripts/systems/campaign_save_service.gd")


class InterruptedReplacementService extends "res://scripts/systems/campaign_save_service.gd":
	var rename_calls := 0

	func _rename(from_path: String, to_path: String) -> Error:
		rename_calls += 1
		# Fail temp -> formal and the following rollback, leaving only a valid .bak.
		if rename_calls in [2, 3]:
			return ERR_CANT_CREATE
		return super._rename(from_path, to_path)


var checks := 0
var failures := 0
var save_path := ""


func _initialize() -> void:
	save_path = OS.get_temp_dir().path_join(
		"dsr-campaign-save-service-%d.cfg" % OS.get_process_id())
	_cleanup()
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value:
		failures += 1


func _run() -> void:
	var state := root.get_node("GameState")
	state.reset_game_progress()
	state.money = 125
	var snapshot: Dictionary = state.capture_save_state(
		{"health": {"health": 64.0}})
	var service = ServiceScript.new()
	service.save_path = save_path
	check(service.load_game().is_empty(), "无存档时返回空状态")
	check(service.save_game(snapshot) == OK and FileAccess.file_exists(save_path),
		"单槽写入创建存档")
	var loaded: Dictionary = service.load_game()
	check(loaded.get("money") == 125 and loaded.get("player_state").get("health").get("health") == 64.0,
		"单槽读取恢复完整快照")
	state.money = 0
	check(service.apply_saved_game() == OK and state.money == 125
			and state.opening_cinematic_played,
		"启动读取应用快照并跳过开场镜头")
	var script_args := PackedStringArray([
		"--script",
		"res://tests/campaign_save_service_test.gd",
	])
	var level_args := PackedStringArray([
		"--scene",
		"res://scenes/world/levels/lvl_1.tscn",
	])
	check(not service.should_load_saved_state(script_args, ""),
		"脚本测试默认跳过正常存档")
	check(service.should_load_saved_state(script_args, save_path),
		"隔离存档的脚本测试允许读取")
	state.money = 7
	if service.should_load_saved_state(level_args, ""):
		service.apply_saved_game()
	check(state.money == 7,
		"--scene 关卡启动忽略已有正常存档")
	check(service.should_load_saved_state(PackedStringArray(), ""),
		"主场景正常启动允许读取存档")
	service.apply_saved_game()
	check(state.money == 125,
		"主场景正常启动应用已有存档")

	var corrupt := ConfigFile.new()
	corrupt.set_value("save", "schema_version", 99)
	check(corrupt.save(save_path) == OK, "构造未知版本存档")
	check(service.load_game().is_empty() and service.last_error_code == &"unsupported_version",
		"未知版本拒绝读取")

	for invalid_version in ["1", 1.0, true]:
		service.save_game(snapshot)
		var version_config := ConfigFile.new()
		check(version_config.load(save_path) == OK, "读取版本测试存档")
		version_config.set_value("save", "schema_version", invalid_version)
		check(version_config.save(save_path) == OK, "写入错误版本类型")
		state.money = 41
		check(service.load_game().is_empty() and state.money == 41,
			"schema_version 仅接受精确 int：%s" % [var_to_str(invalid_version)])
		check(service.apply_saved_game() != OK and state.money == 41,
			"错误版本类型不应用且不改状态：%s" % [var_to_str(invalid_version)])

	service.save_game(snapshot)
	var metadata_config := ConfigFile.new()
	check(metadata_config.load(save_path) == OK, "读取元数据校验存档")
	metadata_config.set_value("save", "saved_at_unix", "now")
	check(metadata_config.save(save_path) == OK, "写入错误保存时间")
	check(service.load_game().is_empty(), "错误保存时间拒绝读取")

	service.save_game(snapshot)
	metadata_config = ConfigFile.new()
	check(metadata_config.load(save_path) == OK, "重新读取元数据校验存档")
	metadata_config.set_value("save", "opening_cinematic_played", 1)
	check(metadata_config.save(save_path) == OK, "写入错误开场标记")
	check(service.load_game().is_empty(), "错误开场标记拒绝读取")

	service.save_game(snapshot)
	metadata_config = ConfigFile.new()
	check(metadata_config.load(save_path) == OK, "再次读取元数据校验存档")
	metadata_config.erase_section_key("save", "saved_at_unix")
	check(metadata_config.save(save_path) == OK, "删除必需保存时间")
	check(service.load_game().is_empty(), "缺失保存时间拒绝读取")

	service.save_game(snapshot)
	var malformed_nested := ConfigFile.new()
	check(malformed_nested.load(save_path) == OK, "读取嵌套校验存档")
	malformed_nested.set_value("player", "player_state", {"equipment": {
		"primary_weapon": null,
		"secondary_weapon": null,
		"medkit": null,
		"medkit_count": 0,
		"active_slot": 0,
		"reserve_ammo": {&"pistol": "twelve"},
		"magazines": [0, 0],
	}})
	check(malformed_nested.save(save_path) == OK, "写入错误装备嵌套数据")
	state.money = 41
	check(service.load_game().is_empty() and state.money == 41,
		"错误装备嵌套数据在应用前拒绝")

	service.save_game(snapshot)
	malformed_nested = ConfigFile.new()
	check(malformed_nested.load(save_path) == OK, "重新读取嵌套校验存档")
	malformed_nested.set_value("world", "items",
		{&"coin": {"display_name": "硬币", "count": "3"}})
	check(malformed_nested.save(save_path) == OK, "写入错误物品嵌套数据")
	check(service.apply_saved_game() != OK and state.money == 41,
		"错误物品嵌套数据不应用且不改状态")

	service.save_game(snapshot)
	malformed_nested = ConfigFile.new()
	check(malformed_nested.load(save_path) == OK, "再次读取嵌套校验存档")
	malformed_nested.set_value("campaign", "campaign_checkpoint", {
		"level": "1",
		"completed_level": 1,
		"available_level": 1,
		"claimed_reward_levels": {},
		"shop_flags": {},
		"task_a_returned": "returned",
		"money": 100,
		"rewarded_task_ids": {},
		"purchased_shop_item_ids": {},
		"player_state": {},
	})
	check(malformed_nested.save(save_path) == OK, "写入错误检查点嵌套数据")
	check(service.load_game().is_empty(),
		"错误检查点嵌套数据在应用前拒绝")

	var invalid := snapshot.duplicate(true)
	invalid.money = "125"
	check(service.save_game(invalid) != OK and service.last_error_code == &"invalid_state",
		"错误字段类型拒绝写入")

	var malformed := ConfigFile.new()
	malformed.set_value("save", "schema_version", 1)
	check(malformed.save(save_path) == OK and service.load_game().is_empty()
			and service.last_error_code == &"invalid_state",
		"缺失必需字段拒绝读取")

	service.save_path = save_path + ".missing-dir/save.cfg"
	check(service.save_game(snapshot) != OK and service.last_error_code == &"write_failed",
		"写入失败返回明确错误")

	service.save_path = save_path
	service.save_game(snapshot)
	var temp_directory := save_path + ".tmp"
	DirAccess.make_dir_absolute(temp_directory)
	check(service.save_game(snapshot) != OK and service.load_game().get("money") == 125,
		"临时文件写入失败保留旧存档")
	DirAccess.remove_absolute(temp_directory)

	state.money = 250
	var replacement_snapshot: Dictionary = state.capture_save_state(
		{"health": {"health": 100.0}})
	var interrupted = InterruptedReplacementService.new()
	interrupted.save_path = save_path
	check(interrupted.save_game(replacement_snapshot) != OK
			and interrupted.last_error_code == &"rollback_failed"
			and FileAccess.file_exists(save_path + ".bak")
			and not FileAccess.file_exists(save_path),
		"替换与回滚失败后保留有效备份")
	state.money = 0
	check(interrupted.apply_saved_game() == OK and state.money == 125
			and FileAccess.file_exists(save_path),
		"启动从有效备份恢复旧存档")
	interrupted.free()

	check(service.save_game(snapshot) == OK
			and DirAccess.rename_absolute(save_path, save_path + ".bak") == OK,
		"构造有效备份和损坏主存档")
	var corrupt_primary := ConfigFile.new()
	corrupt_primary.set_value("save", "schema_version", "broken")
	check(corrupt_primary.save(save_path) == OK, "写入损坏主存档")
	var corrupt_primary_text := FileAccess.get_file_as_string(save_path)
	state.money = 41
	check(service.apply_saved_game() == OK and state.money == 125,
		"损坏主存档可回退到有效备份")
	check(FileAccess.file_exists(save_path)
			and FileAccess.get_file_as_string(save_path) == corrupt_primary_text
			and FileAccess.file_exists(save_path + ".bak"),
		"备份回退保留损坏主存档和有效备份")

	var invalid_backup := ConfigFile.new()
	invalid_backup.set_value("save", "schema_version", 99)
	check(invalid_backup.save(save_path + ".bak") == OK, "写入损坏备份")
	state.money = 41
	check(service.apply_saved_game() != OK and state.money == 41,
		"主存档和备份均无效时不应用且不改状态")

	var invalid_startup := ConfigFile.new()
	invalid_startup.set_value("save", "schema_version", 1)
	check(invalid_startup.save(save_path) == OK
			and service._remove_file(save_path + ".bak") == OK,
		"构造启动失败的孤立损坏存档")
	state.money = 41
	var previous_override := OS.get_environment("DSR_CAMPAIGN_SAVE_CONFIG")
	OS.set_environment("DSR_CAMPAIGN_SAVE_CONFIG", save_path)
	service._ready()
	service._ready()
	if previous_override.is_empty():
		OS.unset_environment("DSR_CAMPAIGN_SAVE_CONFIG")
	else:
		OS.set_environment("DSR_CAMPAIGN_SAVE_CONFIG", previous_override)
	var warning_count := 0
	var has_warning_count := false
	for property in service.get_property_list():
		if property.name == "startup_warning_count":
			has_warning_count = true
			warning_count = int(service.get("startup_warning_count"))
	check(has_warning_count, "启动加载错误通过可观察 warning 计数报告")
	check(warning_count == 1, "启动加载错误只报告一次")
	check(FileAccess.file_exists(save_path) and state.money == 41,
		"启动加载失败保留原存档且不改状态")

	check(service.stage_reset() == OK and not FileAccess.file_exists(save_path),
		"重置暂存移走正式存档")
	check(service.restore_staged_reset() == OK and FileAccess.file_exists(save_path),
		"加载失败可恢复暂存存档")
	service.stage_reset()
	check(service.finish_staged_reset() == OK and not FileAccess.file_exists(save_path),
		"提交重置后删除暂存存档")
	service.save_game(snapshot)
	var backup_path := save_path + ".bak"
	var backup_pending := backup_path + ".reset-pending"
	check(DirAccess.rename_absolute(save_path, backup_path) == OK
			and FileAccess.file_exists(backup_path),
		"构造仅备份可恢复存档")
	check(service.stage_reset() == OK and not FileAccess.file_exists(backup_path)
			and FileAccess.file_exists(backup_pending),
		"重置暂存包含备份存档")
	check(service.restore_staged_reset() == OK and FileAccess.file_exists(backup_path)
			and not FileAccess.file_exists(backup_pending),
		"加载失败恢复备份存档")
	service.stage_reset()
	check(service.finish_staged_reset() == OK and not FileAccess.file_exists(backup_path)
			and not FileAccess.file_exists(backup_pending),
		"提交重置删除备份暂存")

	service.save_game(snapshot)
	var pending_path: String = save_path + ".reset-pending"
	check(DirAccess.rename_absolute(save_path, pending_path) == OK,
		"构造主存档重置崩溃窗口")
	var script_skip_service = ServiceScript.new()
	script_skip_service.save_path = save_path
	root.add_child(script_skip_service)
	await process_frame
	check(FileAccess.file_exists(pending_path),
		"未隔离脚本测试不清理也未读取正常存档路径")
	script_skip_service.queue_free()
	await process_frame
	check(DirAccess.rename_absolute(pending_path, save_path) == OK,
		"恢复崩溃窗口准备隔离启动")
	check(DirAccess.rename_absolute(save_path, pending_path) == OK,
		"重新构造主存档重置崩溃窗口")
	var crash_service = ServiceScript.new()
	crash_service.save_path = save_path
	var previous_crash_override := OS.get_environment("DSR_CAMPAIGN_SAVE_CONFIG")
	OS.set_environment("DSR_CAMPAIGN_SAVE_CONFIG", save_path)
	root.add_child(crash_service)
	if previous_crash_override.is_empty():
		OS.unset_environment("DSR_CAMPAIGN_SAVE_CONFIG")
	else:
		OS.set_environment("DSR_CAMPAIGN_SAVE_CONFIG", previous_crash_override)
	await process_frame
	check(not FileAccess.file_exists(save_path)
			and not FileAccess.file_exists(pending_path),
		"启动将残留主存档 pending 视为已请求重置")
	check(crash_service.stage_reset() == OK,
		"清理残留 pending 后重置不再永久阻塞")
	check(crash_service.finish_staged_reset() == OK,
		"清理残留 pending 后可结束已请求重置")
	check(crash_service.save_game(snapshot) == OK
			and crash_service.stage_reset() == OK
			and FileAccess.file_exists(pending_path),
		"清理残留 pending 后可再次暂存正式重置")
	check(crash_service.finish_staged_reset() == OK,
		"后续正式重置可完成")

	check(crash_service.save_game(snapshot) == OK
			and DirAccess.rename_absolute(save_path, backup_path) == OK
			and DirAccess.rename_absolute(backup_path, backup_pending) == OK,
		"构造备份存档重置崩溃窗口")
	check(crash_service.stage_reset() == OK
			and not FileAccess.file_exists(backup_pending),
		"残留备份 pending 不会阻塞后续重置")
	check(crash_service.finish_staged_reset() == OK,
		"清理残留备份 pending 后可结束已请求重置")
	check(crash_service.save_game(snapshot) == OK
			and crash_service.stage_reset() == OK
			and crash_service.finish_staged_reset() == OK,
		"清理备份 pending 后可再次完成正式重置")
	crash_service.queue_free()
	await process_frame

	print("CAMPAIGN SAVE SERVICE: %d/%d passed" % [checks - failures, checks])
	service.free()
	_cleanup()
	quit(1 if failures else 0)


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak", ".reset-pending", ".bak.reset-pending"]:
		var path: String = save_path + str(suffix)
		if DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(path)
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
