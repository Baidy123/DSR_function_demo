@tool
class_name CinematicShot3D
extends Camera3D

const GROUP := &"cinematic_shot"
enum Easing { LINEAR, SMOOTH, EASE_IN, EASE_OUT, EASE_IN_OUT }

@export_range(0.0, 10.0, 0.05, "suffix:s") var enter_seconds := 0.6
@export_range(0.0, 30.0, 0.05, "suffix:s") var hold_seconds := 1.2
@export_range(0.0, 10.0, 0.05, "suffix:s") var return_seconds := 0.6
@export var pause_world := true
@export var transition_easing: Easing = Easing.SMOOTH
@export var shake_enabled := false
@export var shake_position_amplitude := Vector3(0.1, 0.05, 0.1)
@export var shake_rotation_degrees := Vector3.ONE
@export_range(0.01, 60.0, 0.01) var shake_frequency := 12.0
@export_range(0.0, 5.0, 0.01) var shake_fade_in_seconds := 0.15
@export_range(0.0, 5.0, 0.01) var shake_fade_out_seconds := 0.25
@export var shake_seed := 0

func _ready() -> void:
	current = false
	set_process(false)
	set_physics_process(false)
	if not Engine.is_editor_hint(): add_to_group(GROUP)

func configuration_error() -> StringName:
	if not is_finite(enter_seconds) or enter_seconds < 0.0:
		return &"invalid_enter_seconds"
	for value in [hold_seconds, return_seconds,
			shake_fade_in_seconds, shake_fade_out_seconds]:
		if not is_finite(float(value)) or float(value) < 0.0: return &"invalid_timing"
	if not is_finite(shake_frequency) or shake_frequency < 0.01:
		return &"invalid_shake_frequency"
	if not shake_position_amplitude.is_finite() or not shake_rotation_degrees.is_finite():
		return &"invalid_shake"
	return &""

func runtime_snapshot() -> Dictionary:
	return {
		"transform": global_transform,
		"projection": projection, "keep_aspect": keep_aspect,
		"size": size, "fov": fov, "frustum_offset": frustum_offset,
		"near": near, "far": far, "cull_mask": cull_mask,
		"h_offset": h_offset, "v_offset": v_offset,
		"environment": environment, "attributes": attributes, "compositor": compositor,
		"enter_seconds": enter_seconds, "hold_seconds": hold_seconds,
		"return_seconds": return_seconds, "pause_world": pause_world,
		"transition_easing": transition_easing, "shake_enabled": shake_enabled,
		"shake_position_amplitude": shake_position_amplitude,
		"shake_rotation_degrees": shake_rotation_degrees,
		"shake_frequency": shake_frequency,
		"shake_fade_in_seconds": shake_fade_in_seconds,
		"shake_fade_out_seconds": shake_fade_out_seconds, "shake_seed": shake_seed,
	}
