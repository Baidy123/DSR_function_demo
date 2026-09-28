extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:
		failures += 1

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	enemy.get_node("AI").set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	var weapon := WeaponData.new()
	weapon.initial_accuracy = 0.4
	weapon.shot_accuracy_penalty = 0.0
	weapon.accuracy_recovery_delay = 10.0
	# 若错误读取散布锥，100%仍会偏离中心。
	weapon.min_spread_angle_degrees = 5.0
	weapon.max_spread_angle_degrees = 5.0
	enemy.equip_weapon(weapon)
	check(is_equal_approx(enemy.weapon_stability, 0.4), "装备读取初始中心概率")
	for frame in range(4):
		await physics_frame
	var target: Vector3 = player.global_position + Vector3.UP * 0.8
	enemy.update_weapon(0.0, target)
	enemy.weapon_stability = 1.0
	enemy.try_fire()
	check(enemy.last_shot_direction.is_equal_approx(enemy.aim_direction), "100%沿实际枪口中心发射")
	check(enemy.last_shot_collider == player, "无遮挡对准时中心枪实际命中玩家")
	weapon.damage = 0.0
	var missed := true
	var bounded := true
	var vertical := false
	enemy._shot_rng.seed = 511
	for shot in range(100):
		enemy.shot_cooldown = 0.0
		enemy.weapon_stability = 0.0
		enemy.try_fire()
		var angle: float = rad_to_deg(enemy.aim_direction.angle_to(enemy.last_shot_direction))
		missed = missed and not enemy.last_shot_direction.is_equal_approx(enemy.aim_direction)
		bounded = bounded and angle >= 7.99 and angle <= 20.01
		vertical = vertical or absf(enemy.last_shot_direction.y) > 0.02
	check(missed, "0%不抽到中心方向")
	check(bounded and vertical, "偏射沿用8至20度三维范围")
	var central := 0
	for shot in range(1000):
		enemy.shot_cooldown = 0.0
		enemy.weapon_stability = 0.4
		enemy.try_fire()
		central += int(enemy.last_shot_direction.is_equal_approx(enemy.aim_direction))
	check(central >= 350 and central <= 450, "40%中心概率抽样符合配置")
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2, 2, 0.3)
	wall.add_child(shape)
	scene.add_child(wall)
	wall.global_position = (enemy.global_position + player.global_position) * 0.5 + Vector3.UP
	for frame in range(3):
		await physics_frame
	enemy.weapon_stability = 1.0
	enemy.shot_cooldown = 0.0
	enemy.try_fire()
	check(enemy.last_shot_collider == wall, "100%也由首个碰撞物挡住")
	check(enemy.shot_count == 1102, "概率抽样不改变实际开火次数")
	scene.free()
	quit(0 if failures == 0 else 1)
