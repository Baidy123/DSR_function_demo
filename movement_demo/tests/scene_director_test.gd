extends SceneTree

## Contract-level scene lifecycle tests. Real saved-level/UI and camera rendering
## remain covered separately; fixtures here never change authored level resources.
const Director = preload("res://scripts/systems/scene_director.gd")
const Pause = preload("res://scripts/systems/scene_pause_coordinator.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")
const Filter = preload("res://scripts/systems/scene_event_filter.gd")
const Presentation = preload("res://scripts/systems/presentation_camera.gd")
const HealthScene = preload("res://scenes/player/player_health.tscn")

var checks := 0
var failures := 0

class HealthSource extends Node:
	signal died
	var is_dead := false
	func die() -> void:
		is_dead = true
		died.emit()

class ResultView extends RefCounted:
	signal restart_requested
	var deaths := 0
	var errors := 0
	var pending := false
	func bind(_health: Node) -> void:
		pass
	func show_death() -> void:
		deaths += 1
	func set_pending(value: bool) -> void:
		pending = value
	func show_load_error() -> void:
		errors += 1
		pending = false
	func hide_result() -> void:
		pending = false

class GuideSource extends Node:
	signal finished
	var begins := 0
	var cancels := 0
	var synchronous := false
	func begin() -> void:
		begins += 1
		if synchronous: finished.emit()
	func cancel() -> void:
		cancels += 1

class Events extends Node:
	signal fired
	signal item_gained(item_id: StringName, total: int)
	signal action_finished
	var calls: Array[String] = []
	func record(label: String) -> void:
		calls.append(label)
	func complete_synchronously() -> void:
		calls.append("synchronous")
		action_finished.emit()
	func start_wait() -> void:
		calls.append("started")
	func record_default(label: String = "default") -> void:
		calls.append(label)

class PlayerBody extends CharacterBody3D:
	const MAX_STAMINA := 100.0
	var stamina := 100.0
	var stamina_exhausted := false
	var is_in_dialogue := false
	var current_speed := 3.0
	var is_sprinting := true
	var is_facing_npc := false
	var combat: Node = null
	func receive_hit(damage: float) -> void:
		get_node("Health").receive_hit(damage)

class LevelView extends Node:
	signal continue_requested
	var completions := 0
	var errors := 0
	var pending := false
	func show_completion() -> void:
		completions += 1
	func hide_result() -> void:
		pass
	func set_transition_pending(value: bool) -> void:
		pending = value
	func show_load_error() -> void:
		errors += 1
		pending = false
	func next_scene_path() -> String:
		return "res://tests/fixture_next_level.tscn"

class SilentCancelCamera extends Camera3D:
	signal presentation_finished(request_id: int, result: StringName)
	var cancellations := 0
	func start_presentation(_source: Camera3D, _focus: Vector3, _options: Dictionary, _id: int) -> bool:
		return true
	func advance_presentation(_delta: float) -> void:
		pass
	func cancel_presentation(_restore: bool = true) -> void:
		cancellations += 1

class WavesSource extends RefCounted:
	signal encounter_completed
	signal wave_committed(wave: Node, focus: Vector3)
	var status: StringName = &"waiting"
	var requests := 0
	func prepare_events() -> void:
		pass
	func request_wave(_wave: Node) -> bool:
		requests += 1
		status = &"ready"
		return true
	func start_encounter() -> void:
		pass
	func wave_status(_wave: Node) -> StringName:
		return status
	func reset_encounter() -> void:
		status = &"waiting"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_test_pause_owners()
	await _test_no_waves_and_death()
	await _test_guides()
	await _test_rule_guide_scope()
	await _test_health_binding_identity()
	await _test_manual_completion_policy()
	await _test_death_precedence()
	await _test_load_retry()
	await _test_next_level_retry()
	await _test_real_health_result()
	await _test_camera_lifecycle()
	await _test_camera_cancel_without_reply()
	await _test_event_pause_and_filter()
	await _test_synchronous_completion()
	await _test_region_scope_and_stale_callbacks()
	await _test_missing_guide()
	await _test_lost_event_source()
	await _test_independent_event_rules()
	await _test_call_argument_validation()
	await _test_flow_transition_retry()
	await _test_scene_wave_wait_reset()
	await _test_headless_transition_retry()
	check(Pause.for_tree(self).snapshot().count == 0 and not paused, "All fixtures release their pause ownership")
	print("SCENE DIRECTOR: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _test_pause_owners() -> void:
	var ledger = Pause.for_tree(self)
	var old_owner := Node.new()
	var new_owner := Node.new()
	root.add_child(old_owner)
	root.add_child(new_owner)
	var presentation: int = ledger.acquire(old_owner, &"presentation")
	check(paused and ledger.can_advance_presentation(presentation), "Presentation alone freezes gameplay and can advance its own clock")
	var death: int = ledger.acquire(old_owner, &"death", true)
	check(not ledger.can_advance_presentation(presentation), "Death pause blocks the presentation clock")
	ledger.release(presentation)
	ledger.release(presentation)
	check(paused and ledger.snapshot().count == 1, "Repeated presentation release preserves death pause")
	var guide: int = ledger.acquire(new_owner, &"guide", true)
	old_owner.free()
	check(paused and ledger.snapshot().count == 1, "Unloading the old owner cannot release a new scene's guide")
	ledger.release(death)
	check(paused, "Stale token release has no effect on the remaining owner")
	ledger.release(guide)
	check(not paused, "Last managed owner restores originally running gameplay")
	paused = true
	var external: int = ledger.acquire(new_owner, &"guide")
	ledger.release(external)
	check(paused, "Managed pause release preserves an existing external pause")
	paused = false
	ledger.acquire(new_owner, &"guide")
	ledger.acquire(new_owner, &"death")
	new_owner.free()
	check(not paused and ledger.snapshot().count == 0, "One owner leaving releases all of its still-held reasons")

func _fixture(rules: Array = [], guide: Node = null, extra: Dictionary = {}) -> Dictionary:
	var scene := Node3D.new()
	scene.name = "DirectorFixture"
	var host := Node3D.new()
	host.name = "EnemyWaves"
	scene.add_child(host)
	var events := Events.new()
	events.name = "Events"
	scene.add_child(events)
	var health := HealthSource.new()
	health.name = "Health"
	scene.add_child(health)
	if guide != null:
		guide.name = "Guide"
		scene.add_child(guide)
	for key in ["level_flow", "camera"]:
		var node: Node = extra.get(key)
		if node != null and node.get_parent() == null: scene.add_child(node)
	var view := ResultView.new()
	var director = Director.new()
	director.name = "SceneDirector"
	var bindings := {"health": health, "result_view": view, "rules": rules}
	if guide != null: bindings.guide = guide
	bindings.merge(extra, true)
	director.configure(host, bindings)
	host.add_child(director)
	root.add_child(scene)
	return {"scene": scene, "host": host, "director": director, "events": events, "health": health, "view": view}

func _ready_fixture(f: Dictionary) -> void:
	for frame in 3: await process_frame
	# Deterministic action time after initialization; only this caller advances it.
	f.director.set_process(false)
	f.director.set_physics_process(false)

func _dispose(f: Dictionary) -> void:
	f.scene.free()
	await process_frame
	check(Pause.for_tree(self).snapshot().count == 0 and not paused, "Scene disposal leaves no pause token")

func _steps(f: Dictionary, count: int = 8, delta: float = 0.0) -> void:
	for index in count: f.director.advance(delta)

func _test_no_waves_and_death() -> void:
	var f := _fixture()
	await _ready_fixture(f)
	check(f.director.state == &"running" and not paused, "No Wave, Guide, or CombatZone is needed to run")
	_steps(f)
	check(f.director.state == &"running", "Zero configured waves do not imply automatic victory")
	f.health.die()
	check(f.director.state == &"dead" and paused and f.view.deaths == 1, "Death outside any combat region immediately pauses and displays the result")
	f.health.died.emit()
	_steps(f)
	check(f.view.deaths == 1, "Repeated death is idempotent")
	await _dispose(f)

func _test_guides() -> void:
	var guide := GuideSource.new()
	var f := _fixture([], guide)
	await _ready_fixture(f)
	check(f.director.state == &"guide" and paused and guide.begins == 1, "Optional guide starts once and owns its pause")
	f.director.reset_region()
	check(guide.begins == 1 and f.director.state == &"guide", "Region reset does not replay or complete scene introduction")
	guide.finished.emit()
	_steps(f)
	check(f.director.state == &"running" and not paused, "Guide completion releases its own pause")
	await _dispose(f)
	guide = GuideSource.new()
	f = _fixture([], guide, {"guide_pauses_world": false})
	await _ready_fixture(f)
	check(guide.begins == 1 and not paused, "Interactive tutorial can wait for completion while gameplay runs")
	f.health.die()
	guide.finished.emit()
	_steps(f)
	check(f.director.state == &"dead" and paused and f.view.deaths == 1, "Late guide completion cannot undo death")
	await _dispose(f)
	guide = GuideSource.new()
	guide.synchronous = true
	f = _fixture([], guide)
	await _ready_fixture(f)
	_steps(f)
	check(f.director.state == &"running" and not paused, "Guide listener is installed before a synchronous begin completion")
	await _dispose(f)

func _test_death_precedence() -> void:
	for death_first in [false, true]:
		var f := _fixture()
		await _ready_fixture(f)
		if death_first: f.health.die()
		f.director.request_completion()
		if not death_first: f.health.die()
		await process_frame
		_steps(f)
		check(f.director.state == &"dead" and f.view.deaths == 1 and paused, "Death wins same-step completion, death_first=%s" % death_first)
		await _dispose(f)

func _test_rule_guide_scope() -> void:
	for region_scope in [true, false]:
		var action = Action.new()
		action.kind = Action.Kind.GUIDE
		action.target_path = ^"../Tutorial"
		var f := _fixture([_rule(_trigger(&"fired"), [action, _record("after-guide")], region_scope)])
		var guide := GuideSource.new()
		guide.name = "Tutorial"
		f.scene.add_child(guide)
		await _ready_fixture(f)
		f.events.fired.emit()
		_steps(f)
		check(guide.begins == 1 and paused and f.director.state == &"guide", "Event action begins a guide, region_scope=%s" % region_scope)
		f.director.reset_region()
		if region_scope:
			check(guide.cancels == 1 and not paused and f.director.state == &"running", "Region reset cancels its own guide and releases its pause")
			guide.finished.emit()
			_steps(f)
			check(f.events.calls.is_empty(), "Late region-guide completion cannot execute the canceled continuation")
		else:
			check(guide.cancels == 0 and paused and f.director.state == &"guide", "Region reset preserves a scene-scoped event guide")
			guide.finished.emit()
			_steps(f)
			check(f.events.calls == ["after-guide"] and not paused, "Scene guide still completes its continuation after a region reset")
		await _dispose(f)

func _test_health_binding_identity() -> void:
	var f := _fixture()
	await _ready_fixture(f)
	var duplicate = Director.new()
	var duplicate_view := ResultView.new()
	duplicate.configure(f.host, {"health": f.health, "result_view": duplicate_view})
	f.scene.add_child(duplicate)
	await process_frame
	await process_frame
	check(duplicate.state == &"error" and f.director.state == &"running", "A second director cannot bind the same live Health authority")
	duplicate.free()
	var old_view = f.view
	f.director.free()
	var replacement = Director.new()
	var replacement_view := ResultView.new()
	replacement.configure(f.host, {"health": f.health, "result_view": replacement_view})
	f.host.add_child(replacement)
	f.director = replacement
	f.view = replacement_view
	await _ready_fixture(f)
	check(replacement.state == &"running", "A released Health authority can bind a new director")
	f.health.die()
	check(replacement_view.deaths == 1 and old_view.deaths == 0 and duplicate_view.deaths == 0, "Only the currently bound director handles Health death")
	await _dispose(f)

func _test_manual_completion_policy() -> void:
	var waves := WavesSource.new()
	var f := _fixture([], null, {"wave_runtime": waves, "auto_complete_waves": false})
	await _ready_fixture(f)
	waves.encounter_completed.emit()
	await process_frame
	_steps(f)
	check(f.director.state == &"running" and not paused, "Disabling wave-based completion ignores the deployment completion signal")
	f.director.request_completion()
	await process_frame
	_steps(f)
	check(f.director.state == &"completed" and paused, "Explicit scene completion remains available when wave auto-completion is disabled")
	await _dispose(f)

func _test_load_retry() -> void:
	var f := _fixture()
	await _ready_fixture(f)
	var calls: Array[Dictionary] = []
	f.director.scene_loader = func(path: String, reload: bool) -> Error:
		calls.append({"path": path, "reload": reload, "paused": paused})
		return ERR_CANT_OPEN
	f.director.request_restart()
	await process_frame
	check(calls.is_empty(), "Restart request is rejected while gameplay is running")
	f.health.die()
	f.view.restart_requested.emit()
	f.view.restart_requested.emit()
	await process_frame
	await process_frame
	check(calls.size() == 1 and calls[0].reload, "Repeated restart clicks cause only one reload attempt")
	check(paused and not f.view.pending and f.view.errors == 1, "Failed reload keeps the result paused and enables retry")
	f.view.restart_requested.emit()
	await process_frame
	await process_frame
	check(calls.size() == 2 and f.view.errors == 2 and paused, "A failed reload can be retried without leaving death pause")
	await _dispose(f)

func _test_next_level_retry() -> void:
	var flow := LevelView.new()
	var f := _fixture([], null, {"level_flow": flow})
	await _ready_fixture(f)
	var calls: Array[Dictionary] = []
	f.director.scene_loader = func(path: String, reload: bool) -> Error:
		calls.append({"path": path, "reload": reload})
		return ERR_CANT_OPEN
	f.director.request_completion()
	await process_frame
	_steps(f)
	check(f.director.state == &"completed" and flow.completions == 1 and paused, "Explicit completion without waves displays one result and waits for input")
	f.director.request_completion()
	_steps(f)
	check(flow.completions == 1 and calls.is_empty(), "Repeated completion neither duplicates UI nor automatically changes scenes")
	flow.continue_requested.emit()
	flow.continue_requested.emit()
	await process_frame
	await process_frame
	check(calls.size() == 1 and calls[0].path == flow.next_scene_path() and not calls[0].reload, "Next-level intent delegates one load with the adapter's exact path")
	check(f.director.state == &"completed" and paused and not flow.pending and flow.errors == 1, "Failed next-level load retains completion and enables retry")
	flow.continue_requested.emit()
	await process_frame
	await process_frame
	check(calls.size() == 2 and flow.errors == 2 and paused, "Next-level failure remains retryable")
	await _dispose(f)

func _test_real_health_result() -> void:
	# A minimal player body supports the real Health component; this does not claim
	# coverage of the player's complete movement/combat controller or GUI input.
	var body := PlayerBody.new()
	var health = HealthScene.instantiate()
	health.name = "Health"
	health.max_health = 25.0
	health.debug_mode = false
	body.add_child(health)
	var f := _fixture([], null, {"health": health, "result_view": null})
	f.scene.add_child(body)
	await _ready_fixture(f)
	var screen: Control = health.get_node("DeathScreen")
	var restart: Button = health.get_node("DeathScreen/Center/Panel/Content/Restart")
	check(f.director.state == &"running" and not screen.visible, "Real Health and result adapter initialize without Wave or Guide")
	var calls: Array[bool] = []
	f.director.scene_loader = func(_path: String, reload: bool) -> Error:
		calls.append(reload)
		return ERR_CANT_OPEN
	body.receive_hit(25.0)
	check(health.is_dead and health.health == 0.0 and body.current_speed == 0.0, "Real Health settles lethal damage and stops its player body")
	check(screen.visible and paused and restart.can_process(), "Director displays the real death UI and its button remains processable")
	restart.pressed.emit()
	restart.pressed.emit()
	await process_frame
	await process_frame
	check(calls == [true] and not restart.disabled and screen.visible and paused, "Real death button requests one reload and recovers after load failure")
	check(health.get_node("DeathScreen/Center/Panel/Content/Message").text.contains("失败"), "Real death view explains loading failure")
	await _dispose(f)

func _add_source_camera(f: Dictionary) -> Camera3D:
	var source := Camera3D.new()
	source.position = Vector3(0.0, 10.0, 10.0)
	source.rotation.x = -PI / 4.0
	source.projection = Camera3D.PROJECTION_ORTHOGONAL
	source.size = 12.0
	f.scene.add_child(source)
	source.make_current()
	return source

func _test_camera_lifecycle() -> void:
	var camera = Presentation.new()
	camera.current = false
	var flow := LevelView.new()
	var f := _fixture([], null, {"camera": camera, "level_flow": flow})
	var source := _add_source_camera(f)
	await _ready_fixture(f)
	var options := {"move_seconds": 0.1, "hold_seconds": 0.1, "return_seconds": 0.1}
	var first: int = f.director.present_target(Vector3(4.0, 0.0, 0.0), options, Rule.Scope.REGION)
	check(first > 0 and paused and root.get_camera_3d() == camera, "Real presentation request switches cameras under a managed pause")
	f.director.reset_region()
	check(not f.director.is_presentation_pending(first) and not paused and root.get_camera_3d() == source, "Region reset cancels region presentation and restores the source camera")
	var second: int = f.director.present_target(Vector3(8.0, 0.0, 0.0), options, Rule.Scope.SCENE)
	f.director.reset_region()
	check(second > first and f.director.is_presentation_pending(second) and paused, "Region reset preserves a scene-scoped presentation")
	camera.presentation_finished.emit(first, &"completed")
	check(f.director.is_presentation_pending(second) and paused, "Stale camera completion cannot release a newer presentation")
	f.director.request_completion()
	await process_frame
	f.director.advance(0.05)
	check(flow.completions == 0 and f.director.is_presentation_pending(second), "Victory waits for the required presentation to finish")
	_steps(f, 5, 0.1)
	check(f.director.state == &"completed" and flow.completions == 1 and paused, "Presentation completion hands pause ownership to the victory result")
	check(root.get_camera_3d() == source, "Required presentation returns to the source before showing victory")
	await _dispose(f)

func _test_camera_cancel_without_reply() -> void:
	var camera := SilentCancelCamera.new()
	var f := _fixture([], null, {"camera": camera})
	_add_source_camera(f)
	await _ready_fixture(f)
	var id: int = f.director.present_target(Vector3.ZERO)
	check(id > 0 and paused, "Camera cancellation fixture holds a real presentation token")
	f.health.die()
	check(camera.cancellations > 0 and f.view.deaths == 1 and f.director.state == &"dead", "A camera that never reports cancellation cannot block the death result")
	camera.presentation_finished.emit(id, &"completed")
	check(paused and Pause.for_tree(self).snapshot().count == 1, "Late camera result cannot release the remaining death pause")
	await _dispose(f)

func _trigger(signal_name: StringName) -> Resource:
	var trigger = Trigger.new()
	trigger.source_path = ^"../Events"
	trigger.signal_name = signal_name
	return trigger

func _record(label: String) -> Resource:
	var action = Action.new()
	action.kind = Action.Kind.CALL_METHOD
	action.target_path = ^"../Events"
	action.method = &"record"
	action.arguments = [label]
	return action

func _rule(trigger: Resource, actions: Array, region: bool = false) -> Resource:
	var rule = Rule.new()
	if trigger != null: rule.triggers.append(trigger)
	rule.actions.assign(actions)
	if region: rule.scope = Rule.Scope.REGION
	return rule

func _test_event_pause_and_filter() -> void:
	var trigger = _trigger(&"item_gained")
	var filter = Filter.new()
	filter.string_name_value = &"key"
	trigger.filters.append(filter)
	var delay = Action.new()
	delay.seconds = 0.5
	var f := _fixture([_rule(trigger, [delay, _record("unlocked")])])
	await _ready_fixture(f)
	f.events.item_gained.emit(&"other", 1)
	_steps(f, 8, 1.0)
	check(f.events.calls.is_empty(), "Wrong item parameters do not trigger a scene action")
	var ledger = Pause.for_tree(self)
	var token: int = ledger.acquire(f.scene, &"test_external")
	f.events.item_gained.emit(&"key", 1)
	f.events.item_gained.emit(&"key", 2)
	_steps(f, 8, 1.0)
	check(f.events.calls.is_empty(), "Events received while paused cannot advance ordinary action delay")
	ledger.release(token)
	_steps(f, 8, 0.0)
	check(f.events.calls.is_empty(), "Paused time was not charged to the event delay")
	_steps(f, 8, 0.1)
	check(f.events.calls == ["unlocked"], "Remembered event completes once after sufficient unpaused time")
	f.events.item_gained.emit(&"key", 3)
	_steps(f, 8, 1.0)
	check(f.events.calls == ["unlocked"], "Repeated events do not replay a completed scene rule")
	await _dispose(f)

func _test_synchronous_completion() -> void:
	var invoke = Action.new()
	invoke.kind = Action.Kind.CALL_METHOD
	invoke.target_path = ^"../Events"
	invoke.method = &"complete_synchronously"
	invoke.completed_trigger = _trigger(&"action_finished")
	var f := _fixture([_rule(_trigger(&"fired"), [invoke, _record("after")])])
	await _ready_fixture(f)
	f.events.fired.emit()
	check(f.events.calls.is_empty(), "Signal callback records the event without recursively invoking actions")
	_steps(f)
	check(f.events.calls == ["synchronous", "after"], "CALL_METHOD listens before invocation and keeps synchronous completion")
	await _dispose(f)

func _test_region_scope_and_stale_callbacks() -> void:
	var scene_rule = _rule(_trigger(&"fired"), [_record("scene")])
	var region_rule = _rule(_trigger(&"fired"), [_record("region")], true)
	var f := _fixture([scene_rule, region_rule])
	await _ready_fixture(f)
	f.events.fired.emit()
	_steps(f)
	check(f.events.calls.count("scene") == 1 and f.events.calls.count("region") == 1, "One source can independently satisfy scene and region rules")
	f.director.reset_region()
	_steps(f)
	check(f.events.calls.size() == 2, "Region reset does not replay the previous round's event pulse")
	f.events.fired.emit()
	_steps(f)
	check(f.events.calls.count("scene") == 1 and f.events.calls.count("region") == 2, "Only region-scoped rules rearm after reset")
	await _dispose(f)
	var invoke = Action.new()
	invoke.kind = Action.Kind.CALL_METHOD
	invoke.target_path = ^"../Events"
	invoke.method = &"start_wait"
	invoke.completed_trigger = _trigger(&"action_finished")
	f = _fixture([_rule(_trigger(&"fired"), [invoke, _record("after")], true)])
	await _ready_fixture(f)
	f.events.fired.emit()
	_steps(f)
	check(f.events.calls == ["started"], "Asynchronous method waits for its actual completion")
	var old_callbacks: Array[Callable] = []
	for connection in f.events.action_finished.get_connections():
		old_callbacks.append(connection.callable)
	f.director.reset_region()
	for callback in old_callbacks:
		if callback.is_valid(): callback.call()
	f.events.action_finished.emit()
	_steps(f)
	check(f.events.calls == ["started"], "Captured old callbacks and late completion cannot advance a reset execution")
	f.events.fired.emit()
	_steps(f)
	check(f.events.calls == ["started", "started"], "New region round starts a fresh asynchronous action")
	f.events.action_finished.emit()
	_steps(f)
	check(f.events.calls == ["started", "started", "after"], "Fresh action responds to its own completion")
	await _dispose(f)

func _test_missing_guide() -> void:
	var f := _fixture([], null, {"guide_required": true})
	await _ready_fixture(f)
	check(f.director.state == &"error", "Explicitly required missing guide reports a configuration error")
	check(not paused, "A missing guide does not leak a permanent guide pause")
	await _dispose(f)

func _test_lost_event_source() -> void:
	var f := _fixture([_rule(_trigger(&"fired"), [_record("unexpected")])])
	await _ready_fixture(f)
	f.events.free()
	_steps(f)
	check(not String(f.director.debug_snapshot().last_error).is_empty(), "Disappearing event source produces a diagnostic instead of silently waiting forever")
	await _dispose(f)
	var invoke = Action.new()
	invoke.kind = Action.Kind.CALL_METHOD
	invoke.target_path = ^"../Events"
	invoke.method = &"start_wait"
	invoke.completed_trigger = _trigger(&"action_finished")
	f = _fixture([_rule(_trigger(&"fired"), [invoke, _record("unexpected")])])
	await _ready_fixture(f)
	f.events.fired.emit()
	_steps(f)
	f.events.free()
	_steps(f)
	check(not String(f.director.debug_snapshot().last_error).is_empty(), "Losing an asynchronous completion source diagnoses the interrupted wait")
	await _dispose(f)

func _test_independent_event_rules() -> void:
	var all_rule = _rule(_trigger(&"fired"), [_record("all")])
	all_rule.combination = Rule.Combination.ALL
	all_rule.triggers.append(_trigger(&"action_finished"))
	var wait = Action.new()
	wait.kind = Action.Kind.WAIT_SIGNAL
	wait.completed_trigger = _trigger(&"action_finished")
	var f := _fixture([all_rule, _rule(_trigger(&"fired"), [wait, _record("waiter")]), _rule(_trigger(&"fired"), [_record("independent")])])
	await _ready_fixture(f)
	f.events.fired.emit()
	_steps(f)
	check(f.events.calls == ["independent"], "An asynchronous rule cannot block an unrelated ready rule; ALL keeps partial progress")
	f.events.action_finished.emit()
	_steps(f)
	check(f.events.calls.count("all") == 1 and f.events.calls.count("waiter") == 1, "ALL combines events across updates and WAIT_SIGNAL responds to its real source")
	await _dispose(f)
	# A pickup may emit its valid event then disappear; latched facts remain true.
	var disposable := Events.new()
	disposable.name = "Disposable"
	var trigger = _trigger(&"fired")
	trigger.source_path = ^"../Disposable"
	f = _fixture([_rule(trigger, [_record("latched")])])
	f.scene.add_child(disposable)
	await _ready_fixture(f)
	disposable.fired.emit()
	disposable.free()
	_steps(f)
	check(f.events.calls == ["latched"], "Source removal after a valid event does not erase an already latched fact")
	await _dispose(f)

func _test_call_argument_validation() -> void:
	for arguments in [[], ["one", "extra"], [Vector3.ZERO]]:
		var action = _record("unused")
		action.arguments = arguments
		var f := _fixture([_rule(_trigger(&"fired"), [action, _record("invalid-continuation")])])
		await _ready_fixture(f)
		f.events.fired.emit()
		_steps(f)
		check(not String(f.director.debug_snapshot().last_error).is_empty(), "Invalid public method arguments receive an action diagnostic: %s" % str(arguments))
		check(f.events.calls.is_empty(), "Invalid method arguments neither call the target nor continue the rule")
		await _dispose(f)
	var action = _record("unused")
	action.method = &"record_default"
	action.arguments = []
	var f := _fixture([_rule(_trigger(&"fired"), [action])])
	await _ready_fixture(f)
	f.events.fired.emit()
	_steps(f)
	check(f.events.calls == ["default"], "Method validation accepts omitted optional arguments")
	await _dispose(f)

func _test_flow_transition_retry() -> void:
	for reload in [false, true]:
		var action = Action.new()
		action.kind = Action.Kind.RESTART if reload else Action.Kind.CHANGE_SCENE
		action.scene_path = "res://tests/event_requested_destination.tscn"
		var flow := LevelView.new()
		var f := _fixture([_rule(_trigger(&"fired"), [action])], null, {"level_flow": flow})
		await _ready_fixture(f)
		var calls: Array[Dictionary] = []
		f.director.scene_loader = func(path: String, reload_current: bool) -> Error:
			calls.append({"path": path, "reload": reload_current})
			return ERR_CANT_OPEN
		f.events.fired.emit()
		_steps(f)
		await process_frame
		await process_frame
		check(calls.size() == 1 and calls[0].reload == reload, "Scene event action can request a transition during running, reload=%s" % reload)
		check(flow.errors == 1 and not flow.pending and paused, "Event-triggered load failure shows a paused retry result")
		flow.continue_requested.emit()
		flow.continue_requested.emit()
		await process_frame
		await process_frame
		check(calls.size() == 2, "Event-triggered load failure accepts one retry despite repeated clicks")
		if calls.size() == 2:
			check(calls[1] == calls[0], "Retry preserves the exact event destination and reload mode, ignoring the next-level table")
		await _dispose(f)

func _test_scene_wave_wait_reset() -> void:
	# Model the runtime's public waiting/ready/active states without invoking enemy
	# geometry. Real deployment and its reset are the enemy-wave suite's contract.
	for wait_for_clear in [false, true]:
		var waves := WavesSource.new()
		if wait_for_clear: waves.status = &"active"
		var action = Action.new()
		action.kind = Action.Kind.WAIT_WAVE_CLEARED if wait_for_clear else Action.Kind.REQUEST_WAVE
		action.target_path = ^"Wave"
		action.present_spawn = true
		var wait_rule = _rule(_trigger(&"fired"), [action, _record("obsolete-wave-continuation")])
		var independent = _rule(_trigger(&"action_finished"), [_record("independent-scene-rule")])
		var f := _fixture([wait_rule, independent], null, {"wave_runtime": waves, "auto_complete_waves": false})
		var wave := Node3D.new()
		wave.name = "Wave"
		f.host.add_child(wave)
		await _ready_fixture(f)
		f.events.fired.emit()
		_steps(f)
		check(f.events.calls.is_empty() and f.director.debug_snapshot().flows.rules[0].active, "Scene rule waits for an actual deployment result, wait_for_clear=%s" % wait_for_clear)
		# Match the facade's reset order: scene actions first, runtime second.
		f.director.reset_region()
		waves.reset_encounter()
		_steps(f)
		var rule_state: Dictionary = f.director.debug_snapshot().flows.rules[0]
		check(not rule_state.active and not String(rule_state.error).is_empty(), "Region reset diagnoses and cancels the obsolete scene-scoped wave wait")
		f.events.fired.emit()
		waves.status = &"cleared" if wait_for_clear else &"active"
		waves.wave_committed.emit(wave, Vector3.ZERO)
		_steps(f)
		check(f.events.calls.is_empty() and not paused and f.director.debug_snapshot().presentation == 0, "Old wave results cannot restart a canceled action or its armed presentation")
		check(waves.requests == (0 if wait_for_clear else 1), "Region reset does not silently reissue the scene's old deployment request")
		f.events.action_finished.emit()
		_steps(f)
		check(f.events.calls == ["independent-scene-rule"], "Canceling a region-dependent action preserves unrelated scene rules")
		await _dispose(f)

func _test_headless_transition_retry() -> void:
	var f := _fixture()
	await _ready_fixture(f)
	var calls: Array[Dictionary] = []
	f.director.scene_loader = func(path: String, reload: bool) -> Error:
		calls.append({"path": path, "reload": reload})
		return ERR_CANT_OPEN
	f.director.request_change_scene("res://tests/custom_retry_destination.tscn")
	await process_frame
	await process_frame
	check(calls.size() == 1 and paused and not f.director.can_run_actions(), "Loading failure without a LevelFlow adapter still blocks ordinary actions")
	f.director.request_load_retry()
	f.director.request_load_retry()
	await process_frame
	await process_frame
	check(calls.size() == 2 and calls[0] == calls[1], "Custom UI can retry the original failed transition once through the public API")
	await _dispose(f)
