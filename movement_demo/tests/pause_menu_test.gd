extends SceneTree

## 真实场景与 GUI 输入：暂停恢复、说明返回、独立暂停所有权及死亡优先。
const Director = preload("res://scripts/systems/scene_director.gd")
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")
const CAPTURE_DIR := "res://logs/pause-menu-capture/"
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	print("PASS " if value else "FAIL ", label)
	if not value: failures += 1

func _settle(frames: int = 3) -> void:
	for _frame in range(frames): await process_frame

func _key(echo: bool = false) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = KEY_ESCAPE
		event.physical_keycode = KEY_ESCAPE
		event.pressed = pressed
		event.echo = echo and pressed
		root.push_input(event, true)
	await _settle()

func _click(button: Button) -> void:
	await _settle(2)
	var point := button.get_global_rect().get_center()
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
		root.push_input(event, true)
		await process_frame
	await _settle()

func _capture(name: String) -> void:
	if not OS.get_cmdline_user_args().has("--capture"): return
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	root.get_texture().get_image().save_png(CAPTURE_DIR + name + ".png")

func _run() -> void:
	var settings := root.get_node("UserSettings")
	var test_config := OS.get_temp_dir().path_join("dsr-pause-menu-%d.cfg" % OS.get_process_id())
	settings.config_path = test_config
	root.size = Vector2i(1152, 720)
	root.content_scale_size = root.size
	for path in ["res://scenes/main.tscn", "res://scenes/world/levels/lvl_1.tscn",
			"res://scenes/world/levels/lvl_2.tscn", "res://scenes/world/levels/lvl_3.tscn",
			"res://scenes/world/levels/lvl_4.tscn", "res://scenes/world/levels/lvl_5.tscn"]:
		var scene = load(path).instantiate()
		root.add_child(scene)
		current_scene = scene
		await _settle()
		var director = Director.for_node(scene)
		check(director.state == &"running" and not paused, "入场直接游玩，不自动弹说明：" + path)
		var menu = director.get_node_or_null("PauseMenu")
		check(menu != null, "共享入口提供暂停菜单：" + path)
		if menu != null:
			await _key()
			check(menu.visible and paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
				"Esc 打开菜单并暂停：" + path)
			if OS.get_cmdline_user_args().has("--confirm-exit"):
				await _click(menu.get_node("Backdrop/Center/Panel/Content/Main/Exit"))
				check(menu.get_node("Backdrop/Center/Panel/Content/Quit").visible and paused,
					"确认前进程保持运行并显示退出确认")
				print("PAUSE MENU: confirming exit")
				await _click(menu.get_node("Backdrop/Center/Panel/Content/Quit/Confirm"))
				check(false, "确认退出后进程应结束")
				quit(1)
				return
			if path == "res://scenes/main.tscn": await _exercise_menu(scene, menu)
			else:
				await _key()
				check(not menu.visible and not paused, "Esc 恢复关卡：" + path)
				if path.ends_with("lvl_1.tscn"):
					var combat: Node = scene.get_node("Player/Combat")
					check(combat.get_aim_control() == 2,
						"第一关继承酒馆中选择的鼠标瞄准")
					if settings.has_method(&"commit_aim_control"):
						settings.commit_aim_control(1)
					await _exercise_aim_pause(scene, menu)
				if path.ends_with("lvl_5.tscn"): await _key()
		scene.free()
		current_scene = null
		await _settle()
		check(not paused, "场景卸载释放自己的暂停：" + path)
	if FileAccess.file_exists(test_config):
		DirAccess.remove_absolute(test_config)
	print("PAUSE MENU: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _exercise_aim_pause(scene: Node, menu: CanvasLayer) -> void:
	var combat := scene.get_node("Player/Combat")
	scene.get_node("Player/Health").debug_mode = true
	Input.action_press(&"aim")
	for _frame in range(4): await physics_frame
	check(combat.can_combat() and combat.is_aiming, "真实第一关可战斗且右键瞄准")
	# headless 的 DisplayServer 固定返回可见模式；真实捕获在渲染进程验证。
	var rendered := DisplayServer.get_name() != "headless"
	if rendered:
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "真实窗口瞄准捕获鼠标")
	var rounds: int = combat.ammo.magazine_rounds
	await _key()
	check(menu.visible and paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE,
		"瞄准中暂停释放鼠标供菜单使用")
	await _click(menu.get_node("Backdrop/Center/Panel/Content/Main/Resume"))
	for _frame in range(4): await physics_frame
	check(not menu.visible and not paused and combat.is_aiming
		and root.gui_get_focus_owner() == null and combat.ammo.magazine_rounds == rounds,
		"按住瞄准时继续游戏恢复瞄准、释放焦点且按钮不误开火")
	if rendered:
		check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "真实窗口继续游戏恢复鼠标捕获")
	Input.action_release(&"aim")
	for _frame in range(3): await physics_frame
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "松开瞄准后正常释放鼠标")

func _exercise_menu(scene: Node, menu: CanvasLayer) -> void:
	var content := menu.get_node("Backdrop/Center/Panel/Content")
	var main := content.get_node("Main")
	var settings := content.get_node("Settings")
	var confirmation := content.get_node("Quit")
	var guide := menu.get_node("PlayGuide")
	var player := scene.get_node("Player")
	var combat := player.get_node("Combat")
	var position: Vector3 = player.position
	var rounds: int = combat.ammo.magazine_rounds
	Input.action_press(&"move_up")
	Input.action_press(&"fire")
	for _frame in range(5): await physics_frame
	check(player.position == position and combat.ammo.magazine_rounds == rounds, "暂停冻结玩家动作和弹药")
	Input.action_release(&"move_up")
	Input.action_release(&"fire")
	await _key(true)
	check(menu.visible and paused, "长按 Esc 的重复事件不会关闭菜单")
	await _capture("01-pause")
	await _click(main.get_node("Settings"))
	check(settings.visible and not main.visible and paused, "设置子页保持暂停")
	var categories := settings.get_node("Categories") as TabContainer
	categories.current_tab = 1
	var aim_choice := settings.get_node_or_null("Categories/CombatSettings/AimControl/Choice") as OptionButton
	check(aim_choice != null and aim_choice.item_count == 2, "设置提供两种全局瞄准方式")
	if aim_choice != null:
		aim_choice.select(aim_choice.get_item_index(1))
		aim_choice.item_selected.emit(aim_choice.selected)
		check(combat.get_aim_control() == 1 and paused, "设置应用自动锁定且保持暂停")
		aim_choice.select(aim_choice.get_item_index(2))
		aim_choice.item_selected.emit(aim_choice.selected)
		check(combat.get_aim_control() == 2 and paused, "设置应用鼠标瞄准且保持暂停")
	await _capture("02-settings")
	await _key()
	check(main.visible and paused, "设置页 Esc 返回暂停菜单")
	var guide_button := main.get_node_or_null("Guide") as Button
	check(guide_button != null, "暂停首页提供操作说明入口")
	if guide_button == null: return
	await _click(guide_button)
	check(guide.visible and paused, "暂停首页手动打开操作说明")
	await _capture("03-guide")
	await _click(guide.get_node("Backdrop/Panel/Content/Close"))
	check(not guide.visible and main.visible and paused, "关闭说明返回暂停首页，保持暂停")
	await _click(guide_button)
	await _key()
	check(not guide.visible and main.visible and paused, "说明页 Esc 返回暂停首页")
	await _click(main.get_node("Exit"))
	check(confirmation.visible and paused, "退出前显示确认并保持暂停")
	await _key()
	check(main.visible and paused, "Esc 取消退出并返回菜单")
	root.size = Vector2i(640, 480)
	root.content_scale_size = root.size
	await _settle()
	check(root.get_visible_rect().encloses(main.get_node("Resume").get_global_rect())
		and root.get_visible_rect().encloses(main.get_node("Exit").get_global_rect()), "640×480 主菜单按钮完整可见")
	await _capture("04-small-window")
	await _click(main.get_node("Resume"))
	check(not menu.visible and not paused and combat.ammo.magazine_rounds == rounds, "继续按钮恢复游戏且不误开火")
	var owner := Node.new()
	scene.add_child(owner)
	await _key()
	var ledger = Pauses.for_tree(self)
	var other: int = ledger.acquire(owner, &"other", true)
	await _click(main.get_node("Resume"))
	check(not menu.visible and paused, "继续游戏只释放菜单自己的暂停")
	await _key()
	check(not menu.visible and paused, "其他界面暂停时 Esc 不叠菜单")
	ledger.release(other)
	check(not paused, "最后一个暂停拥有者释放后恢复")
	var ui := scene.get_node("DialogueUI")
	await ui.open_dialogue(player, load("res://resources/dialogue/wine_glass.dialogue"), "start")
	await _key()
	check(not menu.visible and player.is_in_dialogue, "对话期间 Esc 不叠菜单")
	ui._close_dialogue()
	await _settle()
	await _key()
	await _click(guide_button)
	var health := player.get_node("Health")
	health.debug_mode = false
	health.receive_hit(health.max_health)
	await _settle()
	check(not menu.visible and not guide.visible and paused, "死亡中断说明和菜单，保留死亡暂停")
	await _key()
	check(not menu.visible and paused and health.is_dead, "死亡界面 Esc 不会恢复战斗")
