extends SceneTree

class EnemyMoveDriver extends Node:
	var actor
	func _physics_process(delta: float) -> void:
		actor.move_character(Vector3.FORWARD, delta, 2.0)

var checks := 0
var failures := 0
var scene
var player
var combat
var slots
var enemy


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	enemy = scene.get_node("Arena/Enemy")
	player.set_physics_process(false)
	for item in get_nodes_in_group("combat_target"):
		if item.has_method("move_character"):
			item.get_node("AI").set_physics_process(false)
			item.set_physics_process(false)
		item.global_position = Vector3(35, 0, 35)
	for cover in get_nodes_in_group("cover_region"): cover.collision_layer = 0
	for door in scene.find_children("*", "AnimatableBody3D", true, false): door.collision_layer = 0
	scene.get_node("CombatTest/CombatZone").global_position = Vector3.ZERO
	player.health.debug_invincible = false
	player.health.debug_mode = false
	slots.primary_weapon = WeaponData.new()
	slots.secondary_weapon = WeaponData.new()
	for weapon in [slots.primary_weapon, slots.secondary_weapon]:
		weapon.melee_damage = 0.0
		weapon.melee_stamina_cost = 0.0
		weapon.melee_windup_seconds = 0.05
		weapon.melee_recovery_seconds = 0.1
		weapon.melee_interval = 0.15
	slots.select_slot(0)
	await _frames(3)
	_test_resources()
	await _test_slot_hits()
	await _test_enemy_hit()
	for mode in ["walk", "sprint", "crouch", "aim", "melee"]:
		var normal: float = await _measure_player(mode, false)
		var slowed: float = await _measure_player(mode, true)
		_check(normal > 0.02 and absf(slowed / normal - 0.5) < 0.06, "玩家真实位移减半：%s（%.4f → %.4f）" % [mode, normal, slowed])
	await _test_enemy_motion()
	await _test_push()
	await _test_lifecycle()
	scene.queue_free()
	await process_frame
	await process_frame
	var restarted = load("res://scenes/main.tscn").instantiate()
	root.add_child(restarted)
	current_scene = restarted
	_check(restarted.get_node("Player").get_melee_movement_multiplier() == 1.0 and restarted.get_node("Arena/Enemy").get_melee_movement_multiplier() == 1.0, "重开场景没有遗留减速")
	restarted.queue_free()
	await process_frame
	print("Melee hit effects: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)


func _test_resources() -> void:
	var data := WeaponData.new()
	_check(data.melee_slow_multiplier == 0.5 and data.melee_slow_seconds == 0.5, "武器默认命中减速50%持续0.5秒")
	data.melee_slow_multiplier = 0.3
	data.melee_slow_seconds = 0.7
	data.melee_knockback_distance = 1.75
	data.melee_knockback_seconds = 0.33
	var path := "user://melee_hit_effects_test.tres"
	_check(ResourceSaver.save(data, path) == OK, "减速和击退可保存为同一武器资源")
	var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	_check(restored != null and is_equal_approx(restored.melee_slow_multiplier, 0.3) and is_equal_approx(restored.melee_slow_seconds, 0.7) and is_equal_approx(restored.melee_knockback_distance, 1.75) and is_equal_approx(restored.melee_knockback_seconds, 0.33), "资源重载保留全部命中效果参数")
	DirAccess.remove_absolute(path)


func _test_slot_hits() -> void:
	for slot in [0, 1]:
		combat.cancel_melee()
		combat.melee_cooldown = 0.0
		slots.select_slot(slot)
		var weapon: WeaponData = combat.weapon
		var factor := 0.5 if slot == 0 else 0.75
		var seconds := 0.5 if slot == 0 else 0.8
		weapon.melee_slow_multiplier = factor
		weapon.melee_slow_seconds = seconds
		weapon.melee_knockback_distance = 0.4 + slot * 0.2
		weapon.melee_knockback_seconds = 0.2
		player.global_position = Vector3.ZERO
		player.rotation = Vector3.ZERO
		enemy.global_position = Vector3(0, 0, -1.2)
		enemy.clear_melee_hit_effects()
		await _frames(3)
		_check(combat.request_melee(), "当前槽可正常发起近战：" + str(slot))
		_check(enemy.get_melee_movement_multiplier() == 1.0, "前摇不提前施加减速：" + str(slot))
		weapon.melee_slow_multiplier = 0.1
		weapon.melee_slow_seconds = 3.0
		weapon.melee_knockback_distance = 4.0
		combat.begin_frame(0.05, false)
		_check(combat.last_melee_target == enemy and is_equal_approx(enemy.get_melee_movement_multiplier(), factor) and is_equal_approx(enemy._hit_slow_remaining, seconds), "玩家命中使用所选槽的减速快照：" + str(slot))
		_check(is_equal_approx(enemy._hit_push_velocity.length() * enemy._hit_push_duration * 0.5, 0.4 + slot * 0.2), "玩家击退沿用同一武器的出手快照：" + str(slot))
		combat.begin_frame(1.0, false)
		enemy.clear_melee_hit_effects()
	player.clear_melee_hit_effects()


func _test_enemy_hit() -> void:
	var weapon := WeaponData.new()
	weapon.melee_damage = 0.0
	weapon.melee_slow_multiplier = 0.4
	weapon.melee_slow_seconds = 0.6
	weapon.melee_knockback_distance = 0.5
	enemy.equip_weapon(weapon)
	enemy.cancel_melee()
	enemy.melee_cooldown = 0.0
	enemy.global_position = Vector3.ZERO
	enemy.rotation = Vector3.ZERO
	player.global_position = Vector3(0, 0, -1.2)
	await _frames(3)
	var settings: Dictionary = enemy.get_node("AI").context.melee.weapon_settings()
	_check(enemy.begin_melee(0.6) and enemy.execute_melee(player, settings, Vector3.FORWARD), "敌人原基础近战入口实际命中玩家")
	_check(is_equal_approx(player.get_melee_movement_multiplier(), 0.4) and is_equal_approx(player._melee_slow_remaining, 0.6), "敌人武器的减速参数传给真实玩家")
	_check(is_equal_approx(player._melee_push_velocity.length() * player._melee_push_duration * 0.5, 0.5), "敌人武器的击退参数保持独立")
	enemy.cancel_melee()
	player.clear_melee_hit_effects()


func _measure_player(mode: String, slowed: bool) -> float:
	_release_input()
	combat.cancel_melee()
	combat.cancel_aim()
	combat.melee_cooldown = 0.0
	player.clear_melee_hit_effects()
	player.global_position = Vector3(-3, 0, 3)
	scene.get_node("CombatTest/CombatZone").global_position = player.global_position
	player.rotation = Vector3.ZERO
	player.manual_crouch = mode == "crouch"
	player.crouch_amount = 1.0 if mode == "crouch" else 0.0
	player._apply_body_posture()
	player.stamina = 100.0
	player.stamina_exhausted = false
	# 双方放在大厅墙体同侧，使用真实视线锁定，不能跨墙伪造瞄准状态。
	enemy.global_position = Vector3(-3, 0, 1.5)
	combat.weapon.locked_move_multiplier = 0.5
	combat.weapon.melee_windup_seconds = 0.05
	combat.weapon.melee_recovery_seconds = 0.5
	await _frames(3)
	var speed: float = player.move_speed
	if mode == "sprint":
		Input.action_press("sprint")
		speed *= player.sprint_speed_multiplier
	elif mode in ["crouch", "aim"]: speed *= 0.5
	if mode == "aim": Input.action_press("aim")
	if mode == "melee": _check(combat.request_melee(), "移动用例通过真实近战资格")
	Input.action_press("move_right" if mode == "aim" else "move_up")
	player.current_speed = speed
	player.velocity = (Vector3.RIGHT if mode == "aim" else Vector3.FORWARD) * speed
	if slowed: _slow(player)
	var before: Vector3 = player.global_position
	player.set_physics_process(true)
	await _frames(6)
	player.set_physics_process(false)
	var distance: float = Vector2(player.global_position.x - before.x, player.global_position.z - before.z).length()
	if mode == "aim": _check(combat.locked_target == enemy, "瞄准位移用例保持真实目标锁定")
	_release_input()
	return distance


func _test_enemy_motion() -> void:
	combat.cancel_melee()
	player.global_position = Vector3(-6, 0, 2)
	enemy.global_position = Vector3(2, 0, 1)
	enemy.cancel_melee()
	enemy.cancel_reload()
	enemy.body_motion.amount = 0.0
	enemy.clear_melee_hit_effects()
	await _frames(3)
	var driver := EnemyMoveDriver.new()
	driver.actor = enemy
	driver.set_physics_process(false)
	scene.add_child(driver)
	var before: Vector3 = enemy.global_position
	driver.set_physics_process(true)
	await _frames(6)
	driver.set_physics_process(false)
	var normal: float = Vector2(enemy.global_position.x - before.x, enemy.global_position.z - before.z).length()
	_slow(enemy)
	before = enemy.global_position
	driver.set_physics_process(true)
	await _frames(6)
	driver.set_physics_process(false)
	driver.queue_free()
	var slowed: float = Vector2(enemy.global_position.x - before.x, enemy.global_position.z - before.z).length()
	_check(normal > 0.02 and absf(slowed / normal - 0.5) < 0.06, "敌人实际快速移动按原速度减半（%.4f → %.4f）" % [normal, slowed])
	_check(is_equal_approx(enemy._hit_slow_remaining, 0.5), "AI移动调用不重复推进受击减速计时")
	# 本地试玩敌人可能是近战兵；此用例明确配置可换弹的远程兵实例。
	var original_profile = enemy.get_node("UnitType").profile
	var original_shooting: bool = enemy.shooting_enabled
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	enemy.shooting_enabled = true
	enemy.ammo.magazine_rounds = 1
	_check(enemy.request_reload(), "换弹组合用例具有真实换弹资格")
	_check(is_equal_approx(enemy.get_effective_movement_multiplier(2.0), 0.5), "敌人换弹限速后再施加减速")
	enemy.cancel_reload()
	enemy.get_node("UnitType").profile = original_profile
	enemy.shooting_enabled = original_shooting
	enemy.body_motion.amount = 1.0
	_check(is_equal_approx(enemy.get_effective_movement_multiplier(1.0), enemy.crouching_speed_multiplier * 0.5), "敌人蹲行与减速组合")
	enemy.body_motion.amount = 0.0
	enemy.clear_melee_hit_effects()


func _test_push() -> void:
	player.manual_crouch = false
	player.crouch_amount = 0.0
	player._apply_body_posture()
	combat.cancel_aim()
	for actor in [player, enemy]:
		actor.global_position = Vector3(-3 if actor == player else 3, 0, 1)
		actor.velocity = Vector3.ZERO
		if actor == player: player.current_speed = 0.0
		await _frames(3)
		var before: Vector3 = actor.global_position
		actor.receive_melee_hit(0.0, before + Vector3.FORWARD, 1.0, 0.2, Vector3.BACK, 0.5, 0.5)
		actor.set_physics_process(true)
		await _frames(18)
		actor.set_physics_process(false)
		_check(absf(actor.global_position.z - before.z - 1.0) < 0.06, "减速不缩短真实击退距离：" + str(actor.name))
		_check(actor.get_melee_movement_multiplier() == 0.5, "击退结束后减速仍按独立期限生效：" + str(actor.name))


func _test_lifecycle() -> void:
	for actor in [player, enemy]:
		actor.clear_melee_hit_effects()
		_slow(actor)
		actor._physics_process(0.3)
		_slow(actor)
		_check(actor.get_melee_movement_multiplier() == 0.5, "连续命中不叠乘：" + str(actor.name))
		actor._physics_process(0.49)
		_check(actor.get_melee_movement_multiplier() == 0.5, "再次命中刷新完整期限：" + str(actor.name))
		actor._physics_process(0.01)
		_check(actor.get_melee_movement_multiplier() == 1.0, "0.5秒届满恢复原速度：" + str(actor.name))
		_slow(actor)
		actor.receive_hit(0.0, actor.global_position + Vector3.RIGHT)
		actor.receive_melee_hit(0.0, actor.global_position + Vector3.RIGHT, 0.0, 0.2)
		_check(actor.get_melee_movement_multiplier() == 0.5, "普通受伤和旧参数调用不会清除已有减速：" + str(actor.name))
		actor.clear_melee_hit_effects()
		actor.receive_melee_hit(0.0, actor.global_position + Vector3.RIGHT, 0.0, 0.2, Vector3.FORWARD, 0.5, 0.0)
		_check(actor.get_melee_movement_multiplier() == 1.0, "武器0时长关闭减速：" + str(actor.name))
		actor.receive_melee_hit(0.0, actor.global_position + Vector3.RIGHT, 0.0, 0.2, Vector3.FORWARD, 1.0, 0.5)
		_check(actor.get_melee_movement_multiplier() == 1.0, "武器100%速度关闭减速：" + str(actor.name))
		_slow(actor)
		actor.set_physics_process(true)
	paused = true
	for frame in 12: await process_frame
	_check(is_equal_approx(player._melee_slow_remaining, 0.5) and is_equal_approx(enemy._hit_slow_remaining, 0.5), "暂停冻结双方减速计时")
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	paused = false
	slots.select_slot(1 - slots.active_slot)
	enemy.equip_weapon(WeaponData.new())
	_check(player.get_melee_movement_multiplier() == 0.5 and enemy.get_melee_movement_multiplier() == 0.5, "换武器不清除身体减速")
	player.set_dialogue_active(true)
	enemy.get_node("AI")._physics_process(0.01)
	_check(player.get_melee_movement_multiplier() == 1.0 and enemy.get_melee_movement_multiplier() == 1.0, "进入对话清理双方受击效果")
	player.set_dialogue_active(false)
	_slow(enemy)
	enemy.reset_target()
	_check(enemy.get_melee_movement_multiplier() == 1.0, "区域复位清理敌人减速")
	_slow(enemy)
	enemy.receive_hit(10000.0)
	_check(enemy.is_dead and enemy.get_melee_movement_multiplier() == 1.0, "死亡清理敌人减速")
	_slow(player)
	player.receive_hit(10000.0)
	_check(player.is_dead() and player.get_melee_movement_multiplier() == 1.0, "死亡清理玩家减速")
	paused = false


func _slow(actor) -> void:
	actor.receive_melee_hit(0.0, actor.global_position + Vector3.RIGHT, 0.0, 0.2, Vector3.FORWARD, 0.5, 0.5)


func _release_input() -> void:
	for action in ["move_up", "move_right", "sprint", "aim"]: Input.action_release(action)


func _frames(count: int) -> void:
	for frame in count:
		await physics_frame
		await process_frame


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
