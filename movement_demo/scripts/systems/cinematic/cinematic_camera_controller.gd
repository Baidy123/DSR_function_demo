class_name CinematicCameraController
extends Node

signal shot_started(request_id: int, shot: CinematicShot3D)
signal shot_phase_changed(request_id: int, phase: StringName)
signal shot_finished(request_id: int, result: StringName)

const Shot = preload("res://scripts/systems/cinematic/cinematic_shot_3d.gd")
const Pauses = preload("res://scripts/systems/scene_pause_coordinator.gd")

@onready var _camera: Camera3D = $PresentationCamera

var _director: Node
var _shot: CinematicShot3D
var _request
var _snapshot: Dictionary
var _phase: StringName = &"idle"
var _pause_token := 0
var _elapsed := 0.0
var _last_error: StringName

func _ready() -> void:
	_camera.presentation_finished.connect(_on_presentation_finished)

func bind_director(director: Node) -> void:
	_director = director

func play_shot(shot: CinematicShot3D) -> Dictionary:
	if _phase != &"idle":
		return _admission(&"busy")
	if not is_instance_valid(_director):
		return _admission(&"no_director")
	if not is_instance_valid(shot) or not (shot is CinematicShot3D):
		return _admission(&"invalid_shot")
	var error: StringName = shot.configuration_error()
	if not error.is_empty():
		_last_error = error
		return _admission(error)
	var snapshot: Dictionary = shot.runtime_snapshot()
	error = _snapshot_error(snapshot)
	if not error.is_empty():
		_last_error = error
		return _admission(error)
	if _source_camera() == null:
		return _admission(&"no_source_camera")
	var request = _director.request_action(&"cinematic_shot", {
		"source": self,
		"target": shot,
		"origin": &"cinematic",
		"parameters": {"snapshot": snapshot},
	})
	if not request.has_started() or request.is_terminal():
		var result: StringName = request.reason if not request.reason.is_empty() else &"busy"
		if not request.is_terminal() and is_instance_valid(_director):
			_director.cancel_request(request.id, result)
		return _admission(result)
	return {"accepted": true, "request_id": request.id, "result": &"started", "reason": &""}

func execute_request(request: SceneRequest) -> Dictionary:
	if _phase != &"idle":
		return _admission(&"busy")
	var shot := request.node(&"target") as CinematicShot3D
	if not is_instance_valid(shot):
		return _admission(&"invalid_shot", request.id)
	var snapshot_value: Variant = request.parameters.get("snapshot")
	if not snapshot_value is Dictionary:
		return _admission(&"invalid_shot", request.id)
	var snapshot: Dictionary = snapshot_value
	var error: StringName = shot.configuration_error()
	if error.is_empty():
		error = _snapshot_error(snapshot)
	if not error.is_empty():
		_last_error = error
		return _admission(error, request.id)
	var source := _source_camera()
	if source == null:
		return _admission(&"no_source_camera", request.id)
	_request = request
	_shot = shot
	_snapshot = snapshot.duplicate(true)
	if shot.pause_world:
		_pause_token = Pauses.for_tree(get_tree()).acquire(
			self, &"cinematic_shot", true, true)
		if _pause_token == 0:
			_reset_active()
			return _admission(&"failed", request.id)
	if not _camera.start_cinematic_shot(source, _snapshot, request.id):
		_last_error = &"failed"
		_reset_active()
		return _admission(&"failed", request.id)
	_phase = &"enter"
	_elapsed = 0.0
	_last_error = &""
	shot_started.emit(request.id, shot)
	shot_phase_changed.emit(request.id, _phase)
	return {"accepted": true, "request_id": request.id, "result": &"started", "reason": &""}

func cancel_shot(reason: StringName = &"manual") -> bool:
	if _phase == &"idle" or not _camera.is_presenting():
		return false
	if reason != &"manual": _last_error = reason
	_camera.cancel_presentation(true)
	return true

func advance(delta: float) -> void:
	if _phase == &"idle" or not is_finite(delta) or delta < 0.0: return
	_camera.advance_presentation(delta)
	if _phase == &"idle": return
	_elapsed += delta
	var next_phase := _phase_for_elapsed(_elapsed)
	if next_phase != _phase:
		_phase = next_phase
		shot_phase_changed.emit(_request.id, _phase)

func pause_token() -> int:
	return _pause_token

func get_snapshot() -> Dictionary:
	var total_seconds := _total_seconds()
	return {
		"phase": _phase,
		"shot": _shot,
		"request_id": _request.id if _request != null else 0,
		"pause_world": _shot.pause_world if is_instance_valid(_shot) else false,
		"elapsed": _elapsed,
		"remaining": maxf(0.0, total_seconds - _elapsed) if _phase != &"idle" else 0.0,
		"last_error": _last_error,
	}

func _on_presentation_finished(id: int, result: StringName) -> void:
	if _request == null or id != _request.id: return
	var request = _request
	if result not in [&"completed", &"cancelled"]: _last_error = result
	_reset_active()
	if is_instance_valid(_director) and _director.has_method("complete_cinematic_request"):
		_director.complete_cinematic_request(id, result)
	shot_finished.emit(id, result)

func _source_camera() -> Camera3D:
	if not is_inside_tree(): return null
	var source := get_viewport().get_camera_3d()
	if not is_instance_valid(source) or source == _camera \
			or not source.is_inside_tree() or source.is_queued_for_deletion():
		return null
	return source

func _snapshot_error(snapshot: Dictionary) -> StringName:
	var transform_value: Variant = snapshot.get("transform")
	if not transform_value is Transform3D or not (transform_value as Transform3D).is_finite():
		return &"invalid_shot"
	for key in ["enter_seconds", "hold_seconds", "return_seconds"]:
		if not _finite_number(snapshot, key, 0.0): return &"invalid_shot"
	if not snapshot.get("pause_world") is bool: return &"invalid_shot"
	if not snapshot.get("projection") is int \
			or int(snapshot.get("projection")) < Camera3D.PROJECTION_PERSPECTIVE \
			or int(snapshot.get("projection")) > Camera3D.PROJECTION_FRUSTUM:
		return &"invalid_shot"
	if not snapshot.get("keep_aspect") is int \
			or int(snapshot.get("keep_aspect")) < Camera3D.KEEP_WIDTH \
			or int(snapshot.get("keep_aspect")) > Camera3D.KEEP_HEIGHT:
		return &"invalid_shot"
	for key in ["size", "fov", "h_offset", "v_offset"]:
		if not _finite_number(snapshot, key): return &"invalid_shot"
	for key in ["near", "far"]:
		if not _finite_number(snapshot, key, 0.000001): return &"invalid_shot"
	if float(snapshot.get("near")) >= float(snapshot.get("far")): return &"invalid_shot"
	var frustum: Variant = snapshot.get("frustum_offset")
	if not frustum is Vector2 or not (frustum as Vector2).is_finite():
		return &"invalid_shot"
	if not snapshot.get("cull_mask") is int or int(snapshot.get("cull_mask")) < 0:
		return &"invalid_shot"
	for key in ["environment", "attributes", "compositor"]:
		if not snapshot.has(key): return &"invalid_shot"
	if snapshot.get("environment") != null and not snapshot.get("environment") is Environment:
		return &"invalid_shot"
	if snapshot.get("attributes") != null and not snapshot.get("attributes") is CameraAttributes:
		return &"invalid_shot"
	if snapshot.get("compositor") != null and not snapshot.get("compositor") is Compositor:
		return &"invalid_shot"
	if not snapshot.get("transition_easing") is int \
			or int(snapshot.get("transition_easing")) < 0 \
			or int(snapshot.get("transition_easing")) > 4:
		return &"invalid_shot"
	if not snapshot.get("shake_enabled") is bool: return &"invalid_shot"
	for key in ["shake_position_amplitude", "shake_rotation_degrees"]:
		var vector: Variant = snapshot.get(key)
		if not vector is Vector3 or not (vector as Vector3).is_finite():
			return &"invalid_shot"
	for key in ["shake_frequency", "shake_fade_in_seconds", "shake_fade_out_seconds"]:
		if not _finite_number(snapshot, key, 0.0): return &"invalid_shot"
	if not snapshot.get("shake_seed") is int: return &"invalid_shot"
	return &""

func _finite_number(snapshot: Dictionary, key: String, minimum: float = -INF) -> bool:
	var value: Variant = snapshot.get(key)
	if not (value is int or value is float): return false
	var number := float(value)
	return is_finite(number) and number >= minimum

func _phase_for_elapsed(value: float) -> StringName:
	var enter_seconds := float(_snapshot.get("enter_seconds", 0.0))
	var hold_seconds := float(_snapshot.get("hold_seconds", 0.0))
	if enter_seconds > 0.0 and value < enter_seconds: return &"enter"
	if hold_seconds > 0.0 and value < enter_seconds + hold_seconds: return &"hold"
	return &"return"

func _total_seconds() -> float:
	return float(_snapshot.get("enter_seconds", 0.0)) \
		+ float(_snapshot.get("hold_seconds", 0.0)) \
		+ float(_snapshot.get("return_seconds", 0.0))

func _reset_active() -> void:
	var token := _pause_token
	_pause_token = 0
	_phase = &"idle"
	_request = null
	_shot = null
	_elapsed = 0.0
	_snapshot.clear()
	if token != 0: Pauses.for_tree(get_tree()).release(token)

func _admission(result: StringName, request_id: int = 0) -> Dictionary:
	return {
		"accepted": result == &"started",
		"request_id": request_id,
		"result": result,
		"reason": &"" if result == &"started" else result,
	}
