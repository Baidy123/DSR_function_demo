extends Camera3D

## Explicitly ticked by the presentation owner, including while the scene is paused.
## This node never changes the source rig, follow target, or scene pause state.
signal presentation_finished(request_id: int, result: StringName)
## Emitted synchronously after this presentation camera actually becomes current.
signal became_current

enum Phase { IDLE, MOVE, HOLD, RETURN }

const VIEW_PROPERTIES: Array[StringName] = [
	&"environment", &"attributes", &"compositor",
	&"projection", &"keep_aspect", &"fov", &"size", &"frustum_offset",
	&"near", &"far", &"cull_mask", &"h_offset", &"v_offset",
]
const SWITCH_VIEW_PROPERTIES: Array[StringName] = [
	&"environment", &"attributes", &"compositor",
	&"projection", &"keep_aspect", &"cull_mask",
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

var _cinematic_mode := false
var _target_transform: Transform3D
var _target_properties: Dictionary
var _shot_options: Dictionary
var _shake_position_noise: FastNoiseLite
var _shake_rotation_noise: FastNoiseLite
var _base_shot_transform: Transform3D
var _start_lens: Dictionary
var _return_lens: Dictionary
var _shot_elapsed: float = 0.0


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
	became_current.emit()
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
	if _cinematic_mode:
		_advance_cinematic(delta)
		return
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


func start_cinematic_shot(source: Camera3D, snapshot: Dictionary, request_id: int) -> bool:
	if is_presenting() or not is_inside_tree() or not is_node_ready():
		return false
	if not _valid_camera(source) or source == self or get_viewport().get_camera_3d() != source:
		return false
	if not _valid_cinematic_snapshot(snapshot):
		return false
	_occlusion_acquired = false
	if source.has_method("begin_presentation_occlusion"):
		if not source.has_method("update_presentation_occlusion") \
				or not source.has_method("end_presentation_occlusion"):
			return false
		if not bool(source.call("begin_presentation_occlusion", self)):
			return false
		_occlusion_acquired = true
	_source = source
	_start_view = source.get_global_transform_interpolated()
	var target_transform: Transform3D = snapshot.get("transform")
	_target_transform = target_transform
	_target_properties = snapshot.duplicate(true)
	_shot_options = snapshot.duplicate(true)
	_request_id = request_id
	_move_seconds = float(snapshot.get("enter_seconds"))
	_hold_seconds = float(snapshot.get("hold_seconds"))
	_return_seconds = float(snapshot.get("return_seconds"))
	_elapsed = 0.0
	_shot_elapsed = 0.0
	_phase = Phase.MOVE
	_cinematic_mode = true
	_capture_start_lens(source)
	_copy_view(source)
	_set_cinematic_switch_properties(_target_properties)
	global_transform = _start_view
	reset_physics_interpolation()
	_occlusion_target.global_position = _cinematic_occlusion_focus()
	_create_shake_noise(snapshot)
	source.tree_exiting.connect(_on_source_tree_exiting)
	make_current()
	became_current.emit()
	return true


func _valid_cinematic_snapshot(snapshot: Dictionary) -> bool:
	var transform_value: Variant = snapshot.get("transform")
	if not transform_value is Transform3D:
		return false
	var target_transform: Transform3D = transform_value
	if not target_transform.is_finite():
		return false
	for key: String in ["enter_seconds", "hold_seconds", "return_seconds"]:
		if not _finite_snapshot_number(snapshot, key, 0.0):
			return false
	for key: String in ["size", "fov", "h_offset", "v_offset"]:
		if snapshot.has(key) and not _finite_snapshot_number(snapshot, key):
			return false
	for key: String in ["near", "far"]:
		if snapshot.has(key) and not _finite_snapshot_number(snapshot, key, 0.000001):
			return false
	if snapshot.has("near") and snapshot.has("far") \
			and float(snapshot.get("near")) >= float(snapshot.get("far")):
		return false
	if snapshot.has("frustum_offset"):
		var offset: Variant = snapshot.get("frustum_offset")
		if not offset is Vector2 or not (offset as Vector2).is_finite():
			return false
	if snapshot.has("projection") and not _snapshot_enum(snapshot, "projection",
			Camera3D.PROJECTION_PERSPECTIVE, Camera3D.PROJECTION_FRUSTUM):
		return false
	if snapshot.has("keep_aspect") and not _snapshot_enum(snapshot, "keep_aspect",
			Camera3D.KEEP_WIDTH, Camera3D.KEEP_HEIGHT):
		return false
	if snapshot.has("cull_mask"):
		var cull_mask_value: Variant = snapshot.get("cull_mask")
		if not cull_mask_value is int or int(cull_mask_value) < 0:
			return false
	if snapshot.has("environment"):
		var environment_value: Variant = snapshot.get("environment")
		if environment_value != null and not environment_value is Environment:
			return false
	if snapshot.has("attributes"):
		var attributes_value: Variant = snapshot.get("attributes")
		if attributes_value != null and not attributes_value is CameraAttributes:
			return false
	if snapshot.has("compositor"):
		var compositor_value: Variant = snapshot.get("compositor")
		if compositor_value != null and not compositor_value is Compositor:
			return false
	if snapshot.has("transition_easing") and not _snapshot_enum(snapshot, "transition_easing",
			0, 4):
		return false
	if snapshot.has("shake_enabled") and not snapshot.get("shake_enabled") is bool:
		return false
	for key: String in ["shake_position_amplitude", "shake_rotation_degrees"]:
		if snapshot.has(key):
			var vector: Variant = snapshot.get(key)
			if not vector is Vector3 or not (vector as Vector3).is_finite():
				return false
	for key: String in ["shake_fade_in_seconds", "shake_fade_out_seconds"]:
		if snapshot.has(key) and not _finite_snapshot_number(snapshot, key, 0.0):
			return false
	if snapshot.has("shake_frequency") \
			and not _finite_snapshot_number(snapshot, "shake_frequency", 0.01):
		return false
	if snapshot.has("shake_seed") and not snapshot.get("shake_seed") is int:
		return false
	if snapshot.has("pause_world") and not snapshot.get("pause_world") is bool:
		return false
	return true


func _finite_snapshot_number(snapshot: Dictionary, key: String, minimum: float = -INF) -> bool:
	var value: Variant = snapshot.get(key)
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	return is_finite(number) and number >= minimum


func _snapshot_enum(snapshot: Dictionary, key: String, minimum: int, maximum: int) -> bool:
	var value: Variant = snapshot.get(key)
	return value is int and int(value) >= minimum and int(value) <= maximum


func is_cinematic_shot() -> bool:
	return _cinematic_mode and is_presenting()


func _advance_cinematic(delta: float) -> void:
	var remaining := delta
	for transition in 3:
		var duration := _phase_duration()
		var step := minf(remaining, maxf(0.0, duration - _elapsed))
		_elapsed += step
		_shot_elapsed += step
		remaining -= step
		var progress := _elapsed / duration if duration > 0.0 else 1.0
		var weight := _easing_weight(progress)
		_sample_cinematic_pose(weight)
		if not _source_available():
			_finish(&"source_lost", false)
			return
		if get_viewport().get_camera_3d() != self:
			_finish(&"camera_lost", false)
			return
		global_transform = _base_shot_transform
		_apply_shake()
		if _occlusion_acquired:
			_occlusion_target.global_position = _cinematic_occlusion_focus()
		_update_occlusion(step)
		if _elapsed < duration: return
		_elapsed = 0.0
		match _phase:
			Phase.MOVE: _phase = Phase.HOLD
			Phase.HOLD:
				_phase = Phase.RETURN
				_return_from = _base_shot_transform
				_capture_return_lens()
			Phase.RETURN:
				_finish(&"completed", true)
				return


func _capture_start_lens(source: Camera3D) -> void:
	_start_lens = {
		&"size": source.size,
		&"fov": source.fov,
		&"h_offset": source.h_offset,
		&"v_offset": source.v_offset,
		&"frustum_offset": source.frustum_offset,
		&"near": source.near,
		&"far": source.far,
	}


func _capture_return_lens() -> void:
	_return_lens = {
		&"size": size,
		&"fov": fov,
		&"h_offset": h_offset,
		&"v_offset": v_offset,
		&"frustum_offset": frustum_offset,
		&"near": near,
		&"far": far,
	}


func _sample_cinematic_pose(weight: float) -> void:
	match _phase:
		Phase.MOVE:
			_base_shot_transform = _start_view.interpolate_with(_target_transform, weight)
			_set_cinematic_lens(_lerp_cinematic_lens(_start_lens, _target_lens(), weight))
		Phase.HOLD:
			_base_shot_transform = _target_transform
			_set_cinematic_lens(_target_lens())
		Phase.RETURN:
			if not _source_available(): return
			_refresh_source()
			if not _source_available(): return
			if get_viewport().get_camera_3d() != self: return
			var destination: Transform3D = _return_view()
			_copy_view(_source)
			_base_shot_transform = _return_from.interpolate_with(destination, weight)
			_set_cinematic_lens(_lerp_cinematic_lens(_return_lens, _current_source_lens(), weight))


func _target_lens() -> Dictionary:
	return {
		&"size": float(_target_properties.get(&"size", _start_lens.get(&"size", 1.0))),
		&"fov": float(_target_properties.get(&"fov", _start_lens.get(&"fov", 75.0))),
		&"h_offset": float(_target_properties.get(&"h_offset", _start_lens.get(&"h_offset", 0.0))),
		&"v_offset": float(_target_properties.get(&"v_offset", _start_lens.get(&"v_offset", 0.0))),
		&"frustum_offset": _target_properties.get(&"frustum_offset", _start_lens.get(&"frustum_offset", Vector2.ZERO)),
		&"near": float(_target_properties.get(&"near", _start_lens.get(&"near", near))),
		&"far": float(_target_properties.get(&"far", _start_lens.get(&"far", far))),
	}


func _current_source_lens() -> Dictionary:
	return {
		&"size": _source.size,
		&"fov": _source.fov,
		&"h_offset": _source.h_offset,
		&"v_offset": _source.v_offset,
		&"frustum_offset": _source.frustum_offset,
		&"near": _source.near,
		&"far": _source.far,
	}


func _lerp_cinematic_lens(from: Dictionary, to: Dictionary, weight: float) -> Dictionary:
	return {
		&"size": lerpf(float(from.get(&"size", 1.0)), float(to.get(&"size", 1.0)), weight),
		&"fov": lerpf(float(from.get(&"fov", 75.0)), float(to.get(&"fov", 75.0)), weight),
		&"h_offset": lerpf(float(from.get(&"h_offset", 0.0)), float(to.get(&"h_offset", 0.0)), weight),
		&"v_offset": lerpf(float(from.get(&"v_offset", 0.0)), float(to.get(&"v_offset", 0.0)), weight),
		&"frustum_offset": (from.get(&"frustum_offset", Vector2.ZERO) as Vector2).lerp(to.get(&"frustum_offset", Vector2.ZERO) as Vector2, weight),
		&"near": lerpf(float(from.get(&"near", 0.05)), float(to.get(&"near", 0.05)), weight),
		&"far": lerpf(float(from.get(&"far", 4000.0)), float(to.get(&"far", 4000.0)), weight),
	}


func _set_cinematic_lens(lens: Dictionary) -> void:
	size = float(lens.get(&"size", size))
	fov = float(lens.get(&"fov", fov))
	h_offset = float(lens.get(&"h_offset", h_offset))
	v_offset = float(lens.get(&"v_offset", v_offset))
	frustum_offset = lens.get(&"frustum_offset", frustum_offset) as Vector2
	near = float(lens.get(&"near", near))
	far = float(lens.get(&"far", far))


func _set_cinematic_switch_properties(properties: Dictionary) -> void:
	for property: StringName in SWITCH_VIEW_PROPERTIES:
		if properties.has(property):
			set(property, properties[property])


func _easing_weight(linear: float) -> float:
	var t := clampf(linear, 0.0, 1.0)
	match int(_shot_options.get(&"transition_easing", 1)):
		0: return t
		1: return smoothstep(0.0, 1.0, t)
		2: return t * t
		3: return 1.0 - (1.0 - t) * (1.0 - t)
		4:
			if t < 0.5: return 2.0 * t * t
			return 1.0 - pow(-2.0 * t + 2.0, 2.0) / 2.0
		_: return smoothstep(0.0, 1.0, t)


func _create_shake_noise(snapshot: Dictionary) -> void:
	var seed_value: int = int(snapshot.get(&"shake_seed", 0))
	_shake_position_noise = FastNoiseLite.new()
	_shake_position_noise.seed = seed_value
	_shake_position_noise.frequency = 1.0
	_shake_rotation_noise = FastNoiseLite.new()
	_shake_rotation_noise.seed = seed_value
	_shake_rotation_noise.frequency = 1.0


func _shake_envelope() -> float:
	if not bool(_shot_options.get(&"shake_enabled", false)): return 0.0
	var fade_in: float = maxf(0.0, float(_shot_options.get(&"shake_fade_in_seconds", 0.0)))
	var fade_out: float = maxf(0.0, float(_shot_options.get(&"shake_fade_out_seconds", 0.0)))
	match _phase:
		Phase.MOVE:
			fade_in = minf(fade_in, maxf(0.0, _move_seconds))
			return clampf(_elapsed / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0
		Phase.HOLD:
			return 1.0
		Phase.RETURN:
			fade_out = minf(fade_out, maxf(0.0, _return_seconds))
			return clampf(1.0 - _elapsed / fade_out, 0.0, 1.0) if fade_out > 0.0 else 0.0
	return 0.0


func _apply_shake() -> void:
	if not bool(_shot_options.get("shake_enabled", false)): return
	var amplitude := _shake_envelope()
	var phase := _shot_elapsed * float(_shot_options.shake_frequency)
	var source_basis := _base_shot_transform.basis
	var local_position := Vector3(
		_shake_position_noise.get_noise_1d(phase),
		_shake_position_noise.get_noise_1d(phase + 31.0),
		_shake_position_noise.get_noise_1d(phase + 67.0))
	var local_rotation: Vector3 = Vector3(
		_shake_rotation_noise.get_noise_1d(phase + 13.0),
		_shake_rotation_noise.get_noise_1d(phase + 47.0),
		_shake_rotation_noise.get_noise_1d(phase + 89.0)) \
		* _shot_options.shake_rotation_degrees * amplitude
	var rotation_basis := Basis.from_euler(Vector3(
		deg_to_rad(local_rotation.x),
		deg_to_rad(local_rotation.y),
		deg_to_rad(local_rotation.z)))
	global_transform = Transform3D(
		source_basis * rotation_basis,
		_base_shot_transform.origin + source_basis * (local_position
			* _shot_options.shake_position_amplitude * amplitude))


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


func _cinematic_occlusion_focus() -> Vector3:
	if _source_available() and _source.has_method("get_follow_actor"):
		var actor: Node3D = _source.call("get_follow_actor") as Node3D
		if is_instance_valid(actor) and actor.is_inside_tree() and not actor.is_queued_for_deletion():
			var player_focus: Vector3 = actor.get_global_transform_interpolated().origin
			if player_focus.is_finite(): return player_focus
	if _source_available():
		var source_focus := _ground_focus(
			_source, _source.get_global_transform_interpolated(), 0.0)
		if source_focus.is_finite(): return source_focus
	return _occlusion_target.global_position


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
	_reset_cinematic_state()
	# Reset before notifying: the owner may synchronously start its next request.
	presentation_finished.emit(finished_id, result)


func _reset_cinematic_state() -> void:
	_cinematic_mode = false
	_target_transform = Transform3D()
	_target_properties.clear()
	_shot_options.clear()
	_shake_position_noise = null
	_shake_rotation_noise = null
	_base_shot_transform = Transform3D()
	_start_lens.clear()
	_return_lens.clear()
	_shot_elapsed = 0.0


func _on_source_tree_exiting() -> void:
	if is_presenting(): _finish(&"source_lost", false)


func _exit_tree() -> void:
	if is_presenting(): _finish(&"cancelled", true)
