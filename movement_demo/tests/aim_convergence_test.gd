extends SceneTree

const Ballistics = preload("res://scripts/weapons/shotgun_ballistics.gd")
var checks := 0
var failed := 0
var world: Node3D
var player
var combat
var gun: WeaponData

class RayProbe extends Node:
	var directions: Array[Vector3] = []
	func capture_hit(_hit: Dictionary, direction: Vector3, _source: Node):
		directions.append(direction)
		return null
	func dispatch_impact(_event) -> void: pass

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	_models()
	await _player()
	_separate_aim_parameters()
	world.queue_free()
	await process_frame
	print("AIM CONVERGENCE: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)

func _models() -> void:
	var data := WeaponData.new()
	data.convergence_seconds = 2.0
	var half_time := [0.5, 0.75, 0.8175744762]
	for model in 3:
		data.convergence_model = model
		check(data.recover_player_accuracy(0, 0) == 0 and data.recover_player_accuracy(0, 2) == 1 and data.recover_player_accuracy(1, 0.1) == 1, "Model %d has exact finite endpoints" % model)
		check(absf(data.recover_player_accuracy(0, 1) - half_time[model]) < 0.000001, "Model %d matches independent half-time reference" % model)
		var previous := 0.0
		var monotonic := true
		for step in 201:
			var value := data.recover_player_accuracy(0, step * 0.01)
			monotonic = monotonic and is_finite(value) and value >= previous and value <= 1
			previous = value
		check(monotonic, "Model %d is bounded and monotonic" % model)
		var whole := data.recover_player_accuracy(0.21, 0.73)
		for frames in [30, 60, 144]:
			var split := 0.21
			for frame in frames: split = data.recover_player_accuracy(split, 0.73 / frames)
			check(absf(split - whole) < 0.000001, "Model %d recovery is independent of %d frame partitions" % [model, frames])
		var old_settings := data.get_aim_settings(true)
		data.convergence_seconds = 7
		check(data.get_aim_settings(true) == old_settings, "Model %d leaves shared enemy settings unchanged" % model)
		data.convergence_seconds = 2
	data.convergence_model = WeaponData.ConvergenceModel.QUADRATIC
	check(is_equal_approx(data.recover_player_accuracy(0.75, 0.5), 0.9375) and data.recover_player_accuracy(0.75, 1) == 1, "Arbitrary damage/recoil state resumes phase instead of restarting a full two seconds")
	data.convergence_seconds = 1.6
	check(data.recover_player_accuracy(0, 0.6) > 0.60 and data.recover_player_accuracy(0, 1) < 1, "Longer quadratic template reaches usable spread early but delays perfect aim")
	data.convergence_model = WeaponData.ConvergenceModel.EXPONENTIAL
	data.convergence_seconds = 2
	for k in [0.0, 0.00000001, 3.0, 10.0, NAN, INF, -1.0]:
		data.convergence_exponent_k = k
		check(is_finite(data.recover_player_accuracy(0.1, 0.5)) and data.recover_player_accuracy(0, 2) == 1, "Exponent boundary remains finite: " + str(k))
	data.convergence_model = WeaponData.ConvergenceModel.LINEAR
	data.convergence_seconds = 2
	for mode in [false, true]:
		var enemy_settings := data.get_aim_settings(mode)
		data.spread_recovery_degrees_per_second = 90
		data.stabilize_seconds = 0.1
		check(is_equal_approx(data.recover_player_accuracy(0.2, 0.3), 0.35), "Enemy recovery parameters do not control player convergence: " + str(mode))
		data.convergence_model = WeaponData.ConvergenceModel.EXPONENTIAL
		data.convergence_seconds = 8
		var changed_settings := data.get_aim_settings(mode)
		data.convergence_model = WeaponData.ConvergenceModel.LINEAR
		data.convergence_seconds = 2
		check(data.get_aim_settings(mode) == changed_settings and enemy_settings.initial == changed_settings.initial, "Player formula/time leave enemy recovery data unchanged: " + str(mode))
	data.fire_mode = WeaponData.FireMode.SHOTGUN
	data.shotgun.settle_seconds = 0.1
	check(is_equal_approx(data.recover_player_accuracy(0.2, 0.3), 0.35), "Shotgun player recovery ignores enemy settle time")
	check(data.recover_player_accuracy(NAN, 0) == 0 and data.recover_player_accuracy(0.2, NAN) == 0.2, "Non-finite state and delta cannot propagate")
	data.convergence_model = 99
	for invalid_time in [0.0, -5.0, NAN, INF]:
		data.convergence_seconds = invalid_time
		check(data.convergence_seconds == 4 and is_equal_approx(data.recover_player_accuracy(0.2, 0.4), 0.3), "Invalid duration / old zero marker uses four seconds without legacy fallback: " + str(invalid_time))
	data.convergence_model = WeaponData.ConvergenceModel.EXPONENTIAL
	data.convergence_seconds = 2.7
	data.convergence_exponent_k = 4.1
	var path := "user://aim-convergence-test.tres"
	var saved := ResourceSaver.save(data, path)
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as WeaponData
	check(saved == OK and restored.convergence_model == 2 and restored.convergence_seconds == 2.7 and restored.convergence_exponent_k == 4.1, "Formula, duration and exponent survive resource save/reload")
	check(restored.get_aim_settings(false) == data.get_aim_settings(false) and restored.stabilize_seconds == 0.1 and restored.spread_recovery_degrees_per_second == 90, "Enemy saved values and recovery survive resource round-trip")
	DirAccess.remove_absolute(path)

func _player() -> void:
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	var zone := Area3D.new()
	zone.collision_layer = 0
	zone.add_to_group("combat_zone")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(100, 10, 100)
	zone.add_child(shape)
	world.add_child(zone)
	player = load("res://scenes/player/player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	combat = player.get_node("Combat")
	gun = WeaponData.new()
	gun.shot_noise = null
	gun.convergence_model = WeaponData.ConvergenceModel.QUADRATIC
	gun.convergence_seconds = 2
	gun.min_spread_angle_degrees = 1
	gun.max_spread_angle_degrees = 4
	gun.initial_spread_angle_degrees = 2.5
	gun.magazine_capacity = 300
	combat.equip_weapon(gun)
	for frame in 4: await physics_frame
	check(combat.can_combat(), "Fixture uses real player and physical combat zone")
	for mode in [WeaponData.FireMode.SEMI_AUTO, WeaponData.FireMode.SHOTGUN]:
		gun.fire_mode = mode
		combat.equip_weapon(gun)
		combat.is_aiming = true
		combat.accuracy = 0
		combat.accuracy_recovery_timer = 0.2
		combat.end_frame(0.7, false)
		check(is_equal_approx(combat.accuracy, 0.4375) and combat.accuracy_recovery_timer == 0, "Mode %d advances selected formula only after delay" % mode)
		combat.accuracy = 0
		combat.is_aiming = false
		combat.end_frame(20, false)
		check(is_equal_approx(combat.accuracy, combat.get_weapon_aim_settings(gun).initial), "Mode %d keeps the non-aiming recovery cap" % mode)
		combat.is_aiming = true
		combat.accuracy = 0
		combat.player_position_before_move = player.global_position
		combat.end_frame(20, true)
		check(is_equal_approx(combat.accuracy, combat.get_weapon_aim_settings(gun).moving_cap), "Mode %d keeps the movement recovery cap" % mode)
	gun.fire_mode = WeaponData.FireMode.SEMI_AUTO
	combat.equip_weapon(gun)
	combat.is_aiming = true
	combat.accuracy = 0.75
	combat.accuracy_recovery_timer = 0
	player.crouch_amount = 1
	var crouched_before: float = combat.get_spread_half_angle_degrees()
	combat.end_frame(0.5, false)
	check(is_equal_approx(crouched_before, 1.5) and is_equal_approx(combat.accuracy, 0.9375), "Crouch maps endpoints without changing quadratic progress")
	combat.accuracy = 0
	check(is_equal_approx(combat.get_spread_half_angle_degrees(), 3), "Maximum 4 degrees becomes 3 with n=0.25")
	combat.accuracy = 1
	check(is_equal_approx(combat.get_spread_half_angle_degrees(), 1), "Minimum 1 degree stays 1 when crouched")
	combat.accuracy = 0.5
	for pose in 20: player.crouch_amount = pose % 2
	check(combat.accuracy == 0.5 and is_equal_approx(combat.get_spread_half_angle_degrees(), 2), "Repeated stance changes do not accumulate or write state")
	player.crouch_amount = 0
	check(is_equal_approx(combat.get_spread_half_angle_degrees(), 2.5), "Standing restores original endpoints at the same phase")
	player.crouch_amount = 1
	combat.crouch_spread_reduction = 0.99
	check(combat.get_spread_half_angle_degrees() == 1 and gun.get_headshot_chance(combat.get_effective_accuracy()) == 0, "Clamped crouch maximum cannot grant headshot eligibility")
	gun.max_spread_angle_degrees = 1
	check(combat.get_spread_half_angle_degrees() == 1 and is_finite(combat.get_spread_stability()), "Zero-width spread remains finite")
	gun.max_spread_angle_degrees = 4
	combat.crouch_spread_reduction = 0.25
	var before: float = combat.accuracy
	paused = true
	combat.end_frame(5, false)
	paused = false
	check(combat.accuracy == before, "Pause freezes nonlinear recovery")
	combat.ammo = combat.Ammo.new(gun, {gun.get_ammo_key(): 300})
	combat.ammo.magazine_rounds = 1
	check(combat.request_reload(), "Nonlinear weapon starts original reload")
	combat.end_frame(gun.reload_seconds + 1, false)
	check(not combat.ammo.is_reloading and combat.accuracy == 0 and combat.get_spread_stability() == 0, "Reload completion frame cannot advance curve or enable crouch reduction")
	combat.end_frame(0.1, false)
	check(combat.accuracy == 0 and combat.get_spread_stability() == 0, "Post-reload delay still blocks recovery and stance benefit")
	combat.end_frame(gun.spread_recovery_delay - 0.1 + 0.5, false)
	check(is_equal_approx(combat.accuracy, 0.4375) and combat.get_spread_stability() > combat.accuracy, "After reload wait, quadratic recovery resumes and stance benefit returns")
	# Save the original fields only; no second convergence clock is needed per slot.
	var slots = player.get_node("Equipment")
	slots.primary_weapon = gun
	slots.secondary_weapon = gun.duplicate()
	slots.select_slot(1)
	slots.select_slot(0)
	combat.accuracy = 0.25
	combat.accuracy_recovery_timer = 0.3
	slots.select_slot(1)
	slots.select_slot(0)
	check(combat.accuracy == 0.25 and combat.accuracy_recovery_timer == 0.3, "Switching slots preserves nonlinear state and delay without posture bonus")
	await _ballistics()

func _ballistics() -> void:
	var probe := RayProbe.new()
	probe.name = "ImpactEffects"
	player.add_child(probe)
	var bounded := true
	var max_angle := 0.0
	for shot in 64:
		combat.is_aiming = true
		combat.accuracy = 0
		combat.shot_cooldown = 0
		combat.shoot()
		if probe.directions.is_empty():
			bounded = false
			continue
		var angle := rad_to_deg(probe.directions.back().angle_to(-player.visual.global_basis.z))
		bounded = bounded and angle <= 3.0001
		max_angle = maxf(max_angle, angle)
	check(probe.directions.size() == 64 and bounded and max_angle > 2.5, "Real cone rays use reduced maximum, with no premature perfect aim")
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2(1, 0), Vector2(-1, 0), Vector2.ZERO])
	gun.shotgun.pattern_angle_degrees = 2
	gun.shotgun.stable_jitter_degrees = 1
	gun.shotgun.unstable_jitter_degrees = 4
	combat.equip_weapon(gun)
	for spread_mode in 2:
		gun.shotgun.spread_mode = spread_mode
		# Independent expected config: shrink only the unstable endpoint, never the pattern.
		var expected := gun.shotgun.duplicate()
		expected.unstable_jitter_degrees = 3
		var rng := RandomNumberGenerator.new()
		rng.seed = 527
		var offsets := Ballistics.sample_offsets(expected, 0.5, rng)
		probe.directions.clear()
		combat.is_aiming = true
		combat.accuracy = 0.5
		combat.shot_cooldown = 0
		combat._shotgun_rng.seed = 527
		combat.shoot()
		var directions := Ballistics.directions(-player.visual.global_basis.z, offsets)
		var same := directions.size() == probe.directions.size()
		for i in mini(directions.size(), probe.directions.size()): same = same and directions[i].is_equal_approx(probe.directions[i])
		check(same and combat._shotgun_rng.state == rng.state, "Shotgun mode %d actual rays shrink only random jitter, retaining fixed points and RNG sequence" % spread_mode)


func _separate_aim_parameters() -> void:
	var template := load("res://resources/weapons/test_pistol.tres") as WeaponData
	if not "mouse_aim_accuracy" in template or template.get("mouse_aim_accuracy") == null:
		check(false, "Player weapon saves a separate mouse aim profile")
		return
	for name in ["pistol", "rifle", "smg", "shotgun"]:
		var stock = load("res://resources/weapons/test_%s.tres" % name)
		check(stock.mouse_aim_accuracy != null, "Built-in %s saves a mouse aim profile" % name)
	gun = WeaponData.new()
	var configured: Variant = gun
	check(gun.get_aim_settings(true) == configured.get_aim_settings(true, true), "Old weapons retain saved accuracy when a profile is absent")
	var profile = template.get("mouse_aim_accuracy").get_script().new()
	configured.mouse_aim_accuracy = profile
	profile.convergence_model = WeaponData.ConvergenceModel.QUADRATIC
	profile.convergence_seconds = 1.0
	profile.min_spread_angle_degrees = 1.0
	profile.max_spread_angle_degrees = 5.0
	profile.initial_spread_angle_degrees = 2.0
	profile.spread_recovery_delay = 0.25
	profile.shot_spread_penalty_degrees = 0.6
	profile.starting_stability = 0.85
	profile.stable_jitter_degrees = 0.2
	profile.unstable_jitter_degrees = 2.0
	profile.shell_stability_loss = 0.3
	profile.stability_recovery_delay = 0.7
	profile.headshot_accuracy_threshold = 0.5
	combat.aim_control = combat.AimControl.MOUSE
	player.crouch_amount = 0.0
	combat.equip_weapon(gun)
	check(is_equal_approx(combat.accuracy, 0.75) and is_equal_approx(combat.get_spread_half_angle_degrees(), 2.0),
		"Mouse aim equips with its own initial spread and bounds")
	combat.begin_frame(0.0, true)
	combat.accuracy = 0.0
	combat.accuracy_recovery_timer = 0.25
	combat.end_frame(0.75, false)
	check(is_equal_approx(combat.accuracy, 0.75), "Mouse aim recovers with its own curve and duration")
	combat.aim_control = combat.AimControl.AUTO_LOCK
	combat.begin_frame(0.0, true)
	combat.end_frame(0.5, false)
	check(is_equal_approx(combat.accuracy, 0.875) and gun.get_aim_settings(true).shot_penalty == 0.25,
		"Mode switch preserves progress and uses the original tracking settings")
	check(configured.get_aim_settings(false, true) == gun.get_aim_settings(false) and gun.get_aim_settings(false).initial == 0.5,
		"Enemy probability settings ignore the player mouse profile")
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	check(is_equal_approx(configured.get_aim_settings(true, true).initial, 0.85) and gun.get_aim_settings(true).initial == 0.65
		and configured.get_spread_bounds(true).is_equal_approx(Vector2(0.2, 2.0)),
		"Shotgun uses mouse stability and jitter while keeping its tracking and enemy settings")
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2.ZERO])
	var camera := Camera3D.new()
	camera.position = player.global_position + Vector3.UP * 20.0
	camera.rotation_degrees.x = -90.0
	world.add_child(camera)
	camera.make_current()
	combat.aim_control = combat.AimControl.MOUSE
	combat.equip_weapon(gun)
	var motion := InputEventMouseMotion.new()
	motion.position = camera.unproject_position(player.global_position + Vector3.FORWARD * 6.0)
	root.push_input(motion, true)
	combat.begin_frame(0.0, true)
	combat.accuracy = 0.75
	check(is_equal_approx(combat.get_target_headshot_chance(player), 0.5), "Mouse reticle uses its own headshot threshold")
	var probe := player.get_node("ImpactEffects") as RayProbe
	probe.directions.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 81
	combat._shotgun_rng.seed = 81
	var expected := Ballistics.directions(Vector3.FORWARD, Ballistics.sample_offsets(gun.shotgun, 0.75, rng, 0.65))
	combat.shoot()
	check(probe.directions.size() == 1 and probe.directions[0].is_equal_approx(expected[0])
		and is_equal_approx(combat.accuracy, 0.45) and is_equal_approx(combat.accuracy_recovery_timer, 0.7),
		"Real mouse shot uses its own shotgun jitter, recoil and recovery wait")
	gun.hit_accuracy_loss = 0.2
	combat.hit_accuracy_loss_multiplier = 1.5
	combat.mouse_hit_accuracy_loss_multiplier = 0.5
	combat.accuracy = 0.9
	combat.apply_weapon_hit(gun.get_attack_effects())
	var mouse_after_hit: float = combat.accuracy
	combat.aim_control = combat.AimControl.AUTO_LOCK
	combat.accuracy = 0.9
	combat.apply_weapon_hit(gun.get_attack_effects())
	check(is_equal_approx(mouse_after_hit, 0.8) and is_equal_approx(combat.accuracy, 0.6),
		"Both modes apply the same incoming hit using their own received accuracy multiplier")
