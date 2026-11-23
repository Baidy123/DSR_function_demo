extends SceneTree

var checks := 0
var failures := 0

class ConfigMember extends CharacterBody3D:
	var faction_id: StringName = &"enemy"
	var communication_group: StringName = &""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_training_cooperation_removed()
	var profile: EnemyTrainingProfile = load("res://resources/enemy/training/arena.tres").duplicate(true)
	var removed := {"tactics": ["ranged_flank_weight", "ranged_wall_support_weight", "ranged_wall_probe_distance", "damage_accuracy_penalty", "nearby_shot_accuracy_penalty"],
		"cover": ["shot_radius"], "selection": ["away_from_threat_weight", "closer_to_threat_weight", "cover_quality_weight"], "exit_suppression": ["target_radius"]}
	for section in removed:
		var settings = profile.get(section)
		var properties: Array = settings.get_property_list().map(func(p): return p.name)
		for key in removed[section]:
			check(not properties.has(key) and not settings.overridden.has(key), "无效字段及保存覆盖移除：%s.%s" % [section, key])
	profile.set_setting(&"suppression", &"target_radius", 1.35)
	profile.set_setting(&"search", &"track_sight_angle_degrees", 240.0)
	profile.set_setting(&"search", &"search_hint_decay_mode", 3)
	for key in [&"hit_accuracy_loss_multiplier", &"suppression_accuracy_loss_multiplier", &"hit_speed_loss_multiplier"]:
		profile.set_setting(&"tactics", key, 0.5)
	check(ResourceSaver.save(profile, "res://logs/cleanup_training.tres") == OK, "有效配置仍可保存")
	var saved = ResourceLoader.load("res://logs/cleanup_training.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(is_equal_approx(saved.setting(&"suppression", &"target_radius"), 1.35), "普通压制同名半径仍保留")
	check(saved.setting(&"search", &"track_sight_angle_degrees") == 240.0, "有效公共追踪视角字段仍保留")
	check(saved.setting(&"search", &"search_hint_decay_mode") == 3, "搜索模式往返一致")
	for key in [&"hit_accuracy_loss_multiplier", &"suppression_accuracy_loss_multiplier", &"hit_speed_loss_multiplier"]:
		check(is_equal_approx(saved.setting(&"tactics", key), 0.5) and saved.tactics.overridden.has(String(key)), "三个倍率在训练检查器可导出并保存显式覆盖：" + String(key))
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
	var player = load("res://scenes/player/player.tscn").instantiate()
	host.add_child(player)
	player.owner = host
	host.set_editable_instance(player, true)
	for key in [&"hit_accuracy_loss_multiplier", &"suppression_accuracy_loss_multiplier", &"hit_speed_loss_multiplier"]:
		player.get_node("Combat").set(key, 0.5)
	var packed := PackedScene.new()
	check(packed.pack(host) == OK and ResourceSaver.save(packed, "res://logs/cleanup_scene.tscn") == OK, "拖入场景含配置覆盖可保存")
	var restored = ResourceLoader.load("res://logs/cleanup_scene.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	var restored_enemy = preload("res://tests/enemy/enemy_fire_fixture.gd").primary_enemy(restored)
	for key in [&"hit_accuracy_loss_multiplier", &"suppression_accuracy_loss_multiplier", &"hit_speed_loss_multiplier"]:
		check(restored.get_node("Player/Combat").get(key) == 0.5, "玩家Combat检查器倍率场景保存重载：" + String(key))
	check(restored_enemy.position == Vector3(2, 0, -3) and is_equal_approx(restored_enemy.get_node("AI").utility_fire_weight, 1.7), "场景往返保留位置和AI参数覆盖")
	check(is_equal_approx(restored_enemy.get_node("Training").profile.setting(&"suppression", &"target_radius"), 1.35), "嵌套实例训练覆盖重载一致")
	host.free()
	restored.free()
	print("CONFIGURATION CLEANUP: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _training_cooperation_removed() -> void:
	# Load an actual old serialized resource, rather than depending on today's saved presets.
	var legacy_path := "res://logs/legacy_training_cooperation.tres"
	var file := FileAccess.open(legacy_path, FileAccess.WRITE)
	file.store_string("""[gd_resource type="Resource" script_class="EnemyTrainingProfile" format=3]

[ext_resource type="Script" path="res://scripts/enemy/config/enemy_training_profile.gd" id="1"]
[ext_resource type="Script" path="res://scripts/enemy/config/cooperation_settings.gd" id="2"]

[sub_resource type="Resource" id="legacy_cooperation"]
script = ExtResource("2")
level = 2
intel_seconds = 13.0
spacing_margin = 0.9
overridden = PackedStringArray("level", "intel_seconds", "spacing_margin")

[resource]
script = ExtResource("1")
display_name = "Legacy training"
selected_tactics = Array[StringName]([&"cover"])
cooperation = SubResource("legacy_cooperation")
""")
	file.close()
	var legacy = ResourceLoader.load(legacy_path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(legacy is EnemyTrainingProfile and legacy.display_name == "Legacy training" and legacy.selected_tactics == [&"cover"], "旧训练仍可加载，名称和战术解锁保留")
	check(not legacy.get_property_list().any(func(p): return p.name == &"cooperation"), "训练彻底移除 Cooperation 属性及检查器入口")
	check(legacy.module(&"cooperation") == null, "旧训练协作模块不再参与训练查询")
	check(ResourceSaver.save(legacy, "res://logs/legacy_training_cleaned.tres") == OK, "旧训练可重新保存")
	var saved_text := FileAccess.get_file_as_string("res://logs/legacy_training_cleaned.tres")
	check(not saved_text.contains("cooperation =") and not saved_text.contains("cooperation_settings.gd"), "重新保存不再写回旧 Cooperation 字段或资源引用")
	var restored = ResourceLoader.load("res://logs/legacy_training_cleaned.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.selected_tactics == legacy.selected_tactics and restored.display_name == legacy.display_name, "去除重复配置后训练往返保留有效内容")
	var stale = preload("res://scripts/enemy/config/cooperation_settings.gd").new()
	stale.level = 2
	stale.intel_seconds = 14.0
	stale.spacing_margin = 0.95
	legacy.action_overrides.append(stale)
	check(legacy.module(&"cooperation") == null and legacy.setting(&"cooperation", &"intel_seconds", 5.0) == 5.0, "旧 Action Overrides 不能重新注入个人协作配置")
	legacy.set_setting(&"cooperation", &"intel_seconds", 9.0)
	check(stale.intel_seconds == 14.0, "训练写入接口不再修改协作配置")
	var context = preload("res://scripts/enemy/services/enemy_context.gd").new()
	context.training = legacy
	check(context.setting(&"cooperation", &"intel_seconds", 5.0) == 5.0, "没有区域服务时也不回读旧个人配置")
	var board = preload("res://scripts/enemy/services/enemy_cooperation.gd").new()
	var area := Node3D.new()
	var member := ConfigMember.new()
	area.add_child(member)
	context.actor = member
	context.arena = area
	context.cooperation = board
	var defaults := {&"intel_seconds": 5.0, &"checked_point_seconds": 3.0, &"cover_inspection_seconds": 20.0, &"spacing_margin": 0.45}
	for key in defaults:
		check(context.setting(&"cooperation", key, defaults[key]) == defaults[key], "无绑定个人保留现有默认值：" + String(key))
	check(context.cooperation_level() == 0 and not context.commanded(), "旧训练等级不能让无绑定个人变为团队指挥")
	check(context.setting(&"cooperation", &"intel_seconds", 5.0, {&"intel_seconds": 7.0}) == 7.0, "无绑定仍遵守调用方动作缺省值")
	var squad = preload("res://scripts/world/squad_controller.gd").new()
	area.add_child(squad)
	member.reparent(squad, false)
	squad.profile.intel_seconds = 8.0
	squad.profile.checked_point_seconds = 4.0
	squad.profile.cover_inspection_seconds = 12.0
	squad.profile.spacing_margin = 0.6
	for level in [0, 1, 2]:
		squad.profile.level = level
		for key in defaults:
			check(context.setting(&"cooperation", key, defaults[key]) == squad.profile.get(key), "小队等级%d统一读Profile：%s" % [level, key])
		check(context.cooperation_level() == level and context.commanded() == (level > 0), "配置来源统一不改变0级个人／1、2级团队分流")
	context.training = null
	check(context.setting(&"cooperation", &"spacing_margin", 0.45) == 0.6, "没有个人训练时仍读取小队配置")
	squad.profile = null
	check(context.setting(&"cooperation", &"spacing_margin", 0.45) == 0.45 and not context.commanded(), "小队缺少Profile时安全回退默认值及个人决策")
	member.reparent(area, false)
	var binding := EnemyTeamCooperationBinding.new()
	binding.profile.intel_seconds = 6.0
	board.configure_team_bindings([binding])
	check(context.setting(&"cooperation", &"intel_seconds", 5.0) == 6.0, "旧区域显式团队绑定仍为合法配置来源")
	board.configure_team_bindings([])
	check(context.setting(&"cooperation", &"intel_seconds", 5.0) == 5.0, "解除绑定后回到默认值，不回读已删除的训练模块")
	area.free()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
