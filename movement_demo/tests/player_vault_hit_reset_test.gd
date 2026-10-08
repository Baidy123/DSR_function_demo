extends SceneTree

const STEP := 1.0 / 60.0
const INTENT := {"owner": &"melee_engage"}
const Training = preload("res://scripts/enemy/config/enemy_training_profile.gd")
var checks := 0
var failures := 0
var scene: Node3D
var player
var enemy
var ai
var arena
var zone: Area3D
var region_resets := 0
var enemy_resets := 0
var actual_hits := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	await _hit_during_vault(false, false)
	await _hit_during_vault(false, true)
	await _hit_during_vault(true, false)
	await _real_exit_still_resets()
	print("PLAYER VAULT HIT RESET: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _hit_during_vault(descending: bool, invincible: bool) -> void:
	await _build_fixture(Vector3(-1.0, 0.0, -1.8 if descending else 0.0))
	var label := "descent" if descending else ("ascent invincible" if invincible else "ascent")
	player.health.debug_invincible = invincible
	var scene_id := scene.get_instance_id()
	var hp: float = player.health.health
	_check(label + ": real combat zone, navigation and enemy melee permission are ready", ai.context.environment_ready() and zone.overlaps_body(player) and arena.players_inside.has(player) and ai.context.can_use_action(&"melee_engage"))
	_check(label + ": real wall starts a collision-checked vault", player.request_vault(Vector3.FORWARD))
	if descending:
		# Begin the ordinary windup only once the descending target is within
		# the weapon's unchanged one-metre vertical reach, on the far side.
		for frame in 48:
			await _step()
			if player.is_vaulting() and player.get_vault_progress() > 0.7 and player.global_position.y < 0.95:
				break
	var direction: Vector3 = player.global_position - enemy.global_position
	direction.y = 0.0
	enemy.global_rotation.y = atan2(-direction.x, -direction.z)
	ai.utility_current = {"id": &"melee_engage", "plan": &"melee"}
	var controller = ai.context.melee
	var visible: bool = ai.perception.can_see_player()
	_check(label + ": attacker actually sees and can reach the vaulting player", visible and controller.can_request(visible))
	controller.update(0.0, visible, INTENT)
	_check(label + ": authorized controller begins a real windup without early damage", enemy.melee_active and actual_hits == 0 and is_equal_approx(player.health.health, hp))
	var incoming_y := 0.0
	var impact_height := 0.0
	var hit_frame := -1
	for frame in 24:
		await _step()
		incoming_y = player.velocity.y
		controller.update(STEP, ai.perception.can_see_player(), INTENT)
		if actual_hits > 0:
			hit_frame = frame
			impact_height = player.global_position.y
			break
	_check(label + ": original melee execution actually hits during the requested vault phase", actual_hits == 1 and player.is_vaulting() and (incoming_y < -0.1 if descending else incoming_y > 0.1))
	_check(label + ": damage and invincibility keep their original rules", is_equal_approx(player.health.health, hp if invincible else hp - enemy.weapon.melee_damage) and not player.is_dead())
	_check(label + ": interrupted vault keeps attacks occupied", player.is_vaulting() and not player.combat.request_melee() and not player.combat.request_reload())
	controller.cancel()
	var maximum_height := impact_height
	var horizontal_origin: Vector3 = player.global_position
	for frame in 180:
		await _step()
		maximum_height = maxf(maximum_height, player.global_position.y)
		if not player.is_vaulting() and player.is_on_floor(): break
	# Allow the physics server to publish pending Area exit/enter events too.
	await _step(3)
	_check(label + ": interruption does not turn scripted ascent into a launch", maximum_height <= impact_height + 0.02)
	_check(label + ": real horizontal knockback remains active", player.global_position.x > horizontal_origin.x + 0.2)
	_check(label + ": safely lands without bypassing wall or keeping vault occupied", not player.is_vaulting() and player.is_on_floor() and player.global_position.y < 0.02)
	_check(label + ": no false arena exit or enemy reset occurs", region_resets == 0 and enemy_resets == 0 and zone.overlaps_body(player) and arena.players_inside.has(player))
	_check(label + ": scene identity and living player are preserved", is_instance_valid(scene) and scene.get_instance_id() == scene_id and current_scene == scene and not player.is_dead())
	print("VAULT HIT case=", label, " hit_frame=", hit_frame, " incoming_y=", incoming_y, " impact_y=", impact_height, " maximum_y=", maximum_height, " hp=", player.health.health, " region_resets=", region_resets, " enemy_resets=", enemy_resets, " same_scene=", scene.get_instance_id() == scene_id)
	await _dispose_fixture()

func _real_exit_still_resets() -> void:
	await _build_fixture(Vector3(-1.0, 0.0, 0.0))
	var scene_id := scene.get_instance_id()
	player.global_position = Vector3(4.7, 0.0, 0.0)
	await _step(3)
	_check("ordinary edge still belongs to the arena while the capsule overlaps", zone.overlaps_body(player) and region_resets == 0)
	Input.action_press("move_right")
	for frame in 50:
		await _step()
		if region_resets > 0: break
	Input.action_release("move_right")
	await _step(3)
	_check("real horizontal departure still resets this arena and enemy exactly once", region_resets == 1 and enemy_resets == 1 and not zone.overlaps_body(player) and arena.players_inside.is_empty())
	_check("ordinary arena reset still preserves the current scene", current_scene == scene and scene.get_instance_id() == scene_id)
	await _dispose_fixture()

func _step(count: int = 1) -> void:
	for frame in count:
		await physics_frame
		player._physics_process(STEP)
		enemy._physics_process(STEP)

func _build_fixture(enemy_position: Vector3) -> void:
	region_resets = 0
	enemy_resets = 0
	actual_hits = 0
	scene = Node3D.new()
	scene.name = "VaultHitResetFixture"
	# Reuse real actor subtrees, but no user arena layout or saved tuning.
	var donor = load("res://scenes/main.tscn").instantiate()
	player = donor.get_node("Player")
	donor.remove_child(player)
	donor.free()
	player.position = Vector3.ZERO
	player.vault_duration = 0.8
	player.crouch_height = 1.0
	player.get_node("Health").max_health = 100.0
	scene.add_child(player)
	arena = Node3D.new()
	arena.name = "Arena"
	arena.set_script(preload("res://scripts/world/shooting_range.gd"))
	scene.add_child(arena)
	var region := NavigationRegion3D.new()
	region.name = "NavigationRegion3D"
	region.navigation_mesh = _navigation_mesh()
	arena.add_child(region)
	var environment := Node3D.new()
	environment.name = "Environment"
	region.add_child(environment)
	environment.add_child(_box(Vector3(16.0, 0.5, 16.0), Vector3(0.0, -0.25, 0.0)))
	var wall = load("res://scenes/world/low_cover.tscn").instantiate()
	wall.transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.55, -1.0))
	wall.low_cover = true
	wall.vault_enabled = true
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.0, 1.1, 0.6)
	wall.get_node("CollisionShape3D").shape = shape
	wall.get_node("CollisionShape3D").transform = Transform3D.IDENTITY
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	wall.get_node("Mesh").mesh = mesh
	wall.get_node("Mesh").transform = Transform3D.IDENTITY
	environment.add_child(wall)
	zone = Area3D.new()
	zone.name = "CombatZone"
	zone.collision_layer = 0
	zone.add_to_group("combat_zone")
	var zone_shape := CollisionShape3D.new()
	zone_shape.name = "CollisionShape3D"
	var bounds := BoxShape3D.new()
	# Match the real arena's vertical extent: floor -0.5, ceiling 2.5.
	bounds.size = Vector3(10.0, 3.0, 10.0)
	zone_shape.shape = bounds
	zone_shape.position.y = 1.0
	zone.add_child(zone_shape)
	arena.add_child(zone)
	enemy = load("res://scenes/enemy/enemy.tscn").instantiate()
	enemy.position = enemy_position
	enemy.get_node("NavigationAgent3D").path_height_offset = 0.0
	enemy.get_node("UnitType").profile = preload("res://resources/enemy/units/melee.tres").duplicate(true)
	enemy.get_node("Training").profile = Training.new()
	var weapon := WeaponData.new()
	weapon.fire_mode = WeaponData.FireMode.MELEE
	weapon.melee_damage = 5.0
	enemy.weapon = weapon
	arena.add_child(enemy)
	root.add_child(scene)
	current_scene = scene
	ai = enemy.get_node("AI")
	ai.set_physics_process(false)
	enemy.set_physics_process(false)
	player.set_physics_process(false)
	player.health.debug_invincible = false
	await _step(8)
	arena.presentation_reset.connect(func(_region): region_resets += 1)
	enemy.reset_completed.connect(func(): enemy_resets += 1)
	enemy.melee_struck.connect(func(target, _settings, _direction):
		if target == player: actual_hits += 1)

func _dispose_fixture() -> void:
	player.health.debug_invincible = false
	scene.queue_free()
	await process_frame
	await process_frame

func _navigation_mesh() -> NavigationMesh:
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	var xs := [-7.0, -2.0, 2.0, 7.0]
	var zs := [-7.0, -1.8, -0.2, 7.0]
	var vertices := PackedVector3Array()
	for z in zs:
		for x in xs: vertices.append(Vector3(x, 0.0, z))
	mesh.vertices = vertices
	for z in 3:
		for x in 3:
			if x == 1 and z == 1: continue
			var index: int = z * 4 + x
			mesh.add_polygon(PackedInt32Array([index, index + 1, index + 5, index + 4]))
	return mesh

func _box(size: Vector3, position: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = position
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body

func _check(message: String, condition: bool) -> void:
	checks += 1
	if not condition: failures += 1
	print("PASS " if condition else "FAIL ", message)
