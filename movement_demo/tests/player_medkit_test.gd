extends SceneTree

const STEP := 1.0 / 60.0
const ACTIONS := [&"move_up", &"move_down", &"move_left", &"move_right", &"sprint",
	&"aim", &"fire", &"reload", &"melee", &"crouch", &"vault", &"interact",
	&"weapon_primary", &"weapon_secondary", &"weapon_next", &"weapon_previous"]
var checks := 0
var failed := 0
var scene: Node3D
var player
var health
var medkit
var combat
var indicator
var camera: Camera3D

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var original: Node = load("res://scenes/main.tscn").instantiate()
	player = original.get_node("Player")
	original.remove_child(player)
	original.free()
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(30, 0.2, 30)
	collision.shape = shape
	floor_body.add_child(collision)
	scene.add_child(floor_body)
	floor_body.position.y = -0.1
	camera = Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 7, 10)
	camera.look_at(Vector3(0, 0.8, 0))
	camera.make_current()
	health = player.get_node("Health")
	health.max_health = 100.0
	health.debug_mode = false
	scene.add_child(player)
	player.global_position = Vector3.ZERO
	player.set_physics_process(false)
	combat = player.get_node("Combat")
	medkit = health.get_node_or_null("Medkit")
	_check("medical module is a child of the existing Health", medkit != null)
	if medkit == null:
		_finish()
		return
	medkit.set_physics_process(false)
	indicator = health.get_node("MedkitIndicator")
	await _step(5)
	_check("H is mapped to use_medkit", InputMap.has_action("use_medkit") and InputMap.action_get_events("use_medkit")[0].physical_keycode == KEY_H)
	_check("default resource has two-second treatment and independent stock", medkit.settings.use_seconds == 2.0 and medkit.settings.heal_amount == 50.0 and medkit.remaining_count == 3)
	_check("full health cannot start or consume a kit", not medkit.request_use() and medkit.remaining_count == 3)
	_check("invalid healing cannot damage or overflow health", health.restore_health(-1.0) == 0.0 and health.restore_health(NAN) == 0.0 and health.restore_health(INF) == 0.0 and health.health == 100.0)
	player.receive_hit(75.0)
	_key(KEY_H, true)
	_key(KEY_H, false)
	_check("physical H starts without early healing or consumption", medkit.is_using() and health.health == 25.0 and medkit.remaining_count == 3)
	medkit._physics_process(1.0)
	_check("one second is halfway and still has no effect", is_equal_approx(medkit.get_progress(), 0.5) and health.health == 25.0 and medkit.remaining_count == 3)
	indicator._process(0.0)
	var expected := camera.unproject_position(player.global_position + Vector3.UP * player.get_body_height())
	_check("ring follows the projected head above the body", indicator.visible and absf(indicator.position.x - expected.x) < 0.1 and indicator.position.y < expected.y)
	_check("progress display reads treatment and never captures input", is_equal_approx(indicator.progress, 0.5) and indicator.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(450, 250)
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	_key(KEY_H, true, true)
	_key(KEY_H, false)
	_check("mouse movement and held-key repeat do not cancel or restart", medkit.is_using() and is_equal_approx(medkit.get_progress(), 0.5))
	paused = true
	medkit._physics_process(5.0)
	_check("paused Health cannot advance treatment even though it processes Always", medkit.is_using() and is_equal_approx(medkit.get_progress(), 0.5) and health.health == 25.0)
	paused = false
	medkit._physics_process(0.99)
	_check("treatment cannot finish before two seconds", medkit.is_using() and health.health == 25.0)
	medkit._physics_process(0.01)
	_check("completion heals once and consumes exactly one kit", not medkit.is_using() and health.health == 75.0 and medkit.remaining_count == 2)
	medkit._physics_process(10.0)
	_check("extra frames cannot repeat completion", health.health == 75.0 and medkit.remaining_count == 2)
	_check("weapon HUD shows the remaining quantity", player.get_node("WeaponSlots/Panel/Content/MedkitCount").text.contains("2"))
	medkit.request_use()
	medkit._physics_process(2.0)
	_check("healing clamps at maximum health", health.health == 100.0 and medkit.remaining_count == 1)
	player.receive_hit(25.0)
	medkit.remaining_count = 0
	_check("empty stock refuses treatment", not medkit.request_use())
	medkit.remaining_count = 3
	medkit.settings = medkit.settings.duplicate()
	var saved_settings = medkit.settings
	medkit.settings = null
	_check("empty settings safely disable medical use", not medkit.request_use())
	medkit.settings = saved_settings
	for invalid in [0.0, -1.0, NAN, INF]:
		medkit.settings.use_seconds = invalid
		_check("invalid duration refuses treatment " + str(invalid), not medkit.request_use())
	medkit.settings.use_seconds = 2.0
	for invalid in [0.0, -1.0, NAN, INF]:
		medkit.settings.heal_amount = invalid
		_check("invalid effect refuses treatment " + str(invalid), not medkit.request_use())
	medkit.settings.heal_amount = 50.0
	medkit.request_use()
	medkit._physics_process(1.5)
	player.receive_hit(10.0)
	_check("ordinary hit immediately interrupts and clears progress", not medkit.is_using() and medkit.get_progress() == 0.0 and health.health == 65.0 and medkit.remaining_count == 3)
	medkit._physics_process(4.0)
	_check("cancelled treatment has no delayed healing", health.health == 65.0 and medkit.remaining_count == 3)
	medkit.request_use()
	player.receive_hit(0.0)
	player.receive_hit(-1.0)
	player.receive_hit(NAN)
	_check("invalid damage does not count as a hit", medkit.is_using())
	health.debug_invincible = true
	player.receive_hit(10.0)
	_check("valid hit also cancels under debug invincibility without damage", not medkit.is_using() and health.health == 65.0)
	health.debug_invincible = false
	medkit.request_use()
	medkit._physics_process(1.9)
	_key(KEY_H, true)
	_key(KEY_H, false)
	_check("second H cancels without starting again on the same event", not medkit.is_using() and medkit.remaining_count == 3)
	medkit.request_use()
	medkit._physics_process(0.1)
	_check("next use starts at zero rather than resuming cancelled progress", is_equal_approx(medkit.get_progress(), 0.05))
	medkit.cancel()
	# Use real input dispatch; even actions that currently fail must cancel treatment.
	for action in ACTIONS:
		await _settle()
		_check("can start before action " + str(action), medkit.request_use())
		medkit._physics_process(1.99)
		_action(action, true)
		_check("action cancels immediately before completion: " + str(action), not medkit.is_using() and medkit.remaining_count == 3 and health.health == 65.0)
		_action(action, false)
		combat.cancel_reload()
		combat.cancel_melee()
	await _settle()
	Input.action_press("move_left")
	Input.action_press("move_right")
	_check("opposing held directions still prevent starting", not medkit.request_use())
	Input.action_release("move_left")
	Input.action_release("move_right")
	medkit.request_use()
	Input.action_press("aim")
	medkit._physics_process(2.0)
	_check("held input cancels even without an InputEvent", not medkit.is_using() and medkit.remaining_count == 3)
	Input.action_release("aim")
	await _settle()
	medkit.request_use()
	_key(KEY_C, true)
	_key(KEY_C, false)
	_check("crouch input is not swallowed by treatment", player.manual_crouch and not medkit.is_using())
	await _step(20)
	_check("stationary crouched player can treat", player.is_crouching() and medkit.request_use())
	indicator._process(0.0)
	var crouched_y: float = indicator.position.y
	medkit.cancel()
	player.request_crouch(false)
	await _step(20)
	medkit.request_use()
	indicator._process(0.0)
	_check("head indicator follows the actual crouch height", indicator.position.y < crouched_y)
	_key(KEY_D, true)
	await _step(20)
	_key(KEY_D, false)
	_check("movement both cancels treatment and actually moves", not medkit.is_using() and player.global_position.length() > 0.2)
	await _settle()
	combat.ammo.magazine_rounds = 1
	_check("original reload still starts", combat.request_reload())
	_check("cannot heal alongside active reload", not medkit.request_use())
	combat.ammo.advance_reload(combat.weapon.reload_seconds * 0.6)
	combat.interrupt_reload()
	_check("cannot bypass saved reload checkpoint", combat.ammo.reload_checkpoint == 0.5 and not medkit.request_use())
	combat.cancel_reload()
	medkit.request_use()
	_key(KEY_R, true)
	_key(KEY_R, false)
	_check("R cancels healing and continues original reload", not medkit.is_using() and combat.ammo.is_reloading)
	combat.cancel_reload()
	await _settle()
	medkit.request_use()
	player.set_dialogue_active(true)
	medkit._physics_process(2.0)
	indicator._process(0.0)
	_check("dialogue cancels without healing and hides the ring", not medkit.is_using() and not indicator.visible and medkit.remaining_count == 3)
	player.set_dialogue_active(false)
	_check("closing dialogue never resumes an old treatment", not medkit.is_using())
	medkit.settings.heal_amount = 12.0
	medkit.settings.use_seconds = 0.4
	medkit.request_use()
	medkit.settings.heal_amount = 99.0
	medkit.settings.use_seconds = 0.01
	medkit._physics_process(0.39)
	_check("active use keeps the settings captured at start", medkit.is_using() and health.health == 65.0)
	medkit._physics_process(0.01)
	_check("configured effect and duration drive actual completion", health.health == 77.0 and medkit.remaining_count == 2)
	medkit.request_use()
	camera.rotation.y += PI
	indicator._process(0.0)
	_check("indicator is hidden behind the camera", not indicator.visible)
	camera.rotation.y -= PI
	player.receive_hit(1000.0)
	_check("death cancels synchronously before the paused world can heal", health.is_dead and paused and not medkit.is_using() and medkit.remaining_count == 2)
	_check("heal entry cannot resurrect the player", health.restore_health(100.0) == 0.0 and health.health == 0.0)
	paused = false
	_finish()

func _settle() -> void:
	medkit.cancel()
	for action in ACTIONS: Input.action_release(action)
	combat.cancel_aim()
	combat.cancel_reload()
	combat.cancel_melee()
	player.request_crouch(false)
	await _step(22)

func _step(count: int) -> void:
	for frame in count:
		await physics_frame
		player._physics_process(STEP)
		medkit._physics_process(STEP)

func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if not passed: failed += 1
	print(("PASS " if passed else "FAIL ") + label)

func _finish() -> void:
	print("PLAYER MEDKIT: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
