extends SceneTree

## 使用真实保存关卡、真实敌人死亡和 GUI 输入验证五关“返酒馆→A 解锁→传送门”。
const Flow = preload("res://scripts/systems/level_flow.gd")
const GuideScene = preload("res://scenes/ui/play_guide.tscn")
const QuestControllerScript = preload("res://scripts/systems/stage/quest_controller.gd")

var checks := 0
var failures := 0
var _capture := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_capture = "--capture" in OS.get_cmdline_user_args()
	var fullscreen_proof := "--fullscreen-proof" in OS.get_cmdline_user_args()
	if not fullscreen_proof:
		root.size = Vector2i(1152, 720)
		root.content_scale_size = root.size
	var game_state := root.get_node("GameState")
	game_state.help_choice = "accepted"
	game_state.task_a_returned = ""
	game_state.completed_level = 0
	game_state.available_level = 1
	game_state.pending_player_state = {}
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "默认主入口是酒馆")
	change_scene_to_file(Flow.LEVELS[0])
	await scene_changed
	await process_frame
	await process_frame
	var initial_guide := current_scene.get_node("LevelFlow/PlayGuide")
	check(initial_guide.get_node("Backdrop").size == root.get_visible_rect().size, "首次启动背景铺满视口，无需先调整窗口")
	check(root.get_visible_rect().encloses(initial_guide.get_node("Backdrop/Panel/Content/Close").get_global_rect()), "首次启动关闭按钮完整可见")
	if fullscreen_proof:
		check(root.mode == Window.MODE_FULLSCREEN or root.mode == Window.MODE_EXCLUSIVE_FULLSCREEN, "从全屏模式直接启动")
		await _screenshot("guide_initial_fullscreen.png")
		current_scene.free()
		current_scene = null
		print("LEVEL FLOW FULLSCREEN: %d/%d passed" % [checks - failures, checks])
		quit(1 if failures else 0)
		return

	for number in range(1, 6):
		var scene := current_scene
		check(scene.scene_file_path == Flow.LEVELS[number - 1], "按顺序进入第%d关" % number)
		if number == 2:
			var fallback: Environment = scene.get_world_3d().fallback_environment
			check(
				fallback != null
				and fallback.ambient_light_source == Environment.AMBIENT_SOURCE_DISABLED
				and fallback.reflected_light_source == Environment.REFLECTION_SOURCE_DISABLED,
				"传送后恢复中性默认渲染环境"
			)
		var guide = scene.get_node("LevelFlow/PlayGuide")
		var player = scene.get_node("Player")
		var combat = player.get_node("Combat")
		var health = player.get_node("Health")
		check(guide.visible and paused, "第%d关入场显示说明并暂停" % number)
		var before: Vector3 = player.position
		var stamina_before: float = player.stamina
		var rounds_before: int = combat.ammo.magazine_rounds
		_key(KEY_W, true)
		_key(KEY_2, true)
		_key(KEY_R, true)
		_key(KEY_V, true)
		_key(KEY_H, true)
		for frame in range(6): await physics_frame
		check(player.position == before and player.stamina == stamina_before
			and combat.ammo.magazine_rounds == rounds_before and not combat.ammo.is_reloading
			and not combat.is_melee_active(), "第%d关阅读时不移动、不耗体力、不换弹或攻击" % number)
		for key in [KEY_W, KEY_2, KEY_R, KEY_V, KEY_H]: _key(key, false)
		if number == 1:
			await _screenshot("guide_1152.png")
			root.size = Vector2i(640, 480)
			root.content_scale_size = root.size
			await process_frame
			await process_frame
			var close: Button = guide.get_node("Backdrop/Panel/Content/Close")
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(close.get_global_rect()), "640×480窗口关闭按钮完整可见")
			var body: RichTextLabel = guide.get_node("Backdrop/Panel/Content/Body")
			body.scroll_to_line(body.get_line_count() - 1)
			await process_frame
			check(body.get_v_scroll_bar().value > 0.0, "小窗口可以滚动到说明末尾")
			await _screenshot("guide_640.png")
			root.size = Vector2i(1152, 720)
			root.content_scale_size = root.size
			await process_frame
		await _click(guide.get_node("Backdrop/Panel/Content/Close"))
		check(not guide.visible and not paused and combat.ammo.magazine_rounds == rounds_before,
			"第%d关真实关闭按钮恢复游玩且不误开火" % number)

		if number == 2:
			health.debug_mode = false
			health.receive_hit(health.max_health)
			check(health.is_dead and paused, "第2关死亡显示暂停界面")
			await _click(health.get_node("DeathScreen/Center/Panel/Content/Restart"))
			check(current_scene != scene and current_scene.scene_file_path == Flow.LEVELS[1],
				"死亡按钮只重开当前第2关")
			scene = current_scene
			guide = scene.get_node("LevelFlow/PlayGuide")
			check(guide.visible and paused, "死亡重开后重新显示说明")
			await _click(guide.get_node("Backdrop/Panel/Content/Close"))
			health = scene.get_node("Player/Health")
			player = scene.get_node("Player")

		# 只修改测试实例：无敌防止清波时死亡，时间加速缩短保存的波间等待。
		health.debug_mode = true
		Engine.time_scale = 8.0
		var return_portal = scene.get_node("TavernReturnPortal") as Interactable
		for frame in range(1800):
			if return_portal.visible:
				break
			var movement := [&"move_right", &"move_down", &"move_left", &"move_up"]
			var blocked: bool = scene.get_node("EnemyWaves").debug_snapshot().state == "BLOCKED"
			for index in range(movement.size()):
				if blocked and index == (frame / 90) % movement.size():
					Input.action_press(movement[index])
				else:
					Input.action_release(movement[index])
			for enemy in scene.enemies.duplicate():
				if is_instance_valid(enemy) and not enemy.is_dead:
					enemy.receive_hit(100000.0, player.global_position)
			await physics_frame
			await process_frame
		for action in [&"move_right", &"move_down", &"move_left", &"move_up"]:
			Input.action_release(action)
		Engine.time_scale = 1.0
		check(return_portal.visible and return_portal.enabled and return_portal.monitoring,
			"第%d关真实清场后启用返回酒馆传送门" % number)
		check(not paused and not scene.get_node("LevelFlow/Result").visible,
			"第%d关不再弹出直接进入下一关面板" % number)
		if not return_portal.visible:
			print(scene.get_node("EnemyWaves").debug_snapshot())
			break
		check(return_portal.interact(player), "第%d关返回传送门可以交互" % number)
		var returned: Node = await _wait_for_scene("res://scenes/main.tscn")
		check(returned != null, "第%d关返回传送门加载酒馆" % number)
		if returned == null:
			break
		var quests = returned.get_node("QuestController")
		if number == 1:
			check(quests.status_of(&"task_a") == QuestControllerScript.Status.COMPLETED,
				"第1关返回后任务 A 完成")
		var main_player = returned.get_node("Player")
		var level_portal = returned.get_node("Interactables/LevelPortal")
		if number < 5:
			check(not level_portal.can_interact(main_player), "第%d关返回后门口保持锁定" % number)
			await _open_a(returned, main_player)
			await _choose(returned.get_node("DialogueUI"), "前往第%d关" % (number + 1))
			check(level_portal.can_interact(main_player), "A 交互后解锁第%d关" % (number + 1))
			returned.get_node("DialogueUI")._close_dialogue()
			await process_frame
			check(level_portal.interact(main_player), "门口传送门进入第%d关" % (number + 1))
			var next_scene: Node = await _wait_for_scene(Flow.LEVELS[number])
			check(next_scene != null, "门口传送门真实加载第%d关" % (number + 1))
			if next_scene == null:
				break
		else:
			check(not level_portal.can_interact(main_player), "第5关完成后不再解锁第6关")
			await _open_a(returned, main_player)
			var ui = returned.get_node("DialogueUI")
			check(ui.dialogue_text.text.contains("五关"), "第5关后 A 告知挑战完成")
			check(ui.choices.get_child_count() == 0, "第5关后没有下一关选项")
			ui._close_dialogue()
			await process_frame

	check(current_scene != null and current_scene.scene_file_path == "res://scenes/main.tscn",
		"五关流程最终停在酒馆")
	current_scene.free()
	current_scene = null
	await process_frame
	check(not paused, "说明打开时卸载场景不遗留暂停")
	paused = true
	var standalone_guide = GuideScene.instantiate()
	root.add_child(standalone_guide)
	await process_frame
	await _click(standalone_guide.get_node("Backdrop/Panel/Content/Close"))
	check(paused, "说明关闭保留原本已经存在的暂停")
	standalone_guide.free()
	paused = false
	print("LEVEL FLOW: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func _open_a(scene: Node, player: Node3D) -> void:
	var npc := scene.get_node("NPC")
	await scene.get_node("DialogueUI").open_dialogue(player, npc.dialogue_resource, "start")
	await process_frame


func _choose(ui, keyword: String) -> void:
	for child in ui.choices.get_children():
		if child.text.contains(keyword):
			child.pressed.emit()
			await process_frame
			await process_frame
			return
	push_error("对话缺少选项：" + keyword)


func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _click(button: Button) -> void:
	for frame in range(2): await process_frame
	var position := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = position
	motion.global_position = position
	root.push_input(motion, true)
	await process_frame
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = position
		event.global_position = position
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	for frame in range(4): await process_frame


func _screenshot(filename: String) -> void:
	if not _capture: return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://logs/play_guide_20261027/" + filename)


func _wait_for_scene(path: String) -> Node:
	for _frame in range(180):
		if is_instance_valid(current_scene) and current_scene.scene_file_path == path:
			await process_frame
			await process_frame
			return current_scene
		await process_frame
	return null


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition:
		print("PASS ", message)
	else:
		failures += 1
		print("FAIL ", message)
