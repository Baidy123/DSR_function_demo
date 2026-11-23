extends SceneTree

const ServiceScript := preload("res://scripts/systems/campaign_save_service.gd")

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

	var corrupt := ConfigFile.new()
	corrupt.set_value("save", "schema_version", 99)
	check(corrupt.save(save_path) == OK, "构造未知版本存档")
	check(service.load_game().is_empty() and service.last_error_code == &"unsupported_version",
		"未知版本拒绝读取")

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
		"替换失败保留旧存档")
	DirAccess.remove_absolute(temp_directory)
	check(service.stage_reset() == OK and not FileAccess.file_exists(save_path),
		"重置暂存移走正式存档")
	check(service.restore_staged_reset() == OK and FileAccess.file_exists(save_path),
		"加载失败可恢复暂存存档")
	service.stage_reset()
	check(service.finish_staged_reset() == OK and not FileAccess.file_exists(save_path),
		"提交重置后删除暂存存档")

	print("CAMPAIGN SAVE SERVICE: %d/%d passed" % [checks - failures, checks])
	service.free()
	_cleanup()
	quit(1 if failures else 0)


func _cleanup() -> void:
	for suffix in ["", ".tmp", ".bak", ".reset-pending"]:
		var path: String = save_path + str(suffix)
		if DirAccess.dir_exists_absolute(path):
			DirAccess.remove_absolute(path)
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
