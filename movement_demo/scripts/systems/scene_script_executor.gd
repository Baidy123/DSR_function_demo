extends RefCounted

const Request = preload("res://scripts/systems/scene_request.gd")
const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")
var _director: WeakRef
var _host: WeakRef
var _active: Dictionary = {}

func _init(director: Node, host: Node) -> void:
	_director = weakref(director)
	_host = weakref(host)

func begin_scene_action(request: Request) -> void:
	var target := request.node(&"target")
	if target == null:
		request.fail("missing_script_target")
		return
	if request.parameters.get("mode", &"provider") == &"provider":
		if not target.has_method("begin_scene_action") or not target.has_method("cancel_scene_action"):
			request.fail("script_needs_begin_and_cancel")
			return
		_active[request.id] = {"provider": true}
		request.finished.connect(_cleanup)
		target.begin_scene_action(request)
		return
	var method: StringName = request.parameters.get("method", &"")
	var arguments: Array = request.parameters.get("arguments", [])
	var error := method_error(target, method, arguments)
	var trigger = request.parameters.get("completed_trigger")
	var cancel_method: StringName = request.parameters.get("cancel_method", &"")
	if trigger != null:
		if cancel_method.is_empty(): error = "Async method requires an explicit cancel_method"
		elif not method_error(target, cancel_method, []).is_empty(): error = "Invalid async cancel method"
	if not error.is_empty():
		request.fail(error)
		return
	var subscription = Subscription.new()
	_active[request.id] = {"provider": false, "subscription": subscription, "cancel_method": cancel_method}
	request.finished.connect(_cleanup)
	if trigger != null:
		error = subscription.connect_trigger(_host.get_ref(), trigger, _completed.bind(request.id))
		if not error.is_empty():
			request.fail(error)
			return
	target.callv(method, arguments)
	if trigger == null: request.complete()

func cancel_scene_action(request: Request, reason: StringName) -> void:
	var entry: Dictionary = _active.get(request.id, {})
	var target := request.node(&"target")
	if entry.is_empty() or not is_instance_valid(target): return
	if entry.provider: target.cancel_scene_action(request, reason)
	elif not entry.cancel_method.is_empty(): target.call(entry.cancel_method)

func _completed(id: int) -> void:
	var director = _director.get_ref()
	var request = director.find_request(id) if is_instance_valid(director) else null
	if request != null: request.complete()

func _cleanup(request: Request) -> void:
	var entry: Dictionary = _active.get(request.id, {})
	_active.erase(request.id)
	if entry.has("subscription"): entry.subscription.clear()

static func method_error(target: Node, method: StringName, arguments: Array) -> String:
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
