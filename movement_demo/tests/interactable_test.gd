extends SceneTree

## 场景交互物检查：输入守卫、条件、效果、实例结果与解耦注入。
## 运行：godot --headless --path movement_demo --script res://tests/interactable_test.gd

const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

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
	preload("res://tests/interaction_fixture.gd").attach(scene)
	root.add_child(scene)
	var player := scene.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	var state = root.get_node("GameState")
	var ui = scene.get_node("DialogueUI")
	var npc_a = scene.get_node("NPC")
	var quests = scene.get_node("QuestController")
	var portal = scene.get_node("Interactables/LevelPortal") as Interactable
	var wine = scene.get_node("Interactables/WineGlass") as Interactable
	var terminal = scene.get_node("Interactables/Terminal") as Interactable
	var record = scene.get_node("Interactables/RecordPlayer") as Interactable
	var probe := NoiseProbe.new()
	probe.add_to_group(&"hearing_listener")
	root.add_child(probe)
	await settle()

	check(state != null, "GameState 已注册")
	check(
		portal != null and wine != null and terminal != null and record != null,
		"四个保留交互物实例都在主场景里"
	)
	check(
		portal.effects.size() == 1 and wine.effects.size() == 2 and terminal.effects.size() == 2
		and record.effects.size() == 2,
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

	# 传送门条件：未接取 A 的任务时拒绝，接取后才允许进入。
	stand_at(player, portal)
	await settle()
	check(portal.prompt.visible and portal.prompt.text == "需要先接取 A 的任务", "未接任务时显示传送门阻断提示")
	check(press_key(KEY_E), "未接任务时仍消费按键")
	check(not portal.has_interacted, "未接任务时传送门不执行")

	await ui.open_dialogue(player, npc_a.dialogue_resource, "start")
	await settle()
	check(ui.dialogue_text.text.contains("第1关"), "A 的对话说明第1关目标")
	var refuse_index := _choice_index(ui, "暂时拒绝")
	check(refuse_index >= 0, "A 的任务提供拒绝选项")
	if refuse_index >= 0:
		ui.choices.get_child(refuse_index).pressed.emit()
		await settle()
		await settle()
	check(state.help_choice == "refused", "拒绝 A 后写入拒绝状态")
	ui._close_dialogue()
	await settle()

	await ui.open_dialogue(player, npc_a.dialogue_resource, "start")
	await settle()
	var reaccept_index := _choice_index(ui, "我改主意了")
	check(reaccept_index >= 0, "拒绝后 A 重新提供任务入口")
	if reaccept_index >= 0:
		ui.choices.get_child(reaccept_index).pressed.emit()
		await settle()
		await settle()
	check(state.help_choice == "accepted", "接受 A 的任务写入接取状态")
	check(quests.status_of(&"task_a") == QuestControllerScript.Status.IN_PROGRESS, "接受后任务进入进行中")
	ui._close_dialogue()
	await settle()

	stand_at(player, portal)
	await settle()
	check(portal.prompt.text == "E 进入 关卡1", "接取任务后传送门变为可进入")

	# 唱片机：接取任务前后都能操作，重复使用在开／关之间切换。
	stand_at(player, record)
	await settle()
	check(record.prompt.text == "E 使用 唱片机", "未接取任务时唱片机仍可交互")
	check(press_key(KEY_E), "使用唱片机")
	await settle()
	check(probe.events.size() == 1 and probe.events[0].source == record, "唱片机发出声音事件")
	check(state.is_flag_set(&"music_playing"), "唱片机第一次使用打开音乐")
	check(press_key(KEY_E), "唱片机可以重复使用")
	await settle()
	check(probe.events.size() == 2, "重复使用再次发出声音事件")
	check(not state.is_flag_set(&"music_playing"), "第二次使用回到关闭状态")

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


func _choice_index(ui, keyword: String) -> int:
	for index in ui.choices.get_child_count():
		if ui.choices.get_child(index).text.contains(keyword):
			return index
	return -1
