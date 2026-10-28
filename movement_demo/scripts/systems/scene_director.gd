extends Node

## Scene lifecycle, independent of enemy deployment and CombatZone occupancy.
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")
const Flows = preload("res://scripts/systems/scene_flow_runner.gd")
const ResultView = preload("res://scripts/ui/scene_result_view.gd")
signal state_changed(value: StringName)
signal action_failed(rule: String, reason: String)
var state: StringName = &"preparing"
## Optional loading adapter; return an Error, never report success before accepting the load.
var scene_loader: Callable
var _host: Node
var _bindings: Dictionary
var _health: Node
var _level_flow: Node
var _result_view
var _waves
var _flows
var _pauses
var _camera: Camera3D
var _owns_camera := false
var _initialized := false
var _generation := 0
var _terminal_token := 0
var _guide_token := 0
var _camera_token := 0
var _guide: Node
var _guide_callback: Callable
var _guide_exit_callback: Callable
var _guide_finished := false
var _guide_scope := 0
var _completion_pending := false
var _completion_frame := -1
var _presentation_id := 0
var _active_presentation := 0
var _presentation_scope := 0
var _armed_presentations: Dictionary = {}
var _last_error := ""
var _load_path := ""
var _load_reload := false
var _load_failed := false
var _before_load: StringName
var _connections: Array[Dictionary] = []

func configure(host: Node, bindings: Dictionary = {}) -> void:
	_host = host
	_bindings = bindings

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	initialize.call_deferred()

func initialize() -> void:
	if _initialized or not is_inside_tree(): return
	_initialized = true
	if not is_instance_valid(_host): _host = get_parent()
	_pauses = Pauses.for_tree(get_tree())
	_health = _bindings.get("health")
	if is_instance_valid(_health):
		var existing: WeakRef = _health.get_meta(&"scene_director") if _health.has_meta(&"scene_director") else null
		if existing != null and is_instance_valid(existing.get_ref()) and existing.get_ref() != self:
			report_action_error("bindings", "This player already has a scene director")
			_initialized = false
			_set_state(&"error")
			return
		_health.set_meta(&"scene_director", weakref(self))
	_level_flow = _bindings.get("level_flow")
	_waves = _bindings.get("wave_runtime")
	_camera = _bindings.get("camera")
	_result_view = _bindings.get("result_view")
	if _result_view == null:
		_result_view = ResultView.new()
		_result_view.bind(_health)
	_link(_result_view, &"restart_requested", request_restart)
	_link(_health, &"died", _on_player_died)
	_link(_level_flow, &"continue_requested", request_next_level)
	_link(_waves, &"encounter_completed", _on_waves_completed)
	_link(_waves, &"wave_committed", _on_wave_committed)
	_flows = Flows.new(self, _host)
	_flows.configure(_bindings.get("rules", []))
	if _waves != null: _waves.prepare_events()
	var guide: Node = _bindings.get("guide")
	if guide != null:
		if not begin_guide(guide, _bindings.get("guide_pauses_world", true)): _set_state(&"error")
	elif _bindings.get("guide_required", false):
		report_action_error("opening", "Configured guide is missing")
		_set_state(&"error")
	else:
		_set_state(&"running")
	if is_instance_valid(_health) and _health.get("is_dead") == true: _on_player_died()

func _link(source, signal_name: StringName, callback: Callable) -> void:
	if not is_instance_valid(source) or not source.has_signal(signal_name): return
	if not source.is_connected(signal_name, callback):
		source.connect(signal_name, callback)
		_connections.append({"source": weakref(source), "signal": signal_name, "callback": callback})

func _process(delta: float) -> void:
	advance(delta)

func advance(delta: float) -> void:
	if not _initialized or not is_inside_tree(): return
	if _active_presentation != 0 and _pauses.can_advance_presentation(_camera_token):
		if is_instance_valid(_camera): _camera.advance_presentation(delta)
		else: _finish_presentation()
	if not can_run_actions(): return
	_flows.advance(delta)
	if _completion_pending and state == &"running" and _active_presentation == 0 and _guide == null and Engine.get_process_frames() > _completion_frame:
		_finish_completion()

func can_run_actions() -> bool:
	return _initialized and not _load_failed and state in [&"running", &"guide"] and not get_tree().paused

func begin_guide(provider: Node, pause_world: bool = true, scope: int = 0) -> bool:
	if _guide != null or not is_instance_valid(provider) or not provider.has_method("begin") or not provider.has_method("cancel") or not provider.has_signal("finished"):
		report_action_error("guide", "Guide needs begin(), cancel() and finished")
		return false
	_guide = provider
	_guide_scope = scope
	_guide_finished = false
	if pause_world: _guide_token = _pauses.acquire(self, &"guide", true)
	_set_state(&"guide")
	_guide_callback = _on_guide_finished.bind(_generation, provider.get_instance_id())
	_guide_exit_callback = _on_guide_exiting.bind(_generation, provider.get_instance_id())
	provider.connect(&"finished", _guide_callback)
	provider.tree_exiting.connect(_guide_exit_callback)
	# Completion is subscribed before begin(), including synchronous providers.
	provider.begin()
	return true

func is_guide_pending(provider: Node) -> bool:
	return is_instance_valid(provider) and _guide == provider

func _on_guide_finished(generation: int, id: int) -> void:
	if generation != _generation or not is_instance_valid(_guide) or _guide.get_instance_id() != id: return
	_guide_finished = true
	_clear_guide(false)
	if state == &"guide": _set_state(&"running")

func _on_guide_exiting(generation: int, id: int) -> void:
	if generation != _generation or not is_instance_valid(_guide) or _guide.get_instance_id() != id: return
	_clear_guide(false)
	if state == &"guide":
		report_action_error("guide", "Guide removed before completion")
		_set_state(&"error")

func _clear_guide(cancel: bool) -> void:
	var previous := _guide
	_guide = null
	if is_instance_valid(previous):
		if previous.is_connected(&"finished", _guide_callback): previous.disconnect(&"finished", _guide_callback)
		if previous.tree_exiting.is_connected(_guide_exit_callback): previous.tree_exiting.disconnect(_guide_exit_callback)
		if cancel: previous.cancel()
	if _guide_token != 0: _pauses.release(_guide_token)
	_guide_token = 0

func _on_player_died() -> void:
	if state in [&"dead", &"loading"] or not _initialized: return
	# Acquire terminal ownership first, so cancellation cannot resume combat.
	if _terminal_token == 0: _terminal_token = _pauses.acquire(self, &"death", true)
	_set_state(&"dead")
	_load_failed = false
	_completion_pending = false
	_generation += 1
	_cancel_actions()
	if is_instance_valid(_level_flow): _level_flow.hide_result()
	_result_view.show_death()

func request_completion() -> void:
	if not _initialized or state in [&"dead", &"completed", &"loading", &"error"]: return
	_completion_pending = true
	_completion_frame = Engine.get_process_frames()

func _on_waves_completed() -> void:
	if _bindings.get("auto_complete_waves", true): request_completion()

func _finish_completion() -> void:
	if is_instance_valid(_health) and _health.get("is_dead") == true:
		_on_player_died()
		return
	_completion_pending = false
	_terminal_token = _pauses.acquire(self, &"completion", true)
	_set_state(&"completed")
	_generation += 1
	_cancel_actions()
	if is_instance_valid(_level_flow): _level_flow.show_completion()

func request_restart() -> void:
	if state != &"dead": return
	_start_load("", true)

func request_restart_from_flow() -> void:
	if state not in [&"running", &"guide"]: return
	_start_load("", true)

func request_load_retry() -> void:
	if not _load_failed: return
	_start_load(_load_path, _load_reload)

func request_next_level() -> void:
	if _load_failed and state != &"dead":
		request_load_retry()
		return
	if state != &"completed" or not is_instance_valid(_level_flow): return
	_start_load(_level_flow.next_scene_path(), false)

func request_change_scene(path: String) -> void:
	if state not in [&"running", &"completed"] or path.is_empty(): return
	_start_load(path, false)

func _start_load(path: String, reload_current: bool) -> void:
	_before_load = state
	_load_path = path
	_load_reload = reload_current
	_load_failed = false
	if _terminal_token == 0: _terminal_token = _pauses.acquire(self, &"loading", true)
	_set_state(&"loading")
	_generation += 1
	_cancel_actions()
	_result_view.set_pending(true)
	if is_instance_valid(_level_flow): _level_flow.set_transition_pending(true)
	_execute_load.call_deferred(_generation)

func _execute_load(generation: int) -> void:
	if generation != _generation or not is_inside_tree() or state != &"loading": return
	var result: int
	if scene_loader.is_valid(): result = scene_loader.call(_load_path, _load_reload)
	elif _load_reload: result = get_tree().reload_current_scene()
	else: result = get_tree().change_scene_to_file(_load_path)
	if result == OK: return # Old ownership is released on exit, before the new scene prepares.
	_last_error = "Scene load failed: %s" % error_string(result)
	_load_failed = true
	_set_state(_before_load)
	if state == &"dead": _result_view.show_load_error()
	elif is_instance_valid(_level_flow): _level_flow.show_load_error()
	else:
		# A custom UI can report this diagnostic and invoke request_load_retry().
		report_action_error("loading", _last_error)

func request_wave_for_flow(wave: Node, present: bool, options: Dictionary, scope: int = 1, target_path: NodePath = NodePath()) -> bool:
	if _waves == null or not is_instance_valid(wave): return false
	if present: _armed_presentations[wave.get_instance_id()] = {"options": options.duplicate(), "scope": scope, "target_path": target_path}
	if _waves.request_wave(wave):
		_waves.start_encounter()
		return true
	_armed_presentations.erase(wave.get_instance_id())
	return false

func wave_status(wave: Node) -> StringName:
	return _waves.wave_status(wave) if _waves != null and is_instance_valid(wave) else &"unknown"

func _on_wave_committed(wave: Node, _deployment_focus: Vector3) -> void:
	if state not in [&"running", &"guide"]: return
	var armed: Dictionary = _armed_presentations.get(wave.get_instance_id(), {})
	_armed_presentations.erase(wave.get_instance_id())
	var owner: Node = wave
	var target_path: NodePath
	var options: Dictionary
	var scope := 1
	if not armed.is_empty():
		options = armed.options
		scope = armed.scope
		target_path = armed.get("target_path", NodePath())
		if not target_path.is_empty(): owner = _host
		else: target_path = wave.get("presentation_target_path") if wave.get("presentation_target_path") != null else NodePath()
	elif wave.get("show_spawn_presentation") == true:
		target_path = wave.presentation_target_path
		options = {"move_seconds": wave.presentation_move_seconds, "hold_seconds": wave.presentation_hold_seconds,
			"return_seconds": wave.presentation_return_seconds, "size": wave.presentation_size}
	elif _bindings.get("present_spawned_waves", false):
		owner = _host
		target_path = _bindings.get("presentation_target_path", NodePath())
		options = _bindings.get("presentation_options", {})
	else: return
	var target := owner.get_node_or_null(target_path) if not target_path.is_empty() else null
	if not target is Node3D or not target.is_inside_tree():
		report_action_error("camera", "Spawn presentation needs an explicit Marker3D/Node3D target; skipped")
		return
	present_target(target.global_position, options, scope)

func present_target(focus: Vector3, options: Dictionary = {}, scope: int = 0) -> int:
	if _active_presentation != 0: return -1
	if state not in [&"running", &"guide"]: return 0
	var source: Camera3D = get_viewport().get_camera_3d()
	if not is_instance_valid(source):
		report_action_error("camera", "No active source camera; presentation skipped")
		return 0
	if not _ensure_camera(): return 0
	_presentation_id += 1
	_active_presentation = _presentation_id
	_presentation_scope = scope
	_camera_token = _pauses.acquire(self, &"presentation")
	# Establish pause in the synchronous spawn commit before public spawned callbacks.
	if not _camera.start_presentation(source, focus, options, _active_presentation):
		report_action_error("camera", "Presentation could not start; deployment remains committed")
		_finish_presentation()
		return 0
	return _active_presentation

func _ensure_camera() -> bool:
	if not is_instance_valid(_camera):
		var packed = load("res://scenes/player/presentation_camera.tscn")
		if packed == null:
			report_action_error("camera", "Missing presentation camera scene")
			return false
		_camera = packed.instantiate()
		_camera.name = "PresentationCamera"
		# A sibling of the player's rig, never a Wave child or a second follow rig.
		var parent := _host.get_parent() if _host.has_method("capture_templates") else _host
		parent.add_child(_camera, false, Node.INTERNAL_MODE_BACK)
		_owns_camera = true
	if not _camera.has_method("start_presentation") or not _camera.has_signal("presentation_finished"):
		report_action_error("camera", "Invalid presentation camera binding")
		return false
	_link(_camera, &"presentation_finished", _on_presentation_finished)
	return true

func _on_presentation_finished(id: int, result: StringName) -> void:
	if id != _active_presentation: return
	if result not in [&"completed", &"finished", &"cancelled"]: _last_error = "Presentation: %s" % result
	_finish_presentation()

func _finish_presentation() -> void:
	_active_presentation = 0
	if _camera_token != 0: _pauses.release(_camera_token)
	_camera_token = 0

func is_presentation_pending(id: int) -> bool:
	return id != 0 and id == _active_presentation

func skip_presentation() -> void:
	_cancel_presentation()

func _cancel_presentation(restore: bool = true) -> void:
	if is_instance_valid(_camera) and _camera.has_method("cancel_presentation"):
		_camera.cancel_presentation(restore)
	_finish_presentation()

func reset_region() -> void:
	if not _initialized: return
	_armed_presentations.clear()
	if _active_presentation != 0 and _presentation_scope == 1: _cancel_presentation()
	if _guide != null and _guide_scope == 1:
		_clear_guide(true)
		if state == &"guide": _set_state(&"running")
	_flows.reset_region()
	_completion_pending = false

func _cancel_actions() -> void:
	_armed_presentations.clear()
	_flows.cancel_all()
	_clear_guide(true)
	_cancel_presentation()

func report_action_error(rule: String, reason: String) -> void:
	_last_error = "%s: %s" % [rule, reason]
	action_failed.emit(rule, reason)

func _set_state(value: StringName) -> void:
	if state == value: return
	state = value
	state_changed.emit(state)

func debug_snapshot() -> Dictionary:
	return {"state": state, "generation": _generation, "last_error": _last_error,
		"load_failed": _load_failed, "load_path": _load_path,
		"presentation": _active_presentation, "guide": is_instance_valid(_guide), "completion_pending": _completion_pending,
		"pause": _pauses.snapshot() if _pauses != null else {}, "flows": _flows.snapshot() if _flows != null else {}}

func _exit_tree() -> void:
	_generation += 1
	if not _initialized: return
	_flows.release()
	_clear_guide(true)
	_cancel_presentation(false)
	_pauses.release(_terminal_token)
	_terminal_token = 0
	for connection in _connections:
		var source = connection.source.get_ref()
		if is_instance_valid(source) and source.is_connected(connection.signal, connection.callback):
			source.disconnect(connection.signal, connection.callback)
	_connections.clear()
	if _result_view.has_method("bind"): _result_view.bind(null)
	if _owns_camera and is_instance_valid(_camera): _camera.queue_free()
