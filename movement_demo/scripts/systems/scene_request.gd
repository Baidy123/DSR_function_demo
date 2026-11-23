class_name SceneRequest
extends RefCounted

## One execution identity; nodes are weak references, resources remain resources.
signal finished(request: SceneRequest)
var id: int:
	get: return _id
var generation: int:
	get: return _generation
var status: StringName:
	get: return _status
var reason: StringName:
	get: return _reason
var kind: StringName
var origin: StringName = &"system"
var scope := 0
var parent_id := 0
var dedupe_key: StringName
var parameters: Dictionary = {}
var _id := 0
var _generation := 0
var _status: StringName = &"queued"
var _reason: StringName
var _started := false
var _background := false
var _result: Dictionary = {}
var _director: WeakRef
var _nodes: Dictionary = {}
var _start_guard: Callable

func node(key: StringName) -> Node:
	var ref: WeakRef = _nodes.get(key)
	return ref.get_ref() if ref != null else null

func is_terminal() -> bool:
	return _status in [&"completed", &"failed", &"cancelled", &"rejected"]

func is_current() -> bool:
	var owner = _director.get_ref() if _director != null else null
	return not is_terminal() and is_instance_valid(owner) and owner.is_inside_tree() and owner.request_is_current(self)

func has_started() -> bool:
	return _started

func get_result() -> Dictionary:
	return _result.duplicate(true)

func wait_result() -> Dictionary:
	if not is_terminal(): await finished
	return get_result()

func complete(result: Dictionary = {}) -> void:
	if is_current(): _settle(&"completed", &"", result)

func fail(message: String) -> void:
	if is_current(): _settle(&"failed", StringName(message))

func _settle(value: StringName, why: StringName = &"", result: Dictionary = {}) -> void:
	if is_terminal(): return
	_status = value
	_reason = why
	_result = result.duplicate(true)
	_result["status"] = value
	_result["reason"] = why
	finished.emit(self)
