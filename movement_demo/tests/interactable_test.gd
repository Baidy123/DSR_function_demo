extends SceneTree

## 场景交互物检查：输入守卫、条件、效果、实例结果与解耦注入。
## 运行：godot --headless --path movement_demo --script res://tests/interactable_test.gd

var failures: int = 0


class NoiseProbe extends Node:
	var events: Array = []

	func receive_noise(source: Node3D, position: Vector3, radius: float, occluded_multiplier: float) -> void:
		events.append({"source": source, "position": position, "radius": radius, "occluded": occluded_multiplier})


## 最小状态替身：交互物只按方法名使用状态，不要求具体类型。
class FakeState extends Node:
	var items: Dictionary = {}
	var flags: Dictionary = {}

	func add_item(item_id: StringName, display_name: String = "", count: int = 1) -> void:
		var entry: Dictionary = items.get(item_id, {"display_name": "", "count": 0})
		if not display_name.is_empty():
			entry["display_name"] = display_name
		entry["count"] = int(entry["count"]) + count
		items[item_id] = entry

	func has_item(item_id: StringName) -> bool:
		return get_item_count(item_id) > 0

	func get_item_count(item_id: StringName) -> int:
		return int((items.get(item_id, {}) as Dictionary).get("count", 0))

	func item_display_name(item_id: StringName) -> String:
		return str((items.get(item_id, {}) as Dictionary).get("display_name", item_id))

	func set_flag(flag: StringName, value: bool = true) -> void:
		flags[flag] = value

	func is_flag_set(flag: StringName) -> bool:
		return bool(flags.get(flag, false))


func _initialize() -> void:
	call_deferred("run_checks")


func check(condition: bool, label_text: String) -> void:
	if condition:
		print("PASS: ", label_text)
	else:
		failures += 1
		push_error(label_text)


func press_key(code: Key, echo: bool = false) -> bool:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	return root.is_input_handled()


func settle() -> void:
	for frame in range(4):
		await physics_frame


func stand_at(player: Node3D, target: Node3D) -> void:
	player.position = target.global_position + Vector3(0, 0, -0.9)


## 用 E 把当前对话推进到结束；避免在协程中途关闭界面留下未释放的资源。
func finish_dialogue(ui) -> void:
	for step in range(8):
		if ui.dialogue_player == null:
			break
		press_key(KEY_E)
		await settle()
	await settle()


func run_checks() -> void:
	var scene := load("res://scenes/main.tscn").instantiate() as Node3D
	root.add_child(scene)
	var player := scene.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	var state = root.get_node("GameState")
	var ui = scene.get_node("DialogueUI")
	var keycard = scene.get_node("Interactables/Keycard") as Interactable
	var wine = scene.get_node("Interactables/WineGlass") as Interactable
	var terminal = scene.get_node("Interactables/Terminal") as Interactable
	var record = scene.get_node("Interactables/RecordPlayer") as Interactable
	var reader = scene.get_node("Interactables/AccessGate/Reader") as Interactable
	var barrier = scene.get_node("Interactables/AccessGate/Barrier")
	var probe := NoiseProbe.new()
	probe.add_to_group(&"hearing_listener")
	root.add_child(probe)
	await settle()

	check(state != null, "GameState 已注册")
	check(
		keycard != null and wine != null and terminal != null and record != null
		and reader != null and barrier != null,
		"五个交互物实例都在主场景里"
	)
	check(
		keycard.effects.size() == 2 and wine.effects.size() == 2 and terminal.effects.size() == 2
		and record.effects.size() == 2 and reader.effects.size() == 2,
		"每个交互物的效果资源都装配成功"
	)
	var standalone: Node = load("res://scenes/world/interactable.tscn").instantiate()
	check(standalone is Interactable, "interactable.tscn 可以独立实例化")
	standalone.free()

	# 输入守卫：范围外、其他按键、长按重复事件。
	check(not press_key(KEY_E), "远处按 E 不触发")
	check(not press_key(KEY_F), "其他按键不触发")

	stand_at(player, wine)
	await settle()
	check(wine.prompt.visible and wine.prompt.text == "E 查看 酒杯", "靠近后显示交互提示")
	check(press_key(KEY_E), "靠近按 E 触发")
	check(not press_key(KEY_E, true), "长按重复事件不触发")
	check(ui.dialogue_player != null, "查看酒杯打开对话")
	check(state.is_flag_set(&"saw_wine_clue"), "查看酒杯置位旗标")
	await settle()
	await settle()

	# 对话中不抢按键：终端不应被这次按键触发。
	stand_at(player, terminal)
	await settle()
	press_key(KEY_E)
	check(not terminal.has_interacted, "对话中按 E 不触发交互物")
	await finish_dialogue(ui)

	# 条件交互：缺门禁卡时读卡器拒绝，屏障保持关闭。
	stand_at(player, reader)
	await settle()
	check(reader.prompt.visible and reader.prompt.text == "需要门禁卡", "缺条件时显示阻断提示")
	check(press_key(KEY_E), "缺条件时仍消费按键")
	check(not barrier.is_open, "缺门禁卡时屏障不打开")
	check(not state.is_flag_set(&"arena_access"), "缺门禁卡时不置位通行旗标")

	# 拾取门禁卡。
	stand_at(player, keycard)
	await settle()
	check(keycard.prompt.text == "E 拾取 门禁卡", "拾取提示使用配置的动词")
	check(press_key(KEY_E), "按 E 拾取门禁卡")
	check(state.has_item(&"keycard") and state.get_item_count(&"keycard") == 1, "门禁卡写入物品栏")
	check(not keycard.visible, "拾取后交互物隐藏")
	check(not keycard.can_interact(player), "拾取后不再重复触发")

	# 满足条件后读卡器放行。
	stand_at(player, reader)
	await settle()
	check(reader.prompt.text == "E 刷卡 门禁读卡器", "满足条件后显示可交互提示")
	check(press_key(KEY_E), "持卡刷卡")
	check(barrier.is_open, "持卡后屏障打开")
	check(state.is_flag_set(&"arena_access"), "持卡后置位通行旗标")

	# 唱片机：可重复使用并发出声音事件。
	stand_at(player, record)
	await settle()
	check(press_key(KEY_E), "使用唱片机")
	await settle()
	check(probe.events.size() == 1 and probe.events[0].source == record, "唱片机发出声音事件")
	check(state.is_flag_set(&"music_playing"), "唱片机置位旗标")
	check(press_key(KEY_E), "唱片机可以重复使用")
	await settle()
	check(probe.events.size() == 2, "重复使用再次发出声音事件")

	# 终端：一次性交互。
	stand_at(player, terminal)
	await settle()
	check(press_key(KEY_E), "使用终端")
	check(state.is_flag_set(&"terminal_read"), "终端置位旗标")
	check(ui.dialogue_player != null, "终端打开信息对话")
	await finish_dialogue(ui)
	check(press_key(KEY_E), "已使用的一次性交互物仍消费按键")
	check(ui.dialogue_player == null, "一次性交互物不会再次打开对话")
	check(terminal.prompt.text == "终端已熄屏", "一次性交互物显示已使用提示")

	# 解耦验证：状态从 state_path 注入，效果不依赖 GameState 这个具体节点。
	var fake := FakeState.new()
	root.add_child(fake)
	var isolated := load("res://scenes/world/interactable.tscn").instantiate() as Interactable
	root.add_child(isolated)
	var effect := GiveItemEffect.new()
	effect.item_id = &"probe_item"
	effect.display_name = "测试物品"
	isolated.effects.append(effect)
	isolated.state_path = isolated.get_path_to(fake)
	await settle()
	check(isolated.interact(player), "自定义状态节点下仍可交互")
	check(fake.get_item_count(&"probe_item") == 1, "效果写入注入的状态节点")
	check(not state.has_item(&"probe_item"), "注入状态下不会写到 GameState")
	isolated.free()
	fake.free()

	probe.free()
	scene.free()
	print("Interactable checks finished; failures: ", failures)
	quit(1 if failures else 0)
