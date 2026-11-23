extends Node

## Scene lifecycle, independent of enemy deployment and CombatZone occupancy.
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")
const Flows = preload("res://scripts/systems/scene_flow_runner.gd")
const ResultView = preload("res://scripts/ui/scene_result_view.gd")
const Request = preload("res://scripts/systems/scene_request.gd")
const Scheduler = preload("res://scripts/systems/scene_request_scheduler.gd")
const Interactions = preload("res://scripts/systems/scene_interaction_executor.gd")
const Scripts = preload("res://scripts/systems/scene_script_executor.gd")
const Transitions = preload("res://scripts/systems/scene_transition_executor.gd")
const PauseMenuScene = preload("res://scenes/ui/pause_menu.tscn")
const PlayerState = preload("res://scripts/player/player_campaign_state.gd")
const MAIN_SCENE_PATH := "res://scenes/main.tscn"
const REGISTRATION := &"scene_director_root"
var _scene_root: Node
var _requests
var _next_request := 0
var _guide_request
var _camera_request
var _completion_request
var _interactions
var _scripts
var _load_request
var _load_chain: Array = []
var _load_connections: Array[Dictionary] = []
var _load_parameters: Dictionary = {}
var _load_owns_terminal := false
var _issuing_parent
var _transitions
var _wave_requests: Dictionary = {}
var _completion_executing := false
var _request_controls: Dictionary = {}
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
var _pause_menu: CanvasLayer
var _menu_token := 0
var _camera: Camera3D
var _cinematic_controller: Node
var _cinematic_request
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
var _guide_execution := 0
var _guide_scope := 0
var _completion_pending := false
var _completion_frame := -1
var _completion_pauses_world := true
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
	_scene_root = _bindings.get("scene_root", _host.get_parent() if _host.has_method("capture_templates") else _host)
	var registered = for_node(_scene_root)
	if registered != null and registered != self:
		_initialized = false
		_set_state(&"error")
		report_action_error("bindings", "This scene already has a scene director")
		return
	_scene_root.set_meta(REGISTRATION, weakref(self))
	_requests = Scheduler.new(self)
	_interactions = Interactions.new(self)
	_scripts = Scripts.new(self, _host)
	_transitions = Transitions.new(self)
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
	if is_instance_valid(_level_flow) and _level_flow.has_method("completion_pauses_world"):
		_completion_pauses_world = bool(_level_flow.completion_pauses_world())
	_waves = _bindings.get("wave_runtime")
	if _waves != null and _waves.has_method("bind_authority"):
		_waves.bind_authority(_schedule_wave, authorize_wave_deployment)
		_link(_waves, &"deployment_failed", _on_wave_deployment_failed)
	_camera = _bindings.get("camera")
	_cinematic_controller = _bindings.get("cinematic_controller")
	_result_view = _bindings.get("result_view")
	if _result_view == null:
		_result_view = ResultView.new()
		_result_view.bind(_health)
	if _result_view.has_method(&"set_tavern_available"):
		_result_view.set_tavern_available(
			is_instance_valid(_level_flow) and _level_flow.has_method(&"next_scene_path"))
	_link(_result_view, &"restart_requested", request_restart)
	_link(_result_view, &"return_to_tavern_requested", request_return_to_tavern)
	_link(_health, &"died", _on_player_died)
	_link(_level_flow, &"continue_requested", request_next_level)
	_link(_waves, &"encounter_completed", _on_waves_completed)
	_link(_waves, &"wave_committed", _on_wave_committed)
	_flows = Flows.new(self, _host)
	_flows.configure(_bindings.get("rules", []))
	if _waves != null: _waves.prepare_events()
	_pause_menu = PauseMenuScene.instantiate()
	add_child(_pause_menu)
	_link(_pause_menu, &"pause_requested", request_pause_menu)
	_link(_pause_menu, &"resume_requested", resume_from_pause_menu)
	_link(_pause_menu, &"quit_requested", _quit_game)
	_link(_pause_menu, &"save_game_requested", _save_game_from_menu)
	var guide: Node = _bindings.get("guide")
	if guide != null:
		_set_state(&"running")
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
	if _menu_token != 0: return
	if is_instance_valid(_cinematic_controller) \
			and _cinematic_controller.get_snapshot().get("phase", &"idle") != &"idle" \
			and state not in [&"dead", &"loading"]:
		var token: int = _cinematic_controller.pause_token()
		if token == 0 or _pauses.can_advance_cinematic(token):
			_cinematic_controller.advance(delta)
	_requests.advance(delta)
	if _active_presentation != 0 and _pauses.can_advance_presentation(_camera_token):
		if is_instance_valid(_camera): _camera.advance_presentation(delta)
		else: _finish_presentation()
	if not can_run_actions(): return
	_flows.advance(delta)
	if _completion_pending and state == &"running" and _active_presentation == 0 \
			and not _cinematic_barrier_active() and _guide == null \
			and _requests.snapshot().foreground == 0 \
			and Engine.get_process_frames() > _completion_frame:
		_finish_completion()

func can_run_actions() -> bool:
	return _initialized and not _load_failed and state in [&"running", &"guide"] and not get_tree().paused

func can_save_game() -> bool:
	if not _initialized or _load_failed:
		return false
	var state := get_node_or_null("/root/GameState")
	if state == null:
		return false
	return _scene_root.scene_file_path == MAIN_SCENE_PATH \
		or not state.last_tavern_state.is_empty()

func save_game() -> Dictionary:
	if not can_save_game():
		return {"ok": false, "result": &"unavailable"}
	var state := get_node("/root/GameState")
	var service := get_node_or_null("/root/CampaignSaveService")
	if service == null:
		return {"ok": false, "result": &"save_failed"}
	var in_tavern := _scene_root.scene_file_path == MAIN_SCENE_PATH
	var snapshot: Dictionary
	if in_tavern:
		var player := get_tree().get_first_node_in_group(&"player")
		snapshot = state.capture_save_state(PlayerState.capture(player))
		state.remember_tavern_state(snapshot)
	else:
		snapshot = state.last_tavern_state.duplicate(true)
	if service.save_game(snapshot) != OK:
		return {"ok": false, "result": &"save_failed"}
	return {"ok": true, "result": &"tavern_saved" if in_tavern else &"level_saved"}

func _save_game_from_menu() -> void:
	var result := save_game()
	_pause_menu.show_game_save_result(result.result)

## 普通暂停只在可游玩、没有其他界面或演出占用控制时打开。
func request_pause_menu() -> void:
	if not _initialized or _menu_token != 0 or _load_failed: return
	if is_instance_valid(_cinematic_controller) \
			and _cinematic_controller.get_snapshot().get("phase", &"idle") != &"idle":
		return
	if state not in [&"running", &"completed"] or get_tree().paused: return
	if _requests.snapshot().foreground != 0 or _pauses.snapshot().count != 0: return
	_menu_token = _pauses.acquire(self, &"pause_menu", true)
	_pause_menu.open_menu()
	_pause_menu.set_game_save_available(can_save_game())

func resume_from_pause_menu() -> void:
	if is_instance_valid(_pause_menu): _pause_menu.close_menu()
	if _menu_token != 0:
		_pauses.release(_menu_token)
		_menu_token = 0

func _quit_game() -> void:
	if _menu_token != 0: get_tree().quit()

func begin_guide(provider: Node, pause_world: bool = true, scope: int = 0) -> bool:
	var request = request_action(&"guide", {"source": _host, "target": provider, "scope": scope,
		"scope_owner": region_owner(), "parameters": {"pause_world": pause_world}, "origin": &"rule"})
	return request.has_started() and request.status != &"failed"

func _execute_guide(provider: Node, pause_world: bool = true, scope: int = 0) -> bool:
	if _guide != null or not is_instance_valid(provider) or not provider.has_method("begin") or not provider.has_method("cancel") or not provider.has_signal("finished"):
		report_action_error("guide", "Guide needs begin(), cancel() and finished")
		return false
	_guide = provider
	_guide_scope = scope
	_guide_finished = false
	_guide_execution += 1
	if pause_world: _guide_token = _pauses.acquire(self, &"guide", true)
	_set_state(&"guide")
	_guide_callback = _on_guide_finished.bind(_generation, provider.get_instance_id(), _guide_execution)
	_guide_exit_callback = _on_guide_exiting.bind(_generation, provider.get_instance_id(), _guide_execution)
	provider.connect(&"finished", _guide_callback)
	provider.tree_exiting.connect(_guide_exit_callback)
	# Completion is subscribed before begin(), including synchronous providers.
	provider.begin()
	return true

func is_guide_pending(provider: Node) -> bool:
	return is_instance_valid(provider) and _guide == provider

func _on_guide_finished(generation: int, id: int, execution: int) -> void:
	if generation != _generation or execution != _guide_execution or not is_instance_valid(_guide) or _guide.get_instance_id() != id: return
	_guide_finished = true
	_clear_guide(false)
	if state == &"guide": _set_state(&"running")
	if _guide_request != null:
		var request = _guide_request
		_guide_request = null
		request.complete()

func _on_guide_exiting(generation: int, id: int, execution: int) -> void:
	if generation != _generation or execution != _guide_execution or not is_instance_valid(_guide) or _guide.get_instance_id() != id: return
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
	request_action(&"completion", {"source": _host, "dedupe_key": &"scene_completion"})

func _execute_completion() -> void:
	_completion_pending = true
	_completion_frame = Engine.get_process_frames()

func _on_waves_completed() -> void:
	if _bindings.get("auto_complete_waves", true): request_completion()

func _finish_completion() -> void:
	if _cinematic_barrier_active(): return
	if is_instance_valid(_health) and _health.get("is_dead") == true:
		_on_player_died()
		return
	_completion_pending = false
	var completion = _completion_request
	_completion_request = null
	if completion != null: _requests._finished(completion)
	if _completion_pauses_world:
		_terminal_token = _pauses.acquire(self, &"completion", true)
	_set_state(&"completed")
	_generation += 1
	_cancel_actions()
	if is_instance_valid(_level_flow):
		_completion_executing = true
		if _level_flow.has_method("execute_scene_completion"): _level_flow.execute_scene_completion()
		else: _level_flow.show_completion()
		_completion_executing = false
	if completion != null: completion._settle(&"completed")

func _cinematic_barrier_active() -> bool:
	if _cinematic_request != null and not _cinematic_request.is_terminal():
		return true
	return is_instance_valid(_cinematic_controller) \
		and _cinematic_controller.get_snapshot().get("phase", &"idle") != &"idle"

func request_restart() -> void:
	if state == &"dead": _request_transition({"reload": true, "mode": &"retry_level"})

func request_return_to_tavern() -> void:
	if state != &"dead": return
	if not is_instance_valid(_level_flow) or not _level_flow.has_method(&"next_scene_path"):
		report_action_error("death", "Returning to the tavern requires a level flow adapter")
		_result_view.show_load_error()
		return
	var path: String = _level_flow.next_scene_path()
	if path.is_empty():
		report_action_error("death", "The level flow has no tavern scene path")
		_result_view.show_load_error()
		return
	_request_transition({"path": path, "mode": &"death_return"})

func request_restart_from_flow() -> void:
	if state in [&"running", &"guide"]: _request_transition({"reload": true})

func request_load_retry() -> void:
	if _load_failed: _request_transition(_load_parameters)

func request_next_level() -> void:
	if _load_failed and state != &"dead":
		request_load_retry()
		return
	if state == &"completed" and is_instance_valid(_level_flow):
		_request_transition({"path": _level_flow.next_scene_path()})

func request_change_scene(path: String) -> void:
	if state in [&"running", &"completed"] and not path.is_empty(): _request_transition({"path": path})

func _request_transition(parameters: Dictionary) -> Request:
	return request_action(&"transition", {"source": _host, "parameters": parameters})

func _start_transition(request: Request) -> void:
	var parameters := request.parameters
	if not parameters.get("reload", false) and String(parameters.get("path", "")).is_empty():
		request.fail("missing_scene_path")
		return
	_load_request = request
	_before_load = state
	_load_parameters = parameters.duplicate(true)
	_load_path = parameters.get("path", "")
	_load_reload = parameters.get("reload", false)
	_load_failed = false
	_load_owns_terminal = _terminal_token == 0
	if _load_owns_terminal: _terminal_token = _pauses.acquire(self, &"loading", true)
	_set_state(&"loading")
	_load_chain = _requests.detach_chain(request)
	_generation += 1
	_cancel_actions()
	_result_view.set_pending(true)
	if is_instance_valid(_level_flow): _level_flow.set_transition_pending(true)
	_transitions = Transitions.new(self)
	for execution in _load_chain:
		for key in [&"source", &"target", &"player", &"scope_owner"]:
			var node: Node = execution.node(key)
			if node == null: continue
			var callback := _cancel_loading.bind(request.id, &"target_exited")
			if not node.tree_exiting.is_connected(callback):
				node.tree_exiting.connect(callback)
				_load_connections.append({"node": weakref(node), "callback": callback})
	_transitions.begin_scene_action(request)

func _cancel_loading(id: int, reason: StringName) -> bool:
	if _load_request == null or _transitions.is_committing(): return false
	for execution in _load_chain:
		if execution.id == id:
			_transitions.cancel_scene_action(_load_request, reason)
			return true
	return false

func finish_transition(request: Request, status: StringName, reason: StringName = &"") -> void:
	if _load_request != request: return
	for link in _load_connections:
		var node = link.node.get_ref()
		if is_instance_valid(node) and node.tree_exiting.is_connected(link.callback):
			node.tree_exiting.disconnect(link.callback)
	_load_connections.clear()
	var chain := _load_chain
	_load_chain = []
	_load_request = null
	if status == &"cancelled":
		_load_failed = false
		_set_state(&"running" if _before_load == &"guide" and _guide == null else _before_load)
		if _load_owns_terminal:
			_pauses.release(_terminal_token)
			_terminal_token = 0
		_result_view.set_pending(false)
		if is_instance_valid(_level_flow): _level_flow.set_transition_pending(false)
	if status == &"failed":
		_last_error = "Scene load failed: %s" % reason
		_load_failed = true
		_set_state(_before_load)
		if _load_parameters.get("return_control_on_failure", false):
			_load_failed = false
			if _load_owns_terminal:
				_pauses.release(_terminal_token)
				_terminal_token = 0
			_result_view.set_pending(false)
			if is_instance_valid(_level_flow): _level_flow.set_transition_pending(false)
			action_failed.emit("loading", _last_error)
		elif state == &"dead": _result_view.show_load_error()
		elif is_instance_valid(_level_flow): _level_flow.show_load_error()
		else: report_action_error("loading", _last_error)
	chain.reverse()
	for execution in chain: execution._settle(status, reason)

func request_wave_for_flow(wave: Node, present: bool, options: Dictionary, scope: int = 1, target_path: NodePath = NodePath()) -> bool:
	var request := request_action(&"wave", {"source": _host, "target": wave, "scope": scope,
		"scope_owner": region_owner(), "dedupe_key": StringName("wave_%d" % wave.get_instance_id()) if is_instance_valid(wave) else &"",
		"parameters": {"present": present, "options": options, "target_path": target_path}})
	return request.has_started() and request.status not in [&"failed", &"cancelled", &"rejected"]

func _schedule_wave(wave: Node) -> bool:
	return request_wave_for_flow(wave, false, {})

func _execute_wave_request(request: Request) -> void:
	if _waves == null:
		request.fail("missing_wave_runtime")
		return
	if request.parameters.get("command") == &"start":
		_waves.start_encounter()
		request.complete()
		return
	if request.parameters.get("command") == &"debug_complete":
		if _waves.debug_complete_encounter(): request.complete({"success": true})
		else: request.fail("debug_completion_rejected")
		return
	var wave := request.node(&"target")
	var status: StringName = _waves.wave_status(wave)
	if status in [&"unknown", &"error"]:
		request.fail("invalid_wave")
		return
	if status in [&"active", &"clearing", &"cleared"]:
		request.complete()
		return
	var id := wave.get_instance_id()
	_wave_requests[id] = request
	request.finished.connect(_clear_wave_request.bind(id))
	if request.parameters.get("present", false):
		_armed_presentations[id] = {"options": request.parameters.get("options", {}), "scope": request.scope,
			"target_path": request.parameters.get("target_path", NodePath())}
	if not _waves.request_wave(wave):
		request.fail("wave_rejected")
		return
	_waves.start_encounter()

func _clear_wave_request(request: Request, id: int) -> void:
	if _wave_requests.get(id) != request: return
	_wave_requests.erase(id)
	if request.status != &"completed": _armed_presentations.erase(id)

func _on_wave_deployment_failed(reason: String) -> void:
	for request in _wave_requests.values().duplicate():
		request.fail(reason)

func authorize_wave_deployment(wave: Node) -> bool:
	if not is_instance_valid(wave) or state not in [&"running", &"guide"] or _load_failed or _completion_pending or get_tree().paused: return false
	var request = _wave_requests.get(wave.get_instance_id())
	if request == null or not request.is_current(): return false
	var shot_path: NodePath = wave.get("cinematic_shot_path") if wave.get("cinematic_shot_path") != null else NodePath()
	var presentation := false
	if shot_path.is_empty():
		presentation = _armed_presentations.has(wave.get_instance_id()) \
			or wave.get("show_spawn_presentation") == true \
			or _bindings.get("present_spawned_waves", false)
	return not presentation or _requests.snapshot().foreground == 0

func wave_status(wave: Node) -> StringName:
	return _waves.wave_status(wave) if _waves != null and is_instance_valid(wave) else &"unknown"

func _on_wave_committed(wave: Node, _deployment_focus: Vector3) -> void:
	_present_committed_wave(wave)
	var request = _wave_requests.get(wave.get_instance_id()) if is_instance_valid(wave) else null
	if request != null: request.complete()

func _present_committed_wave(wave: Node) -> void:
	if state not in [&"running", &"guide"]: return
	var wave_id := wave.get_instance_id()
	var armed: Dictionary = _armed_presentations.get(wave_id, {})
	_armed_presentations.erase(wave_id)
	var shot_path: NodePath = wave.get("cinematic_shot_path") if wave.get("cinematic_shot_path") != null else NodePath()
	if not shot_path.is_empty():
		var shot := wave.get_node_or_null(shot_path)
		var controller = _bindings.get("cinematic_controller")
		if controller != null and shot is CinematicShot3D:
			var admission: Dictionary = controller.play_shot(
				shot, CinematicCameraController.SCOPE_REGION)
			if not admission.accepted and admission.result != &"busy":
				report_action_error("camera", "Cinematic shot rejected: %s" % admission.reason)
			return
		report_action_error("camera", "Cinematic shot path is missing or invalid; legacy presentation skipped")
		return
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
	request_action(&"presentation", {"source": wave, "target": target, "scope": scope,
		"scope_owner": region_owner(), "origin": &"rule", "parameters": options})

func present_target(focus: Vector3, options: Dictionary = {}, scope: int = 0) -> int:
	if _active_presentation != 0 or (_requests != null and _requests.snapshot().foreground != 0): return -1
	var parameters := options.duplicate()
	parameters["focus"] = focus
	var request = request_action(&"presentation", {"source": _host, "scope": scope,
		"scope_owner": region_owner(), "parameters": parameters, "origin": &"interaction"})
	return _active_presentation if request.has_started() else 0

func _execute_presentation(focus: Vector3, options: Dictionary = {}, scope: int = 0) -> int:
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
	if _camera_request != null:
		var request = _camera_request
		_camera_request = null
		request.complete()

func is_presentation_pending(id: int) -> bool:
	return id != 0 and id == _active_presentation

func skip_presentation() -> void:
	_cancel_presentation()

func _cancel_presentation(restore: bool = true) -> void:
	if is_instance_valid(_camera) and _camera.has_method("cancel_presentation"):
		_camera.cancel_presentation(restore)
	_finish_presentation()

func reset_region(owner: Node = null) -> void:
	if not _initialized: return
	var retiring := owner if owner != null else region_owner()
	_requests.cancel_scope(retiring, &"region_reset")
	if retiring != region_owner(): return
	if _cinematic_request != null and _cinematic_request.scope == 1 \
			and (_cinematic_request.node(&"scope_owner") == null
				or _cinematic_request.node(&"scope_owner") == retiring):
		_requests.cancel(_cinematic_request.id, &"region_reset")
	_armed_presentations.clear()
	if _active_presentation != 0 and _presentation_scope == 1 and (_camera_request == null or _camera_request.node(&"scope_owner") == retiring): _cancel_presentation()
	if _guide != null and _guide_scope == 1 and (_guide_request == null or _guide_request.node(&"scope_owner") == retiring):
		_clear_guide(true)
		if state == &"guide": _set_state(&"running")
	_flows.reset_region()
	_completion_pending = false

func _cancel_actions() -> void:
	if _requests != null: _requests.cancel_all(&"scene_interrupted")
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
	if state != &"running": resume_from_pause_menu()
	state_changed.emit(state)

func debug_snapshot() -> Dictionary:
	return {"state": state, "generation": _generation, "last_error": _last_error,
		"load_failed": _load_failed, "load_path": _load_path,
		"presentation": _active_presentation, "guide": is_instance_valid(_guide), "completion_pending": _completion_pending,
		"pause": _pauses.snapshot() if _pauses != null else {}, "flows": _flows.snapshot() if _flows != null else {},
		"requests": _requests.snapshot() if _requests != null else {}}

func _exit_tree() -> void:
	_generation += 1
	resume_from_pause_menu()
	if not _initialized: return
	if _load_request != null and not _transitions.is_committing():
		_transitions.cancel_scene_action(_load_request, &"scene_exited")
	if _requests != null: _requests.cancel_all(&"scene_exited")
	if is_instance_valid(_scene_root) and _scene_root.has_meta(REGISTRATION):
		var registration: WeakRef = _scene_root.get_meta(REGISTRATION)
		if registration.get_ref() == self: _scene_root.remove_meta(REGISTRATION)
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

static func for_node(node: Node) -> Node:
	var cursor := node
	while is_instance_valid(cursor):
		if cursor.has_meta(REGISTRATION):
			var registration: WeakRef = cursor.get_meta(REGISTRATION)
			var director = registration.get_ref()
			if is_instance_valid(director) and director.is_inside_tree(): return director
		cursor = cursor.get_parent()
	return null

func request_action(kind: StringName, context: Dictionary = {}) -> Request:
	var request = Request.new()
	_next_request += 1
	request._id = _next_request
	request._generation = _generation
	request._director = weakref(self)
	request.kind = kind
	request.origin = context.get("origin", &"system")
	request.scope = context.get("scope", 0)
	request.parent_id = context.get("parent_id", 0)
	request.dedupe_key = context.get("dedupe_key", &"")
	var parameters: Dictionary = context.get("parameters", {})
	if _contains_node(parameters):
		request._settle(&"rejected", &"node_in_parameters")
		return request
	request.parameters = parameters.duplicate(true)
	request._start_guard = context.get("start_guard", Callable())
	for key in [&"source", &"target", &"player", &"scope_owner"]:
		var node = context.get(key, _host if key == &"source" else null)
		if is_instance_valid(node): request._nodes[key] = weakref(node)
	var available := state in [&"running", &"guide"] and not _load_failed
	if state == &"completed" and not _completion_pauses_world and not _load_failed:
		available = kind in [&"interact", &"dialogue", &"shop", &"script"]
	if kind == &"transition": available = state in [&"running", &"guide", &"dead", &"completed"]
	if not _initialized or _requests == null or not available:
		request._settle(&"rejected", &"scene_unavailable")
		return request
	if kind not in [&"guide", &"presentation", &"completion", &"dialogue", &"shop", &"interact", &"script", &"wave", &"transition", &"cinematic_shot"]:
		request._settle(&"rejected", &"unsupported_kind")
		return request
	for key in request._nodes:
		var node: Node = request.node(key)
		if not is_instance_valid(node) or not node.is_inside_tree() or (node != _scene_root and not _scene_root.is_ancestor_of(node)):
			request._settle(&"rejected", &"foreign_target")
			return request
	if request.parent_id != 0 and (_issuing_parent == null or _issuing_parent.id != request.parent_id or not _issuing_parent.is_current()):
		request._settle(&"rejected", &"invalid_parent")
		return request
	if kind in [&"wave", &"completion", &"cinematic_shot"]: request._background = true
	if kind == &"wave" and request.node(&"target") != null:
		request.dedupe_key = StringName("wave_%d" % request.node(&"target").get_instance_id())
	if kind == &"script":
		var target := request.node(&"target")
		if target != null and target.has_method("scene_action_is_background"):
			request._background = target.scene_action_is_background() == true
	var cinematic_active: bool = is_instance_valid(_cinematic_controller) \
		and _cinematic_controller.get_snapshot().get("phase", &"idle") != &"idle"
	if cinematic_active and not request._background \
			and kind not in [&"dialogue", &"transition"]:
		request._settle(&"rejected", &"cinematic_busy")
		return request
	if kind == &"cinematic_shot" and (cinematic_active or _cinematic_request != null):
		request._settle(&"rejected", &"busy")
		return request
	if kind == &"cinematic_shot" and _pauses != null \
			and _pauses.has_non_dialogue_control_owner():
		request._settle(&"rejected", &"busy")
		return request
	if kind == &"cinematic_shot" \
			and (_requests.foreground_kind() not in [&"", &"dialogue"]
				or _requests.has_queued_non_dialogue_foreground()):
		request._settle(&"rejected", &"busy")
		return request
	var previous = _requests.duplicate_for(request)
	if previous != null: return previous
	_requests.submit(request)
	return request

func can_start_queued_request(request: Request) -> bool:
	if request == null or request._background: return true
	return not is_instance_valid(_cinematic_controller) \
		or _cinematic_controller.get_snapshot().get("phase", &"idle") == &"idle"

func _contains_node(value: Variant) -> bool:
	if value is Node or value is WeakRef: return true
	if value is Array:
		for item in value:
			if _contains_node(item): return true
	if value is Dictionary:
		for key in value:
			if _contains_node(key) or _contains_node(value[key]): return true
	return false

func request_is_current(request: Request) -> bool:
	return _initialized and request.generation == _generation and _requests != null and _requests.owns(request)

func cancel_request(id: int, reason: StringName = &"cancelled") -> void:
	if _cancel_loading(id, reason): return
	if _requests != null: _requests.cancel(id, reason)

func execute_request(request: Request) -> void:
	match request.kind:
		&"wave":
			_execute_wave_request(request)
		&"script":
			_scripts.begin_scene_action(request)
		&"transition":
			_start_transition(request)
		&"dialogue", &"shop", &"interact":
			_interactions.begin_scene_action(request)
		&"guide":
			_guide_request = request
			if not _execute_guide(request.node(&"target"), request.parameters.get("pause_world", true), request.scope):
				_guide_request = null
				request.fail("invalid_guide")
		&"presentation":
			var target := request.node(&"target") as Node3D
			var focus: Variant = target.global_position if target != null else request.parameters.get("focus")
			if not focus is Vector3:
				request.fail("invalid_presentation_target")
				return
			_camera_request = request
			if _execute_presentation(focus, request.parameters, request.scope) == 0:
				_camera_request = null
				request.complete({"skipped": true})
		&"cinematic_shot":
			execute_cinematic_shot_request(request)
		&"completion":
			_completion_request = request
			_execute_completion()

func cancel_request_execution(request: Request, _reason: StringName) -> void:
	if request.kind == &"script": _scripts.cancel_scene_action(request, _reason)
	if request.kind in [&"dialogue", &"shop"]:
		_interactions.cancel_scene_action(request, _reason)
	if _completion_request == request:
		_completion_request = null
		_completion_pending = false
	if _guide_request == request:
		_guide_request = null
		_clear_guide(true)
		if state == &"guide": _set_state(&"running")
	if _camera_request == request:
		_camera_request = null
		_cancel_presentation()
	if _cinematic_request == request and is_instance_valid(_cinematic_controller):
		_cinematic_controller.cancel_shot(_reason)

func find_request(id: int) -> Request:
	return _requests.find(id) if _requests != null else null

func finish_request(id: int) -> void:
	var request := find_request(id)
	if request != null and request.is_current() and request.kind in [&"dialogue", &"shop"]:
		_interactions.end_scene_action(request)

func hold_request_controls(request: Request, pause_world: bool, lock_player: bool = false) -> void:
	if not request.is_current() or _request_controls.has(request.id): return
	var player := request.node(&"player")
	var previous := false
	if lock_player and player != null:
		previous = player.get("is_in_dialogue") == true
		player.set_dialogue_active(true)
	var token: int = _pauses.acquire(self, request.kind, true, pause_world)
	_request_controls[request.id] = {"token": token, "lock_player": lock_player, "previous": previous}

func release_request_controls(request: Request) -> void:
	var controls: Dictionary = _request_controls.get(request.id, {})
	_request_controls.erase(request.id)
	if controls.is_empty(): return
	var player := request.node(&"player")
	if controls.lock_player and is_instance_valid(player):
		player.set_dialogue_active(controls.previous)
		player.set("is_facing_npc", false)
	_pauses.release(controls.token)

func execute_cinematic_shot_request(request: Request) -> void:
	if _cinematic_request != null and _cinematic_request != request:
		request.fail("busy")
		return
	if not is_instance_valid(_cinematic_controller) \
			or not _cinematic_controller.has_method("execute_request"):
		request.fail("no_cinematic_controller")
		return
	if not request.parameters.get("snapshot") is Dictionary:
		var shot := request.node(&"target")
		if not shot is CinematicShot3D:
			request.fail("invalid_shot")
			return
		request.parameters["snapshot"] = shot.runtime_snapshot()
	_cinematic_request = request
	var result: Dictionary = _cinematic_controller.execute_request(request)
	if not result.get("accepted", false):
		if _cinematic_request == request:
			_cinematic_request = null
		if not request.is_terminal():
			request.fail(String(result.get("reason", &"failed")))
		return
	if request.is_terminal() and _cinematic_request == request:
		_cinematic_request = null

func complete_cinematic_request(id: int, result: StringName) -> void:
	if _cinematic_request == null or _cinematic_request.id != id: return
	var request = _cinematic_request
	_cinematic_request = null
	if result == &"completed":
		request.complete({"cinematic_result": result})
	elif result == &"cancelled":
		if request.status != &"cancelling":
			request._settle(&"cancelled", &"cancelled")
	else:
		request.fail(String(result))

func region_owner() -> Node:
	return _host.get_parent() if _host.has_method("capture_templates") else _host

func request_child(parent: Request, kind: StringName, context: Dictionary) -> Request:
	var previous = _issuing_parent
	_issuing_parent = parent
	var child_context := context.duplicate()
	child_context["parent_id"] = parent.id
	var request := request_action(kind, child_context)
	_issuing_parent = previous
	return request
