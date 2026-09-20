extends SceneTree

# 独立运行 Main，检查真实受伤入口、暂停和场景重载，不替代人工手感试玩。
var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var player = scene.get_node("Player")
	var health = player.get_node_or_null("Health")
	_check("玩家接入生命组件与受伤入口", health != null and player.has_method("receive_hit"))
	if health == null or not player.has_method("receive_hit"):
		_finish()
		return
	var spawn: Transform3D = player.global_transform
	_check("初始满血且存活", health.health == health.max_health and not player.is_dead())
	_check("初始生命显示", health.get_node("Status/Content/HealthLabel").text.contains("100 / 100"))
	player.receive_hit(25.0)
	_check("真实受伤入口扣血", health.health == 75.0)
	player.receive_hit(0.0)
	player.receive_hit(-10.0)
	player.receive_hit(NAN)
	player.receive_hit(INF)
	_check("无效伤害不改变生命", health.health == 75.0)
	health.debug_invincible = true
	player.receive_hit(1000.0)
	_check("无敌阻止致死伤害且不回血", health.health == 75.0 and not player.is_dead())
	_check("无敌状态同步显示", health.get_node("Status/Content/HealthLabel").text.contains("无敌"))
	_check("无敌勾选同步", health.get_node("Debug/Controls/Invincible").button_pressed)
	health.get_node("Debug/Controls/Invincible").set_pressed(false)
	_check("界面可以关闭无敌", not health.debug_invincible)
	health.get_node("Debug/Controls/Damage").pressed.emit()
	_check("测试受伤按钮走伤害入口", health.health == 50.0)
	# 通过真实玩家移动与靶子伤害留下需要重置的战斗状态。
	player.global_position = Vector3(20.0, 0.0, 0.0)
	for frame in range(5):
		await physics_frame
	_check("死亡前实际进入战斗区", player.get_node("Combat").can_combat() and scene.get_node("Arena").players_inside.has(player))
	player.stamina = 10.0
	var enemy = scene.get_node("Arena/Enemy")
	enemy.receive_hit(10000.0, player.global_position)
	var target_a = scene.get_node("CombatTest/TargetA")
	var target_b = scene.get_node("CombatTest/TargetB")
	target_a.receive_hit(25.0)
	target_b.receive_hit(10000.0)
	var game_state = root.get_node("GameState")
	game_state.talked_to_a = true
	game_state.help_choice = "accepted"
	var combat = player.get_node("Combat")
	combat.is_aiming = true
	combat.shot_requested = true
	player.velocity = Vector3(2.0, 0.0, 0.0)
	player.current_speed = 2.0
	player.receive_hit(1000.0)
	_check("超量伤害归零并死亡", health.health == 0.0 and player.is_dead())
	_check("死亡暂停世界", paused and not enemy.can_process())
	_check("死亡清掉移动和射击", player.velocity.is_zero_approx() and player.current_speed == 0.0 and not combat.is_aiming and not combat.shot_requested)
	_check("死亡界面与按钮可处理", health.get_node("DeathScreen").visible and health.get_node("DeathScreen/Center/Panel/Content/Restart").can_process())
	var before: int = combat.shot_count
	combat.is_aiming = true
	combat.shoot()
	_check("死亡不能射击", combat.shot_count == before)
	var dead_position: Vector3 = player.global_position
	Input.action_press("move_right")
	player._physics_process(0.2)
	Input.action_release("move_right")
	_check("死亡不能移动", player.global_position.is_equal_approx(dead_position))
	player.receive_hit(25.0)
	health.debug_invincible = true
	_check("死亡后重复伤害或开启无敌不复活", player.is_dead() and health.health == 0.0)
	# 点击真实重开按钮；连点不能触发两次场景切换。
	scene.tree_exited.connect(func(): _check("卸载不刷新已出树敌人", enemy.is_dead))
	var old_id: int = scene.get_instance_id()
	var button = health.get_node("DeathScreen/Center/Panel/Content/Restart")
	button.pressed.emit()
	button.pressed.emit()
	for frame in range(10):
		await process_frame
	scene = current_scene
	_check("重开生成新场景且解除暂停", scene != null and scene.get_instance_id() != old_id and not paused)
	player = scene.get_node("Player")
	health = player.get_node("Health")
	_check("重开恢复生命与耐力", health.health == health.max_health and not player.is_dead() and player.stamina == player.MAX_STAMINA)
	_check("重开回出生点与朝向", player.global_transform.is_equal_approx(spawn))
	_check("重开隐藏死亡界面", not health.get_node("DeathScreen").visible)
	_check("重开保留对话选择", game_state.talked_to_a and game_state.help_choice == "accepted")
	enemy = scene.get_node("Arena/Enemy")
	_check("重开恢复敌人且场外不激活", not enemy.is_dead and enemy.health == enemy.max_health and not enemy.is_arena_active())
	target_a = scene.get_node("CombatTest/TargetA")
	target_b = scene.get_node("CombatTest/TargetB")
	_check("重开恢复靶子计数与生命", target_a.hit_count == 0 and target_b.health == target_b.max_health and not target_b.is_dead)
	# 第二次死亡重开验证暂停不会残留，同时保留另一种对话结果。
	game_state.help_choice = "refused"
	health.debug_invincible = false
	player.receive_hit(health.max_health)
	health.get_node("DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	for frame in range(10):
		await process_frame
	_check("再次死亡重开保留拒绝选择", not paused and not current_scene.get_node("Player").is_dead() and game_state.help_choice == "refused")
	_finish()


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("PLAYER HEALTH: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
