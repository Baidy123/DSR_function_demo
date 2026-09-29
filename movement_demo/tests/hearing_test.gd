extends SceneTree
var checks := 0
var failures := 0
var heard: Array[Vector3] = []
var scene: Node
var player: Node3D
var enemy: Node3D
var ai: Node
var noise: Resource

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	enemy = scene.get_node("Arena/Enemy")
	ai = enemy.get_node("AI")
	player.set_physics_process(false)
	ai.set_physics_process(false)
	check(ai.perception.has_method("receive_noise"), "感知提供逻辑听觉入口")
	check(player.get("movement_noise") is Resource, "玩家提供移动声音资源")
	check(player.get_node("Combat").weapon.get("shot_noise") is Resource, "武器提供枪声资源接口")
	if failures > 0:
		finish()
		return
	noise = player.movement_noise.duplicate()
	noise.occluded_range_multiplier = 0.4
	check(noise.audio_stream == null, "无音频也能使用声音资源")
	ai.perception.noise_heard.connect(func(position: Vector3): heard.append(position))
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	player.get_node("Health").debug_invincible = true
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	await settle()
	check(ai.is_arena_active(), "听觉测试实际入场")
	noise.emit_from(player, 6.0)
	await settle()
	check(heard.size() == 1, "无遮挡范围内听见")
	check(ai.is_alerted and ai.actions[&"search"].noise_search_origin.is_equal_approx(player.global_position), "未目击时记录声源证据，交给统一决策")
	check(not ai.has_visual_memory and enemy.shot_count == 0, "听见不等于目击或盲射")
	ai._physics_process(0.01)
	var origin: Vector3 = ai.last_known_position
	player.global_position += Vector3.RIGHT
	await settle()
	check(ai.last_known_position.is_equal_approx(origin), "安静移动不更新声源记忆")
	var count := heard.size()
	ai.perception.receive_noise(player, enemy.global_position + Vector3(0, 0, 7), 6.0, 0.4)
	check(heard.size() == count, "范围外听不见")
	ai.perception.receive_noise(player, player.global_position, 0.0, 0.4)
	check(heard.size() == count, "零半径禁用声音")
	# 真实碰撞墙用于隔墙近/远对照，随后移除，避免改变已烘焙导航的实走测试。
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = enemy.global_position + Vector3(0, 1, 1.0)
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	await settle()
	noise.emit_from(player, 6.0)
	await settle()
	check(heard.size() == count, "隔墙超出缩小范围时听不见")
	player.global_position = enemy.global_position + Vector3(0, 0, 2.0)
	await settle()
	noise.emit_from(player, 6.0)
	await settle()
	check(heard.size() == count + 1, "隔墙近距离仍听见")
	wall.free()
	await settle()
	# 同一声源重复发声不重新计时；新声音位置可以更新调查目的地。
	ai.actions[&"search"].track_timer = 1.23
	noise.emit_from(player, 6.0)
	await settle()
	check(is_equal_approx(ai.actions[&"search"].track_timer, 1.23), "同位置重复声源不重启调查计时")
	player.global_position += Vector3.RIGHT
	noise.emit_from(player, 6.0)
	await settle()
	check(ai.last_known_position.is_equal_approx(player.global_position), "新发声位置更新记忆")
	ai.has_visual_memory = true
	ai.last_seen_position = enemy.global_position + Vector3.LEFT * 3.0
	ai.actions[&"search"].begin_search()
	check(ai.actions[&"search"].search_origin.is_equal_approx(ai.last_known_position), "新声源搜索不被旧目击圆心覆盖")
	ai.actions[&"search"].debug_tracking_cheat = true
	check(not ai.actions[&"search"]._try_tracking_cheat_hint(1.0), "声音调查不启用隐藏目标提示")
	var training = enemy.get_node("Training")
	training.profile.set_setting(&"perception", &"hearing_enabled", false)
	count = heard.size()
	noise.emit_from(player, 6.0)
	await settle()
	check(heard.size() == count, "关闭听觉不接收声源")
	training.profile.set_setting(&"perception", &"hearing_enabled", true)
	var allowed: Array[StringName] = training.profile.selected_tactics.duplicate()
	training.profile.selected_tactics.clear()
	ai.refresh_configuration(true)
	check(ai.actions.has(&"search"), "清空战术训练不删除兵种默认搜索")
	training.profile.selected_tactics.assign(allowed)
	var unit = enemy.get_node("UnitType")
	var available: Array[EnemyActionDefinition] = unit.profile.default_behaviors.duplicate()
	unit.profile.default_behaviors.clear()
	ai.refresh_configuration(true)
	enemy.reset_target()
	noise.emit_from(player, 6.0)
	await settle()
	check(not ai.actions.has(&"search") and ai.state == ai.State.IDLE, "听见不能赋予兵种没有的搜索动作")
	unit.profile.default_behaviors.assign(available)
	ai.refresh_configuration(true)
	await check_movement_and_shooting()
	await check_priority_and_multiple()
	# 只有声源快照驱动实走，玩家随后移动而不发新声。
	enemy.reset_target()
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	await settle()
	noise.emit_from(player, 6.0)
	await settle()
	origin = ai.last_known_position
	player.global_position += Vector3.RIGHT * 2.0
	var start: Vector3 = enemy.global_position
	for frame in range(90):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
	check(enemy.global_position.distance_to(start) > 0.5, "敌人实际寻路走向声源")
	check(enemy.global_position.distance_to(origin) < start.distance_to(origin), "实走接近发声位置")
	check(ai.last_known_position.is_equal_approx(origin) and enemy.shot_count == 0, "调查中不偷读玩家坐标或开火")
	ai.actions[&"search"].track_timer = 0.0
	ai._physics_process(0.02)
	check(ai.state == ai.State.SEARCH, "调查结束转入声源附近搜索")
	ai.actions[&"search"].search_seconds = 0.05
	ai.actions[&"search"].search_timer = 0.05
	ai._physics_process(0.1)
	check(ai.state == ai.State.IDLE and not ai.is_alerted, "搜索无果恢复待机巡逻")
	player.global_position = Vector3.ZERO
	await settle()
	count = heard.size()
	ai.perception.receive_noise(player, enemy.global_position, 100.0, 1.0)
	check(heard.size() == count and not ai.is_alerted, "竞技场未激活时不因声音唤醒")
	check(not ai.actions[&"search"].noise_search_origin.is_finite(), "离场刷新清理声音调查")
	finish()

func check_movement_and_shooting() -> void:
	var saved_noise = player.movement_noise
	player.movement_noise = noise
	var count := heard.size()
	player.current_speed = 0.0
	player.velocity = Vector3.ZERO
	for frame in range(5):
		await physics_frame
		player._physics_process(1.0 / 60.0)
	check(heard.size() == count, "站立不发出移动声")
	player.rotation.y = -PI / 2.0
	Input.action_press("move_right")
	for frame in range(12):
		await physics_frame
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_right")
	await settle()
	check(heard.size() > count, "实际移动产生可听声源")
	check(heard.size() - count < 12, "移动声按间隔发送而非每帧刷事件")
	player.current_speed = 0.0
	player.velocity = Vector3.ZERO
	player._physics_process(1.0 / 60.0)
	count = heard.size()
	for frame in range(8):
		await physics_frame
		player._move_while_locked(1.0 / 60.0, Vector3.RIGHT)
	await settle()
	check(heard.size() > count, "锁定平移同样产生移动声")
	player.current_speed = 0.0
	player.velocity = Vector3.ZERO
	player._physics_process(1.0 / 60.0)
	count = heard.size()
	player.rotation.y = -PI / 2.0
	Input.action_press("move_up")
	for frame in range(3):
		await physics_frame
		player._physics_process(1.0 / 60.0)
	Input.action_release("move_up")
	await settle()
	check(heard.size() == count, "原地转身不产生脚步声")
	player.rotation.y = -PI / 2.0
	player.movement_noise = saved_noise
	var combat = player.get_node("Combat")
	combat.equip_weapon(combat.weapon.duplicate())
	combat.weapon.shot_noise = noise
	combat.locked_target = null
	combat.is_aiming = true
	combat.shot_cooldown = 0.0
	count = heard.size()
	var shots: int = combat.shot_count
	combat.shoot()
	await settle()
	check(combat.shot_count == shots + 1 and heard.size() == count + 1, "真实开枪发送一次枪声事件")
	count = heard.size()
	combat.shoot()
	await settle()
	check(heard.size() == count, "冷却拒绝的射击不发声")
	combat.cancel_aim()

func check_priority_and_multiple() -> void:
	enemy.reset_target()
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	await settle()
	for id in [&"cover", &"attack_position", &"suppression"]:
		preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, id, true)
		ai.current_action = ai.actions[id]
		ai.current_action._running = true
		ai.utility_current = {"id": id, "accepts_noise": false}
		noise.emit_from(player, 6.0)
		await settle()
		check(ai.current_action == ai.actions[id] and not ai.context.noise_search_origin.is_finite(), "声音不抢占当前%s动作" % id)
		ai.reset_actions()
	ai.perception.sight_distance = 10.0
	enemy.look_at(player.global_position)
	ai._physics_process(0.01)
	noise.emit_from(player, 6.0)
	await settle()
	check(ai.has_visual_memory and not ai.actions[&"search"].noise_search_origin.is_finite(), "真实目击优先于声音调查")
	ai.perception.sight_distance = 0.0
	enemy.reset_target()
	var peer = load("res://scenes/enemy/enemy.tscn").instantiate()
	peer.position = enemy.position + Vector3(2, 0, 0)
	enemy.get_parent().add_child(peer)
	var peer_ai = peer.get_node("AI")
	peer_ai.set_physics_process(false)
	peer_ai.perception.sight_distance = 0.0
	peer_ai.perception.close_awareness_radius = 0.0
	await settle()
	noise.emit_from(player, 6.0)
	await settle()
	check(ai.is_alerted and peer_ai.is_alerted, "范围内多个敌人分别听见并调查")
	check(ai.actions[&"search"] != peer_ai.actions[&"search"], "多个敌人独立保存调查进度")
	var peer_origin: Vector3 = peer_ai.actions[&"search"].noise_search_origin
	var count := heard.size()
	enemy.receive_hit(enemy.health)
	noise.emit_from(player, 6.0)
	await settle()
	check(heard.size() == count and not ai.actions[&"search"].noise_search_origin.is_finite(), "死亡清理调查且不再接收声音")
	check(peer_ai.actions[&"search"].noise_search_origin == peer_origin, "一名敌人死亡不清除其他敌人的调查")
	peer.free()
	enemy.reset_target()
	check(not ai.actions[&"search"].noise_search_origin.is_finite(), "复位不保留过期声源")
	var data = noise.duplicate()
	data.audio_stream = AudioStreamGenerator.new()
	var file := "user://hearing-resource-test.tres"
	check(ResourceSaver.save(data, file) == OK, "声音参数与音效接口可以保存成资源")
	var restored = ResourceLoader.load(file, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.audio_stream is AudioStream and restored.occluded_range_multiplier == 0.4, "声音资源重载保留音频接口及逻辑参数")
	DirAccess.remove_absolute(file)

func settle() -> void:
	for frame in range(3):
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("HEARING: ", checks - failures, "/", checks)
	quit(0 if failures == 0 else 1)
