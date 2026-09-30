extends SceneTree

const Fixture = preload("res://tests/presentation_fixture.gd")
var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Player")
	var combat = actor.get_node("Combat")
	var adapter = actor.get_node("PlayerPresentation")
	var presentation = actor.get_node("Visual/Presentation")
	var enemy = scene.get_node("Arena/Enemy")
	enemy.get_node("AI").set_physics_process(false)
	enemy.set_physics_process(false)
	actor.set_physics_process(false)
	scene.get_node("CombatTest/CombatZone").global_position = Vector3.ZERO
	for target in get_nodes_in_group("combat_target"):
		target.global_position = Vector3(30, 0, 30)
	for door in scene.find_children("*", "AnimatableBody3D", true, false):
		door.collision_layer = 0
	var weapon: WeaponData = combat.weapon.duplicate()
	weapon.melee_windup_seconds = 0.4
	weapon.melee_recovery_seconds = 0.4
	weapon.melee_interval = 1.0
	combat.equip_weapon(weapon)
	presentation.animation_profile = Fixture.profile()
	presentation.animation_profile.melee = &"Shoot"
	presentation.model_scene = Fixture.model_scene()
	await process_frame
	await process_frame
	actor.global_position = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	# 等待传送后的物理重叠列表更新，再验证战斗区内的表现。
	await _frames(3)
	combat.request_melee()
	_check("近战状态选择已配置动画", presentation.current_state == &"melee" and presentation._clip == &"Shoot")
	combat.begin_frame(0.2, false)
	adapter._sync()
	_check("动画进度跟随玩法的前摇与收招", is_equal_approx(presentation._time, 0.25) and adapter.state.melee_phase == combat.MeleePhase.WINDUP)
	presentation._process(1.0)
	_check("动画播放不会独立推进攻击进度", is_equal_approx(presentation._time, 0.25) and is_equal_approx(combat.melee_elapsed, 0.2))
	presentation.play_event(&"fire")
	_check("近战期间开火表现不会覆盖挥击", presentation.current_state == &"melee")
	combat.begin_frame(0.2, false)
	adapter._sync()
	_check("出手进入收招并继续同步", adapter.state.melee_phase == combat.MeleePhase.RECOVERY and is_equal_approx(presentation._time, 0.5))
	combat.begin_frame(0.4, false)
	_check("收招结束回到基础状态", presentation.current_state != &"melee")
	combat.begin_frame(1.0, false)
	presentation.animation_profile.melee = &""
	combat.request_melee()
	_check("缺少近战动画安全回退", presentation._clip == presentation.animation_profile.idle and combat.is_melee_active())
	combat.cancel_melee()
	combat.begin_frame(1.0, false)
	# 真正由玩家物理主循环推进，验证边走边挥击与禁跑。
	actor.velocity = Vector3.ZERO
	actor.current_speed = 0.0
	var before: Vector3 = actor.global_position
	combat.request_melee()
	Input.action_press("move_right")
	Input.action_press("sprint")
	actor.set_physics_process(true)
	await _frames(6)
	actor.set_physics_process(false)
	Input.action_release("move_right")
	Input.action_release("sprint")
	_check("挥击时仍能普通横移", actor.global_position.x > before.x + 0.01)
	_check("挥击朝向固定且不能冲刺", absf(actor.rotation.y) < 0.001 and not actor.is_sprinting and actor.current_speed <= actor.move_speed)
	combat.cancel_melee()
	combat.begin_frame(1.0, false)
	# 靶场复位取消本区尚未完成的攻击和剑光。
	var region = scene.get_node("CombatTest")
	var zone = region.get_node("CombatZone")
	actor.global_position = Vector3(zone.global_position.x, 0, zone.global_position.z)
	await _frames(3)
	combat.request_melee()
	combat.begin_frame(0.4, false)
	_check("挥击记录所在靶场", combat._melee_region != null and combat._melee_region.get_ref() == region)
	scene.get_node("Arena").presentation_reset.emit(scene.get_node("Arena"))
	_check("其他区域复位不取消本次挥击", combat.is_melee_active())
	region._reset_targets()
	await process_frame
	_check("本区复位取消攻击并清理剑光", not combat.is_melee_active() and get_nodes_in_group("player_melee_effect").is_empty())
	combat.begin_frame(1.0, false)
	combat.melee_effect_scene = null
	presentation.model_scene = null
	await process_frame
	combat.request_melee()
	combat.begin_frame(0.4, false)
	_check("关闭模型动画与剑光仍可出手", combat.melee_phase == combat.MeleePhase.RECOVERY and get_nodes_in_group("player_melee_effect").is_empty())
	scene.queue_free()
	await process_frame
	await process_frame
	var passed := 0
	for name in checks:
		if checks[name]: passed += 1
	print("Melee presentation: %d/%d passed" % [passed, checks.size()])
	quit(0 if passed == checks.size() else 1)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _check(title: String, passed: bool) -> void:
	checks[title] = passed
	print(("PASS " if passed else "FAIL ") + title)
