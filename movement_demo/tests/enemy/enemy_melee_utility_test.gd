extends SceneTree

const Library = preload("res://scripts/enemy/enemy_action_library.gd")
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.health.debug_invincible = true
	for cover in get_nodes_in_group("cover_region"):
		cover.collision_layer = 0
		cover.remove_from_group("cover_region")
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	player.global_position = Vector3(24, 0, -3.1)
	var weapon := WeaponData.new()
	actor.equip_weapon(weapon)
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	await frames(4)
	ai.context.update_evidence(0.0, true)
	ai.context.observed_velocity = Vector3.ZERO
	# 退路受阻时近战能创造空间；开阔地直接退让可能比停步挥击更划算。
	var barriers: Array[Node] = []
	for offset in [Vector3(-0.6, 0.8, -0.5), Vector3(0.6, 0.8, -0.5), Vector3(0, 0.8, 0.6)]:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(0.2, 1.6, 3.0) if offset.x != 0.0 else Vector3(1.4, 1.6, 0.2)
		wall.add_child(shape)
		scene.add_child(wall)
		wall.global_position = actor.global_position + offset
		barriers.append(wall)
	await frames(3)
	ai.context.spatial.reset_evaluation()
	var action = ai.actions.get(&"engage")
	check(action != null and ai.actions.size() == 4 and ai.unit_type.profile.definition(&"melee_strike") == null, "沿用四个默认行为，挥击不进入默认或战术目录")
	var melee_unit = load("res://resources/enemy/units/melee.tres")
	var melee_definitions: Dictionary = Library.resolve(melee_unit, ai.training.profile).definitions
	check(melee_definitions.has(&"melee_engage") and not melee_definitions.has(&"engage") and not melee_definitions.has(&"melee_strike"), "近战兵保留原接近行为，不自动获得远程接敌方案")
	var count: int = actor.melee_count
	var options: Array = ai.action_selector.assess_options(ai, true)
	var strikes: Array = melee_options(options)
	check(strikes.size() == 1 and actor.melee_count == count, "候选收集只评估而不挥击")
	var ordinary: Array = options.filter(func(item): return item.id == &"engage" and item.get("plan") != &"melee")
	check(not ordinary.is_empty() and not ai.action_selector.same_option(strikes[0], ordinary[0]), "接敌同时提供原方案与近战方案，统一选择器能区分")
	var chosen: Dictionary = ai.action_selector.choose_option(options)
	check(chosen.get("id") == &"engage" and chosen.get("plan") == &"melee", "近距离退路受阻时按统一代价选中接敌的近战方案")
	ai._start_utility_option(strikes[0], true)
	var output: Dictionary = action.tick(0.0, true)
	check(output.fire.is_empty() and output.melee.get("owner") == &"engage" and output.direction.is_zero_approx(), "近战方案只请求底层挥击，不同时移动开枪")
	ai.context.melee.update(0.0, true, output.melee)
	check(not action.can_interrupt(ordinary[0], true) and action.valid(true), "同一接敌行为切换方案也遵守挥击期间的中断边界")
	ai._update_utility_decision(0.1, true)
	for index in 26:
		await frames(1)
		ai._physics_process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
	check(actor.melee_count > count and player.global_position.z < -3.5, "选中动作经控制器实际推开玩家")
	for barrier in barriers: barrier.queue_free()
	await frames(3)
	ai.context.spatial.reset_evaluation()
	for index in 120:
		await frames(1)
		ai._physics_process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
	check(actor.global_position.distance_to(player.global_position) > 2.5 and ai.utility_current.get("plan") != &"melee", "挥击后交回决策并拉开距离")
	ai.reset_actions()
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	actor.melee_cooldown = 0.0
	player.global_position = Vector3(24, 0, -5)
	await frames(3)
	ai.context.update_evidence(0.0, true)
	check(melee_options(action.collect_candidates(true)).is_empty() and not action.collect_candidates(true).is_empty(), "远距只排除挥击，原接敌方案继续有效")
	player.global_position = Vector3(24, 0, -3.1)
	await frames(3)
	ai.context.update_evidence(0.0, true)
	check(action.collect_candidates(false).is_empty(), "失视不窥探隐藏玩家位置提供近战")
	actor.melee_cooldown = 1.0
	check(melee_options(action.collect_candidates(true)).is_empty() and not action.collect_candidates(true).is_empty(), "冷却排除近战而不移除原接敌方案")
	actor.melee_cooldown = 0.0
	actor.weapon.melee_enabled = false
	check(melee_options(action.collect_candidates(true)).is_empty() and not action.collect_candidates(true).is_empty(), "武器关闭近战仍可正常接敌")
	actor.weapon.melee_enabled = true
	var selected: Dictionary = melee_options(action.collect_candidates(true))[0]
	ai._start_utility_option(selected, true)
	ai.context.melee.update(0.0, true, action.tick(0.0, true).melee)
	var definition = ai.unit_type.profile.definition(&"engage")
	ai.unit_type.profile.default_behaviors.erase(definition)
	ai.refresh_configuration(true)
	check(not actor.melee_active and not ai.actions.has(&"engage") and actor.melee_cooldown > 0.0, "移除发起请求的接敌行为取消挥击且保留冷却")
	ai.unit_type.profile.default_behaviors.append(definition)
	ai.refresh_configuration(true)
	check(ai.actions.has(&"engage") and ai.actions[&"engage"] != action, "恢复接敌创建新实例，不创建独立挥击行为")
	scene.queue_free()
	await process_frame
	await process_frame
	print("Enemy melee utility: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func melee_options(options: Array) -> Array:
	return options.filter(func(item): return item.id == &"engage" and item.get("plan") == &"melee")

func frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
