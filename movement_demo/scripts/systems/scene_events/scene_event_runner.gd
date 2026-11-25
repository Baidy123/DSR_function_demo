class_name SceneEventRunner
extends RefCounted

signal event_finished(event_id: StringName, status: StringName, reason: StringName)

const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")

var _director: Node
var _host: Node
var _entries: Array[Dictionary] = []
var _errors: PackedStringArray = []


func _init(director: Node, host: Node) -> void:
	_director = director
	_host = host


func configure(definitions: Array) -> void:
	release()
	_errors.clear()
	var ids: Dictionary = {}
	for source in definitions:
		if not source is SceneEventDefinition:
			_errors.append("Expected SceneEventDefinition")
			continue
		var id: StringName = source.event_id
		if id.is_empty():
			_errors.append("Scene event id is empty")
		elif ids.has(id):
			_errors.append("Duplicate scene event id: %s" % id)
		else:
			ids[id] = true
	if not _errors.is_empty():
		return
	for source: SceneEventDefinition in definitions:
		var definition := source.duplicate(true) as SceneEventDefinition
		var entry := {
			"definition": definition,
			"generation": 0,
			"received": {},
			"manual_requested": false,
			"fired": false,
			"active": false,
			"index": 0,
			"context": null,
			"subscriptions": [],
			"error": "",
			"terminal_generation": -1,
		}
		_entries.append(entry)
		_validate_and_subscribe(entry)


func trigger_event(event_id: StringName) -> bool:
	for entry in _entries:
		var definition: SceneEventDefinition = entry.definition
		if definition.event_id != event_id:
			continue
		if not definition.enabled or definition.start_mode != SceneEventDefinition.StartMode.MANUAL \
				or entry.fired or not entry.error.is_empty():
			return false
		entry.manual_requested = true
		return true
	return false


func can_accept_event(event_id: StringName) -> bool:
	for entry in _entries:
		var definition: SceneEventDefinition = entry.definition
		if definition.event_id == event_id:
			return definition.enabled and not entry.fired and not entry.active and entry.error.is_empty()
	return false


func reset_event(event_id: StringName) -> bool:
	for entry in _entries:
		var definition: SceneEventDefinition = entry.definition
		if definition.event_id != event_id:
			continue
		_reset_entry(entry, &"event_reset")
		return entry.error.is_empty()
	return false


func advance(delta: float) -> void:
	for entry in _entries:
		if not entry.error.is_empty():
			continue
		var definition: SceneEventDefinition = entry.definition
		if not definition.enabled:
			continue
		if not entry.active and not entry.fired and _ready_to_start(entry) and _conditions_match(entry):
			entry.fired = true
			entry.active = true
		if entry.active:
			_step(entry, delta)


func reset_region() -> void:
	for entry in _entries:
		var definition: SceneEventDefinition = entry.definition
		if definition.scope != SceneEventDefinition.Scope.REGION:
			continue
		_reset_entry(entry, &"region_reset")


func cancel_all(reason: StringName = &"event_runner_cancelled", preserve_requests: Array = [],
		preserve_event_ids: Array[StringName] = []) -> void:
	for entry in _entries:
		var definition: SceneEventDefinition = entry.definition
		if preserve_event_ids.has(definition.event_id):
			continue
		var context: SceneActionContext = entry.context
		if context != null and context.is_waiting_on_any(preserve_requests):
			continue
		var was_active: bool = entry.active
		_cancel_context(entry, reason)
		entry.active = false
		entry.fired = true
		_clear_subscriptions(entry)
		if was_active:
			_emit_terminal(entry, &"cancelled", reason)


func release() -> void:
	cancel_all(&"event_runner_released")
	_entries.clear()


func snapshot() -> Dictionary:
	var events: Array[Dictionary] = []
	for entry in _entries:
		var definition: SceneEventDefinition = entry.definition
		events.append({
			"id": definition.event_id,
			"active": entry.active,
			"fired": entry.fired,
			"action": entry.index,
			"generation": entry.generation,
			"error": entry.error,
		})
	return {"events": events, "errors": _errors.duplicate()}


func _validate_and_subscribe(entry: Dictionary) -> void:
	var definition: SceneEventDefinition = entry.definition
	if definition.start_mode == SceneEventDefinition.StartMode.TRIGGERS and definition.triggers.is_empty():
		_fail_configuration(entry, "TRIGGERS event needs at least one trigger")
		return
	if definition.start_mode != SceneEventDefinition.StartMode.TRIGGERS:
		return
	for index in range(definition.triggers.size()):
		var trigger := definition.triggers[index]
		if trigger == null:
			_fail_configuration(entry, "Scene event trigger is null")
			return
		var subscription = Subscription.new()
		var message: String = subscription.connect_trigger(_host, trigger,
			_record_trigger.bind(entry, index, entry.generation))
		if not message.is_empty():
			subscription.clear()
			_fail_configuration(entry, message)
			return
		entry.subscriptions.append(subscription)


func _record_trigger(entry: Dictionary, index: int, generation: int) -> void:
	if entry.generation != generation or entry.fired or not entry.error.is_empty():
		return
	entry.received[index] = true


func _ready_to_start(entry: Dictionary) -> bool:
	var definition: SceneEventDefinition = entry.definition
	match definition.start_mode:
		SceneEventDefinition.StartMode.AUTO:
			return true
		SceneEventDefinition.StartMode.MANUAL:
			return entry.manual_requested
		SceneEventDefinition.StartMode.TRIGGERS:
			return entry.received.size() == definition.triggers.size() \
				if definition.combination == SceneEventDefinition.Combination.ALL \
				else not entry.received.is_empty()
	return false


func _conditions_match(entry: Dictionary) -> bool:
	var definition: SceneEventDefinition = entry.definition
	var context := SceneActionContext.new().configure(_director, _host, definition, null,
		entry.generation, -1, _entry_is_current.bind(entry, entry.generation))
	for condition in definition.conditions:
		if condition == null:
			_fail_configuration(entry, "Scene condition is null")
			return false
		var diagnostics: PackedStringArray = condition.diagnostics(context)
		if not diagnostics.is_empty():
			_fail_configuration(entry, "; ".join(diagnostics))
			return false
		if not condition.matches(context):
			return false
	return true


func _step(entry: Dictionary, delta: float) -> void:
	var definition: SceneEventDefinition = entry.definition
	if entry.index >= definition.actions.size():
		entry.active = false
		_emit_terminal(entry, &"completed", &"")
		return
	var action: SceneAction = definition.actions[entry.index]
	if action == null:
		_finish_action(entry, &"failed", &"scene_action_is_null")
		return
	var context: SceneActionContext = entry.context
	if context == null:
		context = SceneActionContext.new().configure(_director, _host, definition, action,
			entry.generation, entry.index, _entry_is_current.bind(entry, entry.generation))
		entry.context = context
		action.begin(context)
	else:
		action.advance(context, delta)
	if context.is_terminal():
		_finish_action(entry, context.status, context.reason)


func _finish_action(entry: Dictionary, status: StringName, reason: StringName) -> void:
	var definition: SceneEventDefinition = entry.definition
	entry.context = null
	if status == &"completed":
		entry.index += 1
	elif status == &"failed":
		_report_failure(entry, reason)
		if definition.failure_policy == SceneEventDefinition.FailurePolicy.CONTINUE:
			entry.index += 1
		else:
			entry.active = false
			_emit_terminal(entry, &"failed", reason)
	else:
		entry.active = false
		_emit_terminal(entry, status, reason)
	if entry.index >= definition.actions.size():
		entry.active = false
		_emit_terminal(entry, &"completed", &"")


func _reset_entry(entry: Dictionary, reason: StringName) -> void:
	var was_active: bool = entry.active
	_cancel_context(entry, reason)
	_clear_subscriptions(entry)
	if was_active:
		_emit_terminal(entry, &"cancelled", reason)
	entry.generation += 1
	entry.received.clear()
	entry.manual_requested = false
	entry.fired = false
	entry.active = false
	entry.index = 0
	entry.context = null
	entry.error = ""
	_validate_and_subscribe(entry)


func _emit_terminal(entry: Dictionary, status: StringName, reason: StringName) -> void:
	var generation: int = entry.generation
	if entry.get("terminal_generation", -1) == generation:
		return
	entry.terminal_generation = generation
	event_finished.emit(entry.definition.event_id, status, reason)


func _cancel_context(entry: Dictionary, reason: StringName) -> void:
	var context: SceneActionContext = entry.context
	if context == null or context.is_terminal():
		return
	var action: SceneAction = context.action
	if action != null:
		action.cancel(context, reason)
	context.cancel(reason)


func _entry_is_current(entry: Dictionary, generation: int) -> bool:
	return entry.generation == generation and entry.active and entry.error.is_empty()


func _report_failure(entry: Dictionary, reason: StringName) -> void:
	var definition: SceneEventDefinition = entry.definition
	var message := "%s action %d: %s" % [definition.event_id, entry.index, reason]
	_errors.append(message)
	if is_instance_valid(_director) and _director.has_method(&"report_action_error"):
		_director.report_action_error(definition.label, message)


func _fail_configuration(entry: Dictionary, message: String) -> void:
	entry.error = message
	entry.active = false
	_errors.append("%s: %s" % [entry.definition.event_id, message])
	_clear_subscriptions(entry)


func _clear_subscriptions(entry: Dictionary) -> void:
	for subscription in entry.subscriptions:
		subscription.clear()
	entry.subscriptions.clear()
