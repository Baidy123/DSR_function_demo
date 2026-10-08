extends SceneTree

const LowGeometry = preload("res://scripts/world/low_cover_geometry.gd")
var checks := 0
var failed := 0
var scene: Node3D
var player
var combat
var slots
var wall: Node3D

class BodyTarget extends StaticBody3D:
	var body_height := 1.75
	var hits := 0
	func get_torso_position() -> Vector3:
		return global_position + Vector3.UP * body_height * 0.55
	func get_visibility_points() -> Array[Vector3]:
		return [get_torso_position(), global_position + Vector3.UP * (body_height - 0.06)]
	func receive_hit(_damage: float, _attacker: Vector3) -> void:
		hits += 1

class Recorder extends Node:
	var events: Array[Dictionary] = []
	func receive_noise(source: Node3D, _position: Vector3, radius: float, _multiplier: float) -> void:
		events.append({"source": source, "radius": radius})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	# Retain the real player subtree, including ammo/slots/HUD, in a controlled physical room.
	var original: Node = load("res://scenes/main.tscn").instantiate()
	player = original.get_node("Player")
	original.remove_child(player)
	original.free()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	_box(Vector3(0, -0.1, 0), Vector3(30, 0.2, 30))
	var zone := Area3D.new()
	zone.add_to_group("combat_zone")
	var zone_shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(25, 5, 25)
	zone_shape.shape = bounds
	zone.add_child(zone_shape)
	scene.add_child(zone)
	scene.add_child(player)
	player.set_physics_process(false)
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	slots.primary_weapon = slots.primary_weapon.duplicate()
	slots.secondary_weapon = slots.secondary_weapon.duplicate()
	for weapon in [slots.primary_weapon, slots.secondary_weapon]:
		weapon.melee_stamina_cost = 20.0
	slots.select_slot(0)
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	await _step(5)
	_check("uses real floor and combat overlap", player.is_on_floor() and combat.can_combat())
	_check("standing capsule and visible mesh are 1.75m", _height_matches(1.75))
	var feet: Vector3 = player.global_position
	_send_c_key(true)
	await _step(1)
	_check("physical C input selects manual crouch through the scene input chain", player.manual_crouch and player.crouch_amount > 0.0)
	_send_c_key(false)
	await _step(3)
	_check("crouch visibly transitions before completion", player.crouch_amount > 0.0 and player.crouch_amount < 1.0 and _height_matches(player.get_body_height()))
	await _step(12)
	_check("completed crouch changes mesh/collider together without moving feet", player.is_crouching() and _height_matches(1.0) and player.global_position.distance_to(feet) < 0.01)
	_check("crouched eye and muzzle are actual body points", is_equal_approx(player.get_eye_position().y - player.global_position.y, 0.88) and is_equal_approx(player.get_muzzle_position().y - player.global_position.y, 0.72))
	Input.action_press("aim")
	await _step(15)
	_check("open-ground aiming stays crouched", combat.is_aiming and player.is_crouching())
	wall = load("res://scenes/world/low_cover.tscn").instantiate()
	scene.add_child(wall)
	wall.global_position = Vector3(0, 0.55, -1)
	await _step(20)
	_check("low wall in aim direction temporarily stands", not player.is_crouching() and is_zero_approx(player.crouch_amount) and player.manual_crouch)
	await _step(20)
	_check("hypothetical crouch ray prevents stand/crouch oscillation", is_zero_approx(player.crouch_amount))
	Input.action_release("aim")
	await _step(15)
	_check("release restores manual crouch", player.is_crouching())
	Input.action_press("aim")
	await _step(15)
	_check("another cover aim only temporarily stands before manual input", player.manual_crouch and is_zero_approx(player.crouch_amount))
	_send_c_key(true)
	await _step(1)
	_send_c_key(true, true)
	await _step(2)
	_send_c_key(false)
	_check("C during assisted stand selects standing and keyboard echo does not toggle back", not player.manual_crouch and is_zero_approx(player.crouch_amount))
	Input.action_release("aim")
	await _step(15)
	_check("release aim after physical C keeps standing", not player.manual_crouch and is_zero_approx(player.crouch_amount))
	_send_c_key(true)
	await _step(1)
	_send_c_key(false)
	await _step(14)
	_check("next physical C normally crouches again", player.manual_crouch and player.is_crouching())
	player.rotation.y = PI
	Input.action_press("aim")
	await _step(15)
	_check("back to low wall can aim crouched", player.is_crouching())
	Input.action_release("aim")
	player.request_crouch(false)
	await _step(15)
	_check("manual stand clears crouch intent", not player.manual_crouch and is_zero_approx(player.crouch_amount))
	player.request_crouch(true)
	await _step(15)
	var roof := _box(Vector3(0, 1.35, 0), Vector3(2, 0.2, 1.2))
	await _step(3)
	player.request_crouch(false)
	await _step(20)
	_check("blocked headroom does not expand through ceiling", player.get_body_height() < 1.26 and not player.can_stand())
	roof.queue_free()
	await _step(20)
	_check("standing request completes when headroom clears", is_zero_approx(player.crouch_amount))
	player.rotation = Vector3.ZERO
	var target := BodyTarget.new()
	var target_collision := CollisionShape3D.new()
	var target_shape := CapsuleShape3D.new()
	target_shape.height = 1.75
	target_shape.radius = 0.35
	target_collision.shape = target_shape
	target_collision.position.y = 0.875
	target.add_child(target_collision)
	target.add_to_group("combat_target")
	scene.add_child(target)
	target.global_position = Vector3(0, 0, -2.5)
	var gun_blocker := _box(Vector3(0, 0.75, -1), Vector3(3, 1.5, 0.6))
	Input.action_press("aim")
	await _step(5)
	_check("visible head acquires lock above obscured torso", combat.locked_target == target and combat.get_locked_aim_point().y > 1.6)
	combat.aim_mode = 0
	combat.accuracy = 1.0
	combat.shot_cooldown = 0.0
	combat.shoot()
	_check("visible head does not let muzzle shoot through blocker", combat.last_shot_collider == gun_blocker and target.hits == 0)
	target.body_height = 1.0
	target_shape.height = 1.0
	target_collision.position.y = 0.5
	await _step(5)
	_check("fully hidden target loses lock and selected aim point", combat.locked_target == null and not combat.get_locked_aim_point().is_finite())
	Input.action_release("aim")
	target.queue_free()
	gun_blocker.queue_free()
	player.request_crouch(true)
	await _step(15)
	# The bonus is a view of base accuracy, shared by both existing aim modes.
	for mode in [0, 1]:
		combat.aim_mode = mode
		combat.accuracy = 0.5
		combat.crouch_bonus_blocked_until_recovery = false
		_check("mode %d adds 0.25 without writing base" % mode, is_equal_approx(combat.get_effective_accuracy(), 0.75) and combat.accuracy == 0.5)
		combat.accuracy = 0.9
		_check("mode %d caps effective accuracy at one" % mode, combat.get_effective_accuracy() == 1.0)
	combat.accuracy = 0.5
	combat.crouch_accuracy_bonus = 0.0
	_check("zero bonus disables it", combat.get_effective_accuracy() == 0.5)
	combat.crouch_accuracy_bonus = 0.25
	combat.ammo.magazine_rounds = 1
	_check("crouch allows existing reload", combat.request_reload())
	_check("reload forced zero overrides crouch bonus", combat.get_effective_accuracy() == 0.0)
	combat.end_frame(combat.weapon.reload_seconds + 1.0, false)
	_check("completion frame remains zero", not combat.ammo.is_reloading and combat.get_effective_accuracy() == 0.0)
	combat.end_frame(0.01, false)
	_check("post-reload recovery wait remains zero", combat.get_effective_accuracy() == 0.0)
	combat.end_frame(5.0, false)
	_check("bonus returns after original recovery wait", combat.get_effective_accuracy() >= 0.25)
	combat.apply_melee_disruption()
	_check("melee disruption overrides crouch bonus", combat.get_effective_accuracy() == 0.0)
	slots.select_slot(1)
	_check("switching weapon cannot bypass melee zero", combat.get_effective_accuracy() == 0.0)
	await _step(3)
	combat.end_frame(5.0, false)
	combat.cancel_reload()
	# Emitted radius, not just exported field values; stationary pose changes emit no footsteps.
	var recorder := Recorder.new()
	root.add_child(recorder)
	recorder.add_to_group("hearing_listener")
	player.rotation = Vector3.ZERO
	player.movement_noise_radius = 3.0
	player.sprint_noise_multiplier = 2.0
	player.crouch_noise_multiplier = 0.5
	player._movement_noise_timer = 0.0
	Input.action_press("move_right")
	Input.action_press("sprint")
	await _step(30)
	_check("crouch cannot sprint and emits 1.5m steps", not player.is_sprinting and not recorder.events.is_empty() and is_equal_approx(recorder.events[-1].radius, 1.5))
	Input.action_release("move_right")
	Input.action_release("sprint")
	await _step(20)
	recorder.events.clear()
	player.request_crouch(false)
	await _step(20)
	_check("stationary posture changes do not emit footsteps", recorder.events.is_empty())
	player.sprint_noise_radius = 9.0
	_check("legacy nondefault sprint radius migrates to multiplier", player.sprint_noise_multiplier == 3.0 and player.sprint_noise_radius == 9.0)
	player.movement_noise_radius = 0.0
	player.sprint_noise_radius = 7.0
	player.is_sprinting = true
	_check("legacy base-zero fast-nonzero remains valid", player.get_movement_noise_radius() == 7.0)
	player.sprint_noise_multiplier = 2.0
	_check("explicit multiplier restores base-zero mute", player.get_movement_noise_radius() == 0.0)
	player.movement_noise_radius = 3.0
	player.is_sprinting = false
	var saved = _roundtrip_player({"movement_noise_radius": 0.0, "sprint_noise_multiplier": 2.0, "crouch_noise_multiplier": 0.35})
	saved.movement_noise_radius = 4.0
	saved.is_sprinting = true
	_check("new multiplier saves without serializing a derived zero legacy radius", saved.get_movement_noise_radius() == 8.0 and is_equal_approx(saved.crouch_noise_multiplier, 0.35))
	saved.free()
	saved = _roundtrip_player({"movement_noise_radius": 4.0, "sprint_noise_radius": 12.0})
	_check("old nondefault radius saves as normalized multiplier", saved.sprint_noise_multiplier == 3.0 and saved.sprint_noise_radius == 12.0)
	saved.free()
	saved = _roundtrip_player({"movement_noise_radius": 0.0, "sprint_noise_radius": 7.0})
	saved.is_sprinting = true
	_check("old base-zero exception survives saving", saved.get_movement_noise_radius() == 7.0)
	saved.free()
	saved = _roundtrip_player({"movement_noise_radius": 0.0, "sprint_noise_radius": 6.0})
	saved.is_sprinting = true
	_check("old base-zero radius six is saved despite old export default", saved.get_movement_noise_radius() == 6.0)
	saved.free()
	saved = _roundtrip_player({"movement_noise_radius": 3.0, "sprint_noise_radius": 9.0, "sprint_noise_multiplier": 0.0})
	saved.is_sprinting = true
	_check("explicit zero multiplier overrides old radius and survives saving", saved.get_movement_noise_radius() == 0.0 and saved.sprint_noise_multiplier == 0.0)
	saved.free()
	saved = _roundtrip_player({"movement_noise_radius": 3.0, "sprint_noise_radius": -1.0})
	saved.is_sprinting = true
	_check("legacy sentinel means normal multiplier rather than silent zero", saved.get_movement_noise_radius() == 6.0 and saved.sprint_noise_multiplier == 2.0)
	saved.free()
	var packed_combat := PackedScene.new()
	var settings_node = combat.get_script().new()
	settings_node.crouch_accuracy_bonus = 0.4
	packed_combat.pack(settings_node)
	ResourceSaver.save(packed_combat, "user://half-cover-accuracy-test.tscn")
	var reloaded_combat = load("user://half-cover-accuracy-test.tscn").instantiate()
	_check("player-only accuracy bonus is exported and reloads", is_equal_approx(reloaded_combat.crouch_accuracy_bonus, 0.4))
	reloaded_combat.free()
	settings_node.free()
	DirAccess.remove_absolute("user://half-cover-accuracy-test.tscn")
	# Near cover: waiting to stand pays once at actual attack start.
	player.global_position = Vector3(3, 0, 0)
	player.request_crouch(true)
	await _step(15)
	player.stamina = 100.0
	var count: int = combat.melee_count
	_check("crouch V requests stand without immediate cost", combat.request_melee() and combat.is_waiting_for_melee_stand() and player.stamina == 100.0)
	_check("repeated V cannot queue extra attack", not combat.request_melee())
	await _step(14)
	_check("standing starts one melee and deducts once", combat.melee_count == count + 1 and player.stamina == 80.0)
	await _step(60)
	_check("melee finish restores manual crouch", player.is_crouching())
	_check("another crouch V can be canceled by weapon switch", combat.request_melee() and slots.select_slot(0) and not combat.is_waiting_for_melee_stand())
	# Validate a full physical crossing, input locks and landing pose/direction.
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	player.velocity = Vector3.ZERO
	await _step(5)
	var plan := LowGeometry.query_vault(player, Vector3.FORWARD)
	_check("real low wall produces a safe vault plan", plan.get("valid", false))
	var rounds: int = combat.ammo.magazine_rounds
	var shots: int = combat.shot_count
	var hp: float = player.health.health
	Input.action_press("aim")
	_check("Space-equivalent request starts vault", player.request_vault(Vector3.FORWARD))
	combat.is_aiming = true
	combat.shoot()
	_check("vault rejects attacks and reload without consuming ammo", combat.shot_count == shots and combat.ammo.magazine_rounds == rounds and not combat.request_melee() and not combat.request_reload())
	player.receive_hit(1.0)
	_check("vault still receives damage", player.health.health == hp - 1.0)
	var camera_y: float = player.get_camera_ground_height()
	await _step(24)
	_check("vault lifts actual body while camera ground stays level", player.is_vaulting() and player.global_position.y > 0.5 and is_equal_approx(player.get_camera_ground_height(), camera_y))
	var frozen: Vector3 = player.global_position
	paused = true
	player._physics_process(0.5)
	_check("paused vault cannot progress", player.global_position == frozen)
	paused = false
	await _step(70)
	_check("vault reaches opposite ground and releases occupation", not player.is_vaulting() and player.is_on_floor() and player.global_position.z < -1.5 and absf(player.global_position.y) < 0.02)
	_check("landing stays forward and crouched while aiming away from wall", player.is_crouching() and player.manual_crouch and (-player.global_basis.z).dot(Vector3.FORWARD) > 0.99)
	Input.action_release("aim")
	# Hit interruption above wall must not allow attacks until on real ground.
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	await _step(5)
	_check("second vault starts", player.request_vault(Vector3.FORWARD))
	await _step(24)
	player.receive_melee_hit(1.0, player.global_position + Vector3.RIGHT, 0.1, 0.1)
	_check("interrupted airborne vault remains occupied", player.is_vaulting() and not combat.request_melee())
	await _step(180)
	_check("interrupted vault settles off wall without collider bypass", not player.is_vaulting() and player.is_on_floor() and player.global_position.y < 0.2)
	# A held trigger remains the original input state, while new clicks are discarded.
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	await _step(5)
	combat.ammo.magazine_rounds = 3
	combat.request_reload()
	combat.ammo.advance_reload(combat.weapon.reload_seconds * 0.6)
	_check("vault interrupts reload at existing half checkpoint", player.request_vault(Vector3.FORWARD) and not combat.ammo.is_reloading and combat.ammo.reload_checkpoint == 0.5)
	await _step(15)
	var saved_ammo = combat.ammo
	_check("vault does not auto-resume checkpoint", not saved_ammo.is_reloading and saved_ammo.reload_checkpoint == 0.5)
	_check("vault preserves original weapon switch support", slots.select_slot(1 - slots.active_slot) and player.is_vaulting())
	_check("switch back cannot start reload in midair", slots.select_slot(1 - slots.active_slot) and combat.ammo == saved_ammo and not combat.ammo.is_reloading)
	await _step(65)
	_check("landing resumes the same saved checkpoint", combat.ammo.is_reloading and combat.ammo.reload_progress >= 0.5)
	combat.cancel_reload()
	player.global_position = Vector3.ZERO
	player.rotation = Vector3.ZERO
	await _step(5)
	Input.action_press("aim")
	combat.is_aiming = true
	combat.accuracy = 0.7
	combat.fire_held = true
	Input.action_press("fire")
	player.request_vault(Vector3.FORWARD)
	_check("vault clearing old lock does not clear held trigger or accuracy", combat.fire_held and is_equal_approx(combat.accuracy, 0.7))
	Input.action_release("fire")
	await _step(5)
	_check("release during vault clears held trigger", not combat.fire_held)
	var click := InputEventAction.new()
	click.action = "fire"
	click.pressed = true
	combat._unhandled_input(click)
	_check("new vault click creates no pending shot", not combat.shot_requested and not combat.fire_held)
	await _step(65)
	Input.action_release("aim")
	print("Player half cover: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)

func _send_c_key(pressed: bool, echo: bool = false) -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_C
	key.keycode = KEY_C
	key.pressed = pressed
	key.echo = echo
	Input.parse_input_event(key)
	# 模拟按键也经过真实分发；主动交付积累队列，避免headless多physics帧先于一次输入刷新。
	Input.flush_buffered_events()

func _height_matches(expected: float) -> bool:
	return is_equal_approx(player.get_node("CollisionShape3D").shape.height, expected) and is_equal_approx(player.get_node("Visual/Body").mesh.height, expected) and is_equal_approx(player.get_node("Visual/Body").position.y, expected * 0.5)

func _roundtrip_player(properties: Dictionary):
	var prototype = player.get_script().new()
	for property in properties: prototype.set(property, properties[property])
	scene.add_child(prototype)
	prototype.set_physics_process(false)
	var packed := PackedScene.new()
	packed.pack(prototype)
	ResourceSaver.save(packed, "user://half-cover-noise-test.tscn")
	prototype.free()
	var restored = ResourceLoader.load("user://half-cover-noise-test.tscn", "", ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	scene.add_child(restored)
	restored.set_physics_process(false)
	DirAccess.remove_absolute("user://half-cover-noise-test.tscn")
	return restored

func _step(count: int) -> void:
	for frame in count:
		await physics_frame
		player._physics_process(1.0 / 60.0)

func _box(position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	scene.add_child(body)
	body.global_position = position
	return body

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)
