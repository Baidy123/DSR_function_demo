extends RefCounted

## 身体姿态和单次翻越执行；不读取目标、不选择路线或动作。
const Geometry = preload("res://scripts/systems/character_geometry.gd")
const LowCover = preload("res://scripts/world/low_cover_geometry.gd")
var actor: CharacterBody3D
var crouch_requested := false
var amount := 0.0
var _presentation_transition: StringName = &""
var vault: Dictionary = {}
var progress := 0.0
var falling := false
var _landing_target := Vector3.INF
var _landing_best := INF
var _landing_stalled := 0.0

func setup(body: CharacterBody3D) -> void:
	actor = body
	actor.get_node("CollisionShape3D").shape = actor.get_node("CollisionShape3D").shape.duplicate()
	var mesh: Mesh = preload("res://resources/models/crouch_capsule.tres").duplicate()
	mesh.material = actor.get_node("Body").mesh.material
	if actor.get_node("Body").mesh is CapsuleMesh: mesh.radius = actor.get_node("Body").mesh.radius
	actor.get_node("Body").mesh = mesh
	reset()

func reset() -> void:
	crouch_requested = false
	amount = 0.0
	_presentation_transition = &""
	vault = {}
	progress = 0.0
	falling = false
	_landing_target = Vector3.INF
	_landing_best = INF
	_landing_stalled = 0.0
	_apply_height(actor.get_posture_body_height(false))

func height() -> float:
	return lerpf(actor.get_posture_body_height(false), actor.get_posture_body_height(true), amount)

func presentation_state() -> Dictionary:
	return {
		"amount": amount,
		"transition": &"" if actor.is_dead else _presentation_transition,
		"vaulting": active(),
		"vault_progress": progress if active() else 0.0,
		"vault_falling": active() and falling,
	}

func request_crouch(value: bool) -> void:
	crouch_requested = value

func update_posture(delta: float) -> void:
	if active() or actor.is_dead: return
	var target := 1.0 if crouch_requested else 0.0
	var next := move_toward(amount, target, maxf(delta, 0.0) / maxf(actor.posture_seconds, 0.01))
	var next_height := lerpf(actor.get_posture_body_height(false), actor.get_posture_body_height(true), next)
	if next < amount and not Geometry.can_occupy(actor, actor.global_position, next_height, radius()): return
	# 只记录真实姿态变化；顶阻时保留过渡方向及其冻结的高度。
	if next > amount: _presentation_transition = &"crouch_enter"
	elif next < amount: _presentation_transition = &"crouch_exit"
	if next <= 0.0 or next >= 1.0: _presentation_transition = &""
	amount = next
	_apply_height(next_height)

func radius() -> float:
	return actor.get_node("CollisionShape3D").shape.radius

func _apply_height(value: float) -> void:
	var collision: CollisionShape3D = actor.get_node("CollisionShape3D")
	collision.shape.height = value
	collision.position.y = value * 0.5
	var body: MeshInstance3D = actor.get_node("Body")
	if body.mesh is CapsuleMesh:
		body.mesh.height = value
		body.position.y = value * 0.5
	var marker := actor.get_node_or_null("FrontMarker") as Node3D
	if marker != null: marker.position.y = value - 0.25

func active() -> bool:
	return not vault.is_empty()

func begin(plan: Dictionary) -> bool:
	if active() or actor.is_dead or actor.melee_active or actor.get_tree().paused: return false
	if not plan.get("valid", false) or not is_instance_valid(plan.get("cover")): return false
	var direction: Vector3 = plan.exit - plan.entry
	var checked := LowCover.query_vault_at(actor, plan.cover, actor.global_position, direction, plan.duration, false)
	if not checked.get("valid", false): return false
	vault = checked
	progress = 0.0
	falling = false
	_landing_target = Vector3.INF
	_landing_best = INF
	_landing_stalled = 0.0
	actor.cancel_reload()
	actor.clear_aim()
	actor.velocity = Vector3.ZERO
	amount = 1.0
	_presentation_transition = &""
	_apply_height(float(vault.height))
	return true

func interrupt() -> void:
	if active(): falling = true

func advance(delta: float) -> void:
	if not active() or actor.get_tree().paused: return
	if not is_instance_valid(vault.get("cover")): falling = true
	if not falling:
		progress = minf(1.0, progress + maxf(delta, 0.0) / float(vault.duration))
		var destination := LowCover.sample_vault(vault, progress)
		var collision := actor.move_and_collide(destination - actor.global_position)
		if collision != null: falling = true
		if progress >= 1.0: falling = true
	if falling:
		var ground_height: float = maxf(vault.entry.y, vault.exit.y)
		var horizontal := Vector3.ZERO
		if actor.is_on_floor() and actor.global_position.y > ground_height + 0.2:
			horizontal = _landing_direction(delta)
		actor.velocity.x = horizontal.x
		actor.velocity.z = horizontal.z
		actor.velocity += actor.get_gravity() * delta
		actor.velocity += actor._advance_hit_push(delta)
		actor.move_and_slide()
		if actor.is_on_floor() and actor.global_position.y <= ground_height + 0.2:
			vault = {}
			actor.velocity = Vector3.ZERO
			if actor.is_dead: actor.get_node("CollisionShape3D").set_deferred("disabled", true)
			else: actor.vault_landed.emit()

func _landing_direction(delta: float) -> Vector3:
	if not _landing_target.is_finite():
		_landing_target = vault.entry if actor.global_position.distance_squared_to(vault.entry) < actor.global_position.distance_squared_to(vault.exit) else vault.exit
	var other: Vector3 = vault.exit if _landing_target.is_equal_approx(vault.entry) else vault.entry
	var height: float = actor.get_posture_body_height(false)
	var blocked: bool = not Geometry.can_occupy(actor, _landing_target, height, radius())
	# A character or a new obstacle may occupy the nearer endpoint after takeoff.
	# Try the original other endpoint; never release vault occupation on the wall.
	if (blocked or _landing_stalled >= 0.3) and Geometry.can_occupy(actor, other, height, radius()):
		_landing_target = other
		_landing_best = INF
		_landing_stalled = 0.0
	var direction: Vector3 = _landing_target - actor.global_position
	direction.y = 0.0
	var distance: float = direction.length()
	if distance < _landing_best - 0.02:
		_landing_best = distance
		_landing_stalled = 0.0
	else:
		_landing_stalled += maxf(0.0, delta)
	return direction.normalized() * maxf(actor.move_speed, 0.5)
