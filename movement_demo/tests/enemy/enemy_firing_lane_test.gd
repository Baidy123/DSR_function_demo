extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	ai.cover_selection.debug_attack_points = false
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	player.get_node("Health").debug_invincible = true
	enemy.global_position = Vector3(20, 0, -2)
	player.global_position = Vector3(20, 0, 2)
	enemy.face_direction(Vector3.BACK, 10.0)
	ai.training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.0)
	for frame in range(8): await physics_frame
	var origin: Vector3 = enemy.get_shot_origin()
	var fire = ai.context.fire
	check(fire.has_clear_firing_lane(origin, Vector3.BACK, 4.0), "无障碍射界可以开火")
	check(not fire.has_clear_firing_lane(origin, Vector3.ZERO, 4.0), "无效瞄准方向拒绝开火")
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.1, 0.1, 0.1)
	collision.shape = shape
	blocker.add_child(collision)
	scene.add_child(blocker)
	# 中心弹道可通，但枪口散布体积碰到头顶小障碍；旧二维投影无法正确表达。
	blocker.global_position = origin + Vector3(0, 0.14, 0.3)
	for frame in range(3): await physics_frame
	check(ai.cover_selection.has_clear_line(origin, origin + Vector3.BACK * 4.0) and not fire.has_clear_firing_lane(origin, Vector3.BACK, 4.0), "中心射线通畅仍拒绝枪口近处三维障碍")
	var shots: int = enemy.shot_count
	fire.update(1.0, true, false, {"owner": &"engage", "bypass_steady": true})
	check(enemy.shot_count == shots, "真实开火入口遵守枪口空间门槛")
	blocker.global_position = origin + Vector3(0.7, 0, 2)
	for frame in range(3): await physics_frame
	check(fire.has_clear_firing_lane(origin, Vector3.BACK, 4.0), "远处外围散布擦障碍不会被旧全锥规则一票否决")
	check(fire.firing_lane_quality(origin, Vector3.BACK, 4.0) < 1.0, "远处外围遮挡仍降低有效火力评分")
	enemy.aim_turn_speed_degrees = 0.0
	enemy.has_aim = true
	enemy.aim_acquired = true
	enemy.aim_direction = origin.direction_to(blocker.global_position)
	fire.update(0.1, true, false, {"owner": &"engage", "bypass_steady": true})
	check(enemy.shot_count == shots, "目标方向通畅但当前枪口朝障碍时暂缓开火")
	enemy.aim_direction = Vector3.BACK
	fire.update(0.1, true, false, {"owner": &"engage", "bypass_steady": true})
	check(enemy.shot_count == shots + 1 and enemy.last_shot_collider == player, "当前枪口转出障碍后真实射击命中玩家")
	print("FIRING LANE: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
