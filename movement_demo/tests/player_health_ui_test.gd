extends RefCounted

# 在 Main 的独立运行中调用；发送真实鼠标事件，验证 GUI 与对话输入的先后顺序。
func run(scene: Node) -> Dictionary:
	var tree: SceneTree = scene.get_tree()
	var p = scene.get_node("Player")
	var h = p.get_node("Health")
	var ui = scene.get_node("DialogueUI")
	var state = tree.root.get_node("GameState")
	var checks := {}
	var stamina_bar = h.get_node_or_null("Status/Content/Stamina/Bar")
	checks["接入可见体力条"] = stamina_bar != null and stamina_bar.is_visible_in_tree()
	var status_rect: Rect2 = h.get_node("Status").get_global_rect()
	checks["双条集中在左下角"] = status_rect.position.x < 32.0 and status_rect.end.y > scene.get_viewport().get_visible_rect().size.y - 32.0 and status_rect.has_point(h.get_node("Status/Content/HealthBar").get_global_rect().get_center())
	if stamina_bar == null:
		return checks
	state.help_choice = ""
	state.talked_to_a = false
	await ui.open_dialogue(p, load("res://resources/dialogue/npc_b.dialogue"), "start")
	for frame in range(2):
		await tree.process_frame
	checks["对话时状态条不遮挡正文"] = not h.get_node("Status").visible
	await _click(tree, h.get_node("Debug/Controls/Invincible"))
	checks["普通对话中可以开启无敌"] = h.is_invincible() and ui.dialogue_player == p
	await _click(tree, h.get_node("Debug/Controls/Damage"))
	checks["无敌下点击伤害不扣血也不推进对话"] = h.health == 100.0 and ui.dialogue_player == p
	await _click(tree, h.get_node("Debug/Controls/Invincible"))
	await _click(tree, h.get_node("Debug/Controls/Damage"))
	checks["关闭无敌后按钮扣血且不推进对话"] = h.health == 75.0 and ui.dialogue_player == p
	checks["生命条同步实际扣血"] = h.get_node("Status/Content/HealthBar").value == 75.0
	await _click(tree, ui.dialogue_text)
	checks["点击普通对话仍可推进"] = ui.dialogue_player == null
	await ui.open_dialogue(p, load("res://resources/dialogue/npc_b.dialogue"), "start")
	var key := InputEventAction.new()
	key.action = "interact"
	key.pressed = true
	Input.parse_input_event(key)
	await tree.process_frame
	key.pressed = false
	Input.parse_input_event(key)
	checks["E仍可推进对话"] = ui.dialogue_player == null
	await ui.open_dialogue(p, load("res://resources/dialogue/npc_a.dialogue"), "start")
	for frame in range(3):
		await tree.process_frame
	await _click(tree, ui.choices.get_child(0))
	checks["对话选项仍可点击"] = state.help_choice == "accepted" and state.talked_to_a
	checks["选项同次点击不跳过下一句"] = ui.dialogue_player == p
	p.receive_hit(1000.0)
	checks["对话中死亡暂停对话输入"] = h.is_dead and tree.paused and not ui.can_process()
	await _click(tree, h.get_node("DeathScreen/Center/Panel/Content/Restart"))
	for frame in range(8):
		await tree.process_frame
	p = tree.current_scene.get_node("Player")
	checks["死亡按钮真实点击可重开"] = not tree.paused and not p.is_dead() and p.health.health == p.health.max_health
	checks["重开保留鼠标选中的对话结果"] = state.help_choice == "accepted" and state.talked_to_a
	checks["重开退出旧对话"] = not p.is_in_dialogue and tree.current_scene.get_node("DialogueUI").dialogue_player == null
	# 重开后仍能走路、奔跑和减速停下，不使用旧版瞬时移动断言。
	var start: Vector3 = p.global_position
	Input.action_press("move_up")
	for frame in range(30):
		await tree.physics_frame
	checks["重开后仍可移动"] = p.global_position.distance_to(start) > 0.5
	Input.action_press("sprint")
	for frame in range(30):
		await tree.physics_frame
	checks["重开后可奔跑并消耗耐力"] = p.is_sprinting and p.stamina < p.MAX_STAMINA
	stamina_bar = p.health.get_node("Status/Content/Stamina/Bar")
	checks["体力条跟随奔跑消耗"] = stamina_bar.value < stamina_bar.max_value and absf(stamina_bar.value - p.stamina) < 2.0
	Input.action_release("move_up")
	Input.action_release("sprint")
	for frame in range(30):
		await tree.physics_frame
	checks["松键仍减速停止"] = is_zero_approx(p.current_speed)
	for frame in range(60):
		await tree.physics_frame
	checks["体力条跟随恢复到满"] = is_equal_approx(stamina_bar.value, p.MAX_STAMINA)
	return checks


func _click(tree: SceneTree, control: Control) -> void:
	# 等待刚显示的容器完成布局，再读取实际点击位置。
	for frame in range(2):
		await tree.process_frame
	var point: Vector2 = control.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	Input.parse_input_event(motion)
	await tree.process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await tree.process_frame
