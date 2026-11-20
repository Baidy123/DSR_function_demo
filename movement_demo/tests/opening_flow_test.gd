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
	create_timer(55.0, true, false, true).timeout.connect(func() -> void:
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
	var cameras: Array[String] = []
	var state := root.get_node("GameState")
	check(await _wait_for(func(): return ui.dialogue_panel.visible), "the arrival dialogue opens on load")
	check(not ui.portrait.visible, "the player has no portrait during the opening monologue")
	check(ui.has_node("DialoguePanel/MarginContainer/Content/Transcript/History") and ui.has_node("Portrait"),
		"the scrollable transcript and the external portrait are separate nodes")
	check(Director.for_node(player) != null and player.is_in_dialogue
		and player.get_node("Equipment").active_slot == -1, "outdoor director locks the unarmed player")
	check(player.get_node("Health").max_health == 100.0 and player.get_node("Health").health == 100.0,
		"F5 exterior starts with 100 health")
	await _capture("arrival")
	check(await _dialogue(ui), "arrival dialogue finishes by clicking")
	check(ui.history.get_child_count() > 3 and ui.history.get_child(0).get_child_count() == 1
		and ui.history.get_child(0).get_child(0).text.begins_with("主角坐在"),
		"stage directions are present, while the scene-description paragraph is omitted")
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
	ui.camera_cue_started.connect(func(cue: String) -> void:
		check(not ui.choices.visible and not ui.skip_followup.visible, "choices are hidden during camera cue " + cue)
		cameras.append(cue))
	var portal := current_scene.get_node("Interactables/LevelPortal") as Interactable
	var curtain := current_scene.get_node("BarEnvironment/Booths/Booth4/Curtain") as Node3D
	var commissioner := current_scene.get_node("NPC") as Node3D
	var merchant := current_scene.get_node("RewardNPC") as Node3D
	var merchant_seat := current_scene.get_node("BarEnvironment/SouthLounge/Tables/Setting1/NorthSofa/Seats/Center") as TavernSeat
	var seated_cues: Array[String] = []
	var presentation := player.get_node("PlayerPresentation")
	var seat_motion := {
		"last": player.global_position, "steps": 0, "largest_step": 0.0,
		"walking_animation": false, "lowering_animation": false,
	}
	var sample_seat_motion := func() -> void:
		if not is_instance_valid(player) or not is_instance_valid(ui):
			return
		var position: Vector3 = player.global_position
		if ui.is_loading and ui.dialogue_line != null and not ui.dialogue_line.get_tag_value("sit").is_empty():
			var step: float = position.distance_to(seat_motion.last)
			seat_motion.steps += int(step > 0.001)
			seat_motion.largest_step = maxf(seat_motion.largest_step, step)
			var base: StringName = presentation.state.base_state()
			seat_motion.walking_animation = seat_motion.walking_animation or base == &"move"
			seat_motion.lowering_animation = seat_motion.lowering_animation \
				or (base == &"crouch_enter" and player.crouch_amount > 0.05 and player.crouch_amount < 0.95)
		seat_motion.last = position
	physics_frame.connect(sample_seat_motion)
	ui.scripted_seat_assigned.connect(func(cue: String) -> void:
		sample_seat_motion.call()
		check(seat_motion.steps >= 8 and seat_motion.largest_step <= 0.16
			and seat_motion.walking_animation and seat_motion.lowering_animation,
			"dialogue seating travels and lowers over consecutive physics frames for " + cue)
		seat_motion.steps = 0
		seat_motion.largest_step = 0.0
		seat_motion.walking_animation = false
		seat_motion.lowering_animation = false
		var seat: TavernSeat = player.current_seat()
		var actor_facing: Vector3 = -player.global_basis.z
		var seat_facing: Vector3 = -seat.global_basis.z
		check(seat.occupant() == player and player.is_crouching()
			and Vector2(actor_facing.x, actor_facing.z).normalized().dot(Vector2(seat_facing.x, seat_facing.z).normalized()) > 0.999,
			"dialogue script seats the player at the fixed heading for " + cue)
		seated_cues.append(cue))
	check(Director.for_node(player) != null, "tavern has its own director")
	check(current_scene.get_node("BarEnvironment").scene_file_path.is_empty(),
		"the tavern environment is authored inline in Main")
	check(curtain.to_local(commissioner.global_position).z < -1.0, "commissioner sits behind the northeast curtain")
	check(merchant_seat.occupant() == merchant, "merchant occupies the left lounge seat")
	check(merchant_seat.get_node_or_null(merchant_seat.initial_occupant_path) == merchant
		and current_scene.get_node("BarEnvironment/Tables/Table1/Seats/East/SeatPoint").occupant() == current_scene.get_node("HallReader"),
		"occupied seats store their initial NPC assignments")
	var walker := current_scene.get_node("Walker") as TavernNPC
	check((commissioner as TavernNPC).special_npc and not walker.special_npc
		and merchant.get_script() == walker.get_script(), "ordinary and special NPCs share the same class")
	var seats := current_scene.get_node("BarEnvironment/Booths/Booth4/Seating/Seats")
	check(seats.get_child_count() == 7
		and current_scene.get_node("BarEnvironment/BarCounter/Stool1/SeatPoint").occupant() == current_scene.get_node("CounterPatron")
		and merchant_seat.get_parent().get_child_count() == 3,
		"stools, sofas and booth rows publish individual seat slots")
	var authored := (load("res://scenes/main.tscn") as PackedScene).instantiate()
	check(authored.get_node("NPC").position.is_equal_approx(commissioner.position)
		and authored.get_node("RewardNPC").position.is_equal_approx(merchant.position),
		"fixed seats keep the same position from scene file to gameplay")
	var new_seated := ["HallReader", "HallGuest", "EastGuest", "LoungeGuest", "CounterGuest"]
	check(new_seated.all(func(actor_name: String) -> bool:
		var actor := current_scene.get_node(actor_name) as TavernNPC
		return actor.current_seat() != null and actor.position.is_equal_approx(authored.get_node(actor_name).position)),
		"the five additional seated NPCs start in their authored positions")
	authored.free()
	check(not portal.enabled, "warehouse exit stays closed before delivery")
	check(not curtain.get_node("SolidCurtain/CollisionShape3D").disabled,
		"the curtain starts as an active physical barrier")
	var previous := walker.position
	await create_timer(0.3).timeout
	check(not walker.position.is_equal_approx(previous), "director starts tavern background activity")
	check(walker.collision_layer == 1 and walker.get_node("CollisionShape3D").shape is CapsuleShape3D,
		"main scene patrol actor has a solid capsule")
	await _go_to(walker.floor_position(Vector3(1.8, 0, -4.8)))
	check(await _wait_for(func(): return absf(walker.position.x - 1.8) > 0.4),
		"walker detours around the player blocking the route")
	check(await _wait_for(func(): return absf(walker.position.x - 1.8) < 0.2 and walker.position.z > -4.2),
		"walker rejoins the original route after the detour")

	await _go_to(opening._target)
	_interact()
	await _conversation(ui, "bartender", ["你这里是不是", "这么明显", "她好说话吗"])
	check(opening.phase == Opening.Phase.VISITOR, "bartender points to the curtain")
	check(cameras == ["booth"], "bartender guidance triggers the booth camera during the dialogue")
	await _go_to(opening._target)
	await _conversation(ui, "departing visitor", ["她把你赶出来了？"])
	var visitor := current_scene.get_node("Visitor") as CharacterBody3D
	check(opening.phase == Opening.Phase.CURTAIN and visitor.visible,
		"visitor remains visible while walking towards the exit")
	check(not curtain.passage_authorized and not curtain.get_node("SolidCurtain/CollisionShape3D").disabled,
		"the visitor's scripted exit leaves the curtain locked again")
	check(not state.get_flag("KNOWS_BIG_SIS_PRINCIPLE"), "the authored visitor replies do not reveal her principles")
	_interact()
	await _conversation(ui, "knocking at the curtain")
	check(await _wait_for(func(): return opening.phase == Opening.Phase.COMMISSIONER), "player crosses the curtain")
	_interact()
	check(await _wait_for(func(): return ui.dialogue_panel.visible), "speaking from inside opens the commission")
	check(await _dialogue(ui, ["你想去那个仓库", "去过，但", "为什么找我", "可我现在没钱", "你怎么知道", "有这么多人"]),
		"commissioner dialogue reaches agreement with optional branches")
	check(state.get_flag("FUNDING_DISCLOSED") and state.get_flag("ASKED_ACCESS_PATTERN")
		and state.get_flag("ASKED_ACCESS_SOCIAL"), "commissioner choices update funding and access flags")
	check(cameras == ["booth", "merchant"], "commissioner guidance triggers the merchant camera during the dialogue")
	check(state.help_choice == "accepted" and state.available_level == 1 and not portal.enabled,
		"commission registers the task while the door waits for gear")
	check(_verified_page_turn, "clicking a long line shows its next page before choices or a new line")
	check(seated_cues == ["commissioner"] and player.current_seat() == null,
		"commission dialogue controls sitting and then releases the player")
	Input.action_press("move_down")
	var left_booth := await _wait_for(func(): return curtain.to_local(player.global_position).z > 0.8)
	Input.action_release("move_down")
	check(left_booth, "player can walk out through the curtain after its scripted entry")

	var approach: Vector3 = opening._target
	var rail: Node3D = current_scene.get_node("BarEnvironment/SouthLounge/Enclosure/NorthWest")
	await _go_to(Vector3(approach.x, 0, rail.global_position.z - 0.4))
	_interact()
	check(not ui.dialogue_panel.visible and opening.phase == Opening.Phase.MERCHANT,
		"the rail blocks merchant interaction from the hall side")
	await _go_to(opening._target)
	_interact()
	await _conversation(ui, "merchant introduction", ["那我先看看"])
	check(seated_cues == ["commissioner", "merchant"] and player.current_seat() != null,
		"merchant dialogue seats the player through the catalog")
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
	check(player.current_seat() == null, "delivery finishes by releasing the scripted seat")
	physics_frame.disconnect(sample_seat_motion)
	var loadout: Dictionary = player.get_node("Equipment").campaign_snapshot()
	check(state.get_flag("opening_complete") and not player.is_in_dialogue
		and loadout.primary_weapon != null and loadout.secondary_weapon == null
		and loadout.reserve_ammo.get(&"smg", 0) == 60 and loadout.medkit_count == 1,
		"delivery grants exactly one weapon, reserve ammunition and a medkit")
	check(portal.enabled and portal.conditions_met(), "delivery unlocks the campaign portal")
	var runner := current_scene.get_node("Runner") as TavernNPC
	check(runner.visible and not runner.get_node("Crate").visible, "the runner leaves without the delivered crate")
	check(await _wait_for(func(): return not visitor.visible, 950)
		and visitor.global_position.distance_to(visitor.floor_position(Vector3(0.15, 0, 7.06))) < 0.2,
		"visitor disappears only after reaching the exit")
	check(await _wait_for(func(): return not runner.visible, 950)
		and runner.global_position.distance_to(runner.floor_position(runner.route_points().back())) < 0.2
		and runner.global_position.distance_to(current_scene.get_node("BarEnvironment/Architecture/StaffDoor").global_position) < 1.6,
		"runner leaves through the staff door")

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
	_press_action(&"interact")


func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	root.push_input(event)
	event = InputEventAction.new()
	event.action = action
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
			if ui.dialogue_line.character == "{大姐头名字}" and ui.dialogue_line.text.begins_with("出去右转"):
				check(ui.history.get_child_count() > 10 and ui.transcript.get_v_scroll_bar().visible
					and not ui.dialogue_panel.get_global_rect().intersects(ui.portrait.get_global_rect()),
					"long transcript can scroll and the portrait is outside the panel")
				await process_frame
				await process_frame
				var scroll := ui.transcript.get_v_scroll_bar() as VScrollBar
				check(scroll.value >= scroll.max_value - scroll.page - 1.0,
					"camera return reveals the latest line above the choices")
				await _capture("commissioner")
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


func _wait_for(condition: Callable, frames := 420) -> bool:
	for tick in frames:
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
