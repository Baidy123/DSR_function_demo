extends SceneTree

var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	ai.set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var health = player.get_node("Health")
	var cover = enemy.get_node("Cover")
	_check("父节点提供瞄准更新和射击执行", enemy.has_method("update_weapon") and enemy.has_method("try_fire"))
	if not checks.values().all(func(value): return value):
		_finish()
		return
	_check("完成停稳验证后默认允许跑打", ai.fire_while_moving)
	health.debug_invincible = true
	ai.debug_tracking_cheat = false
	cover.debug_cover_selection = false
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	for frame in range(5):
		await physics_frame
	var target: Vector3 = player.global_position + Vector3.UP * 0.8
	_check("射击场景有真实视线", ai.can_see_player())
	enemy.standing_spread_degrees = 0.0
	enemy.moving_spread_degrees = 0.0
	enemy.aim_turn_speed_degrees = 90.0
	# 瞄准从身体朝向开始；90度偏转不能一步瞬间完成。
	enemy.rotation.y += PI / 2.0
	var initial: Vector3 = -enemy.global_basis.z
	enemy.update_weapon(0.1, target)
	_check("跟枪每帧最多旋转角速度乘时间", is_equal_approx(rad_to_deg(initial.angle_to(enemy.aim_direction)), 9.0))
	_check("未追上目标不发首枪", not enemy.try_fire())
	for frame in range(20):
		enemy.update_weapon(0.1, target)
	enemy.look_at(player.global_position)
	_check("追上目标后具备开火条件", enemy.aim_acquired)
	health.debug_invincible = false
	var hp: float = health.health
	_check("射击执行返回成功", enemy.try_fire())
	_check("真实射线命中玩家扣血", enemy.last_shot_collider == player and health.health == hp - enemy.shot_damage)
	var count: int = enemy.shot_count
	_check("冷却阻止重复开火", not enemy.try_fire() and enemy.shot_count == count)
	enemy.update_weapon(0.0)
	enemy.update_weapon(0.0, target)
	_check("丢失重瞄不能绕过射击冷却", not enemy.try_fire() and enemy.shot_count == count)
	enemy.update_weapon(enemy.shot_interval, target)
	health.debug_invincible = true
	hp = health.health
	enemy.try_fire()
	_check("无敌仍命中但不扣血", enemy.last_shot_collider == player and health.health == hp)
	enemy.shot_cooldown = 0.0
	count = enemy.shot_count
	enemy.rotation.y += deg_to_rad(31.0)
	_check("枪口偏离身体超过30度不射击", not enemy.try_fire() and enemy.shot_count == count)
	enemy.look_at(player.global_position)
	# 持续跟枪不因目标突然换向而重置；本枪沿滞后方向，不强制抽中玩家。
	enemy.shot_cooldown = 0.0
	initial = enemy.aim_direction
	var shifted: Vector3 = enemy.get_shot_origin() + initial.rotated(Vector3.UP, deg_to_rad(20.0)) * 5.0
	enemy.update_weapon(0.01, shifted)
	_check("目标换向不会瞬间重瞄", rad_to_deg(initial.angle_to(enemy.aim_direction)) <= 0.91 and enemy.aim_acquired)
	enemy.try_fire()
	_check("零散布弹道沿实际滞后瞄准方向", enemy.last_shot_direction.is_equal_approx(enemy.aim_direction) and enemy.last_shot_direction.angle_to((shifted - enemy.get_shot_origin()).normalized()) > deg_to_rad(18.0))
	# 三维散布有上下和左右偏移，并且受半角限制。
	enemy.standing_spread_degrees = 4.0
	enemy.moving_spread_degrees = 8.0
	var bounded := true
	var vertical := false
	var horizontal := false
	var wider := false
	enemy._shot_rng.seed = 20260920
	for sample in range(160):
		enemy.update_weapon(0.1, target)
		enemy.shot_cooldown = 0.0
		enemy.try_fire(sample % 2 == 1)
		var angle: float = rad_to_deg(enemy.aim_direction.angle_to(enemy.last_shot_direction))
		bounded = bounded and angle <= (8.001 if sample % 2 == 1 else 4.001)
		vertical = vertical or absf(enemy.last_shot_direction.y) > 0.02
		horizontal = horizontal or absf(enemy.last_shot_direction.x) > 0.02
		wider = wider or (sample % 2 == 1 and angle > 4.0)
	_check("站立与移动散布都在各自锥内", bounded)
	_check("散布包含上下和左右偏移", vertical and horizontal)
	_check("移动散布可比站立更大", wider)
	# 实体墙挡住同一枪；不是根据目标名单直接扣血。
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 0.3)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = (enemy.global_position + player.global_position) * 0.5 + Vector3.UP
	for frame in range(3):
		await physics_frame
	enemy.standing_spread_degrees = 0.0
	enemy.shot_cooldown = 0.0
	enemy.update_weapon(1.0, target)
	hp = health.health
	enemy.try_fire()
	_check("墙是首个碰撞物且玩家不扣血", enemy.last_shot_collider == wall and health.health == hp)
	count = enemy.shot_count
	ai._update_shooting(1.0, ai.can_see_player(), false)
	_check("AI隔墙不请求开火", enemy.shot_count == count and not enemy.aim_acquired)
	wall.free()
	for frame in range(3):
		await physics_frame
	# AI 授权只影响请求，执行层无需知道具体策略。
	ai.combat_type = ai.CombatType.RANGED
	ai.state = ai.State.HOLD_POSITION
	enemy.look_at(player.global_position)
	enemy.shot_cooldown = 0.0
	ai.fire_while_moving = false
	count = enemy.shot_count
	ai._update_shooting(1.0, true, true)
	_check("停稳模式拒绝移动射击", enemy.shot_count == count)
	ai._update_shooting(1.0, true, false)
	_check("停稳模式站定后射击", enemy.shot_count == count + 1)
	count = enemy.shot_count
	ai.fire_while_moving = true
	ai._update_shooting(1.0, true, true)
	_check("打开跑打后移动也可射击", enemy.shot_count == count + 1)
	count = enemy.shot_count
	cover.phase = cover.Phase.RUN_TO_COVER
	ai._update_shooting(1.0, true, false)
	_check("跑向掩体时禁止射击", enemy.shot_count == count)
	cover.phase = cover.Phase.HIDE
	ai._update_shooting(1.0, true, false)
	_check("躲藏时禁止射击", enemy.shot_count == count)
	cover.phase = cover.Phase.PEEK_OUT
	ai._update_shooting(1.0, true, false)
	_check("有效探头动作期间不射击", enemy.shot_count == count)
	cover.reset()
	ai._update_shooting(1.0, false, false)
	_check("丢失视野清掉瞄准且不射击", enemy.shot_count == count and not enemy.has_aim)
	ai.combat_type = ai.CombatType.MELEE
	ai._update_shooting(1.0, true, false)
	_check("近战类型不会开枪", enemy.shot_count == count)
	ai.combat_type = ai.CombatType.RANGED
	ai.state = ai.State.SEARCH
	ai._update_shooting(1.0, true, false)
	_check("搜索记忆不授权射击", enemy.shot_count == count)
	ai.state = ai.State.HOLD_POSITION
	player.is_in_dialogue = true
	ai._update_shooting(1.0, true, false)
	_check("对话期间不射击", enemy.shot_count == count)
	player.is_in_dialogue = false
	enemy.shot_range = 1.0
	ai._update_shooting(1.0, true, false)
	_check("射程之外不射击", enemy.shot_count == count)
	enemy.shot_range = 12.0
	enemy.shooting_enabled = false
	ai._update_shooting(1.0, true, false)
	_check("检查器关闭射击有效", enemy.shot_count == count)
	enemy.shooting_enabled = true
	enemy.receive_hit(enemy.max_health)
	enemy.update_weapon(1.0, target)
	_check("死亡无法执行开火", not enemy.try_fire())
	enemy.reset_target()
	_check("复位清除冷却瞄准与射击计数", enemy.shot_count == 0 and enemy.shot_cooldown == 0.0 and not enemy.has_aim)
	player.global_position = Vector3.ZERO
	for frame in range(5):
		await physics_frame
	count = enemy.shot_count
	ai._update_shooting(1.0, true, false)
	_check("场外不射击", enemy.shot_count == count)
	await _check_live_encounter()
	_finish()



## 实际物理帧运行 AI，确认授权不是只在手动调用辅助方法时有效。
func _check_live_encounter() -> void:
	current_scene.free()
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var p = scene.get_node("Player")
	var health = p.get_node("Health")
	p.set_physics_process(false)
	health.debug_invincible = true
	ai.debug_tracking_cheat = false
	enemy.get_node("Cover").debug_cover_selection = false
	enemy.standing_spread_degrees = 0.0
	enemy.moving_spread_degrees = 0.0
	enemy.aim_turn_speed_degrees = 720.0
	enemy.shot_interval = 0.1
	p.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	enemy.look_at(p.global_position)
	var moving_shot := false
	var travelled: float = 0.0
	for frame in range(180):
		var before: Vector3 = enemy.global_position
		var count: int = enemy.shot_count
		await physics_frame
		var movement: float = before.distance_to(enemy.global_position)
		travelled += movement
		moving_shot = moving_shot or (movement > 0.005 and enemy.shot_count > count)
	_check("真实接敌走位中可以开火", travelled > 0.5 and moving_shot)
	# 关闭选项后继续真实AI：走位中停火，到位置后仍可射击。
	ai.fire_while_moving = false
	enemy.reset_target()
	p.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	enemy.look_at(p.global_position)
	var stopped_shot := false
	moving_shot = false
	for frame in range(300):
		var before: Vector3 = enemy.global_position
		var count: int = enemy.shot_count
		await physics_frame
		if enemy.shot_count > count:
			var movement: float = before.distance_to(enemy.global_position)
			moving_shot = moving_shot or movement > 0.005
			stopped_shot = stopped_shot or movement <= 0.005
	_check("真实停稳模式移动不射击", not moving_shot)
	_check("真实停稳模式到位后射击", stopped_shot)
	# 真正由敌人子弹触发玩家死亡，再按现有按钮重开。
	var game_state = root.get_node("GameState")
	game_state.talked_to_a = true
	game_state.help_choice = "accepted"
	health.debug_invincible = false
	enemy.shot_damage = health.max_health
	enemy.shot_cooldown = 0.0
	for frame in range(60):
		await physics_frame
		if health.is_dead:
			break
	_check("敌人弹道触发玩家死亡暂停", health.is_dead and paused)
	var count: int = enemy.shot_count
	ai._update_shooting(1.0, true, false)
	_check("玩家死亡后不再请求开火", enemy.shot_count == count)
	if not health.is_dead:
		return
	health.get_node("DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	for frame in range(10):
		await process_frame
	enemy = current_scene.get_node("Arena/Enemy")
	_check("敌人致死重开后生命武器与AI复位", not paused and not current_scene.get_node("Player").is_dead() and enemy.shot_count == 0 and not enemy.has_aim and not enemy.get_node("AI").is_arena_active())
	_check("敌人致死重开保留对话选择", game_state.talked_to_a and game_state.help_choice == "accepted")

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("ENEMY SHOOTING: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
