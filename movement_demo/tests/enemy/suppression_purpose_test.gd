extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0
var scene
var arena
var player
var shooter
var observer
var ai
var observer_ai
var wall

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	arena = scene.get_node("Arena")
	shooter = arena.get_node("Enemy")
	shooter.get_node("UnitType").profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	shooter.weapon = WeaponData.new()
	shooter.position = Vector3(5, 0, 0)
	ai = shooter.get_node("AI")
	ai.set_physics_process(false)
	player = scene.get_node("Player")
	player.position = Vector3(20, 0, 0)
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var nav := NavigationMesh.new()
	nav.agent_height = 1.75
	nav.vertices = PackedVector3Array([Vector3(-8, 0.5, -8), Vector3(8, 0.5, -8), Vector3(8, 0.5, 8), Vector3(-8, 0.5, 8)])
	nav.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = nav
	for body in region.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	root.add_child(scene)
	current_scene = scene
	root.get_node("DebugSettings").enabled = false
	player.get_node("Health").debug_invincible = true
	observer = load("res://scenes/enemy/enemy.tscn").instantiate()
	observer.name = "ActualObserver"
	observer.position = Vector3(0, 0, 4)
	observer.weapon = WeaponData.new()
	observer.get_node("AI").set_physics_process(false)
	arena.add_child(observer)
	observer_ai = observer.get_node("AI")
	_configure(shooter)
	_configure(observer)
	wall = load("res://scenes/world/cover.tscn").instantiate()
	region.add_child(wall)
	wall.global_position = Vector3(21.6, 1.25, 0)
	wall.get_node("CollisionShape3D").shape = BoxShape3D.new()
	wall.get_node("CollisionShape3D").shape.size = Vector3(0.4, 2.5, 14.0)
	await _settle(10)
	await _shared_blind_fire()
	observer.queue_free()
	await process_frame
	observer = null
	observer_ai = null
	await _personal_wave()
	await _dynamic_block()
	await _close_pressure()
	await _purpose_binding()
	print("SUPPRESSION PURPOSE: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _configure(actor) -> void:
	Fixture.configure_timing(actor)
	var controller = actor.get_node("AI")
	controller.training.profile.selected_tactics.assign([&"suppression", &"cooperate"])
	controller.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	controller.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	controller.refresh_configuration(true)
	controller.set_physics_process(false) # _ready may enable the controller after the pre-tree fixture setup.
	controller.cover_selection.debug_cover_selection = false
	controller.cover_selection.debug_attack_points = false
	actor.weapon.magazine_capacity = 100
	actor.ammo.magazine_rounds = 100
	actor.debug_shooting = false
	actor.look_at(player.global_position)

func _settle(frames: int) -> void:
	for frame in frames: await physics_frame

func _tick() -> void:
	await physics_frame
	if is_instance_valid(observer_ai): observer_ai._physics_process(STEP)
	ai._physics_process(STEP)

func _shared_blind_fire() -> void:
	var shots: int = shooter.shot_count
	for frame in 50: await _tick()
	var action = ai.actions[&"suppression"]
	check(not ai.context.has_visual_memory and not ai.context.sees_player and ai.context.cooperation_target_evidence().get("shared", false), "遮挡接收者只获得队友真实报告而未伪造个人目击")
	check(ai.context.cooperation_snapshot().requests.is_empty(), "共享情报复现没有换弹或推进掩护需求")
	check(action.collect_candidates(false).is_empty() and shooter.shot_count == shots, "仅收到共享坐标不产生无目的墙后点射或出口扫射")
	var basis: Dictionary = ai.context.cooperation_target_evidence()
	var removed := true
	for mode in [&"exit_left", &"exit_right", &"exit_sweep"]:
		removed = removed and action.preview_candidate(mode, basis).is_empty()
	check(removed, "出口和双端扫射方案全部退出运行候选")
	observer.ammo.magazine_rounds = 1
	check(observer.request_reload(), "观察者通过真实武器接口请求换弹")
	await _tick()
	check(not ai.context.cooperation_snapshot().requests.is_empty(), "换弹状态产生真实同目标掩护需求")
	shots = shooter.shot_count
	check(action.collect_candidates(false).is_empty(), "有真实掩护需求仍不能越过完整硬遮挡生成压制")
	for frame in 30: await _tick()
	check(shooter.shot_count == shots, "掩护需求不会使硬墙后的接收者实际浪费子弹")
	_check_memory_fire_blocked(ai.context.cooperation_target_evidence().get("aim_position", player.global_position + Vector3.UP * 0.8))

func _observe_then_lose() -> Vector3:
	ai.reset_actions()
	ai.context.reset_memory()
	shooter.cancel_reload()
	shooter.ammo.magazine_rounds = 100
	shooter.global_position = Vector3(25, 0, 0)
	shooter.velocity = Vector3.ZERO
	player.global_position = Vector3(23, 0, 0)
	shooter.look_at(player.global_position)
	await _settle(3)
	for frame in 8: await _tick()
	check(ai.context.sees_player, "单人先通过真实感知目击墙前玩家")
	var point: Vector3 = ai.context.last_seen_aim_position
	check(point.is_finite() and ai.context.fire.has_clear_firing_lane(shooter.get_shot_origin(), point - shooter.get_shot_origin(), shooter.get_shot_origin().distance_to(point)), "真实可见帧记录完整枪线可达的身体采样")
	player.global_position = Vector3(20, 0, 0)
	await _settle(3)
	await _tick()
	return point

func _personal_wave() -> void:
	var last_visible: Vector3 = await _observe_then_lose()
	var action = ai.actions[&"suppression"]
	var evidence: Dictionary = ai.context.suppression_basis()
	check(not ai.context.sees_player and evidence.get("source") == &"visual_loss", "个人真实失视产生独立事件而无需队友请求")
	check(evidence.get("aim_position", Vector3.INF).is_equal_approx(last_visible), "个人失视冻结最后真实可射身体点而非墙后脚底")
	var initial: int = shooter.shot_count
	var ran: bool = action.active
	var completed := false
	var checked_active := false
	var limit: int = ai.context.fire.burst_shot_count
	for frame in 240:
		await _tick()
		ran = ran or action.active
		if action.active and not checked_active:
			_check_active_prediction(action)
			checked_active = true
		if ran and not action.active:
			completed = true
			break
	check(ran and completed and shooter.shot_count > initial, "单人由正常 Utility 向可射消失点完成有限实弹波次")
	check(shooter.shot_count - initial <= limit, "个人一波实弹数不超过原剩余连射预算")
	check(checked_active, "实际运行的个人波次经过只读预测与停顿零收益检查")
	player.global_position = Vector3(19, 0, 2)
	await _settle(3)
	check(ai.context.suppression_basis().get("aim_position", Vector3.INF).is_equal_approx(last_visible) and action.collect_candidates(false).is_empty(), "隐藏移动不改写个人射击点且旧失视事件不能重启")

func _dynamic_block() -> void:
	var last_visible: Vector3 = await _observe_then_lose()
	var action = ai.actions[&"suppression"]
	var candidate: Dictionary = action.preview_candidate(&"point")
	check(not candidate.is_empty(), "动态堵塞前个人消失点具有合法有限方案")
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 3.0, 5.0)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	blocker.global_position = Vector3(24, 1.5, 0)
	await _settle(3)
	check(not action.validate(candidate, false), "候选提交前新增远处硬遮挡会重新否决")
	action.step(STEP, false)
	check(not action.active, "执行中射界被完整硬遮挡立即停止波次")
	check(not action.begin(candidate, false), "旧候选不能绕过新遮挡再次开始")
	_check_memory_fire_blocked(last_visible)
	blocker.queue_free()

func _check_memory_fire_blocked(point: Vector3) -> void:
	var before: int = shooter.shot_count
	shooter.cancel_reload()
	shooter.ammo.magazine_rounds = 100
	shooter.shot_cooldown = 0.0
	shooter.has_aim = true
	shooter.aim_acquired = true
	shooter.aim_direction = (point - shooter.get_shot_origin()).normalized()
	ai.context.fire.fire_pause_remaining = 0.0
	ai.context.fire.update(STEP, false, false, {"owner": &"suppression", "mode": &"memory", "point": point})
	check(shooter.shot_count == before, "底层 memory 火控也拒绝射向硬遮挡后的区域")

func _check_active_prediction(action) -> void:
	var fire = ai.context.fire
	var saved: float = fire.fire_pause_remaining
	var execution := [action.remaining, action.aim_point, action._shots_remaining, action._evidence.duplicate(true), action._claim.duplicate(true), action.plan.duplicate(true), fire.fire_burst_shots]
	fire.fire_pause_remaining = ai.context.utility_horizon_seconds + 1.0
	var candidate: Dictionary = action.preview_candidate(&"point")
	check(not candidate.is_empty() and is_equal_approx(candidate.outcome.unavailable_seconds, ai.context.utility_horizon_seconds) and is_zero_approx(ai.context.cooperation_candidate_seconds(candidate)), "正在执行的波次若机械停顿覆盖窗口便不虚构火力或支援收益")
	check(execution == [action.remaining, action.aim_point, action._shots_remaining, action._evidence, action._claim, action.plan, fire.fire_burst_shots], "个人压制预测不会续期证据、重装波次或改写执行瞄准")
	fire.fire_pause_remaining = saved

func _close_pressure() -> void:
	wall.collision_layer = 0
	ai.reset_actions()
	ai.context.reset_memory()
	shooter.global_position = Vector3(25, 0, 0)
	shooter.velocity = Vector3.ZERO
	player.global_position = Vector3(23, 0, 0)
	shooter.look_at(player.global_position)
	shooter.cancel_reload()
	shooter.ammo.magazine_rounds = 100
	await _settle(3)
	var before: int = shooter.shot_count
	var saw_close_candidate := false
	var pressure := 0.0
	for frame in 120:
		await _tick()
		pressure = maxf(pressure, ai.context.fire.close_suppression_pressure())
		var options: Array = ai.actions[&"suppression"].collect_candidates(ai.context.sees_player)
		saw_close_candidate = saw_close_candidate or options.any(func(option): return option.get("suppression_reason") == &"close")
	check(ai.context.cooperation_snapshot().requests.is_empty() and pressure > 0.0, "单人真实近距压力不需要伪造队友请求")
	check(saw_close_candidate, "玩家逼近可让有限可见压制进入正常Utility候选")
	check(shooter.shot_count > before, "近距交战保持原Utility和真实反应瞄准门控下的实弹")

## Commit legal candidates to verify purpose continuity independently of which
## equally valid action wins an autonomous decision in this open fixture.
func _purpose_binding() -> void:
	_configure(shooter)
	ai.context.reset_memory()
	shooter.global_position = Vector3(25, 0, 0)
	shooter.velocity = Vector3.ZERO
	player.global_position = Vector3(23, 0, 0)
	shooter.look_at(player.global_position)
	observer = load("res://scenes/enemy/enemy.tscn").instantiate()
	observer.name = "PurposeObserver"
	observer.position = Vector3(0, 0, 4)
	observer.weapon = WeaponData.new()
	observer.get_node("AI").set_physics_process(false)
	arena.add_child(observer)
	observer_ai = observer.get_node("AI")
	_configure(observer)
	await _settle(4)
	for frame in 5: await _tick()
	observer.ammo.magazine_rounds = 1
	check(observer.request_reload(), "目的绑定契约由友军真实换弹提供并存的支援理由")
	await _tick()
	var action = ai.actions[&"suppression"]
	var close: Array = action.collect_candidates(true).filter(func(option): return option.get("suppression_reason") == &"close")
	check(not close.is_empty(), "目的绑定契约提交的是实际近距目击候选")
	if close.is_empty(): return
	if not action.active: ai._start_utility_option(close[0], true)
	check(action.active and action._reason == &"close", "近距波次通过原提交接口锁定目的")
	player.global_position = Vector3(20, 0, 0)
	await _settle(3)
	observer_ai._physics_process(STEP)
	ai.context.update_evidence(STEP, ai.perception.can_see_player())
	check(not ai.context.cooperation_snapshot().requests.is_empty() and ai.context.fire.close_suppression_pressure() <= 0.0, "近距理由消失时仍存在真实队友需求")
	action.step(STEP, ai.context.sees_player)
	check(not action.active, "近距目的消失立即停止原波次，不能静默改成掩护")
	ai._cancel_utility_execution()
	var support: Array = action.collect_candidates(true).filter(func(option): return option.get("suppression_reason") == &"support")
	check(not support.is_empty(), "新的正常决策可另外提出真实队友掩护波次")
	if support.is_empty(): return
	ai._start_utility_option(support[0], true)
	var original_request: int = action._request_id
	observer.cancel_reload()
	await physics_frame
	observer_ai._physics_process(STEP)
	observer.ammo.magazine_rounds = 1
	check(observer.request_reload(), "第二个掩护周期来自新的真实换弹开始")
	await physics_frame
	observer_ai._physics_process(STEP)
	ai.context.update_evidence(STEP, ai.perception.can_see_player())
	var requests: Array = ai.context.cooperation_snapshot().requests
	check(not requests.is_empty() and requests.all(func(request): return request.get("request_id", request.get("id", 0)) != original_request), "换弹结束再开始生成新请求身份")
	action.step(STEP, ai.context.sees_player)
	check(not action.active, "正在执行的掩护锁定原请求，不能借新请求继续旧波次")
	ai._cancel_utility_execution()
	observer.queue_free()
	await process_frame
	observer = null
	observer_ai = null
