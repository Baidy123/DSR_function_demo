extends Camera3D

## Explicitly ticked by the presentation owner, including while the scene is paused.
## This node never changes the source rig, follow target, or scene pause state.
signal presentation_finished(request_id: int, result: StringName)

enum Phase { IDLE, MOVE, HOLD, RETURN }

const VIEW_PROPERTIES: Array[StringName] = [
	&"environment", &"attributes", &"compositor",
	&"projection", &"keep_aspect", &"fov", &"size", &"frustum_offset",
	&"near", &"far", &"cull_mask", &"h_offset", &"v_offset",
]

var _phase: Phase = Phase.IDLE
var _source: Camera3D
var _request_id: int = 0
var _elapsed: float = 0.0
var _move_seconds: float = 0.0
var _hold_seconds: float = 0.0
var _return_seconds: float = 0.0
var _start_view: Transform3D
var _focus_view: Transform3D
var _start_size: float = 1.0
var _focus_size: float = 1.0
var _start_focus: Vector3
var _focus: Vector3
var _return_from: Transform3D
var _return_size: float = 1.0
var _return_fov: float = 75.0
var _return_h_offset: float = 0.0
var _return_v_offset: float = 0.0
var _return_frustum: Vector2
var _occlusion_target: Node3D
var _occlusion_acquired: bool = false


func _ready() -> void:
	# An owner may tick from idle processing even though the source uses physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	set_process(false)
	set_physics_process(false)
	_occlusion_target = Node3D.new()
	_occlusion_target.name = "PresentationFocus"
	add_child(_occlusion_target, false, Node.INTERNAL_MODE_BACK)
	_occlusion_target.top_level = true


func start_presentation(source: Camera3D, focus: Vector3, options: Dictionary, request_id: int) -> bool:
	if is_presenting() or not is_inside_tree() or not is_node_ready() or is_queued_for_deletion():
		return false
	if not _valid_camera(source) or source == self or source.get_viewport() != get_viewport():
		return false
	if get_viewport().get_camera_3d() != source or not focus.is_finite():
		return false
	_source = source
	_focus = focus
	_start_view = source.get_global_transform_interpolated()
	_start_focus = _ground_focus(source, _start_view, focus.y)
	if not _start_focus.is_finite():
		_source = null
		return false
	# A single helper stays on the source adapter. Never capture somebody else's faded clones.
	_occlusion_acquired = false
	if source.has_method("begin_presentation_occlusion"):
		if not source.has_method("update_presentation_occlusion") or not source.has_method("end_presentation_occlusion"):
			_source = null
			return false
		_occlusion_acquired = bool(source.call("begin_presentation_occlusion", self))
		if not _occlusion_acquired:
			_source = null
			return false
	_request_id = request_id
	_move_seconds = _option(options, &"move_seconds", 0.6)
	_hold_seconds = _option(options, &"hold_seconds", 1.0)
	_return_seconds = _option(options, &"return_seconds", 0.6)
	_start_size = source.size
	var requested_size: float = _option(options, &"size", 0.0)
	_focus_size = requested_size if requested_size > 0.0 else _start_size
	_focus_view = _start_view
	_focus_view.origin += focus - _start_focus
	_elapsed = 0.0
	_phase = Phase.MOVE
	source.tree_exiting.connect(_on_source_tree_exiting)
	# All visual properties and the interpolated pose are copied BEFORE ownership changes.
	_copy_view(source)
	global_transform = _start_view
	reset_physics_interpolation()
	_occlusion_target.global_position = _start_focus
	make_current()
	return true


func advance_presentation(delta: float) -> void:
	if not is_presenting(): return
	if not _source_available():
		_finish(&"source_lost", false)
		return
	if get_viewport().get_camera_3d() != self:
		_finish(&"camera_lost", false)
		return
	if not is_finite(delta) or delta < 0.0: return
	var remaining: float = delta
	# At most MOVE -> HOLD -> RETURN, even with a large delta or zero-length phases.
	for transition in 3:
		var duration: float = _phase_duration()
		var step: float = minf(remaining, maxf(0.0, duration - _elapsed))
		_elapsed += step
		remaining -= step
		var weight: float = smoothstep(0.0, 1.0, _elapsed / duration) if duration > 0.0 else 1.0
		match _phase:
			Phase.MOVE:
				global_transform = _start_view.interpolate_with(_focus_view, weight)
				size = lerpf(_start_size, _focus_size, weight)
				_occlusion_target.global_position = _start_focus.lerp(_focus, weight)
			Phase.HOLD:
				global_transform = _focus_view
				size = _focus_size
				_occlusion_target.global_position = _focus
			Phase.RETURN:
				_refresh_source()
				if not _source_available():
					_finish(&"source_lost", false)
					return
				if get_viewport().get_camera_3d() != self:
					_finish(&"camera_lost", false)
					return
				var destination: Transform3D = _return_view()
				_copy_view(_source)
				global_transform = _return_from.interpolate_with(destination, weight)
				size = lerpf(_return_size, _source.size, weight)
				fov = lerpf(_return_fov, _source.fov, weight)
				h_offset = lerpf(_return_h_offset, _source.h_offset, weight)
				v_offset = lerpf(_return_v_offset, _source.v_offset, weight)
				frustum_offset = _return_frustum.lerp(_source.frustum_offset, weight)
				var return_focus: Vector3 = _ground_focus(_source, destination, _focus.y)
				if not return_focus.is_finite(): return_focus = _start_focus
				_occlusion_target.global_position = _focus.lerp(return_focus, weight)
		_update_occlusion(step)
		if _elapsed < duration: return
		_elapsed = 0.0
		match _phase:
			Phase.MOVE:
				_phase = Phase.HOLD
			Phase.HOLD:
				_phase = Phase.RETURN
				_return_from = global_transform
				_return_size = size
				_return_fov = fov
				_return_h_offset = h_offset
				_return_v_offset = v_offset
				_return_frustum = frustum_offset
			Phase.RETURN:
				_finish(&"completed", true)
				return


func cancel_presentation(restore_camera: bool = true) -> void:
	if is_presenting(): _finish(&"cancelled", restore_camera)


func is_presenting() -> bool:
	return _phase != Phase.IDLE


func _phase_duration() -> float:
	match _phase:
		Phase.MOVE: return _move_seconds
		Phase.HOLD: return _hold_seconds
		Phase.RETURN: return _return_seconds
	return 0.0


func _option(options: Dictionary, key: StringName, fallback: float) -> float:
	var value: Variant = options.get(key, fallback)
	if not (value is float or value is int): return fallback
	var number: float = float(value)
	return maxf(0.0, number) if is_finite(number) else fallback


func _copy_view(source: Camera3D) -> void:
	for property: StringName in VIEW_PROPERTIES:
		set(property, source.get(property))
	# Resources are referenced read-only; shared Environment/Attributes/materials are never mutated.


func _ground_focus(source: Camera3D, view: Transform3D, ground_y: float) -> Vector3:
	if source.has_method("get_follow_actor"):
		var actor: Node3D = source.call("get_follow_actor") as Node3D
		if is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_queued_for_deletion():
			var point: Vector3 = actor.get_global_transform_interpolated().origin
			if actor.has_method("get_camera_ground_height"):
				point.y = float(actor.call("get_camera_ground_height"))
			return point
	# Unbound cameras use the center view ray and the requested ground plane.
	# Invert the actual projection: project_ray_normal omits asymmetric frustum offsets.
	var clip_near: Vector4 = source.get_camera_projection().inverse() * Vector4(0.0, 0.0, -1.0, 1.0)
	var local_near: Vector3 = Vector3(clip_near.x, clip_near.y, clip_near.z) / clip_near.w
	var origin: Vector3 = view * (local_near + Vector3(source.h_offset, source.v_offset, 0.0))
	var direction: Vector3 = -view.basis.z if source.projection == Camera3D.PROJECTION_ORTHOGONAL else view.basis * local_near.normalized()
	if absf(direction.y) <= 0.00001: return Vector3(INF, INF, INF)
	var distance: float = (ground_y - origin.y) / direction.y
	if distance < 0.0: return Vector3(INF, INF, INF)
	return origin + direction * distance


func _refresh_source() -> void:
	if _source_available() and _source.has_method("prepare_presentation_return"):
		_source.call("prepare_presentation_return")


func _return_view() -> Transform3D:
	# The paused adapter has synchronously refreshed/reset the rig; Godot's interpolated
	# getter can still cache the preceding rendered frame until the next frame boundary.
	if not _source.can_process() and _source.has_method("prepare_presentation_return"):
		return _source.global_transform
	return _source.get_global_transform_interpolated()


func _update_occlusion(delta: float) -> void:
	if _occlusion_acquired and _source_available():
		_source.call("update_presentation_occlusion", self, _occlusion_target, delta)


func _valid_camera(camera: Camera3D) -> bool:
	return is_instance_valid(camera) and camera.is_inside_tree() and not camera.is_queued_for_deletion()


func _source_available() -> bool:
	return _valid_camera(_source) and is_inside_tree() and _source.get_viewport() == get_viewport()


func _finish(result: StringName, restore_camera: bool) -> void:
	var finished_id: int = _request_id
	var source: Camera3D = _source
	var owns_view: bool = is_inside_tree() and get_viewport().get_camera_3d() == self
	if restore_camera and owns_view and _source_available():
		_refresh_source()
		if _source_available() and get_viewport().get_camera_3d() == self:
			_copy_view(source)
			global_transform = _return_view()
			reset_physics_interpolation()
			source.make_current()
	# clear_current(false) never selects an arbitrary camera during unload/source loss.
	if is_inside_tree() and get_viewport().get_camera_3d() == self:
		clear_current(false)
	if is_instance_valid(source):
		if source.tree_exiting.is_connected(_on_source_tree_exiting):
			source.tree_exiting.disconnect(_on_source_tree_exiting)
		if _occlusion_acquired:
			source.call("end_presentation_occlusion", self)
	_occlusion_acquired = false
	_source = null
	_phase = Phase.IDLE
	_elapsed = 0.0
	# Reset before notifying: the owner may synchronously start its next request.
	presentation_finished.emit(finished_id, result)


func _on_source_tree_exiting() -> void:
	if is_presenting(): _finish(&"source_lost", false)


func _exit_tree() -> void:
	if is_presenting(): _finish(&"cancelled", true)
