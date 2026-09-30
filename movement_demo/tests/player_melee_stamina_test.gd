extends SceneTree

var checks: Dictionary = {}
var scene
var player
var combat
var slots


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	player.set_physics_process(false)
	var enemy = scene.get_node("Arena/Enemy")
	enemy.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	for target in get_nodes_in_group("combat_target"):
		target.global_position = Vector3(30, 0, 30)
	for door in scene.find_children("*", "AnimatableBody3D", true, false):
		door.collision_layer = 0
	var zone = scene.get_node("CombatTest/CombatZone")
	zone.global_position = Vector3.ZERO
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	slots.primary_weapon = slots.primary_weapon.duplicate()
	slots.secondary_weapon = slots.secondary_weapon.duplicate()
	slots.primary_weapon.melee_stamina_cost = 20.0
	slots.secondary_weapon.melee_stamina_cost = 35.0
	# 命中测试使用1.2米目标，独立于当前枪械资源的试玩射程。
	slots.primary_weapon.melee_range = 1.6
	slots.select_slot(0)
	await _frames(3)
	_check("旧武器默认近战消耗20点", WeaponData.new().melee_stamina_cost == 20.0)
	_check("体力测试位于有效战斗区", combat.can_combat())
	_key(true)
	await process_frame
	_key(false)
	_check("真实V在前摇开始时扣当前主武器体力", combat.is_melee_active() and player.stamina == 80.0)
	_check("扣体力重设既有恢复延迟", player.stamina_recovery_timer == player.stamina_recovery_delay)
	await process_frame
	_check("原有体力条显示近战消耗", player.health.stamina_bar.value == 80.0)
	_key(true, true)
	await process_frame
	_key(false)
	_check("重复按键和动作中再次请求不重复扣除", not combat.request_melee() and player.stamina == 80.0)
	# 资源变化只能影响下次攻击，已经扣除的体力不会随前摇变化。
	combat.weapon.melee_stamina_cost = 5.0
	combat.begin_frame(0.4, false)
	_check("挥空完成只扣开始时的一次体力", not combat.is_melee_active() and combat.last_melee_target == null and player.stamina == 80.0)
	_check("冷却中请求不会扣体力", not combat.request_melee() and player.stamina == 80.0)
	_ready_next()
	_check("换槽不补充体力", slots.select_slot(1) and player.stamina == 80.0)
	_check("副武器采用自己的35点消耗", combat.request_melee() and player.stamina == 45.0)
	_ready_next()
	_check("取消前摇不返还体力", player.stamina == 45.0)
	player.stamina = 34.0
	player.stamina_recovery_timer = 0.13
	combat.ammo.magazine_rounds = 1
	combat.request_reload()
	var count: int = combat.melee_count
	_check("体力不足拒绝攻击并保留换弹和冷却", not combat.request_melee() and combat.ammo.is_reloading and combat.melee_count == count and combat.melee_cooldown == 0.0)
	_check("失败请求不扣体力也不重置恢复等待", player.stamina == 34.0 and is_equal_approx(player.stamina_recovery_timer, 0.13))
	player.stamina = 35.0
	_check("体力恰好足够时允许攻击并扣至零", combat.request_melee() and player.stamina == 0.0 and player.stamina_exhausted)
	_ready_next()
	player._update_stamina(player.stamina_recovery_delay)
	_check("恢复等待期间不回复体力", player.stamina == 0.0)
	player._update_stamina(0.6)
	_check("等待后沿用原恢复速度且奔跑仍锁定", is_equal_approx(player.stamina, 20.0) and player.stamina_exhausted)
	slots.primary_weapon.melee_stamina_cost = 20.0
	slots.select_slot(0)
	_check("耗尽后近战只需恢复到本次消耗", combat.request_melee() and is_zero_approx(player.stamina))
	_ready_next()
	player._update_stamina(player.stamina_recovery_delay)
	player._update_stamina(player.stamina_recovery_duration)
	_check("回满解除既有奔跑锁定", player.stamina == player.MAX_STAMINA and not player.stamina_exhausted)
	var target = scene.get_node("CombatTest/TargetB")
	target.global_position = Vector3(0, 0, -1.2)
	await _frames(3)
	var hp: float = target.health
	combat.request_melee()
	combat.begin_frame(combat.weapon.melee_windup_seconds, false)
	_check("实际命中只消耗开始时的20点", target.health == hp - combat.weapon.melee_damage and player.stamina == 80.0)
	_ready_next()
	target.global_position = Vector3(30, 0, 30)
	# 真正推进移动分支，确认近战扣空后仍能恢复奔跑消耗。
	var before_sprint: float = player.stamina
	Input.action_press("move_up")
	Input.action_press("sprint")
	player.set_physics_process(true)
	await _frames(6)
	player.set_physics_process(false)
	Input.action_release("move_up")
	Input.action_release("sprint")
	_check("恢复后仍能奔跑并消耗同一份体力", player.is_sprinting and player.stamina < before_sprint)
	player.is_sprinting = false
	player.stamina = 0.0
	player.stamina_exhausted = true
	player.stamina_recovery_timer = 0.23
	combat.weapon.melee_stamina_cost = 0.0
	_check("零消耗允许空体力挥击且不打断恢复", combat.request_melee() and player.stamina == 0.0 and is_equal_approx(player.stamina_recovery_timer, 0.23))
	_ready_next()
	combat.weapon.melee_stamina_cost = 20.0
	player.stamina = 80.0
	player.stamina_exhausted = false
	zone.global_position = Vector3(30, 0, 0)
	await _frames(3)
	_key(true)
	await process_frame
	_key(false)
	_check("场外真实V不消耗体力", not combat.is_melee_active() and player.stamina == 80.0)
	zone.global_position = Vector3.ZERO
	await _frames(3)
	paused = true
	_check("暂停请求不消耗体力", not combat.request_melee() and player.stamina == 80.0)
	paused = false
	player.set_dialogue_active(true)
	_check("对话请求不消耗体力", not combat.request_melee() and player.stamina == 80.0)
	player.set_dialogue_active(false)
	combat.weapon.melee_enabled = false
	_check("武器禁用近战时不消耗体力", not combat.request_melee() and player.stamina == 80.0)
	combat.weapon.melee_enabled = true
	combat.equip_weapon(null)
	_check("无武器请求不消耗体力", not combat.request_melee() and player.stamina == 80.0)
	slots.select_slot(0)
	combat.request_melee()
	zone.global_position = Vector3(30, 0, 0)
	await _frames(3)
	combat.begin_frame(0.2, false)
	_check("离场取消攻击不返还体力", not combat.is_melee_active() and player.stamina == 60.0)
	zone.global_position = Vector3.ZERO
	await _frames(3)
	_ready_next()
	combat.request_melee()
	player.set_dialogue_active(true)
	_check("对话取消攻击不返还体力", not combat.is_melee_active() and player.stamina == 40.0)
	player.set_dialogue_active(false)
	_ready_next()
	combat.request_melee()
	player.health.debug_invincible = false
	player.receive_hit(10000.0)
	_check("死亡取消不返还且后续请求不扣除", not combat.is_melee_active() and not combat.request_melee() and player.stamina == 20.0)
	paused = false
	scene.queue_free()
	await process_frame
	await process_frame
	var passed := 0
	for title in checks:
		if checks[title]: passed += 1
	print("Melee stamina: %d/%d passed" % [passed, checks.size()])
	quit(0 if passed == checks.size() else 1)


func _ready_next() -> void:
	combat.cancel_melee()
	combat.begin_frame(1.0, false)


func _frames(count: int) -> void:
	for index in count:
		await physics_frame
		await process_frame


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
