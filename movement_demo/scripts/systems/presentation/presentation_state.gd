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
## 无外部角色模型挂点时使用；坐标相对于所属 Presentation。
var weapon_mount_position: Vector3 = Vector3.ZERO
var crouch_amount: float = 0.0
var posture_transition: StringName = &""
var vaulting: bool = false
var vault_progress: float = 0.0
var vault_falling: bool = false


func base_state() -> StringName:
	if dead: return &"dead"
	if in_dialogue: return &"dialogue"
	if vaulting: return &"vault_fall" if vault_falling else &"vault"
	if melee_active: return &"melee"
	if posture_transition in [&"crouch_enter", &"crouch_exit"]: return posture_transition
	if reloading: return &"crouch_reload" if crouch_amount > 0.01 else &"reload"
	if crouch_amount > 0.01:
		if Vector2(local_velocity.x, local_velocity.z).length() > 0.02: return &"crouch_move"
		return &"crouch_aim" if aiming else &"crouch"
	if Vector2(local_velocity.x, local_velocity.z).length() > 0.02:
		return &"sprint" if sprinting else &"move"
	return &"aim" if aiming else &"idle"
