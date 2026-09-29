extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	var health = player.get_node("Health")
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	player.set_physics_process(false)
	ai.set_physics_process(false)
	health.debug_invincible = false
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	# 固定本专项验证的惩罚初值；用户可在场景训练资源中独立调参。
	ai.training.profile.set_setting(&"tactics", &"damage_accuracy_penalty", 0.15)
	ai.training.profile.set_setting(&"tactics", &"nearby_shot_accuracy_penalty", 0.02)
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
	player.receive_hit(1.0)
	check(close(combat.get_spread_half_angle_degrees(), 6.0), "真实受伤使玩家散布半角增加3度")
	actor.weapon_stability = 0.8
	actor.receive_hit(1.0)
	check(close(actor.weapon_stability, 0.65), "敌人受伤减15个百分点，而不是乘以85%")
	combat.accuracy = 1.0
	player.receive_hit(0.0)
	player.receive_hit(-1.0)
	player.receive_hit(NAN)
	player.receive_hit(INF)
	check(close(combat.accuracy, 1.0), "无效命中参数不降低玩家准度")
	health.debug_invincible = true
	var debug_health: float = health.health
	player.receive_hit(1.0)
	check(close(health.health, debug_health) and close(combat.get_spread_half_angle_degrees(), 6.0), "Debug 无敌被命中仍扩大3度且不扣血")
	health._debug_damage()
	check(close(health.health, debug_health) and close(combat.get_spread_half_angle_degrees(), 9.0), "Debug 测试受伤按钮也能在无敌时验证命中惩罚")
	health.debug_invincible = false
	combat.accuracy = 1.0
	# 独立线段：经过身体附近，且没有直接命中。
	combat.notice_shot(Vector3(20, 0.8, -1), Vector3(24, 0.8, -1))
	check(close(combat.get_spread_half_angle_degrees(), 3.4), "玩家近弹扩大0.4度")
	actor.weapon_stability = 0.8
	ai.notice_shot(Vector3(22, 0.8, -1), Vector3(26, 0.8, -1))
	check(close(actor.weapon_stability, 0.78), "敌人近弹减2个百分点")
	combat.accuracy = 1.0
	actor.weapon_stability = 0.8
	combat.notice_shot(Vector3(10, 0.8, -1), Vector3(18, 0.8, -1))
	ai.notice_shot(Vector3(10, 0.8, -1), Vector3(18, 0.8, -1))
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
	combat.notice_shot(Vector3(20, 0.8, -1), Vector3(26, 0.8, -1))
	ai.notice_shot(Vector3(20, 0.8, -1), Vector3(26, 0.8, -1))
	check(close(combat.accuracy, 1.0) and close(actor.weapon_stability, 0.8), "隔墙从旁经过的弹道不施加近弹惩罚")
	barrier.queue_free()
	for frame in range(3): await physics_frame
	combat.damage_spread_degrees = 0.0
	ai.training.profile.set_setting(&"tactics", &"damage_accuracy_penalty", 0.0)
	player.receive_hit(1.0)
	actor.receive_hit(1.0)
	check(close(combat.accuracy, 1.0) and close(actor.weapon_stability, 0.8), "导出惩罚设置为零可关闭")
	combat.damage_spread_degrees = 3.0
	ai.training.profile.set_setting(&"tactics", &"damage_accuracy_penalty", 0.15)
	combat.accuracy = 0.01
	actor.weapon_stability = 0.01
	player.receive_hit(1.0)
	actor.receive_hit(1.0)
	check(combat.accuracy == 0.0 and actor.weapon_stability == 0.0, "连续惩罚最多降到零，不被射击或移动下限反向抬高")
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
	player.receive_hit(1.0)
	check(is_finite(combat.accuracy) and combat.get_spread_half_angle_degrees() == 0.0, "固定散布角武器保持有限状态")
	enemy_weapon.initial_accuracy = 1.0
	actor.weapon_stability = 0.0
	actor.weapon_recovery_timer = 0.0
	actor.update_weapon(0.2, player.global_position + Vector3.UP * 0.8)
	check(actor.weapon_stability > 0.0, "初始概率100%的武器受到惩罚后也能恢复")
	weapon.max_spread_angle_degrees = 20.0
	combat.aim_mode = combat.AimMode.PROBABILITY
	combat.accuracy = 1.0
	player.receive_hit(1.0)
	check(close(combat.accuracy, 0.85), "保留概率模式时将Combat角度参数按武器角度范围换算")
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
	print("AIM DISRUPTION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func close(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001

func check(ok: bool, label: String) -> void:
	checks += 1
	print("PASS " if ok else "FAIL ", label)
	if not ok: failures += 1
