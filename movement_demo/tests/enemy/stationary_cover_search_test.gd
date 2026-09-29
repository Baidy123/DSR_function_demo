extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(11)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.cover_selection.debug_cover_selection = false
	ai.actions[&"search"].tracking_cheat_enabled = false
	ai.actions[&"search"].debug_tracking_cheat = false
	player.get_node("Health").debug_invincible = true
	player.global_position = Vector3(18.585854, 0.001, 4.430427)
	actor.global_position = Vector3(26.48409, 0.001, 4.78908)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	actor.health = actor.max_health * 0.1
	ai.recent_damage_pressure = 1.5
	for frame in range(60):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, false)
	var options: Array = ai.action_selector.assess_options(ai, false)
	var covers: Array = options.filter(func(o): return o.id == &"cover" and o.get("mode") != &"peek")
	check(not covers.is_empty(), "静止躲藏场景存在真实可用掩体")
	if covers.is_empty():
		quit(1)
		return
	var choice: Dictionary = covers[0]
	actor.global_position = choice.destination.hide
	for frame in range(3): await physics_frame
	ai._start_utility_option(choice, false)
	check(not ai.perception.can_see_player(), "开始时双方确实被掩体遮挡")
	var fixed_player: Vector3 = player.global_position
	var start: Vector3 = actor.global_position
	var searched := false
	var recovered := false
	var returned_to_hide := false
	var hide_seconds := 0.0
	var longest_hide := 0.0
	var moved := 0.0
	for frame in range(1800):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		var id: StringName = ai.utility_current.get("id", &"")
		recovered = recovered or ai.was_seeing_player
		searched = searched or id == &"search"
		if searched and not recovered and id == &"cover" and ai.utility_current.get("mode") != &"peek": returned_to_hide = true
		if ai.actions[&"cover"].transfer.phase == ai.actions[&"cover"].transfer.Phase.HIDE:
			hide_seconds += 1.0 / 60.0
		else: hide_seconds = 0.0
		longest_hide = maxf(longest_hide, hide_seconds)
		moved = maxf(moved, actor.global_position.distance_to(start))
		if recovered and actor.shot_count > 0: break
	check(player.global_position == fixed_player, "整个场景玩家保持静止")
	check(searched and moved > 0.8, "没有新攻击后敌人离开躲藏并实际推进调查")
	check(not returned_to_hide, "未重新目击前不在搜索与躲藏之间反复切换")
	check(longest_hide < 15.0, "静止玩家不会让敌人无限躲藏")
	check(recovered and actor.shot_count > 0, "绕行调查能重新发现静止玩家并恢复射击")
	print("STATIONARY COVER SEARCH: %d/%d passed, hide=%.2f movement=%.2f" % [checks - failures, checks, longest_hide, moved])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
