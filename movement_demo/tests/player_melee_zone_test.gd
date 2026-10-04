extends SceneTree

var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var combat = player.get_node("Combat")
	# 测试目标位于1.2米；只调整运行时副本，不依赖用户的射程调参。
	var slots = player.get_node("WeaponSlots")
	slots.primary_weapon = slots.primary_weapon.duplicate()
	slots.primary_weapon.melee_range = 1.6
	slots.select_slot(0)
	var enemy = scene.get_node("Arena/Enemy")
	var target = scene.get_node("CombatTest/TargetB")
	player.set_physics_process(false)
	enemy.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	for area in get_nodes_in_group("combat_zone"):
		area.monitoring = false
	for door in scene.find_children("*", "AnimatableBody3D", true, false):
		door.collision_layer = 0
	await _frames(3)
	for body in get_nodes_in_group("combat_target"):
		body.global_position = Vector3(30, 0, 30)
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	target.global_position = Vector3(0, 0, -1.2)
	# 使用没有靶场复位信号的真实 Area，验证区域守卫自身生效。
	var zone := _zone(scene, Vector3(10, 0, 0))
	await _frames(3)
	var hp: float = target.health
	_check("场外与射击共享can_combat判定", not combat.can_combat() and not combat.request_melee())
	combat.ammo.magazine_rounds = 1
	_check("场外仍允许原有换弹", combat.request_reload())
	var count: int = combat.melee_count
	_key(true)
	await process_frame
	_key(false)
	_check("场外真实V不会开始近战或消耗冷却", not combat.is_melee_active() and combat.melee_count == count and combat.melee_cooldown == 0.0)
	_check("场外V不会打断换弹或产生效果", combat.ammo.is_reloading and target.health == hp and get_nodes_in_group("player_melee_effect").is_empty())
	combat.cancel_reload()
	zone.global_position = Vector3.ZERO
	await _frames(3)
	_check("进入有效战斗区后允许近战", combat.can_combat() and combat.request_melee())
	zone.global_position = Vector3(10, 0, 0)
	await _frames(3)
	combat.begin_frame(0.15, false)
	_check("前摇中离场取消攻击而不结算伤害", not combat.is_melee_active() and target.health == hp and get_nodes_in_group("player_melee_effect").is_empty())
	_check("离场取消不会刷新已消耗的冷却", combat.melee_cooldown > 0.0)
	zone.global_position = Vector3.ZERO
	await _frames(3)
	combat.begin_frame(1.0, false)
	combat.request_melee()
	combat.begin_frame(combat.weapon.melee_windup_seconds, false)
	_check("场内正常结算伤害并显示剑光", target.health == hp - combat.weapon.melee_damage and not get_nodes_in_group("player_melee_effect").is_empty())
	zone.global_position = Vector3(10, 0, 0)
	await _frames(2)
	combat.end_frame(0.0, false)
	await process_frame
	_check("出手后离场清理收招与剑光", not combat.is_melee_active() and get_nodes_in_group("player_melee_effect").is_empty())
	# 多区域重叠时，只要还有一个有效区域就符合射击与近战的共同条件。
	zone.global_position = Vector3.ZERO
	var second := _zone(scene, Vector3.ZERO)
	await _frames(3)
	combat.begin_frame(1.0, false)
	combat.request_melee()
	zone.monitoring = false
	await _frames(2)
	combat.begin_frame(combat.weapon.melee_windup_seconds, false)
	_check("另一个有效重叠区仍可支持出手", combat.can_combat() and combat.is_melee_active() and target.health == hp - combat.weapon.melee_damage * 2.0)
	second.monitoring = false
	await _frames(2)
	combat.begin_frame(0.0, false)
	_check("全部区域停用会取消进行中的近战", not combat.can_combat() and not combat.is_melee_active())
	combat.begin_frame(1.0, false)
	_check("监测关闭的区域不能启动近战", not combat.request_melee())
	second.monitoring = true
	second.remove_from_group("combat_zone")
	await _frames(2)
	_check("普通区域不能替代战斗区域", not combat.can_combat() and not combat.request_melee())
	second.add_to_group("combat_zone")
	await _frames(2)
	combat.request_melee()
	second.queue_free()
	await _frames(2)
	combat.begin_frame(0.2, false)
	_check("战斗区域删除后不补结算攻击", not combat.is_melee_active() and target.health == hp - combat.weapon.melee_damage * 2.0)
	scene.queue_free()
	await process_frame
	await process_frame
	var passed := 0
	for title in checks:
		if checks[title]: passed += 1
	print("Melee combat zone: %d/%d passed" % [passed, checks.size()])
	quit(0 if passed == checks.size() else 1)


func _zone(parent: Node, position: Vector3) -> Area3D:
	var area := Area3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(4, 3, 4)
	collider.shape = shape
	area.add_child(collider)
	area.add_to_group("combat_zone")
	parent.add_child(area)
	area.global_position = position
	return area


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


func _key(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.keycode = KEY_V
	event.pressed = pressed
	Input.parse_input_event(event)


func _check(title: String, passed: bool) -> void:
	checks[title] = passed
	print(("PASS " if passed else "FAIL ") + title)
