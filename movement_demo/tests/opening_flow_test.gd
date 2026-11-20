extends SceneTree

const EXTERIOR := "res://scenes/access_denied/hub/tavern_exterior.tscn"
const LEVEL := "res://scenes/world/levels/lvl_1.tscn"
const Opening = preload("res://scripts/world/opening_sequence.gd")
const Director = preload("res://scripts/systems/scene_director.gd")

var failures := 0
var checks := 0
var _verified_page_turn := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(38.0, true, false, true).timeout.connect(func() -> void:
		push_error("Opening watchdog expired")
		quit(1))
	check(ProjectSettings.get_setting("application/run/main_scene") == EXTERIOR, "F5 launches the exterior")
	var exterior := load(EXTERIOR) as PackedScene
	check(exterior != null, "exterior scene loads")
	if exterior == null:
		quit(1)
		return
	var scene := exterior.instantiate()
	root.add_child(scene)
	current_scene = scene
	var opening := scene.get_node("Opening")
	var player := scene.get_node("Player")
	var ui := scene.get_node("DialogueUI")
	var state := root.get_node("GameState")
	check(await _wait_for(func(): return ui.dialogue_panel.visible), "the arrival dialogue opens on load")
	check(Director.for_node(player) != null and player.is_in_dialogue
		and player.get_node("Equipment").active_slot == -1, "outdoor director locks the unarmed player")
	await _capture("arrival")
	check(await _dialogue(ui), "arrival dialogue finishes by clicking")
	check(await _wait_for(func(): return opening.phase == Opening.Phase.ENTER), "car exit and entrance camera finish")
	check(not player.is_in_dialogue and player.get_node("Visual").visible, "arrival restores movement")
	await _capture("exterior")
	await _go_to(opening._target)
	_interact()
	if not await _wait_for(func(): return current_scene != null and current_scene.name == "Main"):
		check(false, "entrance loads the tavern")
		quit(1)
		return
	check(true, "entrance loads the tavern")
	await physics_frame
	await physics_frame
	opening = current_scene.get_node("Opening")
	player = current_scene.get_node("Player")
	ui = current_scene.get_node("DialogueUI")
	var portal := current_scene.get_node("Interactables/LevelPortal") as Interactable
	var curtain := current_scene.get_node("BarEnvironment/Booths/Booth4/Curtain") as Node3D
	var commissioner := current_scene.get_node("NPC") as Node3D
	var merchant := current_scene.get_node("RewardNPC") as Node3D
	var merchant_seat := current_scene.get_node("BarEnvironment/SouthLounge/Tables/Setting1/NorthSofa") as Node3D
	check(Director.for_node(player) != null, "tavern has its own director")
	check(curtain.to_local(commissioner.global_position).z < -1.0, "commissioner sits behind the northeast curtain")
	check(merchant.global_position.distance_to(merchant_seat.global_position) < 0.4, "merchant occupies the left lounge seat")
	check(not portal.enabled, "warehouse exit stays closed before delivery")
	var walker := current_scene.get_node("TavernCast/Walker") as Node3D
	var previous := walker.position
	await create_timer(0.3).timeout
	check(not walker.position.is_equal_approx(previous), "director starts tavern background activity")

	await _go_to(opening._target)
	_interact()
	await _conversation(ui, "bartender", ["你这里是不是", "这么明显", "她好说话吗"])
	check(opening.phase == Opening.Phase.VISITOR, "bartender points to the curtain")
	await _go_to(opening._target)
	await _conversation(ui, "departing visitor", ["她怎么个轴法"])
	check(await _wait_for(func(): return opening.phase == Opening.Phase.CURTAIN), "visitor walks away")
	check(state.get_flag("KNOWS_BIG_SIS_PRINCIPLE"), "visitor follow-up records her principle")
	_interact()
	await _conversation(ui, "knocking at the curtain")
	check(await _wait_for(func(): return opening.phase == Opening.Phase.COMMISSIONER), "player crosses the curtain")
	_interact()
	check(await _wait_for(func(): return ui.dialogue_panel.visible), "speaking from inside opens the commission")
	await _capture("commissioner")
	check(await _dialogue(ui, ["你想去那个仓库", "去过，但", "为什么找我", "可我现在没钱", "你怎么知道", "有这么多人"]),
		"commissioner dialogue reaches agreement with optional branches")
	check(state.get_flag("FUNDING_DISCLOSED") and state.get_flag("ASKED_ACCESS_PATTERN")
		and state.get_flag("ASKED_ACCESS_SOCIAL"), "commissioner choices update funding and access flags")
	check(state.help_choice == "accepted" and state.available_level == 1 and not portal.enabled,
		"commission registers the task while the door waits for gear")
	check(_verified_page_turn, "clicking a long line shows its next page before choices or a new line")

	var approach: Vector3 = opening._target
	var rail: Node3D = current_scene.get_node("BarEnvironment/SouthLounge/Enclosure/NorthWest")
	await _go_to(Vector3(approach.x, 0, rail.global_position.z - 0.4))
	_interact()
	check(not ui.dialogue_panel.visible and opening.phase == Opening.Phase.MERCHANT,
		"the rail blocks merchant interaction from the hall side")
	await _go_to(opening._target)
	_interact()
	await _conversation(ui, "merchant introduction", ["那我先看看"])
	var board := current_scene.get_node("ShopBoard")
	var shop := current_scene.get_node("ShopController")
	check(await _wait_for(func(): return board.visible), "director opens the catalog")
	state.money = 1000
	check(not board.purchase_enabled(&"mind_access_device", -1)
		and not shop.purchase(&"mind_access_device", -1)
		and not state.get_flag("has_mind_access_device") and state.money == 1000,
		"first catalog enforces browse-only in UI and purchase handler")
	await _capture("catalog")
	board.close_button.pressed.emit()
	await _conversation(ui, "price reaction", ["到底为什么这么贵"])
	await _conversation(ui, "gear delivery")
	check(state.get_flag("ASKED_MERCHANT_SUPPLY"), "price follow-up records the supply explanation")
	check(await _wait_for(func(): return opening.phase == Opening.Phase.DEPART), "delivery restores free exploration")
	var loadout: Dictionary = player.get_node("Equipment").campaign_snapshot()
	check(state.get_flag("opening_complete") and not player.is_in_dialogue
		and loadout.primary_weapon != null and loadout.secondary_weapon == null
		and loadout.reserve_ammo.get(&"smg", 0) == 60 and loadout.medkit_count == 1,
		"delivery grants exactly one weapon, reserve ammunition and a medkit")
	check(portal.enabled and portal.conditions_met(), "delivery unlocks the campaign portal")

	await _go_to(Vector3(0, 0, 6.9))
	check(await _wait_for(func(): return portal.get_overlapping_bodies().has(player)), "door interaction area detects the player")
	_interact()
	if await _wait_for(func(): return current_scene != null and current_scene.scene_file_path == LEVEL):
		check(current_scene.get_node("Player/Equipment").campaign_snapshot() == loadout,
			"real first level receives the opening loadout")
	else:
		check(false, "warehouse door loads the real first level")
	print("Opening flow: %d checks, %d failed" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _go_to(point: Vector3) -> void:
	var player := current_scene.get_node("Player") as CharacterBody3D
	player.global_position = point
	player.reset_physics_interpolation()
	await physics_frame
	await physics_frame


func _interact() -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = &"interact"
	root.push_input(event)


func _click() -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = Vector2(8, 120)
	event.pressed = true
	root.push_input(event)
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	root.push_input(event)


func _conversation(ui: Node, label: String, options: Array[String] = []) -> void:
	if not await _wait_for(func(): return ui.dialogue_panel.visible):
		check(false, label + " starts")
		return
	check(await _dialogue(ui, options), label + " completes")


func _dialogue(ui: Node, options: Array[String] = []) -> bool:
	var remaining := options.duplicate()
	for step in 140:
		if not await _wait_for(func(): return not ui.is_loading):
			return false
		if not ui.dialogue_panel.visible:
			return remaining.is_empty()
		if ui.choices.visible:
			var pick: Button
			for button: Button in ui.choices.get_children():
				if button.disabled:
					continue
				if pick == null:
					pick = button
				if not remaining.is_empty() and remaining[0] in button.text:
					pick = button
					remaining.pop_front()
					break
			if pick == null:
				return false
			pick.pressed.emit()
		else:
			var line: DialogueLine = ui.dialogue_line
			var page: int = ui._page
			var has_next_page: bool = page < ui._pages.size() - 1
			_click()
			if has_next_page:
				_verified_page_turn = ui.dialogue_line == line and ui._page == page + 1
		await process_frame
	return false


func _wait_for(condition: Callable) -> bool:
	for tick in 420:
		if condition.call():
			return true
		await physics_frame
	return false


func _capture(label: String) -> void:
	if "--capture" not in OS.get_cmdline_user_args() or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var directory := "res://logs/opening-capture"
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label + ".png"))


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("PASS: ", label)
	else:
		failures += 1
		push_error(label)
