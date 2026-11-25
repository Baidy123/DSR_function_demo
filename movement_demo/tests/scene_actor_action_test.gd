extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const NpcScene = preload("res://scenes/access_denied/hub/tavern_npc.tscn")
const Door = preload("res://scripts/world/range_door.gd")

var failures := 0

class FinishProvider extends Node:
	var calls := 0

	func begin_scene_action(request: SceneRequest) -> void:
		calls += 1
		request.complete()

	func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void:
		pass

class StateProbe extends Node:
	var flags: Dictionary = {}
	func set_flag(key: StringName, value: bool = true) -> void: flags[key] = value

class QuestProbe extends Node:
	signal quest_changed(id: StringName, previous: int, current: int)
	var statuses: Dictionary = {}
	func apply_status(id: StringName, value: int) -> void:
		var previous := int(statuses.get(id, 0))
		if previous == value: return
		statuses[id] = value
		quest_changed.emit(id, previous, value)
	func accept(id: StringName) -> void: apply_status(id, 1)
	func refuse(id: StringName) -> void: apply_status(id, 2)
	func complete(id: StringName) -> void: apply_status(id, 3)
	func fail(id: StringName) -> void: apply_status(id, 4)
	func set_status(id: StringName, value: int) -> void: apply_status(id, value)

class ProviderProbe extends Node:
	var begins := 0
	var parameters: Dictionary = {}
	func begin_scene_action(request: SceneRequest) -> void:
		begins += 1
		parameters = request.parameters.duplicate(true)
		request.complete()
	func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void: pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var f := await _fixture()
	await _test_move_and_route(f)
	await _test_seat_and_visibility(f)
	await _test_cancel_and_patrol(f)
	await _test_world_and_state_actions(f)
	f.scene.free()
	await process_frame
	print("Scene actor actions: %d failures" % failures)
	quit(1 if failures else 0)


func _fixture() -> Dictionary:
	var scene := Node3D.new()
	root.add_child(scene)
	var npc := NpcScene.instantiate() as TavernNPC
	npc.name = "NPC"
	npc.walk_speed = 8.0
	npc.waypoint_pause = 0.0
	scene.add_child(npc)
	var director = Director.new()
	director.configure(scene, {"scene_root": scene})
	scene.add_child(director)
	director.initialize()
	await process_frame
	return {"scene": scene, "npc": npc, "director": director}


func _context(f: Dictionary, action: SceneAction, id: StringName) -> SceneActionContext:
	var definition := SceneEventDefinition.new()
	definition.event_id = id
	return SceneActionContext.new().configure(f.director, f.scene, definition, action, 1, 0)


func _wait_terminal(context: SceneActionContext, frames := 240) -> bool:
	for _frame in range(frames):
		if context.is_terminal():
			return true
		await physics_frame
	return context.is_terminal()


func _test_move_and_route(f: Dictionary) -> void:
	var target := Marker3D.new()
	target.name = "Target"
	target.position = Vector3(1.0, 0.0, 0.0)
	f.scene.add_child(target)
	var original_route: Array[Vector3] = [Vector3(9.0, 0.0, 9.0)]
	f.npc.route = original_route.duplicate()
	var move := MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.target_path = ^"Target"
	move.speed_override = 6.0
	var context := _context(f, move, &"move_target")
	move.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed",
		"MoveActorAction reaches one authored Marker3D")
	check(f.npc.global_position.distance_to(target.global_position) < 0.2 \
		and f.npc.route == original_route and is_equal_approx(f.npc.walk_speed, 8.0),
		"explicit movement does not mutate the NPC route and restores speed")

	var route := TavernRoute.new()
	route.name = "Route"
	for item in [["First", Vector3(1.0, 0.0, 1.0)], ["Second", Vector3(2.0, 0.0, 1.0)]]:
		var marker := Marker3D.new()
		marker.name = item[0]
		marker.position = item[1]
		route.add_child(marker)
	f.scene.add_child(route)
	f.npc.global_position = Vector3.ZERO
	move = MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.route_path = ^"Route"
	context = _context(f, move, &"move_route")
	move.begin(context)
	var saw_first := false
	for _frame in range(240):
		saw_first = saw_first or f.npc.global_position.distance_to(route.get_node("First").global_position) < 0.2
		if context.is_terminal(): break
		await physics_frame
	check(context.status == &"completed" and saw_first \
		and f.npc.global_position.distance_to(route.get_node("Second").global_position) < 0.2,
		"MoveActorAction traverses TavernRoute markers in child order")

	var exit_route := TavernRoute.new()
	exit_route.name = "ExitRoute"
	exit_route.finish_mode = TavernRoute.Finish.DESPAWN
	var exit_marker := Marker3D.new()
	exit_marker.position = Vector3(2.4, 0.0, 1.0)
	exit_route.add_child(exit_marker)
	f.scene.add_child(exit_route)
	move = MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.route_path = ^"ExitRoute"
	context = _context(f, move, &"move_exit_route")
	move.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" and not f.npc.visible,
		"MoveActorAction preserves the TavernRoute DESPAWN finish mode by default")
	f.npc.set_physical_presence(true)

	var loop_route := TavernRoute.new()
	loop_route.name = "LoopRoute"
	loop_route.finish_mode = TavernRoute.Finish.LOOP
	var loop_marker := Marker3D.new()
	loop_marker.position = Vector3(2.7, 0.0, 1.0)
	loop_route.add_child(loop_marker)
	f.scene.add_child(loop_route)
	move = MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.route_path = ^"LoopRoute"
	move.vanish_at_end = true
	context = _context(f, move, &"force_vanish_loop_route")
	move.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" and not f.npc.visible,
		"explicit vanish_at_end overrides a TavernRoute LOOP finish mode")
	f.npc.set_physical_presence(true)

	var paused_target := Marker3D.new()
	paused_target.name = "PausedTarget"
	paused_target.position = Vector3(3.0, 0.0, 1.0)
	f.scene.add_child(paused_target)
	move = MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.target_path = ^"PausedTarget"
	move.process_while_paused = true
	context = _context(f, move, &"move_during_camera")
	move.begin(context)
	paused = true
	check(await _wait_terminal(context) and context.status == &"completed" \
		and f.npc.global_position.distance_to(paused_target.global_position) < 0.2,
		"MoveActorAction can keep directed NPC motion running during a paused camera")
	paused = false
	check(f.npc.process_mode == Node.PROCESS_MODE_INHERIT,
		"paused directed movement restores the NPC process mode")

	var empty := TavernRoute.new()
	empty.name = "EmptyRoute"
	f.scene.add_child(empty)
	move = MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.route_path = ^"EmptyRoute"
	context = _context(f, move, &"empty_route")
	move.begin(context)
	check(context.status == &"failed", "MoveActorAction rejects an empty route")
	move.route_path = ^"MissingRoute"
	context = _context(f, move, &"missing_route")
	move.begin(context)
	check(context.status == &"failed", "MoveActorAction rejects a missing route")


func _test_seat_and_visibility(f: Dictionary) -> void:
	var seat := TavernSeat.new()
	seat.name = "Seat"
	seat.position = f.npc.position + Vector3(0.4, 0.0, 0.0)
	f.scene.add_child(seat)
	await process_frame
	var seating := SeatActorAction.new()
	seating.actor_path = ^"NPC"
	seating.seat_path = ^"Seat"
	seating.mode = SeatActorAction.Mode.SIT
	var context := _context(f, seating, &"sit")
	seating.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" \
		and f.npc.current_seat() == seat, "SeatActorAction seats a TavernNPC through TavernSeat")
	var other_seat := TavernSeat.new()
	other_seat.name = "OtherSeat"
	other_seat.position = seat.position + Vector3(0.3, 0.0, 0.0)
	f.scene.add_child(other_seat)
	await process_frame
	seating = SeatActorAction.new()
	seating.actor_path = ^"NPC"
	seating.seat_path = ^"OtherSeat"
	seating.mode = SeatActorAction.Mode.LEAVE
	context = _context(f, seating, &"leave")
	seating.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" \
		and f.npc.current_seat() == null,
		"SeatActorAction releases the actor's actual seat even when the authored fallback differs")

	var visibility := SetActorVisibleAction.new()
	visibility.actor_path = ^"NPC"
	visibility.visible = false
	context = _context(f, visibility, &"hide")
	visibility.begin(context)
	check(context.status == &"completed" and not f.npc.visible and f.npc.collision_layer == 0,
		"SetActorVisibleAction hides physical presence")
	visibility.visible = true
	context = _context(f, visibility, &"show")
	visibility.begin(context)
	check(context.status == &"completed" and f.npc.visible and f.npc.collision_layer != 0,
		"SetActorVisibleAction restores physical presence")


func _test_cancel_and_patrol(f: Dictionary) -> void:
	var gate := TavernStaffDoor.new()
	gate.name = "Gate"
	var panel := Node3D.new()
	panel.name = "Mesh"
	gate.add_child(panel)
	f.scene.add_child(gate)
	var finish := FinishProvider.new()
	finish.name = "Finish"
	f.scene.add_child(finish)
	var route := TavernRoute.new()
	route.name = "CancelRoute"
	route.finish_mode = TavernRoute.Finish.ACTIVITY
	var far := Marker3D.new()
	far.position = Vector3(20.0, 0.0, 0.0)
	route.add_child(far)
	f.scene.add_child(route)
	route.exit_gate_path = route.get_path_to(gate)
	route.finish_activity_path = route.get_path_to(finish)
	var move := MoveActorAction.new()
	move.actor_path = ^"NPC"
	move.route_path = ^"CancelRoute"
	move.speed_override = 2.0
	var context := _context(f, move, &"cancel_move")
	move.begin(context)
	for _frame in range(3): await physics_frame
	context.cancel(&"test_cancel")
	var stopped: Vector3 = f.npc.global_position
	for _frame in range(8): await physics_frame
	check(context.status == &"cancelled" and not f.npc.is_physics_processing() \
		and f.npc.global_position.is_equal_approx(stopped) and is_equal_approx(f.npc.walk_speed, 8.0),
		"cancelled fixed movement stops physics and restores its speed override")
	check(gate._users.is_empty() and finish.calls == 0,
		"movement cancellation closes gate ownership and cannot run the route finish action")
	check(f.npc.patrol_on_ready == false and f.npc.route == [Vector3(9.0, 0.0, 9.0)],
		"directed movement preserves daily patrol configuration")


func _test_world_and_state_actions(f: Dictionary) -> void:
	var door = Door.new()
	door.name = "Door"
	door.animation_seconds = 0.05
	for item in [[Area3D.new(), "Sensor"], [Node3D.new(), "Panel"], [Label3D.new(), "Label"]]:
		item[0].name = item[1]
		door.add_child(item[0])
	f.scene.add_child(door)
	door.set_physics_process(false)
	var door_action := SetDoorAction.new()
	door_action.door_path = ^"Door"
	door_action.open = true
	var context := _context(f, door_action, &"door")
	door_action.begin(context)
	check(not context.is_terminal(), "SetDoorAction waits for the real door tween")
	check(await _wait_terminal(context) and context.status == &"completed",
		"SetDoorAction completes at the provider tween boundary")
	check(door.is_open and is_equal_approx(door.get_node("Panel").position.x, door.slide_distance),
		"SetDoorAction leaves the authored door at its requested open pose")
	door_action = SetDoorAction.new()
	door_action.door_path = ^"Door"
	door_action.open = false
	context = _context(f, door_action, &"door_cancel")
	door_action.begin(context)
	await physics_frame
	context.cancel(&"test_cancel")
	var stopped_door_x: float = door.get_node("Panel").position.x
	await create_timer(0.10).timeout
	check(context.status == &"cancelled" \
		and is_equal_approx(stopped_door_x, door.get_node("Panel").position.x),
		"cancelling SetDoorAction kills the provider tween")

	var state := StateProbe.new()
	state.name = "State"
	f.scene.add_child(state)
	var flag_action := SetFlagAction.new()
	flag_action.state_path = ^"State"
	flag_action.flag = &"opened"
	flag_action.value = true
	context = _context(f, flag_action, &"flag")
	flag_action.begin(context)
	check(context.status == &"completed" and state.flags.get(&"opened") == true,
		"SetFlagAction uses the configured state target")
	flag_action.state_path = ^"MissingState"
	context = _context(f, flag_action, &"invalid_flag")
	flag_action.begin(context)
	check(context.status == &"failed", "SetFlagAction rejects a missing state target")

	var quests := QuestProbe.new()
	quests.name = "Quests"
	f.scene.add_child(quests)
	var changed := [0]
	quests.quest_changed.connect(func(_id, _old, _new): changed[0] += 1)
	var quest_action := UpdateQuestAction.new()
	quest_action.controller_path = ^"Quests"
	quest_action.quest_id = &"escape"
	quest_action.operation = UpdateQuestAction.Operation.COMPLETE
	context = _context(f, quest_action, &"quest")
	quest_action.begin(context)
	quest_action.begin(_context(f, quest_action, &"quest_repeat"))
	check(context.status == &"completed" and quests.statuses.get(&"escape") == 3 \
		and changed[0] == 1, "UpdateQuestAction maps its enum and preserves one quest signal")

	var provider := ProviderProbe.new()
	provider.name = "Provider"
	f.scene.add_child(provider)
	var provider_action := RunProviderAction.new()
	provider_action.target_path = ^"Provider"
	provider_action.parameters = {"payload": &"safe", "mode": &"method"}
	context = _context(f, provider_action, &"provider")
	provider_action.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" and provider.begins == 1,
		"RunProviderAction completes through a provider contract")
	check(provider.parameters.get("payload") == &"safe" and provider.parameters.get("mode") == &"provider",
		"RunProviderAction forwards parameters but cannot switch to arbitrary method mode")

	var player := Node3D.new()
	player.name = "Player"
	player.add_to_group(&"player")
	f.scene.add_child(player)
	var interactable: Node3D = load("res://scenes/world/interactable.tscn").instantiate()
	interactable.name = "Interactable"
	f.scene.add_child(interactable)
	var interaction := CallInteractionAction.new()
	interaction.interaction_path = ^"Interactable"
	interaction.player_path = ^"Player"
	context = _context(f, interaction, &"interaction")
	interaction.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" \
		and interactable.has_interacted, "CallInteractionAction completes through Interactable")
	interactable.enabled = false
	context = _context(f, interaction, &"blocked_interaction")
	interaction.begin(context)
	check(context.status == &"failed", "CallInteractionAction reports a blocked interaction")


func check(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
