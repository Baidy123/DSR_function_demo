extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile: EnemyTrainingProfile = load("res://resources/enemy/training/arena.tres").duplicate(true)
	var removed := {"tactics": ["ranged_flank_weight", "ranged_wall_support_weight", "ranged_wall_probe_distance"],
		"selection": ["away_from_threat_weight", "closer_to_threat_weight", "cover_quality_weight"], "exit_suppression": ["target_radius"]}
	for section in removed:
		var settings = profile.get(section)
		var properties: Array = settings.get_property_list().map(func(p): return p.name)
		for key in removed[section]:
			check(not properties.has(key) and not settings.overridden.has(key), "无效字段及保存覆盖移除：%s.%s" % [section, key])
	profile.set_setting(&"suppression", &"target_radius", 1.35)
	profile.set_setting(&"cover", &"shot_radius", 2.25)
	profile.set_setting(&"search", &"track_sight_angle_degrees", 240.0)
	profile.set_setting(&"search", &"search_hint_decay_mode", 3)
	profile.set_setting(&"tactics", &"nearby_shot_accuracy_penalty", 0.12)
	check(ResourceSaver.save(profile, "res://logs/cleanup_training.tres") == OK, "有效配置仍可保存")
	var saved = ResourceLoader.load("res://logs/cleanup_training.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(is_equal_approx(saved.setting(&"suppression", &"target_radius"), 1.35), "普通压制同名半径仍保留")
	check(saved.setting(&"cover", &"shot_radius") == 2.25 and saved.setting(&"search", &"track_sight_angle_degrees") == 240.0, "公共服务读取的近弹与追踪视角字段仍保留")
	check(saved.setting(&"search", &"search_hint_decay_mode") == 3 and is_equal_approx(saved.setting(&"tactics", &"nearby_shot_accuracy_penalty"), 0.12), "搜索模式与有效准度数值往返一致")
	var defaults := EnemyTrainingProfile.new()
	check(defaults.setting(&"tactics", &"ranged_min_distance", 0.0, {&"ranged_min_distance": 8.0}) == 8.0, "未覆盖字段仍继承动作参数")
	defaults.set_setting(&"tactics", &"ranged_min_distance", 3.0)
	check(defaults.setting(&"tactics", &"ranged_min_distance", 0.0, {&"ranged_min_distance": 8.0}) == 3.0, "显式覆盖仍优先")
	# 模拟地图中拖入实例并保存嵌套配置覆盖。
	var host := Node3D.new()
	host.name = "SavedMap"
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	host.add_child(enemy)
	enemy.owner = host
	enemy.position = Vector3(2, 0, -3)
	enemy.get_node("Training").profile = saved
	enemy.get_node("AI").utility_fire_weight = 1.7
	host.set_editable_instance(enemy, true)
	var packed := PackedScene.new()
	check(packed.pack(host) == OK and ResourceSaver.save(packed, "res://logs/cleanup_scene.tscn") == OK, "拖入场景含配置覆盖可保存")
	var restored = ResourceLoader.load("res://logs/cleanup_scene.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	var restored_enemy = restored.get_node("Enemy")
	check(restored_enemy.position == Vector3(2, 0, -3) and is_equal_approx(restored_enemy.get_node("AI").utility_fire_weight, 1.7), "场景往返保留位置和AI参数覆盖")
	check(is_equal_approx(restored_enemy.get_node("Training").profile.setting(&"suppression", &"target_radius"), 1.35), "嵌套实例训练覆盖重载一致")
	host.free()
	restored.free()
	print("CONFIGURATION CLEANUP: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
