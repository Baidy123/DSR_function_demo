extends SceneTree

var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var combat = player.get_node("Combat")
	var slots = player.get_node_or_null("WeaponSlots")
	_check("玩家挂载双武器槽", slots != null)
	if slots == null:
		_finish()
		return
	_check("默认装备主武器", slots.active_slot == 0 and combat.weapon == slots.primary_weapon)
	_check("两个槽位各有独立测试资源", slots.primary_weapon != null and slots.secondary_weapon != null and slots.primary_weapon != slots.secondary_weapon)
	_check("数字键与滚轮输入已注册", InputMap.has_action("weapon_primary") and InputMap.has_action("weapon_secondary") and InputMap.has_action("weapon_next") and InputMap.has_action("weapon_previous"))
	await process_frame
	_key(KEY_2)
	_check("数字2切换副武器且不暂停", slots.active_slot == 1 and combat.weapon == slots.secondary_weapon and not paused)
	_check("装备栏显示当前副武器", slots.get_node("Panel/Content/Slots/Secondary/Name").text.contains(slots.secondary_weapon.display_name))
	_check("当前槽位有箭头高亮", slots.get_node("Panel/Content/Slots/Secondary/Name").text.begins_with("▶") and not slots.get_node("Panel/Content/Slots/Primary/Name").text.begins_with("▶"))
	combat.accuracy = 0.05
	combat.accuracy_recovery_timer = 0.6
	combat.shot_cooldown = 0.7
	combat.shot_requested = true
	_key(KEY_1)
	_check("数字1切主武器并清理待发请求", slots.active_slot == 0 and combat.weapon == slots.primary_weapon and not combat.shot_requested)
	_check("切枪保留未结束的冷却", is_equal_approx(combat.shot_cooldown, 0.7))
	_key(KEY_2)
	_check("切回保留该枪精度和恢复延迟", is_equal_approx(combat.accuracy, 0.05) and is_equal_approx(combat.accuracy_recovery_timer, 0.6))
	combat.accuracy = 0.03
	_key(KEY_2)
	_check("重复选择当前槽不会重置精度", is_equal_approx(combat.accuracy, 0.03))
	_key(KEY_1, true)
	_check("忽略长按重复键事件", slots.active_slot == 1)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	_check("滚轮向上切换", slots.active_slot == 0)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check("滚轮向下切换", slots.active_slot == 1)
	player.is_in_dialogue = true
	_key(KEY_1)
	await process_frame
	_check("对话时禁用换枪且隐藏装备栏", slots.active_slot == 1 and not slots.get_node("Panel").visible)
	player.is_in_dialogue = false
	await process_frame
	_check("对话结束恢复显示", slots.get_node("Panel").visible)
	_key(KEY_1)
	slots.secondary_weapon = null
	_key(KEY_2)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	_check("数字键与滚轮跳过空槽", slots.active_slot == 0 and combat.weapon == slots.primary_weapon)
	_check("无效槽位请求被拒绝", not slots.select_slot(-1) and not slots.select_slot(2))
	# 使用真实射线确认两槽的配置进入伤害、射程和冷却流程。
	var primary = slots.primary_weapon.duplicate()
	var secondary = load("res://test_sidearm.tres").duplicate()
	primary.min_spread_angle_degrees = 0.0
	primary.max_spread_angle_degrees = 0.0
	secondary.min_spread_angle_degrees = 0.0
	secondary.max_spread_angle_degrees = 0.0
	slots.primary_weapon = primary
	slots.secondary_weapon = secondary
	_key(KEY_1)
	player.global_position = Vector3(0, 0, -1)
	player.rotation = Vector3.ZERO
	var target = scene.get_node("CombatTest/TargetB")
	target.global_position = Vector3(0, 0, -4.5)
	scene.get_node("CombatTest/TargetA").global_position = Vector3(6, 0, -4.5)
	scene.get_node("CombatTest/Cover").global_position = Vector3(7, 1, -2)
	for frame in range(5):
		await physics_frame
	combat.begin_frame(1.0, true)
	var hp: float = target.health
	combat.shoot()
	_check("主武器真实射线使用主槽伤害", combat.last_shot_collider == target and is_equal_approx(target.health, hp - primary.damage))
	_key(KEY_2)
	var count: int = combat.shot_count
	combat.begin_frame(0.0, true)
	combat.shoot()
	_check("切副武器不能立即绕过上一枪冷却", combat.shot_count == count)
	combat.begin_frame(1.0, true)
	hp = target.health
	combat.shoot()
	_check("副武器真实射线使用副槽伤害与射速", combat.last_shot_collider == target and is_equal_approx(target.health, hp - secondary.damage) and is_equal_approx(combat.shot_cooldown, secondary.shot_interval))
	secondary.fire_range = 1.0
	combat.begin_frame(1.0, true)
	hp = target.health
	combat.shoot()
	_check("副武器实际射程生效", is_equal_approx(target.health, hp) and combat.last_shot_collider != target)
	# 新实例验证初始配置，不修改运行中的用户资源。
	var packed = load("res://main.tscn")
	var other = packed.instantiate()
	var other_slots = other.get_node("Player/WeaponSlots")
	other_slots.primary_weapon = null
	root.add_child(other)
	_check("初始主槽为空时自动选副槽", other_slots.active_slot == 1 and other.get_node("Player/Combat").weapon == other_slots.secondary_weapon)
	other.free()
	other = packed.instantiate()
	other_slots = other.get_node("Player/WeaponSlots")
	other_slots.primary_weapon = null
	other_slots.secondary_weapon = null
	root.add_child(other)
	_check("两槽都为空时安全保持无武器", other_slots.active_slot == -1 and other.get_node("Player/Combat").weapon == null)
	other.free()
	var health = player.get_node("Health")
	health.debug_invincible = false
	health.receive_hit(health.max_health)
	_key(KEY_1)
	_check("死亡时禁止换枪", slots.active_slot == 1 and not slots.select_slot(0))
	var game_state = root.get_node("GameState")
	game_state.help_choice = "accepted"
	health.get_node("DeathScreen/Center/Panel/Content/Restart").pressed.emit()
	for frame in range(10):
		await process_frame
	slots = current_scene.get_node("Player/WeaponSlots")
	combat = current_scene.get_node("Player/Combat")
	_check("死亡重开恢复检查器初始槽位和武器状态", not paused and slots.active_slot == 0 and combat.weapon == slots.primary_weapon and combat.shot_cooldown == 0.0)
	_check("双武器重开仍保留对话选择", game_state.help_choice == "accepted")
	_finish()

func _key(code: Key, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	root.push_input(event)

func _wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event)

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)

func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("WEAPON SLOTS: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
