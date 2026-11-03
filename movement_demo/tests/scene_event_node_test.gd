extends SceneTree

## SceneEvent's public relay contract and its SceneFlowRule node-path adapter.
## Runtime metadata checks do not replace interactive editor dropdown validation.
const Event = preload("res://scripts/systems/scene_event.gd")
const Filter = preload("res://scripts/systems/scene_event_filter.gd")
const Director = preload("res://scripts/systems/scene_director.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Pause = preload("res://scripts/systems/scene_pause_coordinator.gd")

var checks := 0
var failures := 0

class Counter extends RefCounted:
	var count := 0
	func received() -> void:
		count += 1

class Source extends Node:
	signal fired
	signal item_gained(item_id: StringName, amount: int)
	signal body_entered(body: Node)
	signal value_changed(value: Variant)
	var calls: Array[String] = []
	func record(label: String) -> void:
		calls.append(label)

class LateSignalSource extends Node:
	func _ready() -> void:
		add_user_signal(&"became_ready")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _test_manual_event()
	await _test_deferred_binding()
	await _test_timer()
	await _test_signal_arities()
	await _test_filters()
	await _test_invalid_bindings()
	await _test_clear_and_rebind()
	await _test_source_lifecycle()
	await _test_rule_node_paths()
	await _test_signal_property_metadata()
	await _test_recursive_sources()
	await _test_rule_source_loss()
	await _test_detached_source()
	await _test_rule_rejects_parameterized_event()
	check(Pause.for_tree(self).snapshot().count == 0 and not paused, "SceneEvent tests leave no pause owner")
	print("SCENE EVENT NODE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _fixture(source: Node = null, signal_name: StringName = &"", filters: Array = []) -> Dictionary:
	var scene := Node.new()
	scene.name = "SceneEventFixture"
	var event = Event.new()
	event.name = "Event"
	event.signal_name = signal_name
	event.filters.assign(filters)
	if source != null: event.source_path = ^"../Source"
	var counter := Counter.new()
	event.triggered.connect(counter.received)
	# Relay comes first, so a sibling's _ready may introduce its source signal.
	scene.add_child(event)
	if source != null:
		source.name = "Source"
		scene.add_child(source)
	root.add_child(scene)
	return {"scene": scene, "event": event, "source": source, "counter": counter}

func _settle() -> void:
	for frame in 3: await process_frame

func _dispose(f: Dictionary) -> void:
	f.scene.free()
	await process_frame

func _test_manual_event() -> void:
	var f := _fixture()
	await _settle()
	check(f.counter.count == 0, "An unbound SceneEvent does not trigger on initialization")
	f.event.trigger()
	f.event.trigger()
	check(f.counter.count == 2, "Direct trigger emits once per explicit invocation")
	f.event.clear_source()
	f.event.clear_source()
	f.event.trigger()
	check(f.counter.count == 3, "Clearing an optional source is idempotent and preserves manual trigger")
	await _dispose(f)

func _test_deferred_binding() -> void:
	var source := LateSignalSource.new()
	var f := _fixture(source, &"became_ready")
	await _settle()
	source.emit_signal(&"became_ready")
	check(f.counter.count == 1, "Deferred binding sees a signal created by a later sibling's _ready")
	await _dispose(f)

func _test_timer() -> void:
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 0.01
	var f := _fixture(timer, &"timeout")
	await _settle()
	timer.start()
	await create_timer(0.08).timeout
	check(f.counter.count == 1, "A real Timer timeout forwards through SceneEvent")
	f.event.clear_source()
	timer.start()
	await create_timer(0.08).timeout
	check(f.counter.count == 1, "Cleared Timer subscription no longer forwards timeouts")
	await _dispose(f)

func _test_signal_arities() -> void:
	var source := Node.new()
	for arity in range(10):
		var args: Array[Dictionary] = []
		for index in arity: args.append({"name": "argument_%d" % index, "type": TYPE_NIL})
		source.add_user_signal("arity_%d" % arity, args)
	var f := _fixture(source, &"arity_0")
	await _settle()
	for arity in range(9):
		f.event.signal_name = StringName("arity_%d" % arity)
		f.event.filters.clear()
		if arity > 0:
			var last_parameter = Filter.new()
			last_parameter.parameter_index = arity - 1
			last_parameter.value_type = Filter.ValueType.INT
			last_parameter.int_value = arity - 1
			f.event.filters.append(last_parameter)
		var error: String = f.event.bind_source()
		check(error.is_empty(), "Signal with %d arguments can be bound" % arity)
		var args: Array = [f.event.signal_name]
		for index in arity: args.append(index)
		var before: int = f.counter.count
		if arity > 0:
			var wrong: Array = args.duplicate()
			wrong[-1] = -1
			source.callv("emit_signal", wrong)
			check(f.counter.count == before, "Final-parameter filter rejects a mismatch for arity %d" % arity)
		source.callv("emit_signal", args)
		check(f.counter.count == before + 1, "Signal adapter forwards exactly one event for arity %d" % arity)
	f.event.signal_name = &"arity_9"
	check(not f.event._get_configuration_warnings().is_empty(), "Unsupported signal arity is visible in node configuration warnings")
	check(not String(f.event.bind_source()).is_empty(), "Unsupported arity reports a binding error before connecting")
	var before: int = f.counter.count
	source.emit_signal(&"arity_9", 0, 1, 2, 3, 4, 5, 6, 7, 8)
	check(f.counter.count == before, "Unsupported signal cannot trigger the relay")
	await _dispose(f)

func _test_filters() -> void:
	var item = Filter.new()
	item.string_name_value = &"key"
	var amount = Filter.new()
	amount.parameter_index = 1
	amount.value_type = Filter.ValueType.INT
	amount.int_value = 2
	var source := Source.new()
	var f := _fixture(source, &"item_gained", [item, amount])
	await _settle()
	source.item_gained.emit(&"other", 2)
	source.item_gained.emit(&"key", 1)
	check(f.counter.count == 0, "All configured parameter filters must match")
	source.item_gained.emit(&"key", 2)
	check(f.counter.count == 1, "Matching typed item and amount forward one event")
	item.string_name_value = &"changed"
	source.item_gained.emit(&"key", 2)
	check(f.counter.count == 2, "Bound filters keep their runtime snapshot until explicitly rebound")
	check(String(f.event.bind_source()).is_empty(), "Updated filters can be explicitly rebound")
	source.item_gained.emit(&"key", 2)
	source.item_gained.emit(&"changed", 2)
	check(f.counter.count == 3, "Rebinding applies new filter configuration once")
	var exact = Filter.new()
	exact.value_type = Filter.ValueType.INT
	exact.int_value = 1
	f.event.signal_name = &"value_changed"
	f.event.filters.assign([exact])
	check(String(f.event.bind_source()).is_empty(), "Variant signals can use a strict typed filter")
	source.value_changed.emit(1.0)
	source.value_changed.emit(true)
	source.value_changed.emit("1")
	check(f.counter.count == 3, "Float, boolean, and string do not coerce into an integer filter match")
	source.value_changed.emit(1)
	check(f.counter.count == 4, "Exact integer variant matches")
	var group = Filter.new()
	group.operator = Filter.Operator.NODE_IN_GROUP
	group.group_name = &"player"
	f.event.signal_name = &"body_entered"
	f.event.filters.assign([group])
	check(String(f.event.bind_source()).is_empty(), "Node parameter supports a player-group filter")
	var player := Node.new()
	var other := Node.new()
	f.scene.add_child(player)
	f.scene.add_child(other)
	player.add_to_group(&"player")
	source.body_entered.emit(other)
	source.body_entered.emit(null)
	check(f.counter.count == 4, "Non-player and null bodies cannot trigger a player entry event")
	source.body_entered.emit(player)
	check(f.counter.count == 5, "The configured player group is accepted")
	await _dispose(f)

func _test_invalid_bindings() -> void:
	var source := Source.new()
	var f := _fixture(source, &"fired")
	await _settle()
	f.event.source_path = ^"../Missing"
	check(not String(f.event.bind_source()).is_empty(), "Missing explicit source reports a binding error")
	source.fired.emit()
	check(f.counter.count == 0, "A failed rebind does not leave the old source active")
	f.event.source_path = ^"../Source"
	f.event.signal_name = &"missing_signal"
	check(not String(f.event.bind_source()).is_empty(), "Missing source signal reports a binding error")
	f.event.signal_name = &"item_gained"
	var filter = Filter.new()
	filter.parameter_index = 3
	f.event.filters.assign([filter])
	check(not f.event._get_configuration_warnings().is_empty(), "Node configuration warnings expose an out-of-range filter parameter")
	check(not String(f.event.bind_source()).is_empty(), "Out-of-range filter parameter is rejected")
	filter.parameter_index = 0
	filter.value_type = Filter.ValueType.INT
	check(not f.event._get_configuration_warnings().is_empty(), "Node configuration warnings expose a filter type mismatch")
	check(not String(f.event.bind_source()).is_empty(), "Filter type incompatible with the declared signal parameter is rejected")
	f.event.filters.clear()
	f.event.filters.append(null)
	check(not f.event._get_configuration_warnings().is_empty(), "Node configuration warnings expose a null filter resource")
	check(not String(f.event.bind_source()).is_empty(), "Null filters report invalid configuration")
	f.event.filters.clear()
	check(f.event._get_configuration_warnings().is_empty(), "Correcting filters clears their configuration warnings")
	await _dispose(f)

func _test_clear_and_rebind() -> void:
	var source := Source.new()
	var f := _fixture(source, &"fired")
	await _settle()
	for repeat in 3:
		check(String(f.event.bind_source()).is_empty(), "Repeated bind remains valid")
	source.fired.emit()
	check(f.counter.count == 1 and source.fired.get_connections().size() == 1, "Repeated binding owns only one connection")
	var stale: Callable = source.fired.get_connections()[0].callable
	f.event.clear_source()
	check(source.fired.get_connections().is_empty(), "clear_source removes the source connection")
	if stale.is_valid(): stale.call()
	source.fired.emit()
	check(f.counter.count == 1, "Cleared-generation callback and old source emission cannot trigger")
	var second := Source.new()
	second.name = "Second"
	f.scene.add_child(second)
	f.event.source_path = ^"../Second"
	check(String(f.event.bind_source()).is_empty(), "A different source can be explicitly bound")
	source.fired.emit()
	second.fired.emit()
	check(f.counter.count == 2, "After rebinding only the new source forwards events")
	f.event.free()
	check(second.fired.get_connections().is_empty(), "Relay destruction releases its source subscription")
	second.fired.emit()
	check(f.counter.count == 2, "Destroyed relay cannot emit a late event")
	await _dispose(f)

func _test_source_lifecycle() -> void:
	var source := Source.new()
	var f := _fixture(source, &"fired")
	await _settle()
	source.free()
	await _settle()
	check(f.counter.count == 0, "Source loss never fabricates a successful event")
	check(not f.event.diagnostics().is_empty(), "Public diagnostics report a disappearing bound source without rebinding")
	check(not String(f.event.bind_source()).is_empty(), "Source loss remains diagnosable through explicit binding")
	var replacement := Source.new()
	replacement.name = "Source"
	f.scene.add_child(replacement)
	check(String(f.event.bind_source()).is_empty(), "An explicitly requested replacement source can be rebound")
	check(f.event.diagnostics().is_empty(), "Successful rebinding clears the old source diagnostic")
	replacement.fired.emit()
	check(f.counter.count == 1, "Replacement source forwards exactly one event")
	f.scene.remove_child(f.event)
	check(replacement.fired.get_connections().is_empty(), "Relay leaving the tree releases the binding before it is freed")
	replacement.fired.emit()
	check(f.counter.count == 1, "Detached relay does not forward source signals")
	f.event.free()
	await _dispose(f)

func _record(label: String) -> Resource:
	var action = Action.new()
	action.kind = Action.Kind.CALL_METHOD
	action.target_path = ^"../Source"
	action.method = &"record"
	action.arguments = [label]
	return action

func _test_rule_node_paths() -> void:
	var source := Source.new()
	var f := _fixture(source, &"fired")
	var host := Node.new()
	host.name = "EnemyWaves"
	f.scene.add_child(host)
	var first = Rule.new()
	first.event_nodes.append(^"../Event")
	first.actions.append(_record("first"))
	var second = Rule.new()
	second.event_nodes.append(^"../Event")
	second.actions.append(_record("second"))
	var director = Director.new()
	director.configure(host, {"rules": [first, second]})
	host.add_child(director)
	await _settle()
	director.set_process(false)
	for step in 4: director.advance(0.0)
	check(source.calls.is_empty(), "Rules configured with event_nodes wait instead of auto-running")
	var ledger = Pause.for_tree(self)
	var token: int = ledger.acquire(f.scene, &"event_test")
	source.fired.emit()
	f.event.trigger()
	check(f.counter.count == 2 and source.calls.is_empty(), "Bound and direct events can be received while paused without recursively executing actions")
	for step in 4: director.advance(1.0)
	check(source.calls.is_empty(), "Paused director keeps SceneEvent actions pending")
	ledger.release(token)
	for step in 4: director.advance(0.0)
	check(source.calls == ["first", "second"], "One SceneEvent independently satisfies multiple rules after pause release")
	f.event.trigger()
	for step in 4: director.advance(0.0)
	check(source.calls == ["first", "second"], "Repeated relay events do not replay a once-per-scene rule")
	await _dispose(f)

func _signal_property(event: Node) -> Dictionary:
	for property in event.get_property_list():
		if property.name == "signal_name": return property
	return {}

func _test_signal_property_metadata() -> void:
	var f := _fixture(Source.new(), &"fired")
	await _settle()
	var property := _signal_property(f.event)
	check(property.get("hint", PROPERTY_HINT_NONE) == PROPERTY_HINT_ENUM, "Signal-name property exposes dynamic enum metadata")
	var names: PackedStringArray = String(property.get("hint_string", "")).split(",")
	check(names.has("fired") and names.has("item_gained") and names.has("body_entered"), "Signal enum includes the selected source's actual business signals")
	var timer := Timer.new()
	timer.name = "OtherSource"
	f.scene.add_child(timer)
	f.event.source_path = ^"../OtherSource"
	property = _signal_property(f.event)
	names = String(property.get("hint_string", "")).split(",")
	check(names.has("timeout") and not names.has("item_gained"), "Changing the source refreshes signal options instead of retaining another node's signals")
	await _dispose(f)

func _test_recursive_sources() -> void:
	var f := _fixture()
	await _settle()
	f.event.source_path = ^"."
	f.event.signal_name = &"triggered"
	check(not String(f.event.bind_source()).is_empty(), "SceneEvent rejects itself as its signal source")
	check(not f.event.diagnostics().is_empty(), "Self-reference has a public diagnostic")
	var other = Event.new()
	other.name = "OtherEvent"
	other.source_path = ^"../Event"
	other.signal_name = &"triggered"
	var other_counter := Counter.new()
	other.triggered.connect(other_counter.received)
	f.scene.add_child(other)
	f.event.source_path = ^"../OtherEvent"
	check(String(f.event.bind_source()).is_empty(), "A distinct SceneEvent can be used as a relay source")
	await _settle()
	check(not f.event.diagnostics().is_empty() and not other.diagnostics().is_empty(), "Mutually bound relays report a finite recursive-source diagnostic")
	f.event.trigger()
	check(f.counter.count == 1 and other_counter.count == 1, "Mutual relay recursion stops without duplicate trigger emission or stack overflow")
	other.clear_source()
	check(String(f.event.bind_source()).is_empty() and f.event.diagnostics().is_empty(), "Removing a cycle and rebinding clears recursive-source errors")
	other.trigger()
	check(f.counter.count == 2 and other_counter.count == 2, "The repaired one-way relay chain forwards normally")
	await _dispose(f)

func _test_rule_source_loss() -> void:
	for emit_first in [false, true]:
		var source := Source.new()
		var f := _fixture(source, &"fired")
		var host := Node.new()
		host.name = "EnemyWaves"
		f.scene.add_child(host)
		var sink := Source.new()
		sink.name = "Sink"
		f.scene.add_child(sink)
		var action = _record("latched")
		action.target_path = ^"../Sink"
		var rule = Rule.new()
		rule.event_nodes.append(^"../Event")
		rule.actions.append(action)
		var director = Director.new()
		director.configure(host, {"rules": [rule]})
		host.add_child(director)
		await _settle()
		director.set_process(false)
		if emit_first: source.fired.emit()
		source.free()
		for step in 4: director.advance(0.0)
		if emit_first:
			check(sink.calls == ["latched"], "A valid relay event remains latched when its pickup-like source disappears afterward")
		else:
			check(sink.calls.is_empty() and not String(director.debug_snapshot().last_error).is_empty(), "A surviving relay propagates its lost underlying source diagnostic to the waiting rule")
		await _dispose(f)

func _test_detached_source() -> void:
	var source := Source.new()
	var f := _fixture(source, &"fired")
	await _settle()
	f.scene.remove_child(source)
	check(not f.event.diagnostics().is_empty(), "A detached but still-live source is diagnosed as unavailable")
	source.fired.emit()
	check(f.counter.count == 0, "Signals from a source that left the scene cannot satisfy a pending event")
	f.scene.add_child(source)
	check(String(f.event.bind_source()).is_empty(), "Returned source can be explicitly rebound")
	source.fired.emit()
	check(f.counter.count == 1, "Returned source resumes a single valid subscription")
	await _dispose(f)

func _test_rule_rejects_parameterized_event() -> void:
	var source := Source.new()
	var f := _fixture(source, &"fired")
	var invalid := Node.new()
	invalid.name = "ParameterizedEvent"
	invalid.add_user_signal(&"triggered", [{"name": "value", "type": TYPE_INT}])
	f.scene.add_child(invalid)
	var host := Node.new()
	host.name = "EnemyWaves"
	f.scene.add_child(host)
	var rule = Rule.new()
	rule.event_nodes.append(^"../ParameterizedEvent")
	rule.actions.append(_record("invalid-event"))
	var director = Director.new()
	director.configure(host, {"rules": [rule]})
	host.add_child(director)
	await _settle()
	director.set_process(false)
	var entry: Dictionary = director.debug_snapshot().flows.rules[0]
	check(not String(entry.error).is_empty() and not entry.active, "Rule event_nodes rejects a parameterized triggered signal with an entry diagnostic")
	check(invalid.get_signal_connection_list(&"triggered").is_empty(), "Rejected parameterized triggered signal is never connected")
	invalid.emit_signal(&"triggered", 1)
	for step in 4: director.advance(0.0)
	check(source.calls.is_empty(), "Emitting a rejected parameterized event cannot run its rule")
	await _dispose(f)
