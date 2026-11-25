extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")
const Door = preload("res://scripts/world/range_door.gd")
var failures := 0
var checks := 0

class Provider extends Node:
	signal finished
	var timer: Timer
	var tween: Tween
	var progress := 0.0
	var writes := 0
	var cancels := 0
	var synchronous := false
	func scene_action_is_background() -> bool: return true
	func start_legacy() -> void:
		timer = Timer.new()
		timer.one_shot = true
		timer.wait_time = 0.04
		add_child(timer)
		timer.timeout.connect(func(): writes += 1; finished.emit())
		timer.start()
		tween = create_tween()
		tween.tween_property(self, "progress", 10.0, 0.06)
	func cancel_legacy() -> void:
		cancels += 1
		if timer != null: timer.stop()
		if tween != null and tween.is_valid(): tween.kill()
	func begin_scene_action(request) -> void:
		if synchronous:
			request.complete()
			return
		start_legacy()
		finished.connect(func(): request.complete(), CONNECT_ONE_SHOT)
	func cancel_scene_action(request, _reason: StringName) -> void:
		cancel_legacy()
		request.complete()

class SeatProbe extends TavernSeat:
	var request: SceneRequest
	var cancels := 0

	func begin_scene_action(value: SceneRequest) -> void:
		request = value

	func cancel_scene_action(_value: SceneRequest, _reason: StringName) -> void:
		cancels += 1

func _initialize() -> void: _run.call_deferred()
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)

func fixture(rules: Array = []) -> Dictionary:
	var scene := Node3D.new()
	root.add_child(scene)
	var provider := Provider.new()
	provider.name = "Provider"
	scene.add_child(provider)
	var director = Director.new()
	director.configure(scene, {"scene_root": scene, "rules": rules})
	scene.add_child(director)
	director.initialize()
	return {"scene": scene, "provider": provider, "director": director}

func _run() -> void:
	var action = Action.new()
	action.kind = Action.Kind.CALL_METHOD
	action.target_path = ^"Provider"
	action.method = &"start_legacy"
	var trigger = Trigger.new()
	trigger.source_path = ^"Provider"
	trigger.signal_name = &"finished"
	action.completed_trigger = trigger
	for property in action.get_property_list():
		if property.name == &"cancel_method": action.set("cancel_method", &"cancel_legacy")
	var rule = Rule.new()
	rule.scope = Rule.Scope.REGION
	rule.actions.append(action)
	var f := fixture([rule])
	f.director.advance(0.0)
	f.director.reset_region()
	var progress: float = f.provider.progress
	await create_timer(0.10).timeout
	check(f.provider.writes == 0 and is_equal_approx(f.provider.progress, progress) and f.provider.cancels == 1,
		"region cancellation must stop actual Timer and Tween, not only disconnect completion")
	f.scene.free()
	await process_frame
	f = fixture()
	var request = f.director.request_action(&"script", {"source": f.provider, "target": f.provider})
	check(request.has_started(), "director must start cancellable script provider")
	if not request.has_started():
		f.scene.free()
		quit(1)
		return
	f.director.cancel_request(request.id)
	await create_timer(0.10).timeout
	check(request.status == &"cancelled" and f.provider.writes == 0, "cancel hook cannot complete retired request or perform late writes")
	f.provider.synchronous = true
	var fresh = f.director.request_action(&"script", {"source": f.provider, "target": f.provider})
	request.complete()
	check(fresh.status == &"completed" and request.status == &"cancelled", "fresh synchronous execution is independent of stale callback")
	f.scene.free()
	await process_frame
	f = fixture([rule])
	action.cancel_method = &""
	f.director._flows.configure([rule])
	f.director.advance(0.0)
	check(f.provider.timer == null and not String(f.director.debug_snapshot().last_error).is_empty(),
		"uncancellable async CALL_METHOD fails before starting its side effects")
	f.scene.free()
	await process_frame
	f = fixture()
	var regional := Provider.new()
	f.scene.add_child(regional)
	var scene_request = f.director.request_action(&"script", {"source": f.provider, "target": f.provider, "scope": 0})
	var region_request = f.director.request_action(&"script", {"source": regional, "target": regional, "scope": 1, "scope_owner": f.scene})
	f.director.reset_region()
	await create_timer(0.10).timeout
	check(scene_request.status == &"completed" and f.provider.writes == 1 and region_request.status == &"cancelled" and regional.writes == 0,
		"region cancellation preserves independently running scene-scoped background work")
	f.scene.free()
	await process_frame
	await _typed_seat_cancellation()
	await _door()
	print("Scene script cancellation: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)

func _typed_seat_cancellation() -> void:
	var f := fixture()
	var actor := CharacterBody3D.new()
	actor.name = "Actor"
	f.scene.add_child(actor)
	var seat := SeatProbe.new()
	seat.name = "Seat"
	f.scene.add_child(seat)
	var action := SeatActorAction.new()
	action.actor_path = ^"Actor"
	action.seat_path = ^"Seat"
	var definition := SceneEventDefinition.new()
	definition.event_id = &"seat_cancel"
	var context := SceneActionContext.new().configure(f.director, f.scene, definition, action, 1, 0)
	action.begin(context)
	check(seat.request != null and not context.is_terminal(),
		"typed seating remains pending at the provider completion boundary")
	context.cancel(&"test_cancel")
	seat.request.complete()
	check(context.status == &"cancelled" and seat.cancels == 1,
		"typed seat cancellation reaches the provider once and ignores late completion")
	f.scene.free()
	await process_frame

func _door() -> void:
	var f := fixture()
	var door = Door.new()
	for pair in [[Area3D.new(), "Sensor"], [Node3D.new(), "Panel"], [Label3D.new(), "Label"]]:
		pair[0].name = pair[1]
		door.add_child(pair[0])
	f.scene.add_child(door)
	door.set_physics_process(false)
	check(door.has_method("request_open"), "authored sliding door must request director execution")
	if not door.has_method("request_open"):
		f.scene.free()
		return
	var opening = door.request_open(true)
	await create_timer(0.04).timeout
	var closing = door.request_open(false)
	check(opening.status == &"cancelled" and closing.has_started(), "door reversal cancels previous Tween through its request")
	f.director.cancel_request(closing.id)
	var stopped: float = door.get_node("Panel").position.x
	await create_timer(0.35).timeout
	check(closing.status == &"cancelled" and is_equal_approx(stopped, door.get_node("Panel").position.x), "cancelled real door remains stopped beyond original animation duration")
	f.scene.free()
	await process_frame
