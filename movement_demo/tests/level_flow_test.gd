extends SceneTree

## 使用真实保存关卡、真实死亡和 GUI 鼠标事件；不伪造 encounter_completed。
const Flow = preload("res://scripts/systems/level_flow.gd")
const GuideScene = preload("res://scenes/ui/play_guide.tscn")
const Director = preload("res://scripts/systems/scene_director.gd")
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
	check(ProjectSettings.get_setting("application/run/main_scene") == Flow.LEVELS[0], "默认主入口是第1关")
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
		check(player.position == before and player.stamina == stamina_before and combat.ammo.magazine_rounds == rounds_before and not combat.ammo.is_reloading and not combat.is_melee_active(), "第%d关阅读时不移动、不耗体力、不换弹或攻击" % number)
		for key in [KEY_W, KEY_2, KEY_R, KEY_V, KEY_H]: _key(key, false)
		if number == 1:
			await _screenshot("guide_1152.png")
			root.size = Vector2i(640, 480)
			root.content_scale_size = root.size
			await process_frame
			await process_frame
			var button: Button = guide.get_node("Backdrop/Panel/Content/Close")
			check(Rect2(Vector2.ZERO, Vector2(root.size)).encloses(button.get_global_rect()), "640×480窗口关闭按钮完整可见")
			var body: RichTextLabel = guide.get_node("Backdrop/Panel/Content/Body")
			body.scroll_to_line(body.get_line_count() - 1)
			await process_frame
			check(body.get_v_scroll_bar().value > 0.0, "小窗口可以滚动到说明末尾")
			await _screenshot("guide_640.png")
			root.size = Vector2i(1152, 720)
			root.content_scale_size = root.size
			await process_frame
		await _click(guide.get_node("Backdrop/Panel/Content/Close"))
		if guide.visible or paused or combat.ammo.magazine_rounds != rounds_before:
			print("CLOSE DIAGNOSTIC: ", number, " visible=", guide.visible, " paused=", paused, " director=", scene.get_node("SceneDirector").director.debug_snapshot(), " ammo=", combat.ammo.magazine_rounds, "/", rounds_before, " button=", guide.get_node("Backdrop/Panel/Content/Close").get_global_rect(), " viewport=", root.get_visible_rect())
		check(not guide.visible and not paused and combat.ammo.magazine_rounds == rounds_before, "第%d关真实关闭按钮恢复游玩且不误开火" % number)
		if number == 2:
			health.debug_mode = false
			health.receive_hit(health.max_health)
			check(health.is_dead and paused, "真实死亡显示暂停界面")
			await _click(health.get_node("DeathScreen/Center/Panel/Content/Restart"))
			check(current_scene != scene and current_scene.scene_file_path == Flow.LEVELS[1], "死亡按钮只重开当前第2关")
			scene = current_scene
			guide = scene.get_node("LevelFlow/PlayGuide")
			check(guide.visible and paused, "死亡重开后重新显示说明")
			await _click(guide.get_node("Backdrop/Panel/Content/Close"))
			health = scene.get_node("Player/Health")
		# 只修改测试实例：无敌防止测试清波过程中玩家被杀，时间加速缩短保存的波间等待。
		# 每名敌人仍通过真实受伤／死亡受理，原控制器自行判断所有波次全灭。
		health.debug_mode = true
		Engine.time_scale = 8.0
		var result: ColorRect = scene.get_node("LevelFlow/Result")
		for frame in range(1800):
			if result.visible: break
			var movement := [&"move_right", &"move_down", &"move_left", &"move_up"]
			var blocked: bool = scene.get_node("SceneDirector").debug_snapshot().state == "BLOCKED"
			for index in range(movement.size()):
				if blocked and index == (frame / 90) % movement.size(): Input.action_press(movement[index])
				else: Input.action_release(movement[index])
			for enemy in scene.enemies.duplicate():
				if is_instance_valid(enemy) and not enemy.is_dead:
					enemy.receive_hit(100000.0, scene.get_node("Player").global_position)
			await physics_frame
			await process_frame
		for action in [&"move_right", &"move_down", &"move_left", &"move_up"]: Input.action_release(action)
		Engine.time_scale = 1.0
		check(result.visible and paused, "第%d关全部真实波次死亡后显示过关按钮并暂停" % number)
		if not result.visible:
			print(scene.get_node("SceneDirector").debug_snapshot())
			break
		for frame in range(5): await process_frame
		check(current_scene == scene, "第%d关等待按钮点击，不自动切关" % number)
		if number == 5:
			check(scene.get_node("LevelFlow/Result/Center/Panel/Content/Title").text == "五关挑战完成", "第5关显示通关")
			await _screenshot("completed.png")
		await _click(scene.get_node("LevelFlow/Result/Center/Panel/Content/Continue"))
	check(current_scene.scene_file_path == Flow.LEVELS[0] and paused and current_scene.get_node("LevelFlow/PlayGuide").visible, "通关后真实按钮从第1关重玩")
	current_scene.free()
	current_scene = null
	await process_frame
	check(not paused, "说明打开时卸载场景不遗留暂停")
	paused = true
	var guide_host := Node.new()
	root.add_child(guide_host)
	var guide = GuideScene.instantiate()
	guide_host.add_child(guide)
	var director := Director.new()
	director.configure(guide_host, {"guide": guide})
	guide_host.add_child(director)
	await process_frame
	check(guide.visible and director.is_guide_pending(guide), "独立说明由调度器显式启动")
	await _click(guide.get_node("Backdrop/Panel/Content/Close"))
	check(not guide.visible and not director.is_guide_pending(guide), "独立说明完成通知调度器")
	check(paused, "说明关闭保留原本已经存在的暂停")
	guide_host.free()
	check(paused, "独立调度器退出不解除外部暂停")
	paused = false
	print("LEVEL FLOW: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)


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
	# 控件矩形是视口坐标；使用本地 GUI 事件，避免 canvas_items 的窗口缩放二次变换。
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


func check(condition: bool, message: String) -> void:
	checks += 1
	if condition: print("PASS ", message)
	else:
		failures += 1
		print("FAIL ", message)
