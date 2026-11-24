extends RefCounted

const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")
const Action = preload("res://scripts/systems/scene_flow_action.gd")
const Rule = preload("res://scripts/systems/scene_flow_rule.gd")
const Scripts = preload("res://scripts/systems/scene_script_executor.gd")
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
			"presentation": 0, "guide": null, "request": null}
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
				_submit(entry, &"wave", target, {"present": action.present_spawn,
					"options": action.camera_options(), "target_path": action.presentation_target_path})
			Action.Kind.WAIT_WAVE_CLEARED:
				if _director.wave_status(target) == &"unknown": _fail(entry, "Unknown wave: %s" % action.target_path)
			Action.Kind.WAIT_SIGNAL:
				if action.completed_trigger == null:
					_fail(entry, "Wait signal requires an explicit trigger")
				else:
					var error: String = entry.wait.connect_trigger(_host, action.completed_trigger, _action_done.bind(entry, entry.generation, entry.execution, entry.index))
					if not error.is_empty(): _fail(entry, error)
			Action.Kind.PRESENT_TARGET:
				_submit(entry, &"presentation", target, action.camera_options())
			Action.Kind.PLAY_CINEMATIC_SHOT:
				_submit(entry, &"presentation", target, {"camera_shot": true})
			Action.Kind.GUIDE:
				_submit(entry, &"guide", target, {"pause_world": action.guide_pauses_world})
			Action.Kind.COMPLETE_SCENE:
				_submit(entry, &"completion", null, {})
			Action.Kind.RESTART:
				_submit(entry, &"transition", null, {"reload": true})
			Action.Kind.CHANGE_SCENE:
				_submit(entry, &"transition", null, {"path": action.scene_path})
			Action.Kind.CALL_METHOD:
				_submit(entry, &"script", target, {"mode": &"method", "method": action.method,
					"arguments": action.arguments, "completed_trigger": action.completed_trigger, "cancel_method": action.cancel_method})
			Action.Kind.RUN_SCRIPT:
				_submit(entry, &"script", target, {"arguments": action.arguments})
	if not entry.error.is_empty() or not entry.active: return
	if entry.request != null:
		if entry.request.is_terminal():
			if entry.request.status == &"completed": entry.done = true
			else: _fail(entry, "Action %d: %s" % [entry.index, entry.request.reason])
	else:
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
	if entry.done and entry.error.is_empty():
		entry.wait.clear()
		entry.request = null
		entry.index += 1
		entry.started = false
		entry.done = false
		if entry.index == entry.rule.actions.size(): entry.active = false

func _submit(entry: Dictionary, kind: StringName, target: Node, parameters: Dictionary) -> void:
	entry.request = _director.request_action(kind, {"source": _host, "target": target, "parameters": parameters,
		"scope": entry.rule.scope, "scope_owner": _director.region_owner(), "origin": &"rule",
		"start_guard": _condition_at_start.bind(entry, entry.generation, entry.execution)})

func _condition_at_start(entry: Dictionary, generation: int, execution: int) -> bool:
	return entry.generation == generation and entry.execution == execution and entry.active and _condition(entry)

func _cancel_request(entry: Dictionary, reason: StringName) -> void:
	var request = entry.get("request")
	entry.request = null
	if request != null and not request.is_terminal(): _director.cancel_request(request.id, reason)

func _action_done(entry: Dictionary, generation: int, execution: int, index: int) -> void:
	if entry.generation == generation and entry.execution == execution and entry.index == index and entry.active:
		entry.done = true

func _method_error(target: Node, method: StringName, arguments: Array) -> String:
	return Scripts.method_error(target, method, arguments)

func _fail(entry: Dictionary, message: String) -> void:
	_cancel_request(entry, &"action_failed")
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
		_cancel_request(entry, &"region_reset")
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
		_cancel_request(entry, &"flow_cancelled")
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
