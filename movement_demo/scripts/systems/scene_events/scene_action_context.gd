class_name SceneActionContext
extends RefCounted

signal finished(status: StringName, reason: StringName)

var director: Node
var host: Node
var definition: SceneEventDefinition
var action: SceneAction
var generation := 0
var event_id: StringName
var action_index := -1
var state: Dictionary = {}
var _request: SceneRequest
var _complete_on_request_failure := false
var status: StringName = &"running"
var reason: StringName
var _current_guard: Callable
var _request_cancelled := false


func configure(director_node: Node, host_node: Node, event_definition: SceneEventDefinition,
		action_resource: SceneAction, execution_generation: int, index: int,
		current_guard: Callable = Callable()) -> SceneActionContext:
	director = director_node
	host = host_node
	definition = event_definition
	action = action_resource
	generation = execution_generation
	event_id = definition.event_id if definition != null else &""
	action_index = index
	_current_guard = current_guard
	return self


func resolve(path: NodePath) -> Node:
	if not is_instance_valid(host) or path.is_empty():
		return null
	return host.get_node_or_null(path)


func request(kind: StringName, target: Node = null, parameters: Dictionary = {},
		options: Dictionary = {}, complete_on_failure := false) -> SceneRequest:
	if is_terminal() or _request != null or not is_instance_valid(director) \
			or not director.has_method(&"request_action"):
		fail(&"request_unavailable")
		return null
	var request_context := options.duplicate(true)
	request_context["source"] = request_context.get("source", host)
	if is_instance_valid(target):
		request_context["target"] = target
	request_context["parameters"] = parameters.duplicate(true)
	request_context["scope"] = int(definition.scope) if definition != null else 0
	request_context["event_id"] = event_id
	_request = director.request_action(kind, request_context) as SceneRequest
	_complete_on_request_failure = complete_on_failure
	if _request == null:
		fail(&"request_unavailable")
		return null
	if _request.is_terminal():
		_on_request_finished(_request)
	else:
		_request.finished.connect(_on_request_finished, CONNECT_ONE_SHOT)
	return _request


func complete() -> void:
	_settle(&"completed")


func fail(value: StringName) -> void:
	_settle(&"failed", value)


func cancel(value: StringName = &"cancelled") -> void:
	_settle(&"cancelled", value)


func is_terminal() -> bool:
	return status in [&"completed", &"failed", &"cancelled"]


func is_current() -> bool:
	return not is_terminal() and (not _current_guard.is_valid() or _current_guard.call() == true)


func is_waiting_on_any(requests: Array) -> bool:
	return not is_terminal() and _request != null and requests.has(_request)


func _on_request_finished(value: SceneRequest) -> void:
	if is_terminal() or value != _request:
		return
	match value.status:
		&"completed": complete()
		&"failed", &"rejected":
			if _complete_on_request_failure: complete()
			else: fail(value.reason)
		&"cancelled": cancel(value.reason)
		_:
			fail(&"invalid_request_result")


func _settle(value: StringName, why: StringName = &"") -> void:
	if is_terminal():
		return
	status = value
	reason = why
	_current_guard = Callable()
	if _request != null and not _request.is_terminal() and not _request_cancelled \
			and is_instance_valid(director) and director.has_method(&"cancel_request"):
		_request_cancelled = true
		director.cancel_request(_request.id, why if not why.is_empty() else value)
	finished.emit(status, reason)
