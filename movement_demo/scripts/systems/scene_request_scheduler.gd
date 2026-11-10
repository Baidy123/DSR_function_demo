extends RefCounted

const Request = preload("res://scripts/systems/scene_request.gd")
var _director: WeakRef
var _requests: Dictionary = {}
var _connections: Dictionary = {}
var _queue: Array[int] = []
var _foreground := 0
var _dispatching := false

func _init(director: Node) -> void:
	_director = weakref(director)

func submit(request: Request) -> void:
	_requests[request.id] = request
	request.finished.connect(_finished)
	var links: Array[Dictionary] = []
	for key in [&"source", &"target", &"player", &"scope_owner"]:
		var node := request.node(key)
		if node == null: continue
		var callback := cancel.bind(request.id, &"target_exited")
		if not node.tree_exiting.is_connected(callback):
			node.tree_exiting.connect(callback)
			links.append({"node": weakref(node), "callback": callback})
	_connections[request.id] = links
	if _foreground != 0 or _dispatching:
		if request.origin == &"interaction":
			request._settle(&"rejected", &"busy")
		else: _queue.append(request.id)
		return
	_start(request)

func duplicate_for(request: Request) -> Request:
	if request.dedupe_key.is_empty(): return null
	for previous in _requests.values():
		if previous.kind == request.kind and previous.node(&"source") == request.node(&"source") and previous.dedupe_key == request.dedupe_key:
			return previous
	return null

func _start(request: Request) -> void:
	var director = _director.get_ref()
	if director == null or not director.request_is_current(request):
		cancel(request.id, &"stale")
		return
	_foreground = request.id
	request._started = true
	request._status = &"running"
	_dispatching = true
	director.execute_request(request)
	_dispatching = false

func advance(_delta: float) -> void:
	if _foreground != 0 or _dispatching or _queue.is_empty(): return
	var next: int = _queue.pop_front()
	if _requests.has(next): _start(_requests[next])

func cancel(id: int, reason: StringName) -> void:
	var request: Request = _requests.get(id)
	if request == null or request.is_terminal() or request.status == &"cancelling": return
	# Invalidate first; cancel hooks may synchronously report completion.
	request._status = &"cancelling"
	var director = _director.get_ref()
	if is_instance_valid(director): director.cancel_request_execution(request, reason)
	request._settle(&"cancelled", reason)

func cancel_all(reason: StringName) -> void:
	for id in _requests.keys(): cancel(id, reason)

func cancel_scope(owner: Node, reason: StringName) -> void:
	for request in _requests.values().duplicate():
		if request.scope == 1 and request.node(&"scope_owner") == owner: cancel(request.id, reason)

func _finished(request: Request) -> void:
	var director = _director.get_ref()
	if is_instance_valid(director): director.release_request_controls(request)
	for link in _connections.get(request.id, []):
		var node = link.node.get_ref()
		if is_instance_valid(node) and node.tree_exiting.is_connected(link.callback):
			node.tree_exiting.disconnect(link.callback)
	_connections.erase(request.id)
	_queue.erase(request.id)
	_requests.erase(request.id)
	if _foreground == request.id: _foreground = 0
	if request.finished.is_connected(_finished): request.finished.disconnect(_finished)

func owns(request: Request) -> bool:
	return _requests.get(request.id) == request and request.status != &"cancelling"

func find(id: int) -> Request:
	return _requests.get(id)

func snapshot() -> Dictionary:
	var requests: Array[Dictionary] = []
	for request in _requests.values():
		requests.append({"id": request.id, "kind": request.kind, "status": request.status, "scope": request.scope})
	return {"requests": requests, "foreground": _foreground, "controls": _foreground}
