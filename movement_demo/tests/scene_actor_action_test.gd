extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const NpcScene = preload("res://scenes/access_denied/hub/tavern_npc.tscn")

var failures := 0

class FinishProvider extends Node:
	var calls := 0

	func begin_scene_action(request: SceneRequest) -> void:
		calls += 1
		request.complete()

	func cancel_scene_action(_request: SceneRequest, _reason: StringName) -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var f := await _fixture()
	await _test_move_and_route(f)
	await _test_seat_and_visibility(f)
	await _test_cancel_and_patrol(f)
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
	seating = SeatActorAction.new()
	seating.actor_path = ^"NPC"
	seating.seat_path = ^"Seat"
	seating.mode = SeatActorAction.Mode.LEAVE
	context = _context(f, seating, &"leave")
	seating.begin(context)
	check(await _wait_terminal(context) and context.status == &"completed" \
		and f.npc.current_seat() == null, "SeatActorAction releases a TavernNPC from its seat")

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


func check(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
