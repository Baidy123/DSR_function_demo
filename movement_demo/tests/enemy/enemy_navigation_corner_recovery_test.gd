extends SceneTree

const STEP := 1.0 / 60.0
const START := Vector3(-4.2376337, 0.0001646, 4.6681504)
const TARGET := Vector3(-4.5738211, 0.0009404, 0.86796665)
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(20261009)
	await _case(false)
	await _case(true)
	print("NAVIGATION CORNER RECOVERY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _case(cooperation: bool) -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena = scene.get_node("Arena")
	for child in arena.get_children():
		if child != arena.get_node("Enemy") and child.has_method("move_character"): child.free()
	var navigation: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	for body in navigation.get_node("Environment").get_children():
		if body is StaticBody3D and body.name != "Floor":
			body.collision_layer = 0
			body.remove_from_group("cover_region")
	# The captured live CoverA has an offset child collision. Recreate its actual
	# box and the sloped west navigation edge in memory, independently of saved
	# scene edits or the user's navigation bake. Never save either test resource.
	var corner := StaticBody3D.new()
	corner.name = "CapturedCoverACorner"
	corner.position = Vector3(-3.6225033, 1.1, 0.87327695)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.2, 6.890625)
	collision.shape = box
	corner.add_child(collision)
	navigation.add_child(corner)
	var mesh := NavigationMesh.new()
	mesh.vertices = PackedVector3Array([Vector3(-8, 0.3, -4), Vector3(-4.75, 0.3, -3), Vector3(-4.5, 0.3, 5), Vector3(-8, 0.3, 5)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	navigation.navigation_mesh = mesh
	var enemy = arena.get_node("Enemy")
	# Validate a legal spawn first; the captured body reached START through a
	# preceding slide and remained within the agent's existing 0.4m tolerance.
	enemy.position = Vector3(-5.3, 0, 4.7)
	root.add_child(scene)
	current_scene = scene
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = false
	player.global_position = arena.to_global(TARGET)
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = ai.training.profile.duplicate(true)
	ai.training.profile.selected_tactics.clear()
	if cooperation: ai.training.profile.selected_tactics.append(&"cooperate")
	var weapon = load("res://resources/weapons/enemy_test_melee.tres").duplicate(true)
	weapon.melee_range = 1.6
	enemy.equip_weapon(weapon)
	ai.refresh_configuration(true)
	ai.set_physics_process(false)
	for frame in 12: await physics_frame
	check(ai.is_arena_active(), "单近战先合法出生，战斗区与导航已就绪")
	enemy.global_position = arena.to_global(START)
	enemy.look_at(player.global_position)
	await physics_frame
	var initial_distance: float = Vector2(START.x - TARGET.x, START.z - TARGET.z).length()
	check(initial_distance > 3.8 and enemy.weapon.melee_range == 1.6 and not ai.context.melee.can_request(true), "准确现场初始距离3.815米，超过原1.6米近战范围")
	var initial_health: float = player.health.health
	var saw_wall := false
	var saw_return := false
	var saw_melee := false
	var safe := true
	var original_mask: int = enemy.collision_mask
	var original_layer: int = enemy.collision_layer
	var maximum_stall := 0.0
	var stall := 0.0
	for frame in 360:
		await physics_frame
		var before: Vector3 = enemy.global_position
		ai._physics_process(STEP)
		var moved: Vector3 = enemy.global_position - before
		var horizontal := Vector2(moved.x, moved.z).length()
		stall = stall + STEP if horizontal < 0.005 else 0.0
		maximum_stall = maxf(maximum_stall, stall)
		saw_melee = saw_melee or ai.utility_current.get("id") == &"melee_engage"
		for index in enemy.get_slide_collision_count():
			saw_wall = saw_wall or enemy.get_slide_collision(index).get_collider() == corner
		var recovery: Vector3 = enemy.local_motion.get("_navigation_return") if enemy.local_motion.get("_navigation_return") != null else Vector3.INF
		if recovery.is_finite():
			saw_return = true
			var projected: Vector3 = NavigationServer3D.region_get_closest_point(navigation.get_rid(), recovery)
			safe = safe and Vector2(projected.x - recovery.x, projected.z - recovery.z).length() <= 0.05 and before.distance_to(recovery) <= 1.1
		safe = safe and horizontal <= enemy.move_speed * enemy.get_effective_movement_multiplier(1.0) * STEP + 0.005
		safe = safe and enemy.collision_mask == original_mask and enemy.collision_layer == original_layer and not enemy.get_node("CollisionShape3D").disabled
		# Keep the same real wall corner: the body may return west, but cannot
		# enter the box or teleport through it while reaching the player.
		var local: Vector3 = arena.to_local(enemy.global_position)
		if local.z < 4.31858 and local.z > -2.57202: safe = safe and local.x <= -4.571
		if player.health.health < initial_health: break
	check(saw_melee and saw_wall, "普通感知和Utility真实选近战追击并复现掩体边角碰撞")
	check(saw_return and maximum_stall < 1.0, "单人无队友仍在真实受阻后有限退回所属导航走廊")
	check(safe, "恢复沿实际导航与胶囊边界且不增速、不关闭碰撞")
	check(player.health.health < initial_health and enemy.melee_count > 0, "协作%s时自主走出转角并以原范围实际命中玩家" % ("开启" if cooperation else "关闭"))
	print("CORNER SOLO cooperation=", cooperation, " hit=", player.health.health < initial_health, " max_stall=", maximum_stall, " position=", enemy.global_position)
	scene.queue_free()
	await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
