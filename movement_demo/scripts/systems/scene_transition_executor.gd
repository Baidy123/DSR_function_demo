extends RefCounted

const Request = preload("res://scripts/systems/scene_request.gd")
const Transition = preload("res://scripts/systems/scene_transition.gd")
var _director: WeakRef
var _state: WeakRef
var _request: Request
var _prepared: Dictionary = {}
var _generation := 0
var _native_call := false
var _cancelled := false

func _init(director: Node) -> void:
	_director = weakref(director)

func begin_scene_action(request: Request) -> void:
	var director = _director.get_ref()
	_request = request
	_generation = director._generation
	_cancelled = false
	var state: Node = director.get_node_or_null("/root/GameState")
	_state = weakref(state) if state != null else null
	var parameters := request.parameters
	if state != null:
		_prepared = state.prepare_scene_transition(parameters.get("mode", &"plain"),
			parameters.get("player_snapshot", {}), parameters.get("level_number", 0),
			parameters.get("save_snapshot", {}))
		if _prepared.is_empty():
			director.finish_transition(request, &"failed", &"invalid_transition_state")
			return
	_run.call_deferred(request)

func _current() -> bool:
	var director = _director.get_ref()
	return not _cancelled and is_instance_valid(director) and director.is_inside_tree() and director._load_request == _request and director._generation == _generation

func _authorize_native_call() -> bool:
	if not _current(): return false
	var state = _state.get_ref() if _state != null else null
	if state != null and not state.validate_scene_transition(_prepared): return false
	_native_call = true
	return true

func _accepted() -> void:
	if _cancelled: return
	var state = _state.get_ref() if _state != null else null
	if state != null:
		if not state.commit_scene_transition(_prepared):
			push_error("Validated scene transition could not commit")
			return
	_prepared = {}
	var director = _director.get_ref()
	if is_instance_valid(director): director.finish_transition(_request, &"completed")

func _run(request: Request) -> void:
	if not _current():
		cancel_scene_action(request, &"scene_exited")
		return
	var director = _director.get_ref()
	var tree: SceneTree = director.get_tree()
	var path: String = request.parameters.get("path", "")
	var reload_current: bool = request.parameters.get("reload", false)
	var result: int
	if director.scene_loader.is_valid():
		result = await director.scene_loader.call(path, reload_current)
		if _current() and result == OK: _accepted()
	elif reload_current:
		result = await Transition.reload_scene(tree, _authorize_native_call, _accepted)
	else:
		result = await Transition.change_scene(tree, path, _authorize_native_call, _accepted)
	_native_call = false
	if _cancelled or request.is_terminal(): return
	if not _current():
		cancel_scene_action(request, &"scene_exited")
		return
	var state = _state.get_ref() if _state != null else null
	if state != null: state.discard_scene_transition(_prepared)
	_prepared = {}
	director.finish_transition(request, &"failed", StringName(error_string(result)))

func is_committing() -> bool:
	return _native_call

func cancel_scene_action(request: Request, reason: StringName) -> void:
	if _request != request or _cancelled: return
	_cancelled = true
	var state = _state.get_ref() if _state != null else null
	if state != null: state.discard_scene_transition(_prepared)
	_prepared = {}
	var director = _director.get_ref()
	if is_instance_valid(director): director.finish_transition(request, &"cancelled", reason)
