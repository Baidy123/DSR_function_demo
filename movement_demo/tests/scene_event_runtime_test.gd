extends SceneTree

class EventSource extends Node:
	signal pulse

class Host extends Node:
	var calls: Array[String] = []
	var pending_context: SceneActionContext

	func record(value: String) -> void:
		calls.append(value)

class DirectorStub extends Node:
	var errors: Array[String] = []
	var submitted_context: Dictionary = {}
	var complete_requests_immediately := true
	var cancel_count := 0

	func can_run_actions() -> bool:
		return true

	func report_action_error(event_label: String, reason: String) -> void:
		errors.append("%s:%s" % [event_label, reason])

	func request_action(kind: StringName, context: Dictionary = {}) -> SceneRequest:
		submitted_context = context
		var scene_request := SceneRequest.new()
		scene_request.kind = kind
		if complete_requests_immediately:
			scene_request._settle(&"completed")
		return scene_request

	func cancel_request(_id: int, _reason: StringName = &"cancelled") -> void:
		cancel_count += 1

class RecordAction extends SceneAction:
	@export var value := ""

	func begin(context: SceneActionContext) -> void:
		context.host.record(value)
		context.complete()

class FailAction extends SceneAction:
	@export var reason := "expected_failure"

	func begin(context: SceneActionContext) -> void:
		context.fail(reason)

class PendingAction extends SceneAction:
	func begin(context: SceneActionContext) -> void:
		context.host.pending_context = context

class DoubleFinishAction extends SceneAction:
	func begin(context: SceneActionContext) -> void:
		context.complete()
		context.fail("late_failure")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_start_modes_and_order()
	await _test_failure_policies_and_single_terminal()
	await _test_region_reset_and_late_completion()
	await _test_event_terminal_and_manual_reset()
	await _test_context_request_contract()
	await _test_duplicate_ids()
	print("Scene event runtime assertions: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _fixture() -> Dictionary:
	var root := Node.new()
	root.name = "Fixture"
	get_root().add_child(root)
	var host := Host.new()
	host.name = "DirectorHost"
	root.add_child(host)
	var source := EventSource.new()
	source.name = "Source"
	host.add_child(source)
	var director := DirectorStub.new()
	director.name = "Director"
	host.add_child(director)
	var runner := SceneEventRunner.new(director, host)
	return {"root": root, "host": host, "source": source, "director": director, "runner": runner}


func _definition(id: StringName, mode: SceneEventDefinition.StartMode,
		actions: Array[SceneAction], scope := SceneEventDefinition.Scope.SCENE,
		policy := SceneEventDefinition.FailurePolicy.STOP) -> SceneEventDefinition:
	var definition := SceneEventDefinition.new()
	definition.event_id = id
	definition.label = String(id)
	definition.start_mode = mode
	definition.scope = scope
	definition.failure_policy = policy
	definition.actions = actions
	return definition


func _record(value: String) -> RecordAction:
	var action := RecordAction.new()
	action.value = value
	return action


func _test_start_modes_and_order() -> void:
	var f := _fixture()
	var automatic := _definition(&"automatic", SceneEventDefinition.StartMode.AUTO,
		[_record("auto_first"), _record("auto_second")])
	var manual := _definition(&"manual", SceneEventDefinition.StartMode.MANUAL,
		[_record("manual")])
	var triggered := _definition(&"triggered", SceneEventDefinition.StartMode.TRIGGERS,
		[_record("triggered")])
	var trigger := SceneEventTrigger.new()
	trigger.source_path = ^"Source"
	trigger.signal_name = &"pulse"
	triggered.triggers = [trigger]
	f.runner.configure([automatic, manual, triggered])
	f.runner.advance(0.0)
	check(f.host.calls == ["auto_first"], "AUTO begins and advances only its first action")
	f.runner.advance(0.0)
	check(f.host.calls == ["auto_first", "auto_second"], "actions keep configured order")
	check(not f.runner.trigger_event(&"missing"), "unknown manual event is rejected")
	check(f.runner.trigger_event(&"manual"), "manual event resolves by stable id")
	f.runner.advance(0.0)
	check(f.host.calls.back() == "manual", "MANUAL waits for trigger_event")
	f.source.pulse.emit()
	f.runner.advance(0.0)
	check(f.host.calls.back() == "triggered", "TRIGGERS waits for its source signal")
	check(f.runner.snapshot().errors.is_empty(), "valid start modes have no diagnostics")
	f.runner.release()
	f.root.queue_free()
	await process_frame


func _test_failure_policies_and_single_terminal() -> void:
	var f := _fixture()
	var stop_actions: Array[SceneAction] = [FailAction.new(), _record("stop_continued")]
	var continue_actions: Array[SceneAction] = [FailAction.new(), _record("continued")]
	var double_actions: Array[SceneAction] = [DoubleFinishAction.new(), _record("after_double")]
	var definitions := [
		_definition(&"stop", SceneEventDefinition.StartMode.AUTO, stop_actions),
		_definition(&"continue", SceneEventDefinition.StartMode.AUTO, continue_actions,
			SceneEventDefinition.Scope.SCENE, SceneEventDefinition.FailurePolicy.CONTINUE),
		_definition(&"double", SceneEventDefinition.StartMode.AUTO, double_actions),
	]
	f.runner.configure(definitions)
	for _i in range(4):
		f.runner.advance(0.0)
	check("stop_continued" not in f.host.calls, "STOP prevents later actions")
	check(f.host.calls.count("continued") == 1, "CONTINUE advances once after failure")
	check(f.host.calls.count("after_double") == 1, "one action terminal advances once")
	check(f.director.errors.size() == 2, "STOP and CONTINUE both report their original failure")
	f.runner.release()
	f.root.queue_free()
	await process_frame


func _test_region_reset_and_late_completion() -> void:
	var f := _fixture()
	var pending_actions: Array[SceneAction] = [PendingAction.new(), _record("late_advanced")]
	var scene_event := _definition(&"scene_once", SceneEventDefinition.StartMode.AUTO,
		[_record("scene_once")])
	var region_event := _definition(&"region_pending", SceneEventDefinition.StartMode.AUTO,
		pending_actions, SceneEventDefinition.Scope.REGION)
	f.runner.configure([scene_event, region_event])
	f.runner.advance(0.0)
	var stale: SceneActionContext = f.host.pending_context
	check(stale != null and not stale.is_terminal(), "pending action exposes current execution")
	f.runner.reset_region()
	check(stale.is_terminal() and stale.status == &"cancelled", "region reset cancels current execution")
	stale.complete()
	f.runner.advance(0.0)
	check("late_advanced" not in f.host.calls, "late completion cannot advance reset generation")
	check(f.host.calls.count("scene_once") == 1, "SCENE event does not replay on region reset")
	check(f.host.pending_context != stale, "REGION AUTO event starts a fresh generation")
	var pending_weak: WeakRef = weakref(f.host.pending_context)
	f.host.pending_context = null
	f.runner.release()
	check(pending_weak.get_ref() == null, "runner release breaks pending context references")
	f.root.queue_free()
	await process_frame


func _test_event_terminal_and_manual_reset() -> void:
	var f := _fixture()
	var terminals: Array[Array] = []
	f.runner.event_finished.connect(func(id, status, reason): terminals.append([id, status, reason]))
	var replay := _definition(&"replay", SceneEventDefinition.StartMode.MANUAL, [_record("replay")])
	var stopped := _definition(&"stopped", SceneEventDefinition.StartMode.MANUAL, [FailAction.new()])
	f.runner.configure([replay, stopped])
	check(f.runner.can_accept_event(&"replay"), "an unfired event reports that it can accept its trigger")
	check(f.runner.trigger_event(&"replay"), "replay event accepts its first manual trigger")
	f.runner.advance(0.0)
	check(terminals == [[&"replay", &"completed", &""]] and not f.runner.can_accept_event(&"replay"),
		"event completion emits one stable terminal notification")
	check(f.runner.reset_event(&"replay") and f.runner.can_accept_event(&"replay") \
		and f.runner.trigger_event(&"replay"), "a named event can be reset and accepted again")
	f.runner.advance(0.0)
	check(f.host.calls.count("replay") == 2 and terminals.size() == 2,
		"reset starts a fresh event generation without duplicating the old terminal")
	check(f.runner.trigger_event(&"stopped"), "failure event accepts its trigger")
	f.runner.advance(0.0)
	check(terminals.back() == [&"stopped", &"failed", &"expected_failure"],
		"STOP failure emits its failed terminal reason")
	f.runner.release()
	f.root.queue_free()
	await process_frame


func _test_duplicate_ids() -> void:
	var f := _fixture()
	var first := _definition(&"duplicate", SceneEventDefinition.StartMode.AUTO, [_record("first")])
	var second := _definition(&"duplicate", SceneEventDefinition.StartMode.AUTO, [_record("second")])
	f.runner.configure([first, second])
	f.runner.advance(0.0)
	var snapshot: Dictionary = f.runner.snapshot()
	check(not snapshot.errors.is_empty(), "duplicate event ids are diagnosed")
	check(f.host.calls.is_empty(), "duplicate ids never start ambiguous events")
	f.runner.release()
	f.root.queue_free()
	await process_frame


func _test_context_request_contract() -> void:
	var f := _fixture()
	var definition := _definition(&"request", SceneEventDefinition.StartMode.MANUAL, [])
	var context := SceneActionContext.new().configure(f.director, f.host, definition, null, 1, 0)
	var scene_request: SceneRequest = context.request(&"dialogue", f.source, {"line": "hello"})
	check(scene_request != null and context.status == &"completed",
		"context request maps an already-terminal request exactly once")
	check(f.director.submitted_context.get("source") == f.host,
		"context request preserves the action host as its source")
	check(f.director.submitted_context.get("target") == f.source,
		"context request forwards the target node")
	check(f.director.submitted_context.get("parameters", {}).get("line") == "hello",
		"context request copies action parameters")
	var pending_context := SceneActionContext.new().configure(
		f.director, f.host, definition, null, 1, 1)
	f.director.complete_requests_immediately = false
	check(pending_context.request(&"camera") != null, "context owns one pending request")
	pending_context.complete()
	pending_context.complete()
	check(f.director.cancel_count == 1, "terminal methods cancel the owned request exactly once")
	f.root.queue_free()
	await process_frame


func check(value: bool, label: String) -> void:
	if value:
		print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)
