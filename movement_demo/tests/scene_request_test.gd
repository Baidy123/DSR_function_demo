extends SceneTree

const Director = preload("res://scripts/systems/scene_director.gd")
var failures := 0
var checks := 0

class Guide extends Node:
	signal finished
	var begins := 0
	var cancels := 0
	var synchronous := false
	var request
	func begin() -> void:
		begins += 1
		if synchronous: finished.emit()
	func cancel() -> void:
		cancels += 1
		if request != null: request.complete()

class FlagState extends Node:
	var allowed := true
	var action_begins := 0

	func get_flag(_key: StringName, _fallback: bool = false) -> bool:
		return allowed

class CountAction extends SceneAction:
	func begin(context: SceneActionContext) -> void:
		context.resolve(^"State").action_begins += 1
		context.complete()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func fixture() -> Dictionary:
	var scene := Node.new()
	root.add_child(scene)
	var guide := Guide.new()
	scene.add_child(guide)
	var director = Director.new()
	director.configure(scene, {"scene_root": scene})
	scene.add_child(director)
	director.initialize()
	return {"scene": scene, "director": director, "guide": guide}

func context(f: Dictionary, key: StringName = &"") -> Dictionary:
	return {"source": f.guide, "target": f.guide, "origin": &"rule", "dedupe_key": key,
		"parameters": {"pause_world": false}}

func _run() -> void:
	var f := fixture()
	check(f.director.has_method("request_action"), "director must expose unified request lifecycle")
	if failures != 0:
		f.scene.free()
		quit(1)
		return
	f.guide.synchronous = true
	var done = f.director.request_action(&"guide", context(f))
	check(done.status == &"completed" and done.has_started(), "synchronous provider completes before request returns")
	var result: Dictionary = await done.wait_result()
	check(result.status == &"completed", "terminal result remains awaitable without missing its signal")
	f.guide.synchronous = false
	var active = f.director.request_action(&"guide", context(f, &"unique"))
	f.guide.request = active
	var duplicate = f.director.request_action(&"guide", context(f, &"unique"))
	check(duplicate == active and f.guide.begins == 2, "duplicate active request does not begin twice")
	var queued = f.director.request_action(&"guide", context(f, &"second"))
	check(queued.status == &"queued" and not queued.has_started(), "conflicting rule request waits for foreground")
	var finished := [0]
	active.finished.connect(func(_request): finished[0] += 1)
	f.director.cancel_request(active.id, &"test_cancel")
	check(active.status == &"cancelled" and finished[0] == 1 and f.guide.cancels == 1,
		"cancel invalidates identity before reentrant completion and reports once")
	active.complete()
	check(finished[0] == 1, "late completion cannot repeat terminal notification")
	f.director.advance(0.01)
	check(queued.has_started() and f.guide.begins == 3, "queued request begins after previous cleanup")
	var other := fixture()
	var duplicate_director = Director.new()
	duplicate_director.configure(f.scene, {"scene_root": f.scene})
	f.scene.add_child(duplicate_director)
	duplicate_director.initialize()
	check(duplicate_director.state == &"error" and f.director.call("for_node", f.guide) == f.director,
		"duplicate director cannot replace the registered scene owner")
	duplicate_director.free()
	var preparing = Director.new()
	var premature = preparing.request_action(&"guide", context(f))
	check(premature.status == &"rejected" and not premature.has_started(), "preparing director rejects interaction before initialization")
	preparing.free()
	check(f.director.call("for_node", f.guide) == f.director and other.director.call("for_node", other.guide) == other.director,
		"director lookup is local to the explicit scene root")
	var foreign = f.director.request_action(&"guide", context(other))
	check(foreign.status == &"rejected", "cross-scene source cannot execute through another director")
	var unsafe_context := context(f)
	unsafe_context.parameters["hidden_node"] = [other.guide]
	var unsafe_request = f.director.request_action(&"guide", unsafe_context)
	check(unsafe_request.status == &"rejected", "nested parameters cannot retain nodes or hide cross-scene targets")
	var old_callbacks: Array[Callable] = []
	for connection in f.guide.finished.get_connections(): old_callbacks.append(connection.callable)
	f.director.cancel_request(queued.id)
	var fresh = f.director.request_action(&"guide", context(f))
	for callback in old_callbacks:
		if callback.is_valid(): callback.call()
	check(fresh.status == &"running", "captured guide completion cannot finish a newer execution of the same provider")
	f.scene.free()
	check(fresh.status == &"cancelled", "scene exit cancels the currently active guide identity")
	check(queued.status == &"cancelled" and not queued.is_current(), "scene exit invalidates all pending callbacks")
	queued.complete()
	check(queued.status == &"cancelled", "retired execution cannot complete after scene removal")
	var completion = other.director.request_action(&"completion", {"source": other.guide})
	check(not completion.is_terminal(), "completion request waits for the actual completion boundary")
	await process_frame
	await process_frame
	await process_frame
	await process_frame
	check(completion.status == &"completed" and other.director.state == &"completed", "completion result follows actual scene completion")
	other.scene.free()
	await process_frame
	var scoped := fixture()
	var region_a := Node.new()
	var region_b := Node.new()
	scoped.scene.add_child(region_a)
	scoped.scene.add_child(region_b)
	scoped.director._host = region_a
	var scope_context := context(scoped)
	scope_context["scope"] = 1
	scope_context["scope_owner"] = region_b
	var region_b_guide = scoped.director.request_action(&"guide", scope_context)
	scoped.director.reset_region()
	check(region_b_guide.status == &"running" and scoped.guide.cancels == 0 and scoped.director.is_guide_pending(scoped.guide),
		"resetting region A cannot cancel region B guide through legacy global cleanup")
	scoped.scene.free()
	await process_frame
	await _test_queued_event_rechecks_condition()
	print("Scene requests: %d checks; %d failures" % [checks, failures])
	quit(0 if failures == 0 else 1)


func _test_queued_event_rechecks_condition() -> void:
	var scene := Node.new()
	root.add_child(scene)
	var state := FlagState.new()
	state.name = "State"
	scene.add_child(state)
	var guide := Guide.new()
	scene.add_child(guide)
	var condition := SceneFlagCondition.new()
	condition.state_path = ^"State"
	condition.flag = &"allowed"
	var definition := SceneEventDefinition.new()
	definition.event_id = &"queued_condition"
	definition.start_mode = SceneEventDefinition.StartMode.MANUAL
	definition.conditions = [condition]
	definition.actions = [CountAction.new()]
	var director = Director.new()
	director.configure(scene, {"scene_root": scene, "guide": guide,
		"guide_pauses_world": true, "events": [definition]})
	scene.add_child(director)
	director.initialize()
	check(director.trigger_event(&"queued_condition"), "manual event is accepted while a foreground guide owns execution")
	state.allowed = false
	guide.finished.emit()
	director.advance(0.0)
	check(state.action_begins == 0, "queued event rechecks conditions after foreground guide release")
	scene.free()
	await process_frame
