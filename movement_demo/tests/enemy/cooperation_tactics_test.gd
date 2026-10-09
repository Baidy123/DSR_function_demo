extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks := 0
var failures := 0
var scene
var arena
var player
var first
var second
var first_ai
var second_ai

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	arena = scene.get_node("Arena")
	first = arena.get_node("Enemy")
	first_ai = first.get_node("AI")
	first_ai.set_physics_process(false)
	first.position = Vector3(5, 0, -0.9)
	first.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	first.weapon = WeaponData.new()
	player = scene.get_node("Player")
	player.position = Vector3(20, 0, 0)
	player.set_physics_process(false)
	var navigation: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	mesh.vertices = PackedVector3Array([Vector3(-8, 0.5, -8), Vector3(8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	for body in navigation.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	second = load("res://scenes/enemy/enemy.tscn").instantiate()
	second.name = "CooperationPartner"
	second.position = Vector3(5, 0, 0.9)
	second.weapon = WeaponData.new()
	second.get_node("AI").set_physics_process(false)
	arena.add_child(second)
	second_ai = second.get_node("AI")
	for actor in [first, second]: _configure(actor)
	await _settle(12)
	check(first_ai.is_arena_active() and second_ai.is_arena_active(), "真实区域和导航激活两名合法实例")
	check(first_ai.actions.has(&"cooperate") and first_ai.actions.has(&"suppression") and not first_ai.actions.has(&"exit_suppression"), "协作独立装配，压制只有一个实际动作")
	var initial_first: Vector3 = first.global_position
	var initial_second: Vector3 = second.global_position
	var saw_advance := false
	var saw_ready_support := false
	var real_supported_move := false
	var checked_walk_contract := false
	var initial_shots: int = first.shot_count + second.shot_count
	for frame in 420:
		await _tick()
		for ai in [first_ai, second_ai]:
			var snapshot: Dictionary = ai.context.cooperation_snapshot()
			saw_ready_support = saw_ready_support or not snapshot.supports.is_empty()
			if ai.utility_current.get("id", &"") == &"cooperate":
				saw_advance = true
				var action = ai.actions[&"cooperate"]
				if not checked_walk_contract:
					_check_walk_contract(ai, action)
					checked_walk_contract = true
				if action.phase == action.Phase.MOVE and action._support_ready(): real_supported_move = true
	check(first.shot_count + second.shot_count > initial_shots and saw_ready_support, "正常感知与火控建立真实开火支援")
	check(saw_advance and real_supported_move, "原 Utility 自主选择协作推进并在实际支援下执行")
	check(first.global_position.distance_to(initial_first) > 0.5 or second.global_position.distance_to(initial_second) > 0.5, "协作方案产生真实碰撞移动")
	check(checked_walk_contract, "自主协作执行经过严格步行路线边界检查")
	var before_claims: int = first_ai.context.cooperation_snapshot().claims.size()
	for count in 8: first_ai.action_selector.assess_options(first_ai, first_ai.context.sees_player)
	check(first_ai.context.cooperation_snapshot().claims.size() == before_claims, "候选反复收集不认领新任务")
	await _visible_support()
	await _exit_assignment()
	await _expired_evidence()
	await _mixed_roles()
	await _empty_magazine()
	print("COOPERATION TACTICS: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _check_walk_contract(ai, action) -> void:
	var candidate: Dictionary = ai.utility_current.duplicate(true)
	var original: Dictionary = candidate.duplicate(true)
	var candidates: Array[Dictionary] = [candidate]
	var expanded: Array[Dictionary] = action.expand_route_candidates(candidates)
	check(expanded.size() == 1 and expanded[0] == original and expanded[0].get("route", {}).is_empty(), "协作步行展开保留原路线预测且不附加翻越变体")
	var vault := candidate.duplicate(true)
	vault.route = {"vault": {"valid": true}, "before": candidate.destination.path, "after": candidate.destination.path, "destination": candidate.destination.position}
	var vault_candidates: Array[Dictionary] = [vault]
	check(action.expand_route_candidates(vault_candidates).is_empty() and not action.validate(vault, ai.context.sees_player), "复制步行协作信用的翻越候选不能进入评分或提交")

func _configure(actor) -> void:
	Fixture.configure_timing(actor)
	var ai = actor.get_node("AI")
	ai.training.profile.selected_tactics.assign([&"suppression", &"cooperate"])
	ai.training.profile.set_setting(&"search", &"lost_target_hint_chance", 0.0)
	ai.training.profile.set_setting(&"search", &"search_hint_chance", 0.0)
	ai.refresh_configuration(true)
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	actor.look_at(player.global_position)

func _tick() -> void:
	await physics_frame
	first_ai._physics_process(1.0 / 60.0)
	second_ai._physics_process(1.0 / 60.0)

func _settle(frames: int) -> void:
	for frame in frames: await physics_frame

func _reset_open() -> void:
	for ai in [first_ai, second_ai]:
		ai.reset_actions()
		ai.context.reset_memory()
		ai.actor.cancel_reload()
		ai.actor.ammo.magazine_rounds = ai.actor.weapon.magazine_capacity
		ai.actor.velocity = Vector3.ZERO
	first.global_position = Vector3(25, 0, -1.2)
	second.global_position = Vector3(25, 0, 1.2)
	player.global_position = Vector3(20, 0, 0)
	first.look_at(player.global_position)
	second.look_at(player.global_position)

func _visible_support() -> void:
	_reset_open()
	await _settle(4)
	for frame in 40: await _tick()
	second.ammo.magazine_rounds = 1
	check(second.request_reload(), "友军通过原武器接口实际开始换弹")
	var saw_visible_candidate := false
	var saw_visible_selected := false
	var checked_prediction := false
	var starting_shots: int = first.shot_count
	for frame in 120:
		await _tick()
		var candidates: Array = first_ai.action_selector.assess_options(first_ai, first_ai.context.sees_player)
		saw_visible_candidate = saw_visible_candidate or candidates.any(func(candidate): return candidate.id == &"suppression" and candidate.get("plan", &"") == &"visible")
		if not checked_prediction and candidates.any(func(candidate): return candidate.id == &"suppression" and candidate.get("plan", &"") == &"visible"):
			_check_prediction_windows(first_ai.actions[&"suppression"], &"visible")
			checked_prediction = true
		saw_visible_selected = saw_visible_selected or (first_ai.utility_current.get("id", &"") == &"suppression" and first_ai.utility_current.get("plan", &"") == &"visible")
	check(saw_visible_candidate, "目标可见且友军换弹时压制候选进入共同评分")
	check(first.shot_count > starting_shots, "换弹掩护仍通过真实反应、转枪与武器开火")
	# Ordinary fire may already satisfy the request; both legal alternatives are useful.
	check(saw_visible_selected or first_ai.context.cooperation_snapshot().supports.any(func(support): return support.owner_id == first.get_instance_id()), "可见压制或现有正常交战实际履行掩护")
	check(checked_prediction, "真实换弹需求期间完成可见压制预测边界检查")

func _check_prediction_windows(action, mode: StringName) -> void:
	var actor = action.actor
	var context = action.context
	var fire = context.fire
	var saved_pause: float = fire.fire_pause_remaining
	var saved_cooldown: float = actor.shot_cooldown
	var saved_stability: float = actor.weapon_stability
	var saved_wait: float = fire.fire_decision.wait_seconds
	var saved_recovery: float = fire.fire_decision.last_recovery_rate
	var saved_reaction: float = fire.fire_reaction_elapsed
	var saved_aim: Vector3 = actor.aim_direction
	var execution := [action.remaining, action.aim_point, action._shots_remaining, fire.fire_burst_shots, action._evidence.duplicate(true), action._claim.duplicate(true), action.plan.duplicate(true)]
	var horizon: float = context.utility_horizon_seconds
	fire.fire_pause_remaining = horizon + 1.0
	var paused: Dictionary = action.preview_candidate(mode)
	check(not paused.is_empty() and paused.get("cooperation", {}).get("support_seconds", -1.0) == 0.0 and context.cooperation_candidate_seconds(paused) == 0.0, "%s 当前连射停顿覆盖计划窗口时不得领取支援收益" % mode)
	fire.fire_pause_remaining = 0.0
	actor.shot_cooldown = horizon + 1.0
	var cooling: Dictionary = action.preview_candidate(mode)
	check(not cooling.is_empty() and cooling.get("cooperation", {}).get("support_seconds", -1.0) == 0.0 and context.cooperation_candidate_seconds(cooling) == 0.0, "%s 实际枪械冷却覆盖计划窗口时不得领取支援收益" % mode)
	actor.shot_cooldown = 0.0
	if mode == &"visible":
		actor.weapon_stability = 0.0
		fire.fire_decision.wait_seconds = 0.0
		fire.fire_decision.last_recovery_rate = fire.fire_stability_target
		fire.fire_reaction_elapsed = fire.fire_reaction_seconds
		var steady: float = fire.estimated_steady_wait(true)
		var waiting: Dictionary = action.preview_candidate(mode, {}, maxf(0.001, steady * 0.5))
		check(steady > 0.0 and waiting.get("cooperation", {}).get("estimated_start_seconds", 0.0) >= steady and waiting.get("cooperation", {}).get("support_seconds", -1.0) == 0.0 and context.cooperation_candidate_seconds(waiting) == 0.0, "稳枪尚未结束的短计划不得领取可见掩护收益")
		actor.weapon_stability = saved_stability
		fire.fire_decision.wait_seconds = saved_wait
		fire.fire_decision.last_recovery_rate = saved_recovery
		fire.fire_reaction_elapsed = 0.0
		var reacting: Dictionary = action.preview_candidate(mode, {}, 0.01)
		check(reacting.get("cooperation", {}).get("estimated_start_seconds", 0.0) >= fire.fire_reaction_seconds and reacting.get("cooperation", {}).get("support_seconds", -1.0) == 0.0 and context.cooperation_candidate_seconds(reacting) == 0.0, "反应尚未完成的短计划不得领取可见掩护收益")
		fire.fire_reaction_elapsed = fire.fire_reaction_seconds
		var target: Vector3 = context.perception.visible_aim_position(true)
		actor.aim_direction = -(target - actor.get_shot_origin()).normalized()
		var turning: Dictionary = action.preview_candidate(mode, {}, 0.1)
		check(turning.get("cooperation", {}).get("estimated_start_seconds", 0.0) > 0.1 and turning.get("cooperation", {}).get("support_seconds", -1.0) == 0.0 and context.cooperation_candidate_seconds(turning) == 0.0, "尚未转向目标的短计划不得领取可见掩护收益")
	fire.fire_pause_remaining = saved_pause
	actor.shot_cooldown = saved_cooldown
	actor.weapon_stability = saved_stability
	fire.fire_decision.wait_seconds = saved_wait
	fire.fire_decision.last_recovery_rate = saved_recovery
	fire.fire_reaction_elapsed = saved_reaction
	actor.aim_direction = saved_aim
	check(execution == [action.remaining, action.aim_point, action._shots_remaining, fire.fire_burst_shots, action._evidence, action._claim, action.plan], "%s 刷新预测不更改执行瞄准、证据、租约、时长或连射计数" % mode)

func _exit_assignment() -> void:
	_reset_open()
	player.global_position = Vector3(20.8, 0, 0)
	await _settle(4)
	for ai in [first_ai, second_ai]:
		check(ai.perception.can_see_player(), "出口测试先有真实无遮挡目击")
		ai.context.update_evidence(0.01, true)
	var cover = load("res://scenes/world/cover.tscn").instantiate()
	arena.get_node("NavigationRegion3D").add_child(cover)
	cover.global_position = Vector3(22, 1.1, 0)
	cover.get_node("CollisionShape3D").shape = BoxShape3D.new()
	cover.get_node("CollisionShape3D").shape.size = Vector3(0.8, 2.2, 3.0)
	await _settle(4)
	check(not first_ai.perception.can_see_player() and not second_ai.perception.can_see_player(), "实际高墙令两名观察者失视")
	var dual := false
	var selected_exit := false
	var checked_active_prediction := false
	var shots: int = first.shot_count + second.shot_count
	for frame in 120:
		await _tick()
		var claims: Array = first_ai.context.cooperation_snapshot().claims.filter(func(claim): return claim.get("coverage_kind", &"") == &"exit")
		if claims.size() >= 2:
			dual = dual or (claims[0].owner_id != claims[1].owner_id and claims[0].lane_id != claims[1].lane_id and claims[0].cover_id == claims[1].cover_id)
		selected_exit = selected_exit or (first_ai.utility_current.get("plan", &"") in [&"exit_left", &"exit_right"]) or (second_ai.utility_current.get("plan", &"") in [&"exit_left", &"exit_right"])
		if not checked_active_prediction:
			for ai in [first_ai, second_ai]:
				var committed = ai.actions[&"suppression"]
				if committed.active and not committed._claim.is_empty() and committed._current_mode() in [&"exit_left", &"exit_right"]:
					_check_prediction_windows(committed, committed._current_mode())
					checked_active_prediction = true
					break
	check(selected_exit and dual, "正常 Utility 为同一可靠掩体认领不同出口而不抢同槽")
	check(first.shot_count + second.shot_count > shots, "多人出口方案实际打出子弹")
	var action = first_ai.actions[&"suppression"]
	var old_aim: Vector3 = action.aim_point
	var old_remaining: float = action.remaining
	for count in 5: action.collect_candidates(false)
	check(action.aim_point == old_aim and is_equal_approx(action.remaining, old_remaining), "压制预评估不改变真实瞄准和有限时长")
	check(checked_active_prediction, "真实认领出口的执行阶段完成只读预测验证")
	cover.collision_layer = 0
	for frame in 10: await _tick()
	check(first_ai.context.cooperation_snapshot().claims.filter(func(claim): return claim.get("coverage_kind", &"") == &"exit").is_empty(), "出口归属失效后释放两端岗位")
	cover.queue_free()
	await _settle(3)

func _expired_evidence() -> void:
	first_ai.reset_actions()
	second_ai.reset_actions()
	var context = first_ai.context
	context.reset_memory()
	context.sees_player = false
	context._shared_visual = {"target_id": context.cooperation_target_id(), "position": Vector3(20, 0, 0), "captured_at": context.evidence_elapsed_seconds - 10.0,
		"valid_until": context.evidence_elapsed_seconds - 5.0, "id": 987654, "source": &"shared_visual", "shared": true, "confidence": 0.1}
	var action = first_ai.actions[&"suppression"]
	check(action.collect_candidates(false).is_empty(), "过期共享位置仍可供搜索但不能生成精准压制")
	var cooperative = first_ai.actions[&"cooperate"]
	check(cooperative.collect_candidates(false).is_empty(), "过期报告不能启动新的侧向协作推进")
	context._shared_visual.clear()

func _mixed_roles() -> void:
	_reset_open()
	second_ai.unit_type.profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	second_ai.training.profile.selected_tactics.assign([&"cooperate"])
	second_ai.refresh_configuration(true)
	var weapon := preload("res://resources/weapons/enemy_test_melee.tres").duplicate(true)
	second.equip_weapon(weapon)
	var hits := {"count": 0}
	var on_hit := func(damage: float):
		if is_equal_approx(damage, weapon.melee_damage): hits.count += 1
	player.get_node("Health").hit_received.connect(on_hit)
	await _settle(4)
	var start_distance: float = second.global_position.distance_to(player.global_position)
	var initial_shots: int = first.shot_count
	var moved_under_support := false
	var used_cooperate := false
	var closest := start_distance
	for frame in 480:
		await _tick()
		closest = minf(closest, second.global_position.distance_to(player.global_position))
		if second_ai.utility_current.get("id", &"") == &"cooperate":
			used_cooperate = true
			var action = second_ai.actions[&"cooperate"]
			moved_under_support = moved_under_support or (action.phase == action.Phase.MOVE and action._support_ready())
		if hits.count > 0 and used_cooperate: break
	check(used_cooperate and moved_under_support and closest < start_distance - 0.5, "同一协作动作使近战兵在远程真实支援下接近")
	check(first.shot_count > initial_shots and second.melee_count > 0 and hits.count > 0, "混合兵种最终通过独立枪械和近战执行产生实际命中")
	check(not second.can_use_firearms() and second_ai.context.cooperation_snapshot().supports.all(func(support): return support.owner_id != second.get_instance_id()), "近战威胁不伪装成已就绪枪械火力")
	print("MIXED TACTICS observed_cooperate=%s supported_move=%s closest=%.2f melee_hits=%d" % [used_cooperate, moved_under_support, closest, hits.count])
	player.get_node("Health").hit_received.disconnect(on_hit)

func _empty_magazine() -> void:
	_configure(second)
	_reset_open()
	await _settle(4)
	for frame in 50: await _tick()
	first_ai.reset_actions()
	first.ammo.magazine_rounds = 0
	first.cancel_reload()
	var action = first_ai.actions[&"cooperate"]
	check(action.collect_candidates(true).is_empty(), "空匣且尚未换弹时不虚构到位火力来抢推进")
	var began_reload := false
	for frame in 45:
		await _tick()
		began_reload = began_reload or first.ammo.is_reloading
	check(began_reload, "协作失败回退保留统一换弹的实际执行机会")
