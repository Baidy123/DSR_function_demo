extends SceneTree

var failures: int = 0

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

func run_checks() -> void:
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	var player := scene.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	var npc := scene.get_node("NPC") as StaticBody3D
	var area := npc.get_node("InteractionArea") as Area3D
	await settle()
	check(InputMap.has_action("interact"), "交互输入已注册")
	check(not press_key(KEY_E), "远处按 E 不触发")
	player.position = npc.position + Vector3(-1.2, 0, 0)
	await settle()
	check(area.overlaps_body(player), "靠近后检测到玩家")
	check(not press_key(KEY_F), "其他按键不触发")
	check(press_key(KEY_E), "靠近按 E 触发")
	check(not press_key(KEY_E, true), "长按重复事件不触发")
	player.position = Vector3.ZERO
	await settle()
	check(not press_key(KEY_E), "离开后按 E 不触发")
	print("Interaction checks finished; failures: ", failures)
	quit(1 if failures else 0)
