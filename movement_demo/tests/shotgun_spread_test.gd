extends SceneTree

const Ballistics = preload("res://scripts/weapons/shotgun_ballistics.gd")
var checks := 0
var failed := 0

# Observe real ray queries through the existing effects boundary; do not replace shooting.
class RayProbe extends Node:
	var directions := PackedVector3Array()
	func capture_hit(_hit: Dictionary, direction: Vector3, _source: Node):
		directions.append(direction)
		return null
	func dispatch_impact(_event) -> void: pass


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_geometry()
	await _actors()
	print("SHOTGUN SPREAD: %d/%d passed" % [checks - failed, checks])
	quit(1 if failed else 0)


func _geometry() -> void:
	var settings := ShotgunSettings.new()
	settings.pattern = ShotgunPattern.new()
	settings.pattern.points = PackedVector2Array([Vector2.ZERO, Vector2(1, 0), Vector2(-0.5, 0), Vector2(0, 1), Vector2(0, -0.2), Vector2(0.3, 0.8)])
	var original := settings.pattern.points.duplicate()
	check(settings.spread_mode == ShotgunSettings.SpreadMode.RANDOM, "Absent mode defaults to legacy sampling")
	var compatible := true
	var bounded := true
	var outward := true
	var monotonic := true
	var lateral := Vector2.ZERO
	var center_quadrants := {}
	var smallest := INF
	for seed_value in [7, 104729, 4251]:
		for stability in [0.0, 0.5, 1.0]:
			var rng := RandomNumberGenerator.new()
			var reference := RandomNumberGenerator.new()
			rng.seed = seed_value
			reference.seed = seed_value
			settings.spread_mode = ShotgunSettings.SpreadMode.RANDOM
			for shot in 64:
				compatible = compatible and Ballistics.sample_offsets(settings, stability, rng) == _legacy_offsets(settings, stability, reference) and rng.state == reference.state
			settings.spread_mode = ShotgunSettings.SpreadMode.NO_INWARD
			rng.seed = seed_value
			for shot in 1000:
				var state := rng.state
				var offsets := Ballistics.sample_offsets(settings, stability, rng)
				reference.state = state
				var stable := Ballistics.sample_offsets(settings, 1, reference)
				compatible = compatible and rng.state == reference.state
				for i in offsets.size():
					var base := original[i] * settings.pattern_angle_degrees
					var delta := offsets[i] - base
					bounded = bounded and offsets[i].is_finite() and delta.length() <= settings.get_jitter_degrees(stability) + 0.00001
					outward = outward and base.dot(delta) >= -0.00001 and offsets[i].length() + 0.00001 >= base.length()
					monotonic = monotonic and offsets[i].length() + 0.00001 >= stable[i].length() and delta.length() + 0.00001 >= (stable[i] - base).length()
					if i == 1:
						lateral.x += 1 if delta.y < -0.001 else 0
						lateral.y += 1 if delta.y > 0.001 else 0
						smallest = minf(smallest, delta.length() / settings.get_jitter_degrees(stability))
					if i == 0: center_quadrants[Vector2(signf(delta.x), signf(delta.y))] = true
	check(compatible, "Legacy seeds reproduce the original algorithm and both modes consume two draws per pellet")
	check(bounded and outward, "Across seeds, axes, asymmetric points and stability levels, no inward component or unbounded displacement")
	check(monotonic, "Using the same random sequence, lower stability cannot shorten displacement or radius")
	check(lateral.x > 100 and lateral.y > 100, "Both lateral directions remain available instead of radial-only expansion")
	check(center_quadrants.size() == 4 and smallest < 0.02, "Center retains all quadrants and non-center pellets permit arbitrarily small offsets")
	check(settings.pattern.points == original, "Sampling does not mutate shared points")
	settings.stable_jitter_degrees = 0
	var exact := Ballistics.sample_offsets(settings, 1, RandomNumberGenerator.new())
	var base_points := PackedVector2Array()
	for point in original: base_points.append(point * settings.pattern_angle_degrees)
	check(exact == base_points, "Zero stable jitter reproduces every base point exactly")
	for pair in [Vector2.ZERO, Vector2(0.4, 0.4), Vector2(0.8, 0.2)]:
		settings.stable_jitter_degrees = pair.x
		settings.unstable_jitter_degrees = pair.y
		check(is_equal_approx(settings.get_jitter_degrees(0), maxf(pair.x, pair.y)) and is_equal_approx(settings.get_jitter_degrees(1), pair.x), "Existing equal and inverted jitter limits remain valid: " + str(pair))
	settings.unstable_jitter_degrees = 5
	settings.pattern_angle_degrees = 0
	_check_center_fallback(settings, "Zero calibration")
	settings.pattern_angle_degrees = 3
	settings.pattern = null
	_check_center_fallback(settings, "Missing pattern")
	settings.pattern = ShotgunPattern.new()
	settings.pattern.points.clear()
	_check_center_fallback(settings, "Empty pattern")
	settings.pattern.points.resize(100)
	var centers := Ballistics.sample_offsets(settings, 0, RandomNumberGenerator.new())
	check(centers.size() == 64 and centers[0] != centers[1], "64-pellet cap retains independent center samples")
	DirAccess.make_dir_recursive_absolute("res://logs/shotgun_spread")
	var path := "res://logs/shotgun_spread/settings.tres"
	check(ResourceSaver.save(settings, path) == OK, "New mode saves through the original settings resource")
	var restored := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as ShotgunSettings
	check(restored != null and restored.spread_mode == ShotgunSettings.SpreadMode.NO_INWARD and restored.unstable_jitter_degrees == 5, "Reload preserves mode and original tuning")
	check(load("res://resources/weapons/test_shotgun.tres").shotgun.spread_mode == ShotgunSettings.SpreadMode.RANDOM, "Existing weapon without a serialized mode retains legacy behavior")


func _check_center_fallback(settings: ShotgunSettings, label: String) -> void:
	var rng := RandomNumberGenerator.new()
	var reference := RandomNumberGenerator.new()
	rng.seed = 81
	reference.seed = 81
	check(Ballistics.sample_offsets(settings, 0, rng) == _legacy_offsets(settings, 0, reference), label + " uses full-circle sampling without normalizing zero")


# Frozen pre-change implementation: protects exact legacy output, including RNG order.
func _legacy_offsets(settings: ShotgunSettings, stability: float, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result := PackedVector2Array()
	var jitter := settings.get_jitter_degrees(stability)
	for point in settings.get_pattern_points():
		var angle := rng.randf_range(0.0, TAU)
		var radius := sqrt(rng.randf()) * jitter
		result.append(point * clampf(settings.pattern_angle_degrees, 0.0, 15.0) + Vector2(cos(angle), sin(angle)) * radius)
	return result


func _actors() -> void:
	var scene = load("res://scenes/presentation/shotgun_range.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	var combat = player.get_node("Combat")
	var gun := WeaponData.new()
	gun.fire_mode = WeaponData.FireMode.SHOTGUN
	gun.headshot_enabled = false
	gun.shot_noise = null
	gun.magazine_capacity = 12
	gun.aim_range = 18
	gun.shotgun.pattern = ShotgunPattern.new()
	gun.shotgun.pattern.points = PackedVector2Array([Vector2(1, 0), Vector2(0, -1), Vector2.ZERO])
	gun.shotgun.spread_mode = ShotgunSettings.SpreadMode.NO_INWARD
	gun.shotgun.unstable_jitter_degrees = 3
	combat.equip_weapon(gun, false, combat.Ammo.new(gun, {}))
	var player_probe := RayProbe.new()
	player_probe.name = "ImpactEffects"
	player.add_child(player_probe)
	var enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.weapon = gun
	enemy.get_node("AI").process_mode = Node.PROCESS_MODE_DISABLED
	scene.add_child(enemy)
	enemy.set_physics_process(false)
	# Keep the enemy outside the player's test rays; incoming damage can cancel its aim.
	enemy.global_position = Vector3(2, 0, -3)
	enemy.equip_weapon(gun)
	enemy.shooting_enabled = true
	enemy.look_at(player.global_position)
	enemy.aim_direction = (player.get_torso_position() - enemy.get_shot_origin()).normalized()
	enemy.aim_acquired = true
	enemy.has_aim = true
	var enemy_probe := RayProbe.new()
	enemy_probe.name = "ImpactEffects"
	enemy.add_child(enemy_probe)
	for frame in 80: await physics_frame
	for stability in [0.2, 0.65, 1.0]:
		var rng := RandomNumberGenerator.new()
		rng.seed = 729
		var offsets := Ballistics.sample_offsets(gun.shotgun, stability, rng)
		combat.is_aiming = true
		combat.accuracy = stability
		combat.clear_target_lock()
		combat.shot_cooldown = 0
		combat._shotgun_rng.seed = 729
		player_probe.directions.clear()
		var rounds: int = combat.ammo.magazine_rounds
		combat.shoot()
		check(player_probe.directions == Ballistics.directions(-player.visual.global_basis.z, offsets) and combat._shotgun_rng.state == rng.state, "Player real ray queries consume new mode at stability " + str(stability))
		check(combat.ammo.magazine_rounds == rounds - 1 and combat.shot_cooldown == gun.shot_interval and combat.accuracy < stability, "Player retains one ammo, cooldown and stability penalty per shell")
		enemy.weapon_stability = stability
		enemy.shot_cooldown = 0
		enemy._shot_rng.seed = 729
		enemy_probe.directions.clear()
		rounds = enemy.ammo.magazine_rounds
		var success: bool = enemy.try_fire()
		check(success and enemy_probe.directions == Ballistics.directions(enemy.aim_direction, offsets) and enemy._shot_rng.state == rng.state, "Enemy real ray queries consume new mode at stability " + str(stability))
		check(enemy.ammo.magazine_rounds == rounds - 1 and enemy.shot_cooldown == gun.shot_interval and enemy.weapon_stability < stability, "Enemy retains one ammo, cooldown and stability penalty per shell")
	scene.queue_free()
	await process_frame


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failed += 1
	print("PASS " if ok else "FAIL ", label)
