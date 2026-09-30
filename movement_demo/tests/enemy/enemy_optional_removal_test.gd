extends SceneTree

var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
		push_error(label)

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	ai.unit_type.profile.tactical_actions.clear()
	ai.training.profile.selected_tactics.assign([&"exit_suppression", &"covering_retreat", &"attack_position"])
	ai.refresh_configuration(true)
	ai.cover_selection.debug_cover_selection = false
	ai.actions[&"search"].debug_tracking_cheat = false
	ai.actions[&"search"].tracking_cheat_enabled = false
	check(ai.actions.size() == 4 and not ai.actions.has(&"melee_strike"), "全部战术从兵种移除后保留原四个默认模块")
	enemy.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(22, 0, -2)
	enemy.look_at(player.global_position)
	enemy.weapon.magazine_capacity = 2
	enemy.ammo.magazine_rounds = 2
	for frame in range(5): await physics_frame
	var reloaded := false
	for frame in range(360):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		reloaded = reloaded or enemy.ammo.is_reloading
	check(enemy.shot_count >= 2 and reloaded, "没有任何战术时默认接敌仍实际射击和换弹")
	# 移除接敌，单独验证压制仍使用公共射击服务，不依赖接敌实例。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 2
	ai.unit_type.profile.default_behaviors = ai.unit_type.profile.default_behaviors.filter(func(item): return item.action_id != &"engage")
	ai.unit_type.profile.tactical_actions.append(preload("res://resources/enemy/actions/suppression.tres"))
	ai.training.profile.selected_tactics.assign([&"suppression"])
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"engage") and ai.actions.has(&"suppression"), "接敌与压制按定义分别装配")
	enemy.global_position = Vector3(24, 0, -2)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = Vector3(22, 0, -2)
	ai.last_known_position = ai.last_seen_position
	player.global_position = Vector3(26, 0, 4)
	enemy.look_at(ai.last_seen_position)
	for frame in range(4): await physics_frame
	var shots: int = enemy.shot_count
	ai._start_utility_option({"id": &"suppression", "destination": {}, "cost": 0.0}, false)
	var suppression = ai.actions[&"suppression"]
	for frame in range(60):
		await physics_frame
		var output: Dictionary = suppression.tick(1.0 / 60.0, false)
		enemy.face_direction(output.facing, 1.0 / 60.0)
		ai.context.fire.update(1.0 / 60.0, false, false, output.fire)
	check(enemy.shot_count > shots, "移除接敌模块后压制仍能独立实际开火")
	ai.unit_type.profile.tactical_actions.clear()
	ai.refresh_configuration(true)
	check(ai.current_action == null and not suppression.is_active(), "运行中删除压制会取消其执行")
	ai.context.noise_search_origin = Vector3.INF
	ai.is_alerted = true
	ai.last_known_position = Vector3(22, 0, -2)
	var start: Vector3 = enemy.global_position
	var searching := false
	for frame in range(240):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		searching = searching or ai.utility_current.get("id") == &"search"
	check(searching and enemy.global_position.distance_to(start) > 0.3, "移除接敌和压制后仍能根据记忆搜索移动")
	ai.reset_actions()
	ai.context.noise_search_origin = Vector3.INF
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	var first_noise := Vector3(22, 0, -2)
	ai._on_noise_heard(first_noise)
	ai._update_utility_decision(1.0, false)
	check(ai.utility_current.get("id") == &"search", "声音由通用事件进入搜索候选并开始执行")
	var search = ai.actions[&"search"]
	search.track_timer = 1.23
	ai._on_noise_heard(first_noise)
	check(is_equal_approx(search.track_timer, 1.23), "同位置连续发声不会无限重置调查计时")
	var next_noise := Vector3(23, 0, -2)
	ai._on_noise_heard(next_noise)
	check(ai.last_known_position == next_noise and ai.context.noise_search_origin == next_noise and search.track_timer > 1.23, "执行中的搜索能响应新声源，且不依赖战术模块")
	enemy.receive_hit(enemy.max_health)
	check(ai.current_action == null and ai.context.fire.request.is_empty(), "死亡统一取消当前模块和射击意图")
	enemy.reset_target()
	check(not ai.is_alerted and ai.utility_current.is_empty(), "复位清理共享记忆与动作状态")
	print("OPTIONAL REMOVAL: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)
