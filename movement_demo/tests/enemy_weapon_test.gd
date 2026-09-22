extends SceneTree

var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	enemy.get_node("AI").set_physics_process(false)
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	_check("敌人提供装备武器接口", enemy.has_method("equip_weapon"))
	if not checks.values().all(func(value): return value):
		_finish()
		return
	# 场景检查资源接线和按当前配置初始化；具体数值行为由下面独立武器验证。
	_check("场景挂载独立敌人武器并读取当前初始概率", enemy.weapon is WeaponData and enemy.weapon == load("res://enemy_test_pistol.tres") and is_equal_approx(enemy.get_center_probability(), enemy.weapon.initial_accuracy))
	var weapon := WeaponData.new()
	weapon.initial_accuracy = 0.9
	weapon.stabilize_seconds = 1.0
	weapon.accuracy_recovery_delay = 0.5
	weapon.shot_accuracy_penalty = 0.15
	weapon.minimum_accuracy = 0.6
	weapon.player_move_accuracy_loss_per_meter = 0.2
	weapon.moving_accuracy_cap = 0.4
	weapon.target_move_accuracy_loss_per_meter_slow = 0.05
	weapon.target_move_accuracy_loss_per_meter_fast = 0.05
	weapon.target_move_minimum_accuracy = 0.7
	weapon.shot_interval = 0.7
	enemy.equip_weapon(weapon)
	_check("装备读取初始中心概率", is_equal_approx(enemy.get_center_probability(), 0.9))
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	player.get_node("Health").debug_invincible = true
	for frame in range(5):
		await physics_frame
	var target: Vector3 = player.global_position + Vector3.UP * 0.8
	enemy.update_weapon(0.0, target)
	_check("首枪降低概率并读取武器冷却", enemy.try_fire() and is_equal_approx(enemy.get_center_probability(), 0.75) and is_equal_approx(enemy.shot_cooldown, 0.7))
	enemy.shot_cooldown = 0.0
	enemy.try_fire()
	_check("连射到武器惩罚上限", is_equal_approx(enemy.get_center_probability(), 0.6))
	enemy.update_weapon(0.0)
	enemy.update_weapon(0.0, target)
	_check("失去目标重瞄不刷新精度", is_equal_approx(enemy.get_center_probability(), 0.6))
	enemy.update_weapon(0.4, target)
	_check("恢复延迟内不提高概率", is_equal_approx(enemy.get_center_probability(), 0.6))
	enemy.update_weapon(0.3, target)
	_check("跨越恢复延迟只计算剩余时间", is_equal_approx(enemy.get_center_probability(), 0.62))
	enemy.update_weapon(0.1, target + Vector3.RIGHT)
	_check("跟枪不惩罚更低概率，但允许逐渐恢复", is_equal_approx(enemy.get_center_probability(), 0.63))
	enemy.equip_weapon(weapon)
	enemy.update_weapon(0.0, target)
	enemy.update_weapon(0.1, target + Vector3.RIGHT)
	_check("可见目标位移按武器参数累积", is_equal_approx(enemy.get_center_probability(), 0.85))
	enemy.update_weapon(0.0)
	enemy.update_weapon(0.0, target + Vector3.RIGHT * 10.0)
	_check("丢失视野不计算隐藏期间位移", is_equal_approx(enemy.get_center_probability(), 0.85))
	enemy.equip_weapon(weapon)
	var travelled := 0.0
	for frame in range(12):
		await physics_frame
		var before: Vector3 = enemy.global_position
		enemy.move_character(Vector3.RIGHT, 1.0 / 60.0)
		var after: Vector3 = enemy.global_position
		travelled += Vector2(after.x - before.x, after.z - before.z).length()
		enemy.update_weapon(1.0 / 60.0, target)
	_check("移动按实际距离逐渐降低概率", travelled > 0.1 and is_equal_approx(enemy.get_center_probability(), 0.9 - travelled * 0.2))
	_check("运行状态不修改共享资源", weapon.initial_accuracy == 0.9 and weapon.shot_accuracy_penalty == 0.15)
	var other_arena = load("res://arena.tscn").instantiate()
	root.add_child(other_arena)
	var other = other_arena.get_node("Enemy")
	other.get_node("AI").set_physics_process(false)
	other.equip_weapon(weapon)
	_check("两个敌人共享配置但稳定度各自独立", other.weapon == enemy.weapon and is_equal_approx(other.get_center_probability(), 0.9) and enemy.get_center_probability() < 0.9)
	other_arena.free()
	enemy.weapon_stability = 0.2
	enemy.shot_cooldown = 0.0
	enemy.look_at(player.global_position)
	enemy.aim_direction = (target - enemy.get_shot_origin()).normalized()
	enemy.aim_acquired = true
	enemy.try_fire()
	_check("连射不抬高其他原因造成的更低概率", is_equal_approx(enemy.get_center_probability(), 0.2))
	enemy.shot_cooldown = 0.6
	enemy.equip_weapon(weapon.duplicate())
	_check("换枪不绕过尚未结束的冷却", is_equal_approx(enemy.shot_cooldown, 0.6))
	enemy.reset_target()
	_check("刷新恢复武器初始精度并清理冷却", is_equal_approx(enemy.get_center_probability(), 0.9) and enemy.shot_cooldown == 0.0)
	enemy.equip_weapon(null)
	enemy.update_weapon(1.0, target)
	_check("卸下武器不射击", not enemy.try_fire() and not enemy.has_aim)
	enemy.get_node("AI").tactics.update_shooting(1.0, true, false)
	_check("AI允许无武器存在", enemy.weapon == null and enemy.shot_count == 0)

	# 换另一把枪后，实际射线与伤害均读取新资源，而非仅修改显示值。
	var replacement := WeaponData.new()
	replacement.initial_accuracy = 1.0
	replacement.shot_accuracy_penalty = 0.0
	replacement.damage = 7.0
	replacement.fire_range = 1.0
	enemy.equip_weapon(replacement)
	enemy.look_at(player.global_position)
	enemy.update_weapon(1.0, target)
	_check("换枪后的短射程射线不能命中远处玩家", enemy.try_fire() and enemy.last_shot_collider != player)
	replacement.fire_range = 30.0
	var health = player.get_node("Health")
	health.debug_invincible = false
	var hp: float = health.health
	enemy.update_weapon(1.0, target)
	_check("换枪后的实际伤害来自新资源", enemy.try_fire() and enemy.last_shot_collider == player and is_equal_approx(health.health, hp - 7.0))
	_finish()

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)

func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("ENEMY WEAPON: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
