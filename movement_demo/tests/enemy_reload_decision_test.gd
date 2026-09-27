extends SceneTree

const Fixture = preload("res://tests/enemy_fire_fixture.gd")
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
	Fixture.configure_timing(enemy)
	ai.cover_selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	player.get_node("Health").debug_invincible = true
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	for frame in range(5):
		await physics_frame
	check(ai.has_method("assess_reload_options"), "AI有实际环境换弹评估入口")
	if failed > 0:
		finish()
		return
	# 同一换弹耗时，不同路线风险：检查三个方案都可能胜出。
	var safe: Dictionary = ai.reload_plan_costs(2.0, 0.0, 0.0, {"seconds": 1.0, "exposure": 0.8}, {"seconds": 2.0, "exposure": 1.6})
	check(best_plan(safe) == &"here", "当前位置安全时原地换弹胜出")
	var close: Dictionary = ai.reload_plan_costs(2.0, 1.0, 0.0, {"seconds": 0.7, "exposure": 0.7}, {"seconds": 1.4, "exposure": 1.4})
	check(best_plan(close) == &"after_cover", "近处掩体且路程暴露时先快速转移再换弹胜出")
	var distant: Dictionary = ai.reload_plan_costs(2.0, 1.0, 0.0, {"seconds": 4.0, "exposure": 0.6}, {"seconds": 5.0, "exposure": 0.9})
	check(best_plan(distant) == &"on_way", "较长且多数受遮挡路线允许边转移边换弹胜出")
	enemy.health = enemy.max_health * 0.1
	var wounded: Dictionary = ai.reload_plan_costs(2.0, 1.0, 0.0, {"seconds": 0.7, "exposure": 0.7}, {"seconds": 1.4, "exposure": 1.4})
	check(wounded.here - wounded.after_cover > close.here - close.after_cover, "低血量增加规避暴露的收益而不修改遮挡质量")
	enemy.health = enemy.max_health

	# 真实场景查询：没有已知威胁时只原地换；位于墙后时也不无谓找新掩体。
	ai.is_alerted = false
	ai.search.noise_search_origin = Vector3.INF
	var options: Array = ai.assess_reload_options()
	check(options.size() == 1 and options[0].plan == &"here", "没有感知记忆的威胁时不凭空查询玩家位置")
	enemy.global_position = arena.to_global(Vector3(-5, 0, 2.5))
	ai.is_alerted = true
	ai.last_known_position = player.global_position
	options = ai.assess_reload_options()
	check(ai.choose_reload_option(options).plan == &"here", "真实墙体遮挡当前位置时立即换弹")
	var options_before: Array = options.duplicate(true)
	player.global_position += Vector3(0, 0, -2)
	options = ai.assess_reload_options()
	check(options == options_before, "失视评估只使用旧记忆，不读取墙后玩家的新位置")

	# 实际空匣决策由物理循环触发，保留玩家与敌人的真实感知。
	player.global_position = arena.to_global(Vector3(0, 0, 2.5))
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.rotation = Vector3.ZERO
	enemy.move_speed = 1.5
	ai.last_known_position = player.global_position
	enemy.ammo.magazine_rounds = 0
	enemy.weapon.reload_seconds = 2.0
	options = ai.assess_reload_options()
	check(options.size() > 1, "暴露位置能产生经过空间和路线检查的掩体换弹候选")
	for option: Dictionary in options:
		if option.plan != &"here":
			check(not ai.cover_selection._path_to(enemy.global_position, option.destination.hide).is_empty(), "换弹目的地真实可达")
			break
	# 强制测试一个已评估合格的先到掩体方案，只验证执行，不替代上面的选择断言。
	var transfer: Dictionary = ai.choose_reload_option(options)
	check(transfer.plan == &"after_cover", "真实暴露位置评估选择先到掩体而非立即换弹")
	check(not transfer.is_empty(), "评估提供先到掩体方案")
	if not transfer.is_empty():
		enemy.look_at(player.global_position)
		ai._physics_process(1.0 / 60.0)
		check(ai.reload_plan == &"after_cover", "实际AI物理循环采用评估结果")
		check(not enemy.ammo.is_reloading, "先到掩体方案启动时不会先换弹")
		var saw_reload := false
		for frame in range(1500):
			await physics_frame
			ai._update_reload_request(1.0 / 60.0)
			ai.step_reload_plan(1.0 / 60.0, false)
			if enemy.ammo.is_reloading:
				saw_reload = true
				check(ai.reload_plan == &"on_way" or ai.cover.phase == ai.cover.Phase.HIDE, "途中重评只有改选边走边换后才允许提前开始")
				check(Vector2(enemy.velocity.x, enemy.velocity.z).length() <= enemy.move_speed + 0.01, "真实转移中换弹执行普通速度上限")
				break
		check(saw_reload, "先转移方案可以完成寻路并开始换弹")
		if saw_reload:
			for frame in range(180):
				await physics_frame
				if not ai.step_reload_plan(1.0 / 60.0, false):
					break
			check(enemy.ammo.magazine_rounds > 0 and ai.reload_plan == &"", "换完弹释放换弹计划并交回原AI")
	# 单独验证选定方案的执行边界，不在这段中触发战术重评。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.velocity = Vector3.ZERO
	ai.last_known_position = player.global_position
	options = ai.assess_reload_options()
	transfer = ai.choose_reload_option(options)
	ai.start_reload_plan(transfer)
	var original_target: Vector3 = ai.reload_destination.hide
	ai.last_known_position.x += 0.001
	ai._update_reload_request(0.5)
	check(ai.reload_plan == &"after_cover" and ai.reload_destination.hide == original_target and not enemy.ammo.is_reloading, "保持期内微小环境变化不重启或切换方案")
	var arrived_before_reload := false
	for frame in range(1200):
		await physics_frame
		ai.step_reload_plan(1.0 / 60.0, false)
		if enemy.ammo.is_reloading:
			arrived_before_reload = ai.cover.phase == ai.cover.Phase.HIDE
			break
	check(arrived_before_reload, "保持先到掩体方案时，实际到达后才启动换弹")
	var held_position: Vector3 = enemy.global_position
	for frame in range(180):
		await physics_frame
		if not ai.step_reload_plan(1.0 / 60.0, false):
			break
	check(ai.reload_plan.is_empty() and enemy.ammo.magazine_rounds > 0 and enemy.global_position.distance_to(held_position) < 0.05, "抵达后停在掩体完成固定时长换弹，不提前探头")

	# 边走边换在途中完成，仍能正常走完路线，且只装填一次。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.velocity = Vector3.ZERO
	enemy.weapon.reload_seconds = 0.3
	options = ai.assess_reload_options()
	var moving: Dictionary = {}
	for option: Dictionary in options:
		if option.plan == &"on_way" and ai._horizontal_distance(option.destination.hide) > 3.0:
			moving = option
			break
	check(not moving.is_empty(), "真实地图提供可执行的边走边换路线")
	if not moving.is_empty():
		ai.start_reload_plan(moving)
		check(enemy.ammo.is_reloading, "边走边换方案开始时立即启动固定换弹计时")
		var completed_on_route := false
		var recovered_speed := false
		for frame in range(1800):
			await physics_frame
			if not ai.step_reload_plan(1.0 / 60.0, false):
				break
			if not enemy.ammo.is_reloading and ai.cover.phase == ai.cover.Phase.RUN_TO_COVER:
				completed_on_route = true
				recovered_speed = recovered_speed or Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed + 0.1
		check(completed_on_route and recovered_speed, "途中换完后恢复动作速度并继续原路线")
		check(ai.reload_plan.is_empty() and enemy.ammo.magazine_rounds == enemy.weapon.magazine_capacity, "边走边换最终抵达并交接，不重复装填或卡住")

	# 躲藏中受伤仍退出，随后同一枪来弹不把它立即送回去。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	enemy.weapon.reload_seconds = 2.0
	ai.start_reload_plan({"plan": &"on_way", "cost": 0.0, "destination": moving.destination})
	ai.cover.phase = ai.cover.Phase.HIDE
	enemy.update_weapon(0.5)
	var progress: float = enemy.ammo.reload_progress
	enemy.receive_hit(1.0, player.global_position)
	check(not ai.cover.is_active() and ai.reload_plan.is_empty() and is_equal_approx(enemy.ammo.reload_progress, progress), "换弹躲藏中真实受伤仍退出HIDE且不重置换弹")
	ai.notice_shot(player.global_position + Vector3.UP * 0.8, enemy.get_shot_origin())
	check(not ai.cover.is_active(), "同一枪后续来弹不能立即重新躲回去")
	# 下一物理帧有效近弹可增加独立压力，其影响小于实际伤害。
	await physics_frame
	var before_nearby: float = ai.nearby_shot_pressure
	ai.notice_shot(enemy.get_shot_origin() + Vector3.RIGHT, enemy.get_shot_origin())
	check(ai.nearby_shot_pressure > before_nearby and ai.nearby_shot_pressure < ai.recent_damage_pressure, "有效近弹参与压力且弱于实际伤害")
	ai.recent_damage_pressure = 0.0
	ai.nearby_shot_pressure = 0.0
	ai._reload_avoid_position = Vector3.INF
	# 路线堵塞及权限撤销不被保持期锁住，也不取消已开始的换弹进度。
	ai.reset_actions()
	enemy.cancel_reload()
	ai.last_known_position = player.global_position
	enemy.global_position = arena.to_global(Vector3(-2, 0, 0))
	enemy.ammo.magazine_rounds = 0
	enemy.weapon.reload_seconds = 2.0
	transfer = ai.choose_reload_option(ai.assess_reload_options())
	ai.start_reload_plan(transfer)
	check(not ai.reload_destination.is_empty(), "路线失效检查前已启动有效转移")
	if ai.reload_destination.is_empty():
		finish()
		return
	var blocked_target: Vector3 = ai.reload_destination.hide
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1, 2, 1)
	shape.shape = box
	blocker.add_child(shape)
	scene.add_child(blocker)
	blocker.global_position = blocked_target + Vector3.UP
	for frame in range(2): await physics_frame
	ai._update_reload_request(0.41)
	check(ai.reload_destination.is_empty() or ai.reload_destination.hide != blocked_target, "新障碍使目的地失效时在保持期内重评")
	blocker.queue_free()
	await physics_frame
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	transfer = ai.choose_reload_option(ai.assess_reload_options())
	ai.start_reload_plan(transfer)
	ai.training.allowed_actions = ai.training.allowed_actions.filter(func(action): return action.action_id != &"cover")
	ai._physics_process(0.01)
	check(ai.reload_plan == &"here" and enemy.ammo.is_reloading, "转移中撤销掩体权限立即回退，不被保持期卡住")

	var before_damage: float = ai.recent_damage_pressure
	enemy.receive_hit(1.0, player.global_position)
	check(ai.recent_damage_pressure > before_damage + 0.5 and enemy.ammo.is_reloading, "真实受伤增加压力且保留基础换弹进度")
	var pressure: float = ai.recent_damage_pressure
	ai._physics_process(0.1)
	check(ai.recent_damage_pressure < pressure, "压力随时间衰减")
	# 撤销掩体权限后不能一直等待不存在的转移方案。
	ai.reset_actions()
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = 0
	ai.training.allowed_actions.clear()
	options = ai.assess_reload_options()
	check(options.size() == 1 and options[0].plan == &"here", "没有掩体动作权限时只保留基础换弹回退")
	ai._update_reload_request(0.1)
	check(enemy.ammo.is_reloading, "没有可用掩体时不会空匣无限等待")
	player.is_in_dialogue = true
	ai._physics_process(0.1)
	check(not enemy.ammo.is_reloading and ai.reload_plan == &"", "对话取消换弹与战术计划")
	finish()

func best_plan(costs: Dictionary) -> StringName:
	var best: StringName = &"here"
	for plan in costs:
		if costs[plan] < costs[best]:
			best = plan
	return best

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("RELOAD DECISION: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)