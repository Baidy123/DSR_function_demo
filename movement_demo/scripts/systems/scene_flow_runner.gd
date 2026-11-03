extends RefCounted

const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
var _director: Node
var _host: Node
var _entries: Array[Dictionary] = []
var _next_execution := 0
var _errors: PackedStringArray = []

func _init(director: Node, host: Node) -> void:
	_director = director
	_host = host

func configure(rules: Array) -> void:
	release()
	for source in rules:
		if source == null:
			_errors.append("Scene rule is null")
			continue
		var rule = source.duplicate(true)
		rule.triggers = rule.event_configuration()
		var entry := {"rule": rule, "generation": 0, "received": {}, "fired": false, "active": false,
			"index": 0, "remaining": 0.0, "started": false, "done": false, "error": "",
			"subscriptions": [], "wait": Subscription.new(), "execution": 0,
			"presentation": 0, "guide": null}
		_entries.append(entry)
		for path in rule.event_nodes:
			var source_node := _host.get_node_or_null(path) if not path.is_empty() else null
			if source_node == null or not source_node.has_signal(&"triggered"):
				_fail(entry, "Event Nodes requires a node with triggered: %s" % path)
				break
			for metadata in source_node.get_signal_list():
				if metadata.name == &"triggered" and not metadata.args.is_empty():
					_fail(entry, "Event Nodes triggered must have no arguments: %s" % path)
		if not entry.error.is_empty(): continue
		_subscribe(entry)

func _subscribe(entry: Dictionary) -> void:
	for subscription in entry.subscriptions: subscription.clear()
	entry.subscriptions.clear()
	for i in range(entry.rule.triggers.size()):
		var subscription = Subscription.new()
		entry.subscriptions.append(subscription)
		var message: String = subscription.connect_trigger(_host, entry.rule.triggers[i], _record.bind(entry, i, entry.generation))
		if not message.is_empty(): _fail(entry, message)

func _source_errors(entry: Dictionary) -> PackedStringArray:
	var errors: PackedStringArray = []
	if _triggered(entry): return errors
	var available := 0
	for index in range(entry.subscriptions.size()):
		if entry.received.has(index): continue
		var diagnostics: PackedStringArray = entry.subscriptions[index].diagnostics()
		if diagnostics.is_empty(): available += 1
		else: errors.append_array(diagnostics)
	if entry.rule.combination == Rule.Combination.ANY and available > 0: errors.clear()
	return errors

func _record(entry: Dictionary, index: int, generation: int) -> void:
	if entry.generation != generation or entry.fired or not entry.error.is_empty(): return
	entry.received[index] = true

func advance(delta: float) -> void:
	# Select eligible entries before invoking actions. Signals caused by an action run next tick.
	var eligible: Array[Dictionary] = []
	for entry in _entries:
		if not entry.error.is_empty(): continue
		var diagnostics: PackedStringArray = entry.wait.diagnostics() if entry.active else _source_errors(entry)
		if not diagnostics.is_empty() and not entry.done and not entry.fired:
			_fail(entry, "; ".join(diagnostics))
			continue
		if entry.active and not entry.done and not entry.wait.diagnostics().is_empty():
			_fail(entry, "; ".join(entry.wait.diagnostics()))
			continue
		if entry.active: eligible.append(entry)
		elif not entry.fired and _triggered(entry) and _condition(entry):
			entry.fired = true
			entry.active = true
			_next_execution += 1
			entry.execution = _next_execution
			eligible.append(entry)
	for entry in eligible:
		if not _director.can_run_actions(): break
		_step(entry, delta)

func _triggered(entry: Dictionary) -> bool:
	var rule = entry.rule
	return rule.triggers.is_empty() or (entry.received.size() == rule.triggers.size() if rule.combination == Rule.Combination.ALL else not entry.received.is_empty())

func _condition(entry: Dictionary) -> bool:
	var rule = entry.rule
	if rule.condition_method.is_empty(): return true
	var target := _host.get_node_or_null(rule.condition_target)
	var error := _method_error(target, rule.condition_method, rule.condition_arguments)
	if not error.is_empty():
		_fail(entry, "Rule predicate: " + error)
		return false
	var value = target.callv(rule.condition_method, rule.condition_arguments)
	if not value is bool:
		_fail(entry, "Rule predicate must return bool")
		return false
	return value

func _step(entry: Dictionary, delta: float) -> void:
	if entry.index >= entry.rule.actions.size():
		entry.active = false
		return
	var action = entry.rule.actions[entry.index]
	if action == null:
		_fail(entry, "Null scene action")
		return
	var target := _host.get_node_or_null(action.target_path) if not action.target_path.is_empty() else null
	if not entry.started:
		entry.started = true
		entry.done = false
		entry.remaining = action.seconds
		match action.kind:
			Action.Kind.WAIT:
				if not is_finite(action.seconds) or action.seconds < 0.0: _fail(entry, "Invalid wait duration")
			Action.Kind.REQUEST_WAVE:
				if not _director.request_wave_for_flow(target, action.present_spawn, action.camera_options(), entry.rule.scope, action.presentation_target_path):
					_fail(entry, "Wave request rejected: %s" % action.target_path)
			Action.Kind.WAIT_WAVE_CLEARED:
				if _director.wave_status(target) == &"unknown": _fail(entry, "Unknown wave: %s" % action.target_path)
			Action.Kind.PRESENT_TARGET:
				if not target is Node3D:
					_fail(entry, "Presentation target must be Node3D")
				else:
					entry.presentation = _director.present_target(target.global_position, action.camera_options(), entry.rule.scope)
					if entry.presentation < 0: entry.started = false # Another rule owns the camera; retry later.
					elif entry.presentation == 0: entry.done = true # Optional presentation unavailable.
			Action.Kind.GUIDE:
				entry.guide = target
				if not _director.begin_guide(target, action.guide_pauses_world, entry.rule.scope): _fail(entry, "Guide request failed")
			Action.Kind.COMPLETE_SCENE:
				_director.request_completion()
				entry.done = true
			Action.Kind.RESTART:
				_director.request_restart_from_flow()
				entry.done = true
			Action.Kind.CHANGE_SCENE:
				_director.request_change_scene(action.scene_path)
				entry.done = true
			Action.Kind.CALL_METHOD, Action.Kind.WAIT_SIGNAL:
				if action.completed_trigger != null:
					var error: String = entry.wait.connect_trigger(_host, action.completed_trigger, _action_done.bind(entry, entry.generation, entry.execution, entry.index))
					if not error.is_empty(): _fail(entry, error)
				elif action.kind == Action.Kind.WAIT_SIGNAL:
					_fail(entry, "Wait signal requires an explicit trigger")
				if action.kind == Action.Kind.CALL_METHOD and entry.error.is_empty():
					var method_error := _method_error(target, action.method, action.arguments)
					if not method_error.is_empty():
						_fail(entry, method_error)
					else:
						target.callv(action.method, action.arguments)
						if action.completed_trigger == null: entry.done = true
	if not entry.error.is_empty() or not entry.active: return
	match action.kind:
		Action.Kind.WAIT:
			entry.remaining = maxf(0.0, entry.remaining - delta)
			entry.done = entry.remaining <= 0.0
		Action.Kind.REQUEST_WAVE:
			var status: StringName = _director.wave_status(target)
			entry.done = status in [&"active", &"clearing", &"cleared"]
			if status in [&"error", &"unknown"]: _fail(entry, "Wave deployment failed: %s" % action.target_path)
		Action.Kind.WAIT_WAVE_CLEARED:
			entry.done = _director.wave_status(target) == &"cleared"
			if _director.wave_status(target) in [&"error", &"unknown"]: _fail(entry, "Wave wait target lost")
		Action.Kind.PRESENT_TARGET:
			entry.done = entry.started and not _director.is_presentation_pending(entry.presentation)
		Action.Kind.GUIDE:
			if not is_instance_valid(entry.guide): _fail(entry, "Guide removed before completion")
			else: entry.done = not _director.is_guide_pending(entry.guide)
	if entry.done and entry.error.is_empty():
		entry.wait.clear()
		entry.index += 1
		entry.started = false
		entry.done = false
		if entry.index == entry.rule.actions.size(): entry.active = false

func _action_done(entry: Dictionary, generation: int, execution: int, index: int) -> void:
	if entry.generation == generation and entry.execution == execution and entry.index == index and entry.active:
		entry.done = true

func _method_error(target: Node, method: StringName, arguments: Array) -> String:
	if not is_instance_valid(target) or not target.is_inside_tree() or method.is_empty() or method.begins_with("_") or not target.has_method(method):
		return "Missing public action method: %s" % method
	for metadata in target.get_method_list():
		if metadata.name != method: continue
		var parameters: Array = metadata.args
		var minimum: int = parameters.size() - metadata.default_args.size()
		if arguments.size() < minimum or (not metadata.flags & METHOD_FLAG_VARARG and arguments.size() > parameters.size()):
			return "Method %s received %d arguments; expects %d..%d" % [method, arguments.size(), minimum, parameters.size()]
		for i in range(mini(parameters.size(), arguments.size())):
			var expected: int = parameters[i].type
			var actual: int = typeof(arguments[i])
			if expected == TYPE_NIL or actual == expected or (expected == TYPE_FLOAT and actual == TYPE_INT): continue
			if expected == TYPE_OBJECT and arguments[i] == null: continue
			return "Method %s argument %d expects %s, received %s" % [method, i, type_string(expected), type_string(actual)]
		return ""
	return "Method metadata missing: %s" % method

func _fail(entry: Dictionary, message: String) -> void:
	entry.error = message
	entry.active = false
	entry.wait.clear()
	_errors.append("%s: %s" % [entry.rule.label, message])
	_director.report_action_error(entry.rule.label, message)

func reset_region() -> void:
	for entry in _entries:
		if entry.rule.scope != Rule.Scope.REGION:
			# Scene rules do not replay, but cannot keep waiting on a retired deployment.
			if entry.active and entry.started and entry.index < entry.rule.actions.size():
				var action = entry.rule.actions[entry.index]
				if action != null and action.kind in [Action.Kind.REQUEST_WAVE, Action.Kind.WAIT_WAVE_CLEARED]:
					entry.generation += 1
					_fail(entry, "Region reset cancelled pending deployment")
			continue
		entry.generation += 1
		entry.wait.clear()
		entry.received.clear()
		entry.fired = false
		entry.active = false
		entry.started = false
		entry.done = false
		entry.index = 0
		entry.error = ""
		_subscribe(entry)

func cancel_all() -> void:
	for entry in _entries:
		entry.generation += 1
		entry.active = false
		entry.fired = true
		entry.wait.clear()
		for subscription in entry.subscriptions: subscription.clear()
		entry.subscriptions.clear()

func release() -> void:
	cancel_all()
	_entries.clear()
	_errors.clear()

func snapshot() -> Dictionary:
	var entries: Array[Dictionary] = []
	for entry in _entries:
		entries.append({"label": entry.rule.label, "active": entry.active, "fired": entry.fired, "action": entry.index,
			"remaining": entry.remaining, "events": entry.received.size(), "error": entry.error, "execution": entry.execution})
	return {"rules": entries, "errors": _errors.duplicate()}
