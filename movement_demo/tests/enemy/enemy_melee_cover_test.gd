extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	# 固定绕行随机序列，令连续路径与命中时序可复现；仍由原 Utility 自主选择。
	seed(20261007)
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
	player.health.debug_invincible = false
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	enemy.global_position = Vector3(28, 0, 1)
	player.global_position = Vector3(24, 0, -2.5)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	check(ai.perception.can_see_player(), "掩体推进起点真实目击玩家")
	# 用真实受击建立避险需求；不指定赢家、不篡改统一权重或掩体几何。
	enemy.receive_hit(5.0, player.global_position)
	# 重伤时现允许基础躲藏胜出；推进专项用真实目击换弹建立进攻机会。
	# 基础躲藏单独由 enemy_melee_shelter_test 验证，不强选升级动作或改变权重。
	await observe_reload(ai, player)
	var initial_distance: float = enemy.global_position.distance_to(player.global_position)
	var saw_cover := false
	var reached_shelter := false
	var completed := false
	var lost_behind_cover := false
	var reacquired := false
	var searched_before_reacquiring := false
	var reacquiring_body: Object
	var restarted_same_cover := false
	var initial_player_health: float = player.health.health
	var selected_point := Vector3.INF
	var selected_origin := Vector3.ZERO
	var budget_ok := true
	var peak_query_usec := 0
	var peak_cover_execution_usec := 0
	var ran_after_exit := false
	for frame in 600:
		await physics_frame
		var previous_id: StringName = ai.utility_current.get("id", &"")
		ai._physics_process(1.0 / 60.0)
		budget_ok = budget_ok and ai.context.spatial.last_evaluated_count <= ai.context.spatial.EVALUATION_POINTS_PER_FRAME
		peak_query_usec = maxi(peak_query_usec, ai.context.spatial.last_evaluation_usec)
		if previous_id == &"melee_cover" or ai.utility_current.get("id") == &"melee_cover":
			peak_cover_execution_usec = maxi(peak_cover_execution_usec, ai.frame_costs.execution)
		if ai.utility_current.get("id") == &"melee_cover":
			ran_after_exit = ran_after_exit or (ai.current_action.state_label() == "出掩体奔跑接敌" and Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed * 1.1)
			if not saw_cover:
				selected_point = ai.utility_current.destination.hide
				selected_origin = enemy.global_position
			saw_cover = true
			var transfer = ai.current_action.transfer
			if transfer.phase == transfer.Phase.PEEK_OUT:
				reacquiring_body = transfer.active_cover_body
			elif transfer.phase == transfer.Phase.RUN_TO_COVER and transfer.active_cover_body == reacquiring_body:
				restarted_same_cover = true
		if saw_cover and ai.context.cover_selection.is_hidden_at(enemy.global_position, player.global_position + Vector3.UP * 0.8):
			reached_shelter = reached_shelter or enemy.global_position.distance_to(player.global_position) < initial_distance - 0.5
		if reached_shelter and not ai.context.sees_player:
			lost_behind_cover = true
		if lost_behind_cover and ai.context.sees_player:
			reacquired = true
		if lost_behind_cover and not reacquired and ai.utility_current.get("id") == &"search":
			searched_before_reacquiring = true
		if previous_id == &"melee_cover" and ai.utility_current.get("id") != &"melee_cover":
			completed = true
		if player.health.health < initial_player_health: break
	check(saw_cover, "真实受击并目击换弹后原Utility自主选中掩体接近")
	check(selected_point.is_finite() and selected_point.distance_to(player.global_position) < selected_origin.distance_to(player.global_position), "选中掩体落点确实缩短接敌距离")
	check(reached_shelter, "实际走到遮挡后方并拉近与玩家的距离")
	check(completed, "掩体推进完成后释放动作，不永久原地躲藏")
	check(lost_behind_cover and reacquired, "主动进入掩体遮挡后实际绕出并重新目击玩家")
	check(not searched_before_reacquiring, "玩家仍在原处时不因主动躲入掩体而提前开始搜索")
	check(not restarted_same_cover, "绕出阶段不会重启同一掩体的相邻落点形成来回循环")
	if player.health.health >= initial_player_health:
		print("CONTACT DIAGNOSTIC action=", ai.utility_current.get("id"), " position=", enemy.global_position, " visible=", ai.context.sees_player, " melee_count=", enemy.melee_count)
	check(enemy.melee_count > 0 and player.health.health < initial_player_health, "掩体逼近后自主接续原基础挥击并实际伤害玩家")
	check(ran_after_exit, "绕出重新目击后实际奔跑接敌，再交回原挥击")
	check(budget_ok, "近战掩体几何仍通过共享分帧点数预算")
	check(peak_query_usec < 20000, "近战掩体空间评估保留20毫秒验收门槛")
	check(peak_cover_execution_usec < 20000, "掩体到绕出阶段的执行也在20毫秒预算内")
	var action = ai.actions[&"melee_cover"]
	ai.context.utility_unseen_seconds = 6.0
	check(action.collect_candidates(false).is_empty(), "旧目击超时后掩体推进退出并交回搜索")
	# 动态堵住已选落点：导航仍是原地图，执行前的真实身体检查必须拒绝旧点。
	player.combat.cancel_reload()
	player.global_position = Vector3(24, 0, -2.5)
	enemy.reset_target()
	enemy.global_position = Vector3(28, 0, 1)
	enemy.look_at(player.global_position)
	for frame in 4: await physics_frame
	enemy.receive_hit(5.0, player.global_position)
	await observe_reload(ai, player)
	await prepare_geometry(ai)
	var blocked_plan: Dictionary = {}
	for frame in 60:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if ai.utility_current.get("id") == &"melee_cover":
			blocked_plan = ai.utility_current.duplicate(true)
			break
	check(not blocked_plan.is_empty(), "受阻检查由Utility实际选出推进落点")
	if not blocked_plan.is_empty():
		var remembered: Vector3 = ai.context.last_known_position
		player.global_position = Vector3(12, 0, 8)
		await physics_frame
		check(not ai.perception.can_see_player(), "信息隔离用例中的玩家确实不可见")
		ai.context.update_evidence(0.0, false)
		var before: Array = action.collect_candidates(false)
		check(not before.is_empty(), "信息隔离对比包含真实有效的掩体候选")
		player.global_position = Vector3(12, 0, 9)
		player.combat.ammo.infinite_reserve = true
		player.combat.ammo.magazine_rounds = 0
		player.combat.request_reload()
		await physics_frame
		ai.context.update_evidence(0.0, false)
		var after: Array = action.collect_candidates(false)
		check(before == after and ai.context.last_known_position == remembered, "移动隐藏玩家并换弹不改变有效掩体候选")
		player.combat.cancel_reload()
		player.global_position = Vector3(24, 0, -2.5)
		await physics_frame
		ai.context.update_evidence(0.0, ai.perception.can_see_player())
		var blocker := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 2.0, 1.2)
		collision.shape = box
		blocker.add_child(collision)
		root.add_child(blocker)
		blocker.global_position = blocked_plan.destination.hide + Vector3.UP
		await physics_frame
		check(not action.validate(blocked_plan, ai.perception.can_see_player()), "动态封堵后旧掩体落点无法通过执行复核")
		for frame in 36:
			await physics_frame
			ai._physics_process(1.0 / 60.0)
		check(ai.utility_current.get("id") != &"melee_cover" or ai.utility_current.destination.hide.distance_to(blocked_plan.destination.hide) > 0.5, "受阻后实际取消旧路线并重新决策")
		blocker.queue_free()
		await physics_frame
	# 必须覆盖走到掩体之后的第二段，不能只在去掩体途中验证失视。
	var reacquiring: bool = await reach_reacquire(enemy, player)
	check(reacquiring, "续接隔离用例实际进入掩体后的绕出阶段")
	if reacquiring:
		var remembered: Vector3 = ai.context.last_known_position
		var peek: Vector3 = action.transfer.peek_position
		var position: Vector3 = enemy.global_position
		var nav_target: Vector3 = ai.agent.target_position
		var timer: float = action.transfer.timer
		player.global_position = Vector3(12, 0, 8)
		await physics_frame
		check(not ai.perception.can_see_player(), "绕出阶段的信息隔离目标确实不可见")
		ai.context.update_evidence(0.0, false)
		var before: Array = action.collect_candidates(false)
		player.global_position = Vector3(12, 0, 9)
		player.combat.ammo.infinite_reserve = true
		player.combat.ammo.magazine_rounds = 0
		player.combat.request_reload()
		await physics_frame
		ai.context.update_evidence(0.0, false)
		var after: Array = action.collect_candidates(false)
		check(not before.is_empty() and before == after and ai.context.last_known_position == remembered and action.transfer.peek_position == peek, "绕出路线和有效评分不随隐藏玩家位置或换弹变化")
		check(enemy.global_position == position and ai.agent.target_position == nav_target and action.transfer.timer == timer, "绕出候选评估不执行移动、不改导航或重置计时")
		var search_returned := false
		var knowledge_preserved := true
		for frame in 330:
			await physics_frame
			ai._physics_process(1.0 / 60.0)
			knowledge_preserved = knowledge_preserved and ai.context.last_known_position == remembered
			if ai.utility_current.get("id") == &"search":
				search_returned = true
				break
		check(search_returned and knowledge_preserved and enemy.melee_count == 0, "玩家实际离开后有限观察结束交回搜索，不穿墙追踪或攻击")
		player.combat.cancel_reload()
	reacquiring = await reach_reacquire(enemy, player)
	check(reacquiring, "出口受阻用例由真实推进进入绕出阶段")
	if reacquiring:
		ai.context.utility_unseen_seconds = 6.0
		var blocked_exit: Vector3 = action.transfer.peek_position
		var blocker := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.2, 2.0, 1.2)
		collision.shape = box
		blocker.add_child(collision)
		root.add_child(blocker)
		blocker.global_position = blocked_exit + Vector3.UP
		await physics_frame
		var blocked_option: Dictionary = ai.utility_current.duplicate(true)
		check(not action.collect_candidates(false).any(func(candidate): return ai.action_selector.same_option(candidate, blocked_option)), "出口动态封堵后停止提供原绕出方案")
		for frame in 36:
			await physics_frame
			ai._physics_process(1.0 / 60.0)
		check(ai.current_action != action or action.transfer.phase != action.transfer.Phase.PEEK_OUT or action.transfer.peek_position.distance_to(blocked_exit) > 0.5, "出口受阻时实际取消或改走其他路线")
		blocker.queue_free()
		await physics_frame
	reacquiring = await reach_reacquire(enemy, player, true)
	check(reacquiring and ai.context.observed_reload_window() > 0.0, "仅训练掩体时带已观察换弹证据进入绕出阶段")
	if reacquiring:
		var premature_search := false
		for frame in 120:
			if ai.context.sees_player or ai.context.observed_reload_window() <= 0.0: break
			await physics_frame
			ai._physics_process(1.0 / 60.0)
			premature_search = premature_search or ai.utility_current.get("id") == &"search"
		check(not premature_search, "没有可用突进时换弹记忆不会把有效掩体推进交给搜索")
	reacquiring = await reach_reacquire(enemy, player)
	check(reacquiring, "时限用例从真实掩体绕出阶段开始")
	if reacquiring:
		ai.context.utility_unseen_seconds = 6.0
		var continuing: Array = action.collect_candidates(false)
		check(action.valid(false) and not continuing.is_empty() and continuing.all(func(candidate): return ai.action_selector.same_option(candidate, ai.utility_current) and not action.validate(candidate, false)), "旧目击过期只允许继续已开始的绕出，不放行新推进")
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		check(ai.current_action == action and ai.context.utility_unseen_seconds > 6.0, "原选择器保留当前绕出，且不会续写真实目击时间")
		action.transfer.timer = 0.0
		check(not action.valid(false) and action.collect_candidates(false).is_empty(), "目击过期且绕出路段超时后，执行与候选同时失效")
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		check(ai.utility_current.get("id") == &"search", "原路段时限结束后实际由搜索接管")
	reacquiring = await reach_reacquire(enemy, player)
	check(reacquiring, "撤销训练用例在绕出执行期间进行")
	ai.training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(not ai.actions.has(&"melee_cover") and not action.is_enabled() and not action.transfer.is_active(), "撤销训练后不再装配或运行掩体接近，绕出执行同时清理")
	var preset = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	preset.set_setting(&"melee_tactics", &"rush_seconds", 0.7)
	preset.set_setting(&"melee_tactics", &"cover_minimum_progress", 0.9)
	DirAccess.make_dir_recursive_absolute("res://logs")
	check(ResourceSaver.save(preset, "res://logs/melee_tactics_training.tres") == OK, "近战训练参数可保存")
	var restored = load("res://logs/melee_tactics_training.tres")
	check(is_equal_approx(restored.setting(&"melee_tactics", &"rush_seconds"), 0.7) and is_equal_approx(restored.setting(&"melee_tactics", &"cover_minimum_progress"), 0.9), "近战参数重载保留训练显式覆盖")
	print("Melee cover: %d/%d passed; peak query %d us; peak cover execution %d us" % [checks - failures, checks, peak_query_usec, peak_cover_execution_usec])
	quit(0 if failures == 0 else 1)

func reach_reacquire(enemy, player, with_reload: bool = true) -> bool:
	var ai = enemy.get_node("AI")
	player.combat.cancel_reload()
	player.health.debug_invincible = true
	player.global_position = Vector3(24, 0, -2.5)
	enemy.reset_target()
	enemy.global_position = Vector3(28, 0, 1)
	enemy.look_at(player.global_position)
	for frame in 4: await physics_frame
	enemy.receive_hit(5.0, player.global_position)
	if with_reload: await observe_reload(ai, player)
	await prepare_geometry(ai)
	for frame in 180:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		var action = ai.actions.get(&"melee_cover")
		if ai.current_action == action and action != null and action.transfer.phase == action.transfer.Phase.PEEK_OUT and not ai.context.sees_player:
			return true
	return false

func observe_reload(ai, player) -> void:
	var gun := WeaponData.new()
	gun.reload_seconds = 4.0
	player.combat.equip_weapon(gun)
	player.combat.ammo.infinite_reserve = true
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	for frame in 12:
		await physics_frame
		ai.context.update_evidence(1.0 / 60.0, ai.perception.can_see_player())

func prepare_geometry(ai) -> void:
	# 边界用例等待原分帧扫描完成一轮，不指定动作、不放宽预算或执行时限。
	# 首个完整接敌用例仍从冷缓存开始，覆盖实际自主选择和移动。
	var pass_count: int = ai.context.spatial.completed_passes
	for frame in 180:
		await physics_frame
		ai.context.update_evidence(0.0, ai.perception.can_see_player())
		ai.context.spatial.advance_evaluation()
		if ai.context.spatial.completed_passes > pass_count: return

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
