extends SceneTree

var checks := 0
var failed := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	var arena = scene.get_node("Arena")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy_fire_fixture.gd").configure_timing(enemy)
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	player.get_node("Health").debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.move_speed = 1.5
	enemy.ammo.magazine_rounds = 0
	enemy.weapon.reload_seconds = 2.0
	for frame in range(5): await physics_frame
	ai.is_alerted = true
	ai.last_known_position = player.global_position
	ai.last_seen_position = player.global_position
	# 预算扫描逐帧完成，不要求首帧穷举全地图。
	for frame in range(60):
		await physics_frame
		ai.action_selector.advance_evaluation(ai, true)
	var options: Array = ai.assess_reload_options()
	check(options.any(func(o): return o.plan == &"here") and options.any(func(o): return o.plan == &"after_cover") and options.any(func(o): return o.plan == &"on_way"), "三种换弹计划来自共同候选池")
	check(options.all(func(o): return o.id == &"reload" and o.has("breakdown")), "兼容入口只筛选共同评分")
	var transfer: Dictionary = {}
	for option: Dictionary in options:
		if option.plan == &"after_cover" and ai._horizontal_distance(option.destination.hide) > 1.0:
			transfer = option
			break
	check(not transfer.is_empty(), "真实场景提供可行转移")
	if transfer.is_empty():
		finish()
		return
	# 统一选择与保持由utility_ai_test验证；这里固定合法方案，检查实际执行边界。
	for plan: StringName in [&"after_cover", &"on_way", &"here"]:
		ai.reset_actions()
		enemy.cancel_reload()
		enemy.ammo.magazine_rounds = 0
		enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
		enemy.velocity = Vector3.ZERO
		enemy.weapon.reload_seconds = 0.3 if plan == &"on_way" else 2.0
		ai.is_alerted = true
		ai.last_known_position = player.global_position
		var selected: Dictionary = transfer.duplicate()
		selected.plan = plan
		if plan == &"here": selected.destination = {}
		for frame in range(3): await physics_frame
		ai._start_utility_option(selected, false)
		check(enemy.ammo.is_reloading == (plan != &"after_cover"), "%s按选定时机启动" % plan)
		var saw_reload: bool = enemy.ammo.is_reloading
		var early_reload := false
		var limited := true
		var speed_restored := false
		for frame in range(1500):
			await physics_frame
			var executing: bool = ai.step_reload_plan(1.0 / 60.0, false)
			if enemy.ammo.is_reloading:
				saw_reload = true
				early_reload = early_reload or (plan == &"after_cover" and ai.cover.phase != ai.cover.Phase.HIDE)
				limited = limited and Vector2(enemy.velocity.x, enemy.velocity.z).length() <= enemy.move_speed + 0.02
			elif ai.cover.phase == ai.cover.Phase.RUN_TO_COVER:
				speed_restored = speed_restored or Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed + 0.1
			if not executing: break
		check(saw_reload and not early_reload, "%s按顺序执行，先到掩体不会提前换弹" % plan)
		check(limited, "%s换弹时禁止快移" % plan)
		check(ai.reload_plan.is_empty() and enemy.ammo.magazine_rounds > 0, "%s完成装填并交接" % plan)
		if plan == &"on_way": check(speed_restored, "途中换完恢复快速转移")
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	ai._start_utility_option(transfer, false)
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 1)
	shape.shape = box
	blocker.add_child(shape)
	scene.add_child(blocker)
	blocker.global_position = transfer.destination.hide + Vector3.UP
	for frame in range(3): await physics_frame
	ai.invalidate_utility()
	ai._update_utility_decision(0.01, false)
	check(not ai.action_selector.same_option(ai.utility_current, transfer), "目的地被堵立即重评，不受保持期限制")
	blocker.queue_free()
	await physics_frame
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	ai.training.allowed_actions.clear()
	ai._update_utility_decision(0.01, false)
	check(ai.reload_plan == &"here" and enemy.ammo.is_reloading, "撤销战术权限仍能基础换弹")
	var progress: float = enemy.ammo.reload_progress
	enemy.receive_hit(1.0, player.global_position)
	check(enemy.ammo.is_reloading and enemy.ammo.reload_progress == progress, "受伤保留换弹进度")
	var pressure: float = ai.recent_damage_pressure
	ai._physics_process(0.1)
	check(ai.recent_damage_pressure < pressure, "压力随时间衰减")
	player.is_in_dialogue = true
	ai._physics_process(0.1)
	check(not enemy.ammo.is_reloading and ai.utility_current.is_empty(), "对话清理动作和方案")
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("RELOAD DECISION: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
