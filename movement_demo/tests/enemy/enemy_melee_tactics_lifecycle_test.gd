extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_rush"])
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	enemy.global_position = Vector3(20, 0, -4.2)
	player.global_position = Vector3(23, 0, -4.2)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	var rush = ai.actions[&"melee_rush"]
	var bursts := 0
	var fast_frames := 0
	var previous_fast := false
	var paused_once := false
	var fast_search_after_rush := false
	var search_preserved_cooldown := true
	for frame in 120:
		await physics_frame
		player.global_position.x += 4.0 / 60.0
		ai._physics_process(1.0 / 60.0)
		var moving_fast: bool = Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed * 1.1
		# 失视后的快速追查是独立动作，不能把它计作第二次突进或突进续时。
		var fast: bool = moving_fast and ai.current_action == rush
		if moving_fast and ai.utility_current.get("id") == &"search":
			fast_search_after_rush = true
			search_preserved_cooldown = search_preserved_cooldown and rush._burst_remaining == 0.0 and rush.cooldown_remaining() > 0.0
		if fast:
			fast_frames += 1
			if not previous_fast: bursts += 1
		previous_fast = fast
		if fast and not paused_once:
			paused_once = true
			var clock_before: float = ai.context.evidence_elapsed_seconds
			var cooldown_before: float = rush.cooldown_remaining()
			ai.set_physics_process(true)
			paused = true
			for pause_frame in 4: await physics_frame
			check(ai.context.evidence_elapsed_seconds == clock_before and rush.cooldown_remaining() == cooldown_before, "暂停时机会与突进冷却时钟均不推进")
			paused = false
			ai.set_physics_process(false)
	check(bursts == 1 and fast_frames > 0, "无需玩家换弹也可在近距离自主突然突进")
	check(fast_frames <= 61 and enemy.melee_count == 0, "玩家持续逃跑时突进按时结束，不无限加速追踪")
	check(rush.cooldown_remaining() > 0.0, "突进结束后在其他动作执行期间继续保留冷却")
	check(fast_search_after_rush and search_preserved_cooldown, "失视后独立快速追查，不恢复突进时限或返还冷却")
	var second = load("res://scenes/enemy/enemy.tscn").instantiate()
	second.position = Vector3(2, 0, 5)
	second.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	second.get_node("Training").profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	second.weapon = load("res://resources/weapons/enemy_test_melee.tres").duplicate(true)
	second.get_node("AI").set_physics_process(false)
	scene.get_node("Arena").add_child(second)
	var second_ai = second.get_node("AI")
	check(second_ai.actions[&"melee_rush"] != rush and second_ai.actions[&"melee_rush"].cooldown_remaining() == 0.0, "两个近战兵不共享突进实例或冷却")
	check(second_ai.context.observed_reload_window() == 0.0, "新敌人没有继承其他敌人的换弹证据")
	second.queue_free()
	await process_frame
	enemy.reset_target()
	check(rush.cooldown_remaining() == 0.0 and ai.context.observed_reload_window() == 0.0, "真实区域复位清除突进冷却与观察证据")
	enemy.global_position = Vector3(20, 0, -4.2)
	player.global_position = Vector3(23, 0, -4.2)
	enemy.look_at(player.global_position)
	for frame in 15:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if ai.utility_current.get("id") == &"melee_rush": break
	check(ai.utility_current.get("id") == &"melee_rush", "复位后可重新自主选择突进")
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	await physics_frame
	ai._physics_process(1.0 / 60.0)
	check(not ai.actions.has(&"melee_rush") and ai.current_action != rush and Vector2(enemy.velocity.x, enemy.velocity.z).length() <= enemy.move_speed + 0.01, "运行中撤销战术立即停止突进并恢复默认接敌")
	print("Melee tactics lifecycle: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
