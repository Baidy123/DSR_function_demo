extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const View = preload("res://scripts/systems/combat_view.gd")
const STEP := 0.05
var scene
var actor
var player
var context
var camera: Camera3D
var checks := 0
var failures := 0
var body_events := 0
var fire_events := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _run() -> void:
	scene = Fixture.single_member_scene()
	var arena = scene.get_node("Arena")
	actor = Fixture.primary_enemy(arena)
	actor.position = Vector3(0, 0, 0)
	actor.get_node("UnitType").profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	actor.weapon = WeaponData.new()
	player = scene.get_node("Player")
	var region: NavigationRegion3D = arena.get_node("NavigationRegion3D")
	var mesh := NavigationMesh.new()
	mesh.agent_height = 1.75
	mesh.vertices = PackedVector3Array([Vector3(-10, 0.5, -10), Vector3(10, 0.5, -10), Vector3(10, 0.5, 10), Vector3(-10, 0.5, 10)])
	mesh.add_polygon(PackedInt32Array([0, 1, 2, 3]))
	region.navigation_mesh = mesh
	for body in arena.get_node("NavigationRegion3D/Environment").get_children():
		if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
	root.add_child(scene)
	current_scene = scene
	player.global_position = actor.global_position + Vector3(0, 0, -5)
	root.get_node("DebugSettings").enabled = false
	arena.set_physics_process(false)
	actor.set_physics_process(false)
	actor.get_node("AI").set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Combat").set_physics_process(false)
	player.health.debug_invincible = true
	Fixture.configure_timing(actor)
	var ai = actor.get_node("AI")
	ai.training.profile.set_setting(&"tactics", &"shot_interval_multiplier", 1.5)
	ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.15)
	ai.training.profile.set_setting(&"tactics", &"burst_pause_seconds", 0.6)
	ai.refresh_configuration(true)
	context = ai.context
	actor.weapon.shot_interval = 0.2
	actor.weapon.magazine_capacity = 10000
	actor.weapon.damage = 0.0
	actor.weapon.shot_noise = null
	actor.aim_turn_speed_degrees = 720.0
	actor.look_at(player.global_position)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0
	scene.add_child(camera)
	camera.position = Vector3(100, 20, 105)
	camera.look_at(Vector3(100, 0, 100))
	camera.make_current()
	for frame in 6: await physics_frame
	check(context.is_arena_active() and context.perception.can_see_player() and not View.contains_actor(actor, 8.0), "真实感知看到玩家，射手位于实际活动相机画面外")
	check(actor.offscreen_fire_chance == 50.0, "现有敌人默认屏外开火概率50%")
	actor.shot_fired.connect(func(): body_events += 1)
	context.fire.shot_fired.connect(func(): fire_events += 1)
	for mode in [&"visible", &"memory"]:
		var normal := _sample(mode, 100.0)
		var blocked := _sample(mode, 0.0)
		var half := _sample(mode, 50.0)
		check(normal.attempts > 200 and normal.shots == normal.attempts, "%s 屏外100%%保留正常开火" % mode)
		check(blocked.shots == 0 and blocked.ammo_used == 0 and blocked.body_events == 0 and blocked.fire_events == 0, "%s 屏外0%%不耗弹、不触发实际射击事件" % mode)
		check(normal.attempts == blocked.attempts and normal.attempts == half.attempts, "%s 跳过仍消耗完整射击间隔和点射配额，无逐帧重抽" % mode)
		var ratio: float = float(half.shots) / normal.shots if normal.shots > 0 else 0.0
		check(ratio >= 0.4 and ratio <= 0.6 and half.ammo_used == half.shots and half.body_events == half.shots and half.fire_events == half.shots, "%s 固定输入实际发射约为正常50%%，只有成功才耗弹和通知（%.3f）" % [mode, ratio])
	_reset(0.0)
	actor.update_weapon(2.0, player.get_torso_position())
	var random_state: int = actor._offscreen_fire_rng.state
	for index in 20: actor.can_fire()
	check(actor._offscreen_fire_rng.state == random_state and actor.shot_attempt_count == 0, "纯资格查询不抽样、不消耗开火机会")
	check(not actor.try_fire() and actor.shot_attempt_count == 1 and actor.shot_cooldown > 0.0, "直接身体调用也跳过整枪并开始机械冷却")
	for index in 20: actor.try_fire()
	check(actor.shot_attempt_count == 1, "同一冷却内重复调用不会重新抽取")
	camera.global_position = actor.global_position + Vector3(0, 15, 5)
	camera.look_at(actor.global_position)
	check(View.contains_actor(actor, 8.0) and not actor.try_fire(), "重新入画不会清除失败机会的剩余冷却")
	actor.update_weapon(2.0, player.get_torso_position())
	check(actor.try_fire(), "入画后即使参数0%也正常开枪")
	var on_screen := _sample(&"visible", 0.0)
	check(on_screen.shots > 200 and on_screen.shots == on_screen.attempts, "屏内持续射击不受屏外概率影响")
	camera.position = Vector3(100, 20, 105)
	camera.look_at(Vector3(100, 0, 100))
	await _safety_checks(arena)
	actor.weapon.fire_mode = WeaponData.FireMode.SHOTGUN
	_reset(0.0)
	actor.update_weapon(2.0, player.get_torso_position())
	check(not actor.try_fire() and actor.shot_count == 0 and actor.ammo.magazine_rounds == 10000, "霰弹整枪跳过，不逐颗弹丸抽取或耗弹")
	actor.offscreen_fire_chance = 100.0
	actor.update_weapon(2.0, player.get_torso_position())
	check(actor.try_fire() and actor.shot_count == 1 and actor.ammo.magazine_rounds == 9999, "霰弹100%成功时仍按整枪消耗一发")
	actor.offscreen_fire_chance = 25.0
	var packed := PackedScene.new()
	var saved := "res://logs/offscreen_fire_parameter.tscn"
	var error := packed.pack(actor)
	if error == OK: error = ResourceSaver.save(packed, saved)
	var restored = load(saved).instantiate() if error == OK else null
	check(restored != null and restored.offscreen_fire_chance == 25.0, "敌人场景保存重载保留屏外概率")
	if restored != null: restored.free()
	actor.reset_target()
	check(actor.shot_attempt_count == 0 and actor.shot_count == 0 and actor.shot_cooldown == 0.0, "复位清除尝试计数与原射击状态")
	print("OFFSCREEN FIRE: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _reset(chance: float) -> void:
	actor.offscreen_fire_chance = chance
	actor._offscreen_fire_rng.seed = 426
	actor.shot_cooldown = 0.0
	actor.shot_count = 0
	actor.shot_attempt_count = 0
	actor.ammo.magazine_rounds = 10000
	actor.weapon_stability = 1.0
	actor.weapon_recovery_timer = 0.0
	body_events = 0
	fire_events = 0
	context.fire.reset_fire_timing()

func _sample(mode: StringName, chance: float, frames: int = 4000) -> Dictionary:
	_reset(chance)
	var intent := {"owner": &"engage", "mode": mode, "point": player.get_torso_position(), "bypass_steady": true}
	for frame in frames:
		context.fire.update(STEP, context.perception.can_see_player(), false, intent)
	return {"attempts": actor.shot_attempt_count, "shots": actor.shot_count,
		"ammo_used": 10000 - actor.ammo.magazine_rounds, "body_events": body_events, "fire_events": fire_events}

func _safety_checks(arena: Node) -> void:
	_reset(100.0)
	actor.ammo.magazine_rounds = 0
	actor.update_weapon(2.0, player.get_torso_position())
	check(not actor.try_fire() and actor.shot_attempt_count == 0, "100%也不能绕过空弹匣资格")
	actor.ammo.magazine_rounds = 10000
	actor.shooting_enabled = false
	check(not actor.try_fire() and actor.shot_attempt_count == 0, "100%也不能绕过射击总开关")
	actor.shooting_enabled = true
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = Vector3(4, 3, 0.5)
	wall.add_child(collision)
	arena.add_child(wall)
	wall.global_position = actor.global_position.lerp(player.global_position, 0.5) + Vector3.UP
	await physics_frame
	for mode in [&"visible", &"memory"]:
		var blocked := _sample(mode, 100.0, 40)
		check(blocked.attempts == 0, "%s 屏外100%%仍受真实墙体射线限制" % mode)
	wall.queue_free()
	await physics_frame
