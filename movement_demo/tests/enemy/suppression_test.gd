extends SceneTree

var scene: Node
var enemy
var ai
var player
var action
var checks := {}
var blocker: StaticBody3D
const ENEMY_POSITION := Vector3(24, 0, -2)
const VISIBLE_POSITION := Vector3(22, 0, -2)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	action = ai.tactics.area_suppression
	_check("Tactics具有独立火力压制动作", action != null)
	if action == null:
		_finish()
		return
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	player.get_node("Health").debug_invincible = true
	enemy.weapon = enemy.weapon.duplicate()
	enemy.weapon.min_spread_angle_degrees = 0.0
	enemy.weapon.max_spread_angle_degrees = 0.0
	blocker = StaticBody3D.new()
	blocker.name = "SuppressionTestWall"
	blocker.collision_layer = 0
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2, 2, 3)
	collision.shape = box
	blocker.add_child(collision)
	scene.add_child(blocker)
	blocker.global_position = Vector3(23, 1, -2)
	await _prepare_visible()
	_check("测试初始真实看见玩家", ai.was_seeing_player and not action.is_active())
	var memory: Vector3 = ai.last_seen_position
	ai.tactics.fire_reaction_seconds = 0.5
	ai.tactics.fire_reaction_elapsed = 0.5
	await _hide()
	_check("新增墙体确实遮挡玩家", not ai.perception.can_see_player())
	_check("真实失视启动压制", action.is_active())
	_check("持续时间处于3到5秒", action.remaining >= 3.0 - 1.0 / 60.0 and action.remaining <= 5.0)
	_check("压制中心为最后目击胸部位置", action.target_center.is_equal_approx(memory + Vector3.UP * 0.8))
	_check("失视不立即切入追踪搜索", ai.state == ai.State.HOLD_POSITION)
	var stopped_at: Vector3 = enemy.global_position
	var shots: int = enemy.shot_count
	var center: Vector3 = action.target_center
	var first_remaining: float = action.remaining
	var radius_valid := true
	var no_target_drift := true
	player.global_position = Vector3(22, 0, -2.5)
	for frame in range(90):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		radius_valid = radius_valid and action.aim_point.distance_to(center) <= action.target_radius + 0.001
		no_target_drift = no_target_drift and action.target_center == center and ai.last_seen_position == memory
	_check("压制保持原地", enemy.global_position.distance_to(stopped_at) < 0.02)
	_check("压制期间真实开火", enemy.shot_count > shots)
	_check("压制弹道由墙体实际阻挡", enemy.last_shot_collider == blocker)
	_check("瞄准点保持在设定区域", radius_valid)
	_check("隐藏玩家移动不改变压制中心或目击记忆", no_target_drift)
	_check("持续失视不刷新压制计时", action.remaining < first_remaining - 1.4)
	# 共享连射停顿：即使压制也不能清掉已存在的暂停。
	ai.tactics.fire_pause_remaining = 0.4
	shots = enemy.shot_count
	ai.tactics.update_shooting(0.1, false, false)
	_check("压制保留原连射停顿", enemy.shot_count == shots and ai.tactics.fire_pause_remaining > 0.0)
	# 射程边缘的区域仍须选到可射击点，不能锁住一个射程外点直到计时结束。
	var original_range: float = enemy.weapon.fire_range
	enemy.weapon.fire_range = enemy.get_shot_origin().distance_to(action.target_center)
	var within_range := true
	for sample_index in range(64):
		action.on_shot_fired()
		within_range = within_range and enemy.get_shot_origin().distance_to(action.aim_point) <= enemy.weapon.fire_range + 0.0001
	_check("射程边缘的压制瞄准点仍在射程内", within_range)
	enemy.weapon.fire_range = original_range
	# 真正重新见到玩家后停止压制，恢复原射击及选位流程。
	ai.tactics.fire_reaction_seconds = 0.5
	ai.tactics.fire_pause_remaining = 0.0
	enemy.shot_cooldown = 0.0
	shots = enemy.shot_count
	blocker.collision_layer = 0
	player.global_position = VISIBLE_POSITION
	for frame in range(3):
		await physics_frame
	ai._physics_process(1.0 / 60.0)
	_check("重新目击结束压制", ai.was_seeing_player and not action.is_active())
	_check("重新目击回到普通交战", ai.state in [ai.State.REPOSITION, ai.State.HOLD_POSITION])
	_check("压制后重新目击仍遵守反应时间", enemy.shot_count == shots and ai.tactics.fire_reaction_elapsed < 0.5)
	await _hide()
	_check("下一次真实失视可以再次压制", action.is_active())
	action.remaining = 0.01
	ai._physics_process(0.02)
	_check("到时退出并交给追踪搜索", not action.is_active() and ai.state in [ai.State.TRACK, ai.State.SEARCH, ai.State.INVESTIGATE])
	ai._physics_process(0.02)
	_check("结束后持续失视不会重启", not action.is_active())
	await _prepare_visible()
	await _hide()
	enemy.receive_hit(0.0, VISIBLE_POSITION)
	_check("零伤害不打断压制", action.is_active())
	# 概率0也应尝试掩体，不能意外走回中弹攻击占位。
	ai.cover.take_cover_chance = 0.0
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", true)
	ai.tactics.attack_position_chance = 1.0
	enemy.receive_hit(1.0, VISIBLE_POSITION)
	_check("中弹立即结束压制", not action.is_active())
	_check("压制中弹绕过来弹概率进入掩体转移", ai.cover.phase == ai.cover.Phase.RUN_TO_COVER)
	_check("同一次中弹不启动墙角攻击选位", not ai.tactics.attack_position.is_active())
	var cover_goal: Vector3 = enemy.agent.target_position
	ai.cover.notice_shot(VISIBLE_POSITION + Vector3.UP * 0.8, enemy.get_shot_origin())
	_check("同枪来弹不重复选掩体", enemy.agent.target_position == cover_goal and ai.cover.phase == ai.cover.Phase.RUN_TO_COVER)
	# 暂时从候选组移除地图掩体，模拟没有可用掩体；不写回场景。
	await _prepare_visible()
	await _hide()
	var regions := get_nodes_in_group("cover_region")
	for region in regions:
		region.remove_from_group("cover_region")
	enemy.receive_hit(1.0, VISIBLE_POSITION)
	_check("无掩体时仍停止压制并回普通交战", not action.is_active() and not ai.cover.is_active() and ai.state == ai.State.REPOSITION)
	for region in regions:
		region.add_to_group("cover_region")
	await _prepare_visible()
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", false)
	await _hide()
	_check("能力关闭时不压制", not action.is_active())
	await _prepare_visible()
	ai.combat_type = ai.CombatType.MELEE
	await _hide()
	_check("近战不进行火力压制", not action.is_active())
	await _prepare_visible()
	var weapon = enemy.weapon
	enemy.weapon = null
	await _hide()
	_check("无武器不进行压制", not action.is_active())
	enemy.weapon = weapon
	await _prepare_visible()
	ai.has_visual_memory = false
	action.on_target_lost()
	_check("没有目击记忆不凭空压制", not action.is_active())
	await _prepare_visible()
	ai.cover.phase = ai.cover.Phase.RUN_TO_COVER
	action.on_target_lost()
	_check("正在跑掩体时不被压制抢占", not action.is_active() and ai.cover.is_active())
	await _prepare_visible()
	ai.tactics.attack_position.phase = ai.tactics.attack_position.Phase.MOVE
	await _hide()
	_check("压制开始清理原攻击占位", action.is_active() and not ai.tactics.attack_position.is_active())
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", false)
	ai._physics_process(0.02)
	_check("运行中关闭能力退出压制", not action.is_active())
	await _prepare_visible()
	await _hide()
	ai.cover.take_cover_chance = 1.0
	# 从敌人同侧射来，避免临时墙体挡掉近身来弹检查。
	ai.cover.notice_shot(Vector3(26, 0.8, -2), enemy.get_shot_origin())
	_check("成功来弹躲藏仍能抢占压制", ai.cover.is_active() and not action.is_active())
	await _prepare_visible()
	await _hide()
	player.is_in_dialogue = true
	shots = enemy.shot_count
	ai.tactics.update_shooting(1.0, false, false)
	_check("对话期间压制不射击", enemy.shot_count == shots)
	player.is_in_dialogue = false
	player.global_position = Vector3(-20, 0, 30)
	for frame in range(4):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	_check("离场清理压制", not action.is_active())
	await _prepare_visible()
	await _hide()
	enemy.receive_hit(enemy.health, VISIBLE_POSITION)
	_check("死亡立即停止压制", enemy.is_dead and not action.is_active())
	enemy.reset_target()
	_check("刷新清空压制状态和目击边沿", not action.is_active() and not ai.was_seeing_player)
	_finish()


func _prepare_visible() -> void:
	ai.reset_actions()
	ai.search.reset()
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"suppression", true)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", false)
	ai.tactics.fire_reaction_seconds = 0.0
	ai.tactics.burst_shot_count = 3
	ai.tactics.burst_pause_seconds = 0.2
	ai.attack_position_uncertainty = 0.0
	ai.combat_type = ai.CombatType.RANGED
	ai.has_visual_memory = false
	ai.was_seeing_player = false
	ai.last_seen_direction = Vector3.ZERO
	ai.search.debug_tracking_cheat = false
	ai.search.lost_target_hint_chance = 0.0
	ai.search.search_hint_chance = 0.0
	ai.state = ai.State.IDLE
	blocker.collision_layer = 0
	enemy.global_position = ENEMY_POSITION
	enemy.velocity = Vector3.ZERO
	enemy.shooting_enabled = true
	enemy.clear_aim()
	enemy.shot_cooldown = 0.0
	player.global_position = VISIBLE_POSITION
	enemy.look_at(VISIBLE_POSITION)
	for frame in range(4):
		await physics_frame
	ai._physics_process(1.0 / 60.0)


func _hide() -> void:
	blocker.collision_layer = 1
	for frame in range(3):
		await physics_frame
	ai._physics_process(1.0 / 60.0)


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	print("火力压制：", checks.size(), " 项")
	scene.free()
	quit(0 if checks.values().all(func(value): return value) else 1)
