extends RefCounted

var local_velocity: Vector3 = Vector3.ZERO
var sprinting: bool = false
var aiming: bool = false
var in_dialogue: bool = false
var dead: bool = false
var reloading: bool = false
var reload_progress: float = 0.0
var melee_active: bool = false
var melee_progress: float = 0.0
var melee_phase: int = 0
var weapon: Resource


func base_state() -> StringName:
	if dead: return &"dead"
	if in_dialogue: return &"dialogue"
	if melee_active: return &"melee"
	if reloading: return &"reload"
	if Vector2(local_velocity.x, local_velocity.z).length() > 0.02:
		return &"sprint" if sprinting else &"move"
	return &"aim" if aiming else &"idle"
