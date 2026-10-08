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
var crouch_amount: float = 0.0
var vaulting: bool = false
var vault_progress: float = 0.0


func base_state() -> StringName:
	if dead: return &"dead"
	if in_dialogue: return &"dialogue"
	if vaulting: return &"vault"
	if melee_active: return &"melee"
	if reloading: return &"reload"
	if crouch_amount > 0.01:
		return &"crouch_move" if Vector2(local_velocity.x, local_velocity.z).length() > 0.02 else &"crouch"
	if Vector2(local_velocity.x, local_velocity.z).length() > 0.02:
		return &"sprint" if sprinting else &"move"
	return &"aim" if aiming else &"idle"
