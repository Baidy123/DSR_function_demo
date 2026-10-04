extends SceneTree

var checks: Dictionary = {}
var scene
var player
var combat
var slots
var enemy
var target


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
	target = scene.get_node("CombatTest/TargetB")
	player.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	enemy.set_physics_process(false)
	# 隔离专项场地：主场景入口门位于原点前方，遮挡由下方专门的墙体用例验证。
	for door in scene.find_children("*", "AnimatableBody3D", true, false):
		door.collision_layer = 0
	for item in get_nodes_in_group("combat_target"):
		item.global_position = Vector3(35, 0, 35)
	scene.get_node("CombatTest/Cover").global_position = Vector3(30, 0, 30)
	scene.get_node("CombatTest/CombatZone").global_position = Vector3.ZERO
	slots.primary_weapon = slots.primary_weapon.duplicate()
	slots.secondary_weapon = slots.secondary_weapon.duplicate()
	# 固定测试用距离和伤害，不依赖用户在枪械资源里的试玩调参。
	# 本套隔离命中与操作互斥；多次挥击的体力边界由 stamina 专项验证。
	for data in [slots.primary_weapon, slots.secondary_weapon]:
		data.melee_damage = 25.0
		data.melee_range = 1.6
		data.melee_stamina_cost = 0.0
	slots.select_slot(0)
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	enemy.global_position = Vector3(0, 0, -1.2)
	target.global_position = Vector3(0.8, 0, -1.3)
	await _frames(3)
	_check("V物理按键已注册", InputMap.action_get_events("melee")[0].physical_keycode == KEY_V)
	_check("沿用Combat且没有新Melee节点", player.get_node_or_null("Melee") == null and combat.get_script().resource_path.ends_with("player_combat_v3.gd"))
	var hp: float = enemy.health
	var other_hp: float = target.health
	var bullets: int = combat.ammo.magazine_rounds
	_key(true)
	await process_frame
	_check("真实V输入开始前摇且不立即扣血", combat.is_melee_active() and enemy.health == hp)
	_key(false)
	combat.begin_frame(0.05, false)
	_check("前摇未结束不会命中", enemy.health == hp)
	combat.begin_frame(0.07, false)
	_check("只命中正面最近敌人", enemy.health == hp - combat.weapon.melee_damage and target.health == other_hp and combat.last_melee_target == enemy)
	_check("近战不消耗子弹", combat.ammo.magazine_rounds == bullets)
	_check("敌人准度立即清零", enemy.weapon_stability == 0.0)
	enemy.update_weapon(0.1)
	_check("同物理帧不能立即恢复准度", enemy.weapon_stability == 0.0)
	_check("无模型也有剑光", not get_nodes_in_group("player_melee_effect").is_empty() and not player.get_node("Visual/Presentation").has_model())
	var count: int = combat.melee_count
	_key(true, true)
	await process_frame
	_key(false)
	_check("忽略按键长按重复事件", combat.melee_count == count)
	_check("收招期间拒绝切枪和再次近战", not slots.select_slot(1) and not combat.request_melee())
	combat.ammo.magazine_rounds = 2
	_check("收招期间拒绝换弹", not combat.request_reload())
	combat.is_aiming = true
	_check("射击互斥在有效战斗区验证", combat.can_combat())
	var shots: int = combat.shot_count
	combat.shoot()
	_check("收招期间拒绝射击", combat.shot_count == shots)
	combat.begin_frame(0.25, false)
	_check("收招结束仍保留攻击间隔", not combat.is_melee_active() and combat.melee_cooldown > 0.0 and not combat.request_melee())
	_check("收招后允许切枪", slots.select_slot(1))
	_check("切枪不能刷新近战冷却", not combat.request_melee())
	combat.begin_frame(0.3, false)
	_check("每次挥击只结算一次", enemy.health == hp - slots.primary_weapon.melee_damage)
	await create_timer(0.18).timeout
	_check("剑光自动清理", get_nodes_in_group("player_melee_effect").is_empty())
	# 禁用AI时仍由敌人身体推进受击外力，不需要改动决策层。
	var position_before: Vector3 = enemy.global_position
	enemy.set_physics_process(true)
	await _frames(16)
	enemy.set_physics_process(false)
	_check("停用AI也能完成约1米物理击退", absf(enemy.global_position.distance_to(position_before) - 1.0) < 0.06)
	enemy.update_weapon(0.0) # 先消耗实际击退位移引起的移动惩罚与恢复等待。
	enemy.update_weapon(2.0)
	_check("原有等待结束后恢复敌人准度", enemy.weapon_stability > 0.0)
	# 背后、距离外、高度差和墙体均不命中。
	slots.select_slot(0)
	for data in [Vector3(0, 0, 1), Vector3(0, 0, -2), Vector3(0, 1.5, -1)]:
		enemy.global_position = data
		target.global_position = Vector3(30, 0, 30)
		await _frames(2)
		var before: float = enemy.health
		_swing()
		_check("排除范围外目标" + str(data), enemy.health == before and combat.last_melee_target == null)
	enemy.global_position = Vector3(0, 0, -1.3)
	var wall := _wall(Vector3(0, 0.9, -0.6), Vector3(2, 2, 0.12))
	await _frames(2)
	var before_wall: float = enemy.health
	_swing()
	_check("墙体阻挡近战", enemy.health == before_wall)
	wall.queue_free()
	await _frames(2)
	# 前摇期间离开目标不会在旧位置命中；参数在开始时快照。
	combat.request_melee()
	enemy.global_position = Vector3(0, 0, -3)
	await _frames(2)
	combat.begin_frame(1.0, false)
	_check("目标能在前摇中离开范围", enemy.health == before_wall)
	enemy.global_position = Vector3(0, 0, -1.3)
	await _frames(2)
	combat.request_melee()
	combat.weapon.melee_damage = 7.0
	combat.weapon.melee_range = 0.1
	combat.begin_frame(1.0, false)
	_check("本次使用开始时的枪械参数快照", enemy.health == before_wall - 25.0)
	combat.weapon.melee_range = 1.6
	# 固定靶保留原有固定性质并使用当前武器近战伤害。
	enemy.global_position = Vector3(30, 0, 30)
	target.global_position = Vector3(0, 0, -1.2)
	await _frames(2)
	var fixed_position: Vector3 = target.global_position
	var fixed_hp: float = target.health
	_swing()
	_check("枪械独立近战伤害作用于固定靶", target.health == fixed_hp - 7.0 and target.global_position == fixed_position)
	slots.secondary_weapon.melee_damage = 11.0
	slots.select_slot(1)
	_swing()
	_check("换枪使用新枪的近战参数", target.health == fixed_hp - 18.0)
	# 半程换弹被V中断，收招后沿用原检查点续换。
	combat.ammo.magazine_rounds = 1
	_check("允许开始换弹", combat.request_reload())
	combat.ammo.advance_reload(combat.weapon.reload_seconds * 0.6)
	_check("V可打断半程换弹", combat.request_melee() and not combat.ammo.is_reloading and is_equal_approx(combat.ammo.reload_checkpoint, 0.5))
	combat.end_frame(0.2, false)
	_check("近战期间不自动续换", not combat.ammo.is_reloading and is_equal_approx(combat.ammo.reload_checkpoint, 0.5))
	combat.begin_frame(0.4, false)
	combat.end_frame(0.01, false)
	_check("收招后恢复半程换弹", combat.ammo.is_reloading and combat.ammo.reload_progress >= 0.5)
	combat.cancel_reload()
	combat.begin_frame(1.0, false)
	combat.request_melee()
	var paused_elapsed: float = combat.melee_elapsed
	paused = true
	combat.begin_frame(0.5, false)
	_check("暂停时攻击计时不推进", combat.melee_elapsed == paused_elapsed and not combat.request_melee())
	paused = false
	player.set_dialogue_active(true)
	_check("对话立即取消前摇且禁止近战", not combat.is_melee_active() and not combat.request_melee())
	player.set_dialogue_active(false)
	combat.begin_frame(1.0, false)
	combat.weapon.melee_enabled = false
	_check("枪械可单独关闭近战", not combat.request_melee())
	combat.weapon.melee_enabled = true
	combat.equip_weapon(null)
	_check("无武器时安全拒绝", not combat.request_melee())
	slots.select_slot(0)
	# 击退遇墙、复位、死亡清理；使用真实物理帧推进。
	enemy.reset_target()
	enemy.global_position = Vector3(0, 0, -1.2)
	wall = _wall(Vector3(0, 0.9, -1.9), Vector3(3, 2, 0.15))
	await _frames(3)
	enemy.receive_melee_hit(1.0, Vector3.ZERO, 2.0, 0.2)
	enemy.set_physics_process(true)
	await _frames(18)
	enemy.set_physics_process(false)
	_check("击退被墙阻挡不会穿墙", enemy.global_position.z > -1.9 and enemy.global_position.z < -1.2)
	enemy.receive_melee_hit(1.0, Vector3.ZERO, 1.0, 0.2)
	enemy.reset_target()
	_check("敌人复位清除击退", enemy._hit_push_remaining == 0.0)
	enemy.receive_melee_hit(enemy.health + 1.0, Vector3.ZERO, 1.0, 0.2)
	_check("致死近战不会留下击退", enemy.is_dead and enemy._hit_push_remaining == 0.0)
	wall.queue_free()
	combat.request_melee()
	player.get_node("Health").debug_invincible = false
	player.receive_hit(10000.0)
	_check("死亡同帧取消近战", not combat.is_melee_active())
	paused = false
	scene.queue_free()
	await process_frame
	await process_frame
	var passed := 0
	for name in checks:
		if checks[name]: passed += 1
	print("Player melee: %d/%d passed" % [passed, checks.size()])
	quit(0 if passed == checks.size() else 1)


func _swing() -> void:
	combat.cancel_melee()
	combat.begin_frame(2.0, false)
	combat.request_melee()
	combat.begin_frame(1.0, false)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _wall(position: Vector3, size: Vector3) -> StaticBody3D:
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = position
	return wall


func _key(pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.keycode = KEY_V
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)


func _check(title: String, passed: bool) -> void:
	checks[title] = passed
	print(("PASS " if passed else "FAIL ") + title)
