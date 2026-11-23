extends CanvasLayer

signal finished(result: StringName)

const ShotScene = preload("res://scenes/cinematic/cinematic_shot_3d.tscn")

@export var enabled := true
## 自动测试默认跳过自动播放；专项测试会在入树前显式开启。
@export var run_in_script_tests := false
@export_range(0.0, 5.0, 0.05, "suffix:s") var fade_seconds := 0.8
@export_range(0.0, 10.0, 0.05, "suffix:s") var pan_seconds := 2.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var hold_seconds := 1.0
@export_range(0.0, 10.0, 0.05, "suffix:s") var return_seconds := 1.0
@export_node_path("Node3D") var player_path: NodePath = ^"../Player"
@export_node_path("Node3D") var npc_path: NodePath = ^"../NPC"
@export_node_path("Camera3D") var source_camera_path: NodePath = ^"../Camera3D"
@export_node_path("Node") var scene_director_path: NodePath = ^"../SceneDirector"

@onready var _overlay: ColorRect = $Overlay

var _phase: StringName = &"idle"
var _fade_elapsed := 0.0
var _request_id := 0
var _shot: Node3D
var _controller: Node
var _player: Node3D
var _previous_dialogue_active := false
var _owns_player_lock := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_overlay.color = Color.BLACK
	if not _should_play():
		visible = false
		_phase = &"skipped"
		return
	_phase = &"locking"
	_player = get_node_or_null(player_path) as Node3D
	if is_instance_valid(_player) and _player.has_method(&"set_dialogue_active"):
		_previous_dialogue_active = bool(_player.get("is_in_dialogue"))
		_player.call(&"set_dialogue_active", true)
		_owns_player_lock = true
	set_process(true)
	_start.call_deferred()


func debug_snapshot() -> Dictionary:
	return {
		"phase": _phase,
		"request_id": _request_id,
		"fade_alpha": _overlay.color.a,
	}


func _should_play() -> bool:
	if not enabled:
		return false
	if OS.get_cmdline_args().has("--script") and not run_in_script_tests:
		return false
	var state := get_node_or_null("/root/GameState")
	return state != null and state.has_method(&"claim_opening_cinematic") \
		and bool(state.call(&"claim_opening_cinematic"))


func _start() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if not is_inside_tree():
		return
	if not is_instance_valid(_player):
		_finish(&"no_player")
		return
	_phase = &"fade"
	_fade_elapsed = 0.0


func _process(delta: float) -> void:
	if _phase != &"fade":
		return
	_fade_elapsed += maxf(0.0, delta)
	var duration := maxf(0.0, fade_seconds)
	_overlay.color.a = clampf(1.0 - _fade_elapsed / duration, 0.0, 1.0) \
		if duration > 0.0 else 0.0
	if _fade_elapsed < duration:
		return
	set_process(false)
	_begin_pan()


func _begin_pan() -> void:
	var camera := get_node_or_null(source_camera_path) as Camera3D
	var npc := get_node_or_null(npc_path) as Node3D
	var director := get_node_or_null(scene_director_path)
	if not is_instance_valid(camera) or not is_instance_valid(npc) or director == null:
		_finish(&"missing_scene_binding")
		return
	_controller = director.get_node_or_null("CinematicCameraController")
	var shot_parent := director.get_node_or_null("CinematicShots")
	if _controller == null or shot_parent == null:
		_finish(&"missing_camera_controller")
		return
	_shot = ShotScene.instantiate()
	_shot.name = "OpeningNPCPan"
	shot_parent.add_child(_shot)
	var target_view := camera.get_global_transform_interpolated()
	var focus_ground := _camera_ground_focus(camera, target_view, _player.global_position.y)
	var delta: Vector3 = npc.global_position - focus_ground
	delta.y = 0.0
	target_view.origin += delta
	_shot.global_transform = target_view
	_shot.projection = camera.projection
	_shot.keep_aspect = camera.keep_aspect
	_shot.size = camera.size
	_shot.fov = camera.fov
	_shot.frustum_offset = camera.frustum_offset
	_shot.near = camera.near
	_shot.far = camera.far
	_shot.cull_mask = camera.cull_mask
	_shot.h_offset = camera.h_offset
	_shot.v_offset = camera.v_offset
	_shot.environment = camera.environment
	_shot.attributes = camera.attributes
	_shot.compositor = camera.compositor
	_shot.enter_seconds = maxf(0.0, pan_seconds)
	_shot.hold_seconds = maxf(0.0, hold_seconds)
	_shot.return_seconds = maxf(0.0, return_seconds)
	_shot.pause_world = true
	_controller.shot_finished.connect(_on_shot_finished)
	var admission: Dictionary = _controller.play_shot(_shot)
	if not bool(admission.get("accepted", false)):
		_finish(StringName(admission.get("result", &"failed")))
		return
	_request_id = int(admission.get("request_id", 0))
	_phase = &"enter"


func _camera_ground_focus(camera: Camera3D, view: Transform3D, ground_y: float) -> Vector3:
	var clip_near: Vector4 = camera.get_camera_projection().inverse() * Vector4(0.0, 0.0, -1.0, 1.0)
	var local_near := Vector3(clip_near.x, clip_near.y, clip_near.z) / clip_near.w
	var origin := view * (local_near + Vector3(camera.h_offset, camera.v_offset, 0.0))
	var direction := -view.basis.z if camera.projection == Camera3D.PROJECTION_ORTHOGONAL \
		else view.basis * local_near.normalized()
	if absf(direction.y) <= 0.00001:
		return _player.global_position
	var distance := (ground_y - origin.y) / direction.y
	if distance < 0.0 or not is_finite(distance):
		return _player.global_position
	return origin + direction * distance


func _on_shot_finished(request_id: int, result: StringName) -> void:
	if request_id != _request_id:
		return
	_finish(result)


func _finish(result: StringName) -> void:
	if _phase in [&"done", &"skipped"]:
		return
	if is_instance_valid(_controller) \
			and _controller.shot_finished.is_connected(_on_shot_finished):
		_controller.shot_finished.disconnect(_on_shot_finished)
	if is_instance_valid(_shot):
		_shot.queue_free()
	_shot = null
	_release_player_lock()
	_overlay.color.a = 0.0
	visible = false
	_phase = &"done" if result == &"completed" else &"error"
	finished.emit(result)


func _release_player_lock() -> void:
	if not _owns_player_lock:
		return
	_owns_player_lock = false
	if is_instance_valid(_player) and _player.has_method(&"set_dialogue_active"):
		_player.call(&"set_dialogue_active", _previous_dialogue_active)


func _exit_tree() -> void:
	_release_player_lock()
	if is_instance_valid(_controller) \
			and _controller.shot_finished.is_connected(_on_shot_finished):
		_controller.shot_finished.disconnect(_on_shot_finished)
