extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = preload("res://tests/enemy/enemy_fire_fixture.gd").unbound_scene()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	var health = player.get_node("Health")
	var actor = preload("res://tests/enemy/enemy_fire_fixture.gd").primary_enemy(scene)
	var ai = actor.get_node("AI")
	player.set_physics_process(false)
	ai.set_physics_process(false)
	health.debug_invincible = false
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	# 攻击基础值来自两把测试武器，受方只配置倍率。
	ai.training.profile.set_setting(&"tactics", &"hit_accuracy_loss_multiplier", 1.0)
	ai.training.profile.set_setting(&"tactics", &"suppression_accuracy_loss_multiplier", 1.0)
	actor.debug_shooting = false
	for wall in get_nodes_in_group("cover_region"): wall.collision_layer = 0
	player.global_position = Vector3(22, 0, -2)
	actor.global_position = Vector3(24, 0, -2)
	var weapon := WeaponData.new()
	weapon.min_spread_angle_degrees = 3.0
	weapon.max_spread_angle_degrees = 24.0
	weapon.spread_recovery_delay = 0.4
	weapon.spread_recovery_degrees_per_second = 10.0
	weapon.reload_seconds = 0.5
	weapon.shot_spread_penalty_degrees = 0.0
	combat.equip_weapon(weapon, false, preload("res://scripts/weapons/weapon_ammo.gd").new(weapon, {weapon.ammo_type: 100}))
	var enemy_weapon := WeaponData.new()
	enemy_weapon.reload_seconds = 0.5
	enemy_weapon.accuracy_recovery_delay = 0.4
	enemy_weapon.stabilize_seconds = 2.0
	actor.equip_weapon(enemy_weapon)
	for frame in range(8): await physics_frame
	combat.accuracy = 1.0
	player.receive_weapon_hit(1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	check(close(combat.accuracy, 0.85) and close(combat.get_spread_half_angle_degrees(), 6.15), "攻击武器命中损失15个百分点，玩家散布据自身表示映射")
	actor.weapon_stability = 0.8
	actor.receive_weapon_hit(1.0, Vector3.ZERO, weapon.get_attack_effects())
	check(close(actor.weapon_stability, 0.65), "敌人受伤减15个百分点，而不是乘以85%")
	combat.accuracy = 1.0
	player.receive_weapon_hit(0.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	player.receive_weapon_hit(-1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	player.receive_weapon_hit(NAN, Vector3.ZERO, enemy_weapon.get_attack_effects())
	player.receive_weapon_hit(INF, Vector3.ZERO, enemy_weapon.get_attack_effects())
	check(close(combat.accuracy, 1.0), "无效命中参数不降低玩家准度")
	health.debug_invincible = true
	var debug_health: float = health.health
	player.receive_weapon_hit(1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	check(close(health.health, debug_health) and close(combat.accuracy, 0.85), "真实武器命中无敌玩家仍扣15个百分点且不扣血")
	health._debug_damage()
	check(close(health.health, debug_health) and close(combat.accuracy, 0.85), "无攻击来源的测试扣血不回退旧准度常量或重复惩罚")
	health.debug_invincible = false
	combat.accuracy = 1.0
	# 独立线段：经过身体附近，且没有直接命中。
	combat.notice_shot(Vector3(20, 0.8, -1), Vector3(24, 0.8, -1), enemy_weapon.get_attack_effects())
	check(close(combat.accuracy, 0.98), "攻击武器擦过损失2个百分点")
	actor.weapon_stability = 0.8
	ai.notice_shot(Vector3(22, 0.8, -1), Vector3(26, 0.8, -1), weapon.get_attack_effects())
	check(close(actor.weapon_stability, 0.78), "敌人近弹减2个百分点")
	combat.accuracy = 1.0
	actor.weapon_stability = 0.8
	combat.notice_shot(Vector3(10, 0.8, -1), Vector3(18, 0.8, -1), enemy_weapon.get_attack_effects())
	ai.notice_shot(Vector3(10, 0.8, -1), Vector3(18, 0.8, -1), weapon.get_attack_effects())
	check(close(combat.accuracy, 1.0) and close(actor.weapon_stability, 0.8), "弹道截断后的延长线不触发近弹")
	var barrier := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(7, 2.2, 0.2)
	shape.shape = box
	barrier.add_child(shape)
	scene.add_child(barrier)
	barrier.global_position = Vector3(23, 1.1, -1.5)
	for frame in range(3): await physics_frame
	combat.notice_shot(Vector3(20, 0.8, -1), Vector3(26, 0.8, -1), enemy_weapon.get_attack_effects())
	ai.notice_shot(Vector3(20, 0.8, -1), Vector3(26, 0.8, -1), weapon.get_attack_effects())
	check(close(combat.accuracy, 1.0) and close(actor.weapon_stability, 0.8), "隔墙从旁经过的弹道不施加近弹惩罚")
	barrier.queue_free()
	for frame in range(3): await physics_frame
	combat.hit_accuracy_loss_multiplier = 0.0
	ai.training.profile.set_setting(&"tactics", &"hit_accuracy_loss_multiplier", 0.0)
	player.receive_weapon_hit(1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	actor.receive_weapon_hit(1.0, Vector3.ZERO, weapon.get_attack_effects())
	check(close(combat.accuracy, 1.0) and close(actor.weapon_stability, 0.8), "导出惩罚设置为零可关闭")
	combat.hit_accuracy_loss_multiplier = 1.0
	ai.training.profile.set_setting(&"tactics", &"hit_accuracy_loss_multiplier", 1.0)
	combat.accuracy = 0.01
	actor.weapon_stability = 0.01
	player.receive_weapon_hit(1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	actor.receive_weapon_hit(1.0, Vector3.ZERO, weapon.get_attack_effects())
	check(combat.accuracy == 0.0 and actor.weapon_stability == 0.0, "连续惩罚最多降到零，不被射击或移动下限反向抬高")
	_test_multipliers(player, combat, actor, ai, weapon, enemy_weapon)
	# 成功开始、过程、完成帧、恢复等待与恢复后的边界。
	combat.accuracy = 1.0
	actor.weapon_stability = 0.8
	combat.ammo.magazine_rounds = 1
	actor.ammo.magazine_rounds = 1
	check(combat.request_reload() and actor.request_reload(), "双方成功开始换弹")
	check(combat.accuracy == 0.0 and actor.weapon_stability == 0.0 and close(combat.get_spread_half_angle_degrees(), 24.0), "换弹开始立即降至最低准度")
	combat.end_frame(0.2, false)
	actor.update_weapon(0.2, player.global_position + Vector3.UP * 0.8)
	check(combat.accuracy == 0.0 and actor.weapon_stability == 0.0, "换弹中不偷偷恢复准度")
	combat.end_frame(1.0, false)
	actor.update_weapon(1.0, player.global_position + Vector3.UP * 0.8)
	check(not combat.ammo.is_reloading and not actor.ammo.is_reloading and combat.accuracy == 0.0 and actor.weapon_stability == 0.0, "跨过完成时间的大帧也不提前恢复")
	combat.end_frame(0.2, false)
	actor.update_weapon(0.2, player.global_position + Vector3.UP * 0.8)
	check(combat.accuracy == 0.0 and actor.weapon_stability == 0.0, "完成后遵守原恢复等待")
	combat.end_frame(0.3, false)
	actor.update_weapon(0.3, player.global_position + Vector3.UP * 0.8)
	check(combat.accuracy > 0.0 and actor.weapon_stability > 0.0, "等待结束后准度自然恢复")
	combat.accuracy = 0.7
	actor.weapon_stability = 0.7
	check(not combat.request_reload() and not actor.request_reload() and close(combat.accuracy, 0.7) and close(actor.weapon_stability, 0.7), "满匣换弹失败不降低准度")
	combat.ammo.magazine_rounds = 1
	actor.ammo.magazine_rounds = 1
	combat.request_reload()
	actor.request_reload()
	combat.cancel_reload()
	actor.cancel_reload()
	check(combat.accuracy == 0.0 and actor.weapon_stability == 0.0, "取消换弹不还原旧准度")
	# 真实发射验证：直击不能再叠近弹；自己的射击不受自身近弹惩罚。
	weapon.min_spread_angle_degrees = 0.0
	weapon.max_spread_angle_degrees = 20.0
	weapon.damage = 1.0
	combat.accuracy = 1.0
	combat.is_aiming = true
	combat.locked_target = actor
	combat.shot_cooldown = 0.0
	actor.weapon_stability = 0.8
	combat.shoot()
	check(combat.last_shot_collider == actor and close(actor.weapon_stability, 0.65), "玩家实际直击敌人只减15%，不叠加2%近弹")
	check(close(combat.accuracy, 1.0), "玩家不会被自己的弹道降低准度")
	# 不锁定，令确定性中心射线擦过敌人侧面。
	combat.locked_target = null
	player.visual.look_at(Vector3(24, player.visual.global_position.y, -1))
	combat.accuracy = 1.0
	combat.shot_cooldown = 0.0
	combat.ammo.magazine_rounds = 2
	actor.weapon_stability = 0.8
	combat.shoot()
	check(combat.last_shot_collider != actor and close(actor.weapon_stability, 0.78), "玩家实际未命中弹道触发敌人近弹惩罚")
	health.debug_invincible = true
	debug_health = health.health
	combat.accuracy = 1.0
	actor.weapon_stability = 1.0
	actor.ammo.magazine_rounds = 2
	actor.shot_cooldown = 0.0
	actor.has_aim = true
	actor.aim_acquired = true
	actor.aim_direction = (player.global_position + Vector3.UP * 0.8 - actor.get_shot_origin()).normalized()
	actor.face_direction(actor.aim_direction, 10.0)
	check(actor.try_fire() and actor.last_shot_collider == player and close(combat.get_spread_half_angle_degrees(), 3.0) and close(health.health, debug_health), "敌人实际直击无敌玩家不扣血且只增加3度，不叠加近弹")
	combat.accuracy = 1.0
	actor.weapon_stability = 1.0
	actor.shot_cooldown = 0.0
	actor.aim_direction = (Vector3(22, 0.8, -1) - actor.get_shot_origin()).normalized()
	actor.face_direction(actor.aim_direction, 10.0)
	check(actor.try_fire() and actor.last_shot_collider != player and close(combat.get_spread_half_angle_degrees(), 0.4) and close(health.health, debug_health), "敌人实际擦身弹道触发无敌玩家0.4度惩罚")
	health.debug_invincible = false
	# 角度上下限相同不允许除零。
	weapon.max_spread_angle_degrees = weapon.min_spread_angle_degrees
	player.receive_weapon_hit(1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	check(is_finite(combat.accuracy) and combat.get_spread_half_angle_degrees() == 0.0, "固定散布角武器保持有限状态")
	enemy_weapon.initial_accuracy = 1.0
	actor.weapon_stability = 0.0
	actor.weapon_recovery_timer = 0.0
	actor.update_weapon(0.2, player.global_position + Vector3.UP * 0.8)
	check(actor.weapon_stability > 0.0, "初始概率100%的武器受到惩罚后也能恢复")
	weapon.max_spread_angle_degrees = 20.0
	combat.aim_mode = combat.AimMode.PROBABILITY
	combat.accuracy = 1.0
	player.receive_weapon_hit(1.0, Vector3.ZERO, enemy_weapon.get_attack_effects())
	check(close(combat.accuracy, 0.85), "概率模式同样按攻击武器百分点扣减，不读取旧角度配置")
	actor.shot_cooldown = 0.0
	ai.context.fire.fire_pause_remaining = 0.0
	ai.context.fire.fire_reaction_elapsed = ai.context.fire.fire_reaction_seconds
	ai.training.profile.set_setting(&"tactics", &"fire_while_moving", true)
	var path := PackedVector3Array([Vector3(24.5, 0.3, -2)])
	var threat := Vector3(22, 0, -2)
	var route: Dictionary = ai.context.spatial.assess_route(ai.context, path, threat, 1.0, 1.0, true)
	check(route.fire_seconds == 0.0, "移动评分不预支换弹完成前的火力")
	route = ai.context.spatial.assess_route(ai.context, path, threat, 1.0, 0.0, true)
	check(route.fire_seconds > 0.0, "换弹结束后的开阔路线仍能计入火力")
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	route = ai.context.spatial.assess_route(ai.context, path, threat, 1.0, 0.0, true)
	check(route.fire_seconds == 0.0, "同帧改变感知参数不复用旧射击路线缓存")
	await _test_moving_recovery(scene, player, combat)
	print("AIM DISRUPTION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _test_moving_recovery(scene: Node, player, combat) -> void:
	# 使用真实玩家物理循环与移动输入；隔离敌人，保证等待期间没有新的攻击。
	for actor in preload("res://tests/enemy/enemy_fire_fixture.gd").members(scene.get_node("Arena")):
		actor.set_physics_process(false)
		actor.get_node("AI").set_physics_process(false)
	var weapon := WeaponData.new()
	weapon.min_spread_angle_degrees = 2.0
	weapon.max_spread_angle_degrees = 10.0
	weapon.initial_spread_angle_degrees = 4.0
	weapon.moving_spread_angle_degrees = 8.0
	weapon.spread_recovery_degrees_per_second = 4.0
	weapon.spread_recovery_delay = 0.4
	weapon.initial_accuracy = 0.75
	weapon.moving_accuracy_cap = 0.25
	weapon.stabilize_seconds = 0.5
	weapon.accuracy_recovery_delay = 0.4
	player.get_node("Health").debug_invincible = true
	for action in [&"aim", &"fire", &"sprint", &"move_up", &"move_down", &"move_left", &"move_right"]:
		Input.action_release(action)
	for mode in [combat.AimMode.SPREAD_CONE, combat.AimMode.PROBABILITY]:
		var label: String = "散布模式" if mode == combat.AimMode.SPREAD_CONE else "概率模式"
		combat.aim_mode = mode
		combat.equip_weapon(weapon)
		player.global_position = Vector3(22, 0, -2)
		player.velocity = Vector3.ZERO
		player.current_speed = 0.0
		player.clear_hit_effects()
		player.set_physics_process(true)
		Input.action_press("move_left")
		for frame in 20: await physics_frame
		var before: Vector3 = player.global_position
		player.receive_weapon_hit(1.0, Vector3.ZERO, {"hit_accuracy_loss": 1.0})
		for frame in 12: await physics_frame
		check(not combat.is_aiming and player.global_position.distance_to(before) > 0.1 and combat.accuracy == 0.0,
			label + "：真实走路且未瞄准，受击后的恢复等待不会立即抬高精度")
		for frame in 30: await physics_frame
		check(combat.accuracy > 0.0 and combat.accuracy < 0.25,
			label + "：持续走路时额外损失经过等待后逐渐恢复")
		for frame in 60: await physics_frame
		check(close(combat.accuracy, 0.25) and combat.status.text.contains("25%"),
			label + "：持续走路只恢复到移动限制，左上角显示同步恢复")
		if mode == combat.AimMode.SPREAD_CONE:
			check(close(combat.get_spread_half_angle_degrees(), 8.0), "移动中恢复到8度，不绕过原移动散布限制")
		var chest: Vector3 = player.get_torso_position()
		combat.notice_shot(chest + Vector3(-3, 0, 0.2), chest + Vector3(3, 0, 0.2),
			{"near_miss_radius": 0.5, "suppression_accuracy_loss": 1.0})
		for frame in 12: await physics_frame
		check(combat.accuracy == 0.0, label + "：新的擦过损失重新等待，不被走路瞬间抵消")
		for frame in 30: await physics_frame
		check(combat.accuracy > 0.0 and combat.accuracy < 0.25, label + "：擦过后持续走路也能逐渐恢复")
		Input.action_release("move_left")
		for frame in 120: await physics_frame
		check(close(combat.accuracy, 0.75), label + "：停步后未瞄准只恢复到初始稳定度75%")
		if mode == combat.AimMode.SPREAD_CONE:
			check(close(combat.get_spread_half_angle_degrees(), 4.0), "停步后恢复初始4度，不跨帧收拢到初始值以内")
	player.set_physics_process(false)

func _test_multipliers(player, combat, actor, ai, weapon: WeaponData, enemy_weapon: WeaponData) -> void:
	var attack := WeaponData.new()
	attack.hit_accuracy_loss = 0.2
	attack.suppression_accuracy_loss = 0.04
	attack.hit_speed_loss = 0.3
	var frozen := attack.get_attack_effects()
	attack.hit_accuracy_loss = 0.9
	for factor in [0.0, 0.5, 1.0, 2.0]:
		combat.hit_accuracy_loss_multiplier = factor
		ai.training.profile.set_setting(&"tactics", &"hit_accuracy_loss_multiplier", factor)
		combat.hit_speed_loss_multiplier = 0.5
		ai.training.profile.set_setting(&"tactics", &"hit_speed_loss_multiplier", 0.5)
		combat.accuracy = 0.8
		actor.weapon_stability = 0.8
		player.receive_weapon_hit(1.0, Vector3.ZERO, frozen)
		actor.receive_weapon_hit(1.0, Vector3.ZERO, frozen)
		check(close(combat.accuracy, 0.8 - 0.2 * factor) and close(actor.weapon_stability, 0.8 - 0.2 * factor), "双方命中倍率与冻结武器百分点值：×" + str(factor))
		check(close(player.get_hit_movement_multiplier(), 0.85) and close(actor.get_hit_movement_multiplier(), 0.85), "速度损失倍率独立于命中精度倍率，30%×0.5只减速15%")
	combat.hit_accuracy_loss_multiplier = 1.0
	combat.hit_speed_loss_multiplier = 1.0
	ai.training.profile.set_setting(&"tactics", &"hit_accuracy_loss_multiplier", 1.0)
	ai.training.profile.set_setting(&"tactics", &"hit_speed_loss_multiplier", 1.0)
	combat.suppression_accuracy_loss_multiplier = 2.0
	ai.training.profile.set_setting(&"tactics", &"suppression_accuracy_loss_multiplier", 2.0)
	player.clear_hit_effects()
	actor.clear_hit_effects()
	combat.accuracy = 0.8
	actor.weapon_stability = 0.8
	frozen.near_miss_radius = 0.5
	combat.notice_shot(Vector3(20, 0.8, -1), Vector3(24, 0.8, -1), frozen)
	ai.notice_shot(Vector3(22, 0.8, -1), Vector3(26, 0.8, -1), frozen)
	check(close(combat.accuracy, 0.8) and close(actor.weapon_stability, 0.8), "同一弹道在攻击武器窄擦过范围外不生效")
	frozen.near_miss_radius = 1.5
	combat.notice_shot(Vector3(20, 0.8, -1), Vector3(24, 0.8, -1), frozen)
	ai.notice_shot(Vector3(22, 0.8, -1), Vector3(26, 0.8, -1), frozen)
	check(close(combat.accuracy, 0.72) and close(actor.weapon_stability, 0.72), "只扩大攻击武器范围即可擦过，压制4%×2扣8个百分点")
	check(player.get_hit_movement_multiplier() == 1.0 and actor.get_hit_movement_multiplier() == 1.0, "擦过不会套用命中速度损失")
	combat.suppression_accuracy_loss_multiplier = 1.0
	ai.training.profile.set_setting(&"tactics", &"suppression_accuracy_loss_multiplier", 1.0)
	combat.accuracy = 0.8
	actor.weapon_stability = 0.8
	player.receive_hit(1.0)
	actor.receive_hit(1.0)
	check(close(combat.accuracy, 0.8) and close(actor.weapon_stability, 0.8), "无攻击来源生命事件不产生旧固定精度惩罚")
	frozen.hit_accuracy_loss = NAN
	frozen.hit_speed_loss = INF
	player.receive_weapon_hit(1.0, Vector3.ZERO, frozen)
	actor.receive_weapon_hit(1.0, Vector3.ZERO, frozen)
	check(close(combat.accuracy, 0.8) and close(actor.weapon_stability, 0.8) and player.get_hit_movement_multiplier() == 1.0, "非有限基础损失不污染精度与移动状态")

func close(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
