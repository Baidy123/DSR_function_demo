extends SceneTree

## Real player input, camera projection and physics visibility; no lock-result injection.
class Target extends StaticBody3D:
	var hits := 0
	var opening_snapshot := {}
	func receive_hit(_damage: float, _origin: Vector3 = Vector3.ZERO) -> void:
		hits += 1
	func get_visibility_points() -> Array[Vector3]:
		return [global_position + Vector3.UP * 0.8, global_position + Vector3.UP * 1.6]
	func get_melee_stun_state() -> Dictionary:
		return opening_snapshot.duplicate()

var checks := 0
var failures := 0
var world: Node3D
var player
var combat
var camera: Camera3D
var targets: Array[Target] = []
var original_mouse_mode: int
var fired_stabilities: Array[float] = []
var capture_ui := false
const CAPTURE_DIRECTORY := "res://logs/target_switch_20261028"

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	capture_ui = OS.get_cmdline_user_args().has("--capture") and DisplayServer.get_name() != "headless"
	original_mouse_mode = Input.mouse_mode
	root.get_node("DebugSettings").enabled = false
	Engine.physics_ticks_per_second = 240
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.collision_mask = 1
	zone.add_to_group("combat_zone")
	_box(zone, Vector3(100, 10, 100))
	world.add_child(zone)
	player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	combat = player.get_node("Combat")
	combat.shot_fired.connect(func(_hit: bool, stability: float): fired_stabilities.append(stability))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	camera.position = Vector3(0, 30, -3)
	camera.rotation_degrees = Vector3(-90, 0, 0)
	world.add_child(camera)
	camera.make_current()
	for frame in 4: await physics_frame
	check(is_equal_approx(combat.target_switch_travel_ratio, 0.12) and combat.target_switch_min_distance == 10 and combat.target_switch_max_distance == 48 and combat.target_switch_half_angle_degrees == 45 and combat.target_switch_turn_speed_degrees == 360 and combat.get("target_switch_reset_seconds") == null and combat.get("target_switch_distance") == null, "Player exposes distance ratio, bounds, direction angle and turn speed without fixed travel or pause settings")
	await _directions()
	await _distance_travel()
	await _gestures()
	await _automatic_lock()
	await _legality()
	await _combat_state()
	await _turning()
	await _turn_accuracy()
	await _headshot_ui()
	_gesture_clock()
	await _ui_focus()
	await _lifecycle()
	Input.action_release("aim")
	Input.action_release("fire")
	paused = false
	world.queue_free()
	await process_frame
	Input.mouse_mode = original_mouse_mode
	print("TARGET SWITCH: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _box(body: CollisionObject3D, size: Vector3, offset: Vector3 = Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = offset
	body.add_child(collision)

func _setup(points: Array[Vector3], mode: int = 1) -> void:
	Input.action_release("aim")
	Input.action_release("fire")
	combat.cancel_aim()
	combat.cancel_melee()
	for target in targets: target.free()
	targets.clear()
	player.position = Vector3.ZERO
	player.visual.rotation = Vector3.ZERO
	var gun := WeaponData.new()
	gun.aim_range = 50
	gun.cone_angle_degrees = 70
	gun.shot_noise = null
	gun.headshot_enabled = false
	gun.min_spread_angle_degrees = 0
	gun.max_spread_angle_degrees = 20
	gun.initial_spread_angle_degrees = 10
	if mode == 2: gun.fire_mode = WeaponData.FireMode.SHOTGUN
	combat.aim_mode = 0 if mode == 0 else 1
	var ammunition = load("res://scripts/weapons/weapon_ammo.gd").new(gun, {gun.get_ammo_key(): 24})
	combat.equip_weapon(gun, false, ammunition)
	fired_stabilities.clear()
	# Equal bounds isolate direction, continuity and lifecycle from candidate spacing.
	combat.target_switch_min_distance = 32
	combat.target_switch_max_distance = 32
	combat.target_switch_turn_speed_degrees = 360
	for point in points:
		var target := Target.new()
		target.position = point
		_box(target, Vector3(0.6, 1.8, 0.6), Vector3.UP * 0.9)
		world.add_child(target)
		targets.append(target)
	# Only A is initially registered, so initial acquisition uses the original path.
	targets[0].add_to_group("combat_target")
	for frame in 3: await physics_frame
	Input.action_press("aim")
	combat.begin_frame(0, true)
	for target in targets: target.add_to_group("combat_target")
	for frame in 2: await process_frame # Resume after the capture frame has fully completed.
	combat.accuracy = 0.8
	combat.accuracy_recovery_timer = 1

func _direction(from: Node3D, to: Node3D) -> Vector2:
	return (camera.unproject_position(to.global_position + Vector3.UP * 0.8) - camera.unproject_position(from.global_position + Vector3.UP * 0.8)).normalized()

func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_visible_rect().get_center()
	event.global_position = event.position
	event.relative = relative
	event.screen_relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(event, true)

func _step(delta: float = 0.0) -> void:
	combat.begin_frame(delta, Input.is_action_pressed("aim"))
	combat.end_frame(delta, false)

func _rest() -> void:
	await create_timer(0.135).timeout
	_step()

func _directions() -> void:
	for yaw in [0.0, 70.0]:
		camera.rotation_degrees.y = yaw
		for point in [Vector3(-4, 0, -5), Vector3(4, 0, -5), Vector3(1, 0, -9), Vector3(1, 0, -1), Vector3(-4, 0, -9), Vector3(3, 0, 4)]:
			await _setup([Vector3(0, 0, -5), point])
			var direction := _direction(targets[0], targets[1])
			_motion(direction * 40)
			check(combat.locked_target == targets[0], "Mouse input only queues the request before the combat frame")
			_step()
			check(combat.locked_target == targets[1], "Projected direction selects candidate %s with camera yaw %s" % [point, yaw])
	camera.rotation_degrees.y = 0
	for angle in [44.9, 45.1]:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
		_motion(_direction(targets[0], targets[1]).rotated(deg_to_rad(angle)) * 40)
		_step()
		check(combat.locked_target == targets[1 if angle < 45 else 0], "Direction half-angle boundary %s degrees" % angle)
	await _setup([Vector3(0, 0, -5), Vector3(3, 0, -5), Vector3(6, 0, -5)])
	_motion(Vector2.RIGHT * 40)
	_step()
	check(combat.locked_target == targets[1], "Aligned candidates select the nearest screen neighbor")

func _gestures() -> void:
	await _setup([Vector3(0, 0, -5), Vector3(3, 0, -5), Vector3(6, 0, -5)])
	_motion(Vector2.RIGHT * 20)
	_motion(Vector2.LEFT * 20)
	_step()
	check(combat.locked_target == targets[0], "Opposing subthreshold motion cancels instead of accumulating path length")
	_motion(Vector2.RIGHT * 20)
	_step()
	await _rest()
	_motion(Vector2.RIGHT * 20)
	_step()
	check(combat.locked_target == targets[0], "Separated small motions do not combine into a gesture")
	_motion(Vector2.RIGHT * 20)
	_step()
	check(combat.locked_target == targets[1], "An accumulated deliberate gesture switches once")
	_motion(Vector2.RIGHT * 80)
	_step()
	check(combat.locked_target == targets[2], "Continuing in the same direction switches again without a pause")
	await _setup([Vector3(0, 0, -5), Vector3(2, 0, -5), Vector3(4, 0, -5), Vector3(6, 0, -5)])
	_motion(Vector2.RIGHT * 400)
	_motion(Vector2.RIGHT * 100)
	_step()
	check(combat.locked_target == targets[1], "A large event and extra pending input select only one neighbor")
	for frame in 3: _step()
	check(combat.locked_target == targets[1], "No more movement means no more switching")
	_motion(Vector2.RIGHT * 31)
	_step()
	check(combat.locked_target == targets[1], "Large-event remainder and pending movement do not carry into the next request")
	_motion(Vector2.RIGHT)
	_step()
	check(combat.locked_target == targets[2], "A fresh full distance switches again immediately")
	await _setup([Vector3(0, 0, -5), Vector3(3, 0, -5)])
	_motion(Vector2.LEFT * 40)
	_step()
	_motion(Vector2.RIGHT * 31)
	_step()
	check(combat.locked_target == targets[0], "A failed request leaves no displacement in the next request")
	_motion(Vector2.RIGHT)
	_step()
	check(combat.locked_target == targets[1], "A no-candidate request can be retried immediately after fresh threshold motion")

func _distance_travel() -> void:
	for sample in [Vector2(50, 10), Vector2(200, 24), Vector2(500, 48)]:
		await _setup([Vector3(0, 0, -5), Vector3(1, 0, -5)])
		combat.target_switch_travel_ratio = 0.12
		combat.target_switch_min_distance = 10
		combat.target_switch_max_distance = 48
		var origin := camera.unproject_position(targets[0].position + Vector3.UP * 0.8)
		var aim := camera.project_position(origin + Vector2.RIGHT * sample.x, 29.2)
		targets[1].position = aim - Vector3.UP * 0.8
		for frame in 2: await physics_frame
		var gap := origin.distance_to(camera.unproject_position(targets[1].position + Vector3.UP * 0.8))
		check(absf(gap - sample.x) < 0.01 and combat._visible_target_point(targets[1]).is_finite(), "Fixture presents a visible %s-pixel target gap" % sample.x)
		_motion(Vector2.RIGHT * (sample.y - 0.5))
		_step()
		check(combat.locked_target == targets[0], "%s-pixel gap waits below its %s-pixel required travel" % [sample.x, sample.y])
		_motion(Vector2.RIGHT)
		_step()
		check(combat.locked_target == targets[1], "%s-pixel gap switches at its distance-scaled travel, including minimum/maximum bounds" % sample.x)

func _automatic_lock() -> void:
	await _setup([Vector3(1, 0, -3), Vector3(0, 0, -8), Vector3(-2, 0, -5)])
	combat.cancel_aim()
	player.visual.rotation = Vector3.ZERO
	_step()
	check(combat.locked_target == targets[1], "Original automatic acquisition prefers facing alignment over a nearer target")
	targets[0].position = Vector3(0.7, 0, -1.5)
	await physics_frame
	_step()
	check(combat.locked_target == targets[1], "A closer enemy cannot steal a valid lock without a mouse gesture")
	targets[1].remove_from_group("combat_target")
	_step()
	check(combat.locked_target == targets[2], "Invalidation still reacquires by the original facing-alignment rule")

func _legality() -> void:
	for reason in ["range", "screen", "removed", "queued", "hidden", "wall"]:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
		var obstacle: StaticBody3D
		match reason:
			"range": combat.weapon.aim_range = 5.5
			"screen": targets[1].position.x = 40
			"removed": targets[1].remove_from_group("combat_target")
			"queued": targets[1].queue_free()
			"hidden": targets[1].hide()
			"wall":
				obstacle = StaticBody3D.new()
				obstacle.position = Vector3(2, 1, -2.5)
				_box(obstacle, Vector3(1, 3, 1))
				world.add_child(obstacle)
		if reason != "queued":
			for frame in 2: await physics_frame
		_motion(Vector2.RIGHT * 40)
		_step()
		check(combat.locked_target == targets[0], "Candidate rejected by original visibility rules: " + reason)
		if reason == "queued": targets.remove_at(1)
		if is_instance_valid(obstacle): obstacle.free()
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	_motion(Vector2.RIGHT * 40)
	targets[1].remove_from_group("combat_target")
	_step()
	check(combat.locked_target == targets[0], "Candidate invalidated between input and frame is not locked")
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	var low_wall := StaticBody3D.new()
	low_wall.position = Vector3(2, 0.6, -2.5)
	_box(low_wall, Vector3(1, 1.2, 1))
	world.add_child(low_wall)
	for frame in 2: await physics_frame
	_motion(Vector2.RIGHT * 40)
	_step()
	check(combat.locked_target == targets[1] and combat.get_locked_aim_point().y > 1.5, "Partial cover retains the original visible upper-body aim point")
	low_wall.free()
	# Overhead camera projects vertically separated targets to the same screen point.
	await _setup([Vector3(0, 0, -5), Vector3(0, 3, -5)])
	_motion(Vector2.RIGHT * 40)
	_step()
	check(combat.locked_target == targets[0], "Coincident projections do not cause arbitrary target switching")

func _combat_state() -> void:
	for mode in 3:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)], mode)
		combat.shot_cooldown = 0.4
		var rounds: int = combat.ammo.magazine_rounds
		var count: int = combat.shot_count
		_motion(Vector2.RIGHT * 40)
		_step()
		check(combat.locked_target == targets[1] and is_equal_approx(combat.accuracy, 0.8) and is_equal_approx(combat.accuracy_recovery_timer, 1), "Mode %d switch preserves accuracy and recovery wait" % mode)
		check(combat.ammo.magazine_rounds == rounds and combat.shot_count == count and is_equal_approx(combat.shot_cooldown, 0.4), "Mode %d switch does not shoot, consume ammo or reset cooldown" % mode)
		_step(0.01)
		check(combat.accuracy < 0.8 and combat.last_target_position == targets[1].position, "Mode %d positive-time turning charges tracking while the new target sample stays current" % mode)
	for mode in 3:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)], mode)
		if mode == 2:
			combat.weapon.shotgun.pattern = ShotgunPattern.new()
			combat.weapon.shotgun.stable_jitter_degrees = 0
		combat.accuracy = 0.8
		var rounds_before: int = combat.ammo.magazine_rounds
		var shots_before: int = combat.shot_count
		_motion(Vector2.RIGHT * 40)
		Input.action_press("fire")
		var fire := InputEventAction.new()
		fire.action = "fire"
		fire.pressed = true
		root.push_input(fire, true)
		# Accuracy changes after the mouse/click events and before the actual firing frame.
		combat.accuracy = 1
		_step()
		check(combat.locked_target == targets[1] and combat.shot_count == shots_before + 1 and combat.ammo.magazine_rounds == rounds_before - 1 and not combat.shot_requested, "Mode %d fires and consumes one round immediately during a manual turn" % mode)
		check(combat.last_shot_collider == targets[0] and targets[0].hits == 1 and targets[1].hits == 0, "Mode %d actual shot follows current facing instead of bending to the new lock" % mode)
		check(fired_stabilities.size() == 1 and fired_stabilities[0] == 1, "Mode %d firing signal uses accuracy at emission rather than at input" % mode)
		combat.shot_cooldown = 0
		combat.accuracy = 0.42
		combat.shoot()
		check(combat.shot_count == shots_before + 2 and fired_stabilities.size() == 2 and is_equal_approx(fired_stabilities[1], 0.42), "Mode %d direct fire during turning also uses current reduced accuracy" % mode)
		_step(0.5)
		check(combat.shot_count == shots_before + 2 and combat.ammo.magazine_rounds == rounds_before - 2, "Mode %d finishing the turn never emits a delayed extra shot" % mode)
		Input.action_release("fire")
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	combat.ammo.magazine_rounds -= 1
	check(combat.request_reload(), "Fixture starts the original magazine reload")
	var progress: float = combat.ammo.reload_progress
	_motion(Vector2.RIGHT * 40)
	_step()
	check(combat.locked_target == targets[1] and combat.ammo.is_reloading and combat.ammo.reload_progress == progress, "Switching while aiming preserves the existing reload")

func _turning() -> void:
	await _setup([Vector3(1, 0, -5), Vector3(4, 0, -5)])
	check(absf(angle_difference(player.visual.rotation.y, atan2(-1.0, 5.0))) < 0.0001, "Original first acquisition still faces its target immediately")
	for fps in [30, 60, 120]:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
		combat.target_switch_turn_speed_degrees = 90
		_motion(Vector2.RIGHT * 40)
		var bounded := true
		for frame in int(fps * 0.2):
			var before: float = player.visual.rotation.y
			_step(1.0 / fps)
			bounded = bounded and absf(angle_difference(before, player.visual.rotation.y)) <= deg_to_rad(90.0 / fps) + 0.00001
		check(bounded and is_equal_approx(absf(player.visual.rotation.y), deg_to_rad(18)), "Manual turn respects angular speed and reaches eighteen degrees in 0.2 seconds at %d Hz" % fps)
		var before_pause: float = player.visual.rotation.y
		paused = true
		_step(1)
		paused = false
		check(is_equal_approx(player.visual.rotation.y, before_pause), "Pause freezes the pending manual turn at %d Hz" % fps)
		_step(0.3)
		check(absf(angle_difference(player.visual.rotation.y, atan2(-4.0, 5.0))) < 0.0001, "Manual turn reaches the target without overshoot at %d Hz" % fps)
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5), Vector3(8, 0, -5)])
	combat.target_switch_turn_speed_degrees = 90
	_motion(Vector2.RIGHT * 40)
	_step(0.05)
	var before_second: float = player.visual.rotation.y
	_motion(Vector2.RIGHT * 40)
	_step(0.05)
	check(combat.locked_target == targets[2] and absf(angle_difference(before_second, player.visual.rotation.y)) <= deg_to_rad(4.5) + 0.00001 and is_equal_approx(absf(player.visual.rotation.y), deg_to_rad(9)), "A second switch during turning redirects smoothly from the current facing")
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	combat.target_switch_turn_speed_degrees = 90
	_motion(Vector2.RIGHT * 40)
	_step(0.1)
	var before_move: float = player.visual.rotation.y
	targets[1].position.x = -4
	await physics_frame
	_step(0.05)
	check(combat.locked_target == targets[1] and player.visual.rotation.y > before_move and absf(angle_difference(before_move, player.visual.rotation.y)) <= deg_to_rad(4.5) + 0.00001, "Turning follows the target's latest position instead of a frozen switch-time heading")
	check(combat.accuracy < 0.8 and combat.last_target_position == targets[1].position, "Target movement during the turn still incurs the original tracking penalty")
	for mode in [WeaponData.FireMode.SEMI_AUTO, WeaponData.FireMode.AUTOMATIC]:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
		combat.weapon.fire_mode = mode
		combat.target_switch_turn_speed_degrees = 90
		combat.accuracy = 1
		var count: int = combat.shot_count
		var rounds: int = combat.ammo.magazine_rounds
		_motion(Vector2.RIGHT * 40)
		Input.action_press("fire")
		var event := InputEventAction.new()
		event.action = "fire"
		event.pressed = true
		root.push_input(event, true)
		_step(0.1)
		check(combat.shot_count == count + 1 and combat.ammo.magazine_rounds == rounds - 1, "Mode %d shoots immediately while still turning" % mode)
		if mode == WeaponData.FireMode.AUTOMATIC:
			_step(0.1)
			check(combat.shot_count == count + 1, "Automatic fire retains the existing cooldown during turning")
			_step(0.1)
			check(combat.shot_count == count + 2 and absf(angle_difference(player.visual.rotation.y, atan2(-4.0, 5.0))) > 0.01, "Held automatic fire continues at the original interval before finishing the turn")
			_step(0.2)
			check(combat.shot_count == count + 3, "Completing the turn preserves automatic firing cadence")
		else:
			Input.action_release("aim")
			_step()
			Input.action_press("aim")
			_step(1)
			check(combat.shot_count == count + 1 and not combat.shot_requested, "Canceling and reacquiring aim never repeats the already-fired single click")
		Input.action_release("fire")

func _tracking_fixture(mode: int) -> void:
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)], mode)
	var gun: WeaponData = combat.weapon
	gun.target_move_accuracy_loss_per_meter_slow = 0.1
	gun.target_move_accuracy_loss_per_meter_fast = 0.1
	gun.target_move_minimum_accuracy = 0.4
	gun.target_move_spread_degrees_per_meter_slow = 2
	gun.target_move_spread_degrees_per_meter_fast = 2
	gun.target_move_max_spread_angle_degrees = 12
	gun.tracking_parallel_tolerance_degrees = 0
	if mode == 2:
		gun.shotgun.tracking_loss_per_meter = Vector2(0.1, 0.1)
		gun.shotgun.tracking_stability_floor = 0.4
	combat.target_switch_turn_speed_degrees = 90
	_motion(Vector2.RIGHT * 40)
	_step() # Acquire B without rotating or inventing displacement between A and B.

func _turn_accuracy() -> void:
	for mode in 3:
		await _tracking_fixture(mode)
		combat.accuracy_recovery_timer = 0
		var expected := 0.8 - deg_to_rad(9) * sqrt(41.0) * 0.1
		_step(0.1)
		check(is_equal_approx(combat.accuracy, expected), "Mode %d turns nine degrees using original per-meter tracking loss without simultaneous recovery" % mode)
		var after: float = combat.accuracy
		check(not combat._apply_target_movement_accuracy_penalty(0.1) and combat.accuracy == after, "Mode %d consumes each turn's tracking distance once" % mode)
		for movement in [0.2, 2.0]:
			await _tracking_fixture(mode)
			targets[1].position.z += movement
			await physics_frame
			var arc_distance: float = deg_to_rad(9) * Vector2(4, -5 + movement).length()
			# With tolerance zero, projecting (0, dz) across midpoint (4, -5+dz/2) gives this length.
			var lateral_distance: float = movement * 4.0 / Vector2(4, -5 + movement * 0.5).length()
			expected = 0.8 - maxf(arc_distance, lateral_distance) * 0.1
			_step(0.1)
			check(is_equal_approx(combat.accuracy, expected), "Mode %d combines turn and target displacement by maximum, not addition (movement %s)" % [mode, movement])
		await _tracking_fixture(mode)
		combat.accuracy = 0.45
		combat.target_switch_turn_speed_degrees = 360
		_step(0.1)
		check(is_equal_approx(combat.accuracy, 0.4), "Mode %d turning respects the existing tracking accuracy floor" % mode)
		await _tracking_fixture(mode)
		combat.accuracy = 0.2
		combat.accuracy_recovery_timer = 0
		_step(0.1)
		check(combat.accuracy > 0.2 and combat.accuracy < 0.4, "Mode %d damage below the floor recovers gradually without being raised directly to the floor" % mode)
		await _tracking_fixture(mode)
		Input.action_press("fire")
		var fire := InputEventAction.new()
		fire.action = "fire"
		fire.pressed = true
		root.push_input(fire, true)
		_step(0.1)
		check(fired_stabilities.size() == 1 and is_equal_approx(fired_stabilities[0], 0.8 - deg_to_rad(9) * sqrt(41.0) * 0.1), "Mode %d immediate shot reads accuracy after this frame's turn penalty" % mode)
		Input.action_release("fire")
		await _tracking_fixture(mode)
		paused = true
		_step(1)
		paused = false
		check(combat.accuracy == 0.8, "Mode %d pause neither rotates nor charges turn accuracy" % mode)
		_step(0.1)
		check(is_equal_approx(combat.accuracy, 0.8 - deg_to_rad(9) * sqrt(41.0) * 0.1), "Mode %d resume charges only the new frame's angle" % mode)

func _gesture_clock() -> void:
	# Value-only recognizer tests use injected arrival times, separate from scene input above.
	var gesture_script = load("res://scripts/player/target_switch_gesture.gd")
	for fps in [30, 60, 120]:
		var gesture = gesture_script.new()
		var requests := 0
		for frame in fps:
			gesture.feed_motion(Vector2.RIGHT * (120.0 / fps), 1000000 + int(frame * 1000000.0 / fps))
			if gesture.take_motion().length() >= 32:
				requests += 1
				gesture.consume()
		check(requests == 3, "Continuous 120-pixel motion yields three 32-pixel requests at %d Hz" % fps)
		gesture.feed_motion(Vector2.RIGHT * 8, 2000000)
		check(gesture.take_motion() == Vector2.RIGHT * 32, "The next eight pixels finish the fourth request at %d Hz" % fps)
		gesture.consume()
		gesture.feed_motion(Vector2.LEFT * 32, 2001000)
		check(gesture.take_motion() == Vector2.LEFT * 32, "A full reverse movement is available without stopping at %d Hz" % fps)
	var gesture = gesture_script.new()
	gesture.feed_motion(Vector2.RIGHT * 20, 0)
	gesture.feed_motion(Vector2.RIGHT * 0.1, 100000)
	gesture.feed_motion(Vector2.RIGHT * 20, 130000)
	check(gesture.take_motion() == Vector2.RIGHT * 20, "Subpixel noise does not prevent a small gesture from expiring")
	gesture.feed_motion(Vector2.LEFT * 40, 140000)
	check(gesture.take_motion() == Vector2.LEFT * 20, "Net displacement rather than traveled length controls the threshold")
	gesture.feed_motion(Vector2.LEFT * 20, 150000)
	check(gesture.take_motion() == Vector2.LEFT * 40, "Reversal can eventually produce a deliberate opposite request")
	gesture.reset()
	gesture.feed_motion(Vector2.RIGHT * 40, 200000)
	gesture.reset()
	check(gesture.take_motion().is_zero_approx(), "Reset clears motion pending delivery")
	gesture.feed_motion(Vector2.RIGHT * 400, 300000)
	gesture.feed_motion(Vector2.RIGHT * 100, 301000)
	check(gesture.take_motion() == Vector2.RIGHT * 500 and gesture.take_motion().is_zero_approx(), "Accumulated input is delivered only once without new motion")
	gesture.consume()
	gesture.feed_motion(Vector2.RIGHT * 31, 302000)
	check(gesture.take_motion() == Vector2.RIGHT * 31, "Consumption discards overflow instead of carrying it to the next distance")
	gesture.feed_motion(Vector2.RIGHT, 303000)
	check(gesture.take_motion() == Vector2.RIGHT * 32, "Fresh threshold motion after consumption needs no rearming pause")

func _headshot_ui() -> void:
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	combat.weapon.headshot_enabled = true
	combat.weapon.headshot_accuracy_threshold = 0.9
	# UI isolation only; the three-mode turn-accuracy section tests the real losses above.
	combat.weapon.target_move_spread_degrees_per_meter_slow = 0
	combat.weapon.target_move_spread_degrees_per_meter_fast = 0
	# Snapshot contract only: enemy melee lifetime is covered by its existing joint test.
	targets[0].opening_snapshot = {"opening_available": true, "threshold_multiplier": 0.8}
	var reticle = combat.get_node("HUD/Reticle")
	reticle._process(0)
	var boosted: float = combat.get_target_headshot_chance(targets[0])
	check(boosted > 0 and reticle._draw_aim and not reticle._draw_switch_target and reticle._headshot_ready and is_equal_approx(reticle._headshot_probability, boosted), "Real reticle reads the aligned target opening snapshot")
	_motion(Vector2.RIGHT * 40)
	_step(0.02)
	reticle._process(0)
	check(combat.locked_target == targets[1] and combat.is_turning_to_target() and reticle._draw_switch_target and not reticle._draw_aim and not reticle._headshot_ready and reticle._headshot_probability == 0, "Turning shows its distinct target marker instead of ordinary aim and the previous diamond")
	await _capture_view("turning")
	_step(0.2)
	reticle._process(0)
	check(not combat.is_turning_to_target() and reticle._draw_aim and not reticle._draw_switch_target and not reticle._headshot_ready, "Alignment restores ordinary aim using the new target's own headshot eligibility")
	await _capture_view("aligned")
	await _rest()
	_motion(Vector2.LEFT * 40)
	_step()
	reticle._process(0)
	check(combat.is_turning_to_target() and reticle._draw_switch_target and not reticle._draw_aim and not reticle._headshot_ready, "Even a target with an opening has no aim circle or diamond before alignment")
	_step(0.2)
	reticle._process(0)
	check(combat.locked_target == targets[0] and is_equal_approx(reticle._headshot_probability, boosted) and targets[0].opening_snapshot.opening_available, "Switching back restores the target-specific diamond without consuming its opening")
	_motion(Vector2.RIGHT * 40)
	_step()
	Input.action_release("aim")
	_step()
	reticle._process(0)
	check(not reticle._draw_switch_target and not reticle._draw_aim, "Canceling aim clears both ordinary and turning target markers")

func _capture_view(label: String) -> void:
	if not capture_ui: return
	DirAccess.make_dir_recursive_absolute(CAPTURE_DIRECTORY)
	await RenderingServer.frame_post_draw
	var path := CAPTURE_DIRECTORY.path_join(label + ".png")
	var result := root.get_texture().get_image().save_png(path)
	check(result == OK, "Saved actual rendered viewport: " + path)

func _ui_focus() -> void:
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	var button := Button.new()
	button.text = "Input-blocking UI fixture"
	button.position = Vector2(20, 20)
	root.add_child(button)
	button.grab_focus()
	_motion(Vector2.RIGHT * 40)
	_step()
	check(combat.locked_target == targets[0] and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "Focused UI blocks mouse gestures and releases combat capture")
	button.queue_free()
	for frame in 2: await process_frame
	_step()
	for frame in 2: await process_frame
	_motion(Vector2.RIGHT * 40)
	_step()
	check(combat.locked_target == targets[1], "Closing focused UI allows a fresh gesture")

func _lifecycle() -> void:
	for interruption in ["aim", "aim_event_pair", "pause", "dialogue", "weapon", "target", "focus", "melee"]:
		await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
		_motion(Vector2.RIGHT * 40)
		match interruption:
			"aim":
				Input.action_release("aim")
				_step()
				Input.action_press("aim")
			"pause":
				paused = true
				paused = false
			"aim_event_pair":
				for pressed in [false, true]:
					var event := InputEventAction.new()
					event.action = "aim"
					event.pressed = pressed
					Input.parse_input_event(event)
					Input.flush_buffered_events()
			"dialogue":
				player.set_dialogue_active(true)
				player.set_dialogue_active(false)
			"weapon": combat.equip_weapon(combat.weapon.duplicate(true))
			"target":
				targets[0].remove_from_group("combat_target")
				_step()
				targets[0].add_to_group("combat_target")
			"focus":
				root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
				root.propagate_notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
			"melee":
				combat.request_melee()
				combat.cancel_melee()
		player.visual.rotation = Vector3.ZERO
		_step()
		check(combat.locked_target == targets[0], "Interrupted queued gesture cannot leak after " + interruption)
		await process_frame
		await _rest()
		_motion(Vector2.RIGHT * 40)
		_step()
		check(combat.locked_target == targets[1], "Fresh deliberate input works after " + interruption)
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	check(combat._owns_switch_mouse_capture, "Fixture owns temporary capture before leaving the scene")
	var mouse_was_captured: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var previous_mode: int = combat._previous_mouse_mode
	world.remove_child(player)
	check(not combat._owns_switch_mouse_capture and (not mouse_was_captured or Input.mouse_mode == previous_mode), "Removing the player releases capture ownership and restores the supported backend mode")
	world.add_child(player)
	player.set_physics_process(false)
	await _setup([Vector3(0, 0, -5), Vector3(4, 0, -5)])
	_motion(Vector2.RIGHT * 40)
	player.health.debug_invincible = false
	player.receive_hit(player.health.health + 1)
	check(player.is_dead() and combat.locked_target == null, "Death clears the lock with a mouse request pending")
	check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "Death UI releases temporary mouse capture")
