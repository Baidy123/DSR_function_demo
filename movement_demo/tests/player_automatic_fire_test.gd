extends SceneTree

var scene: Node
var player
var combat
var slots
var checks := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks[label] = ok
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	player.set_physics_process(false)
	var configurable_weapon := false
	for property in combat.get_property_list():
		if property.name == "weapon":
			configurable_weapon = bool(property.usage & PROPERTY_USAGE_EDITOR)
	check(not configurable_weapon, "Combat不再提供重复的武器配置入口")
	check(combat.weapon == slots.primary_weapon, "实际武器由初始槽位提供")
	var weapon = slots.primary_weapon.duplicate()
	check("fire_mode" in weapon, "武器提供单发自动配置")
	if not "fire_mode" in weapon:
		_finish()
		return
	check(weapon.fire_mode == 0, "现有武器默认保持单发")
	weapon.shot_interval = 0.2
	slots.primary_weapon = weapon
	slots.select_slot(0)
	player.global_position = Vector3(0, 0, -1)
	for frame in range(5):
		await physics_frame
	Input.action_press("aim")
	_fire_press()
	_step(0.01)
	var count: int = combat.shot_count
	for frame in range(50):
		_step(0.02)
	check(count == 1 and combat.shot_count == count, "单发按住只发一枪")
	_fire_release()
	_fire_press()
	_step(0.01)
	check(combat.shot_count == count + 1, "单发再次点击才能再发")
	_fire_release()
	weapon.fire_mode = 1
	combat.shot_cooldown = 0.0
	count = combat.shot_count
	# 模拟按下事件被 UI 消费：Input 状态改变，但 Combat 没收到未处理事件。
	Input.action_press("fire")
	_step(1.0)
	check(combat.shot_count == count, "UI消费的按下不会启动自动开火")
	Input.action_release("fire")
	_fire_press()
	_step(0.01)
	count = combat.shot_count
	_step(0.1)
	check(combat.shot_count == count, "自动射击遵守枪械冷却")
	_step(0.11)
	check(combat.shot_count == count + 1, "自动按住超过间隔继续发射")
	for frame in range(25):
		_step(0.02)
	check(combat.shot_count >= count + 3, "自动按住持续发射多枪")
	combat.shot_cooldown = weapon.shot_interval
	count = combat.shot_count
	for frame in range(11):
		_step(1.0 / 60.0)
	check(combat.shot_count == count, "60Hz下未满12帧不提前射击")
	_step(1.0 / 60.0)
	check(combat.shot_count == count + 1, "60Hz下0.2秒间隔恰好12帧不多等一帧")
	_fire_release()
	count = combat.shot_count
	_step(1.0)
	check(combat.shot_count == count, "松开左键立即停止连发")
	_fire_press()
	_step(1.0)
	count = combat.shot_count
	Input.action_release("fire")
	_step(1.0)
	check(combat.shot_count == count, "释放事件被UI消费也停止连发")
	_fire_press()
	_step(1.0)
	count = combat.shot_count
	_step(2.0)
	check(combat.shot_count == count + 1, "长帧最多一枪不集中补发")
	Input.action_release("aim")
	_step(1.0)
	count = combat.shot_count
	Input.action_press("aim")
	_step(1.0)
	check(combat.shot_count == count, "取消瞄准清理扳机需重新按下")
	_fire_release()
	_fire_press()
	_step(0.01)
	count = combat.shot_count
	player.is_in_dialogue = true
	_step(1.0)
	player.is_in_dialogue = false
	_step(1.0)
	check(combat.shot_count == count, "对话打断连发且结束不误射")
	_fire_release()
	_fire_press()
	_step(0.01)
	var cooldown: float = combat.shot_cooldown
	slots.select_slot(1)
	check(is_equal_approx(combat.shot_cooldown, cooldown), "自动射击后切枪保留冷却")
	count = combat.shot_count
	_step(1.0)
	check(combat.shot_count == count, "切换副武器清理连发状态")
	_fire_release()
	slots.select_slot(0)
	_fire_press()
	_step(1.0)
	player.global_position = Vector3(0, 0, 4)
	for frame in range(4):
		await physics_frame
	count = combat.shot_count
	_step(1.0)
	check(combat.shot_count == count, "离开战斗区域停止自动射击")
	_fire_release()
	player.global_position = Vector3(0, 0, -1)
	for frame in range(4):
		await physics_frame
	_fire_press()
	_step(1.0)
	count = combat.shot_count
	var health = player.get_node("Health")
	health.debug_invincible = false
	player.receive_hit(health.max_health * 2.0)
	combat.shoot()
	check(player.is_dead() and not combat.fire_held and combat.shot_count == count, "死亡清理扳机并禁止继续射击")
	paused = false
	_fire_release()
	Input.action_release("aim")
	_finish()

func _step(delta: float) -> void:
	combat.begin_frame(delta, Input.is_action_pressed("aim"))
	combat.end_frame(delta, false)

func _fire_press() -> void:
	Input.action_press("fire")
	var event := InputEventAction.new()
	event.action = "fire"
	event.pressed = true
	combat._unhandled_input(event)

func _fire_release() -> void:
	Input.action_release("fire")
	var event := InputEventAction.new()
	event.action = "fire"
	combat._unhandled_input(event)

func _finish() -> void:
	print("PLAYER FIRE MODES: ", checks.size(), " failed=", checks.values().count(false))
	scene.free()
	quit(1 if checks.values().has(false) else 0)
