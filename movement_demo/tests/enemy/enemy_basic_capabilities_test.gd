extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var unit = enemy.get_node("UnitType")
	var training = enemy.get_node("Training")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	Fixture.configure_timing(enemy)
	enemy.debug_shooting = false
	ai.cover_selection.debug_cover_selection = false
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	for frame in range(5):
		await physics_frame
	var target: Vector3 = player.global_position + Vector3.UP * 0.8
	_check("测试站位有真实视线", ai.perception.can_see_player())

	unit.profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	enemy.update_weapon(1.0, target)
	_check("近战即使装备枪也不能直接瞄准", not enemy.has_aim)
	var shots: int = enemy.shot_count
	_check("近战直接请求开火被拒绝", not enemy.try_fire() and enemy.shot_count == shots)
	# 模拟其他调用者遗留的瞄准标志，执行接口自身仍须检查兵种。
	enemy.has_aim = true
	enemy.aim_acquired = true
	enemy.aim_direction = (target - enemy.get_shot_origin()).normalized()
	enemy.shot_cooldown = 0.0
	_check("伪造瞄准不能绕过近战限制", not enemy.can_fire() and not enemy.try_fire())
	_check("被拒绝的开火不产生射击计数和冷却", enemy.shot_count == shots and enemy.shot_cooldown == 0.0)
	enemy.update_weapon(0.0, target)
	_check("近战武器更新清理残留瞄准", not enemy.has_aim and not enemy.aim_acquired)

	var start: Vector3 = enemy.global_position
	for frame in range(12):
		await physics_frame
		enemy.move_character(Vector3.RIGHT, 1.0 / 60.0)
	_check("近战仍可直接执行移动", enemy.global_position.x > start.x + 0.1)
	var rotation_before: float = enemy.rotation.y
	enemy.face_direction(Vector3.RIGHT, 0.05)
	_check("近战仍可直接执行转身", not is_equal_approx(enemy.rotation.y, rotation_before))
	enemy.look_at(player.global_position)

	unit.profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	enemy.update_weapon(1.0, target)
	_check("远程直接瞄准并实际开火", enemy.has_aim and enemy.try_fire())
	_check("远程实际射线仍命中玩家", enemy.last_shot_collider == player)
	enemy.update_weapon(1.0, target)
	unit.profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	_check("远程切近战后未更新瞄准也立即拒绝开火", not enemy.try_fire())
	enemy.shot_cooldown = 0.5
	enemy.update_weapon(0.2, target)
	_check("禁用枪械仍推进旧冷却并清理瞄准", is_equal_approx(enemy.shot_cooldown, 0.3) and not enemy.has_aim)

	# 训练只解锁战术，不能授予近战枪械资格。
	training.profile.selected_tactics.assign([&"suppression"])
	ai.refresh_configuration(true)
	ai.context.fire.update(2.0, true, false, {"owner": &"engage"})
	_check("训练开放接敌仍不能让近战AI瞄准", not enemy.has_aim)
	_check("训练开放压制仍不能让近战装配枪械动作", not ai.actions.has(&"suppression"))
	unit.profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	ai.refresh_configuration(true)
	_check("远程资格允许装配已有压制动作", ai.actions.has(&"suppression"))
	ai.context.fire.request = {"owner": &"suppression", "mode": &"memory", "point": target}
	unit.profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	shots = enemy.shot_count
	ai.refresh_configuration(true)
	ai.context.fire.update_shooting(1.0, false, false)
	_check("切近战撤销枪械动作并清理瞄准，没有多开一枪", not ai.actions.has(&"suppression") and not enemy.has_aim and enemy.shot_count == shots)
	unit.profile = load("res://resources/enemy/units/ranged.tres").duplicate(true)
	training.profile.selected_tactics.clear()
	unit.profile.default_behaviors.clear()
	ai.refresh_configuration(true)
	enemy.update_weapon(1.0, target)
	_check("基础开火不要求登记或授权战术动作", enemy.try_fire())
	shots = enemy.shot_count
	ai.context.fire.update(2.0, true, false, {"owner": &"engage"})
	_check("动作清单关闭仍阻止AI自行开火", enemy.shot_count == shots and not enemy.has_aim)

	# 基础执行不依赖AI或Training；保留UnitType作为兵种资格来源。
	ai.free()
	training.free()
	enemy.update_weapon(1.0, target)
	_check("无AI和Training的远程身体仍能执行开火", enemy.try_fire())
	enemy.shooting_enabled = false
	enemy.update_weapon(1.0, target)
	_check("禁射开关阻止瞄准与开火", not enemy.has_aim and not enemy.try_fire())
	enemy.shooting_enabled = true
	var weapon: WeaponData = enemy.weapon
	enemy.equip_weapon(null)
	enemy.update_weapon(1.0, target)
	_check("有远程资格但无枪仍不能开火", not enemy.has_aim and not enemy.try_fire())
	enemy.equip_weapon(weapon)
	enemy.update_weapon(1.0, target)
	enemy.receive_hit(enemy.health)
	_check("死亡立即拒绝基础开火", not enemy.try_fire())
	enemy.reset_target()
	enemy.look_at(player.global_position)
	enemy.update_weapon(1.0, target)
	_check("刷新后仍按远程兵种执行", enemy.try_fire())
	enemy.update_weapon(1.0, target)
	enemy.remove_child(unit)
	_check("缺少兵种配置时拒绝直接开火", not enemy.try_fire())
	enemy.update_weapon(0.0, target)
	_check("缺少兵种配置时清理瞄准", not enemy.has_aim)
	rotation_before = enemy.rotation.y
	enemy.face_direction(Vector3.RIGHT, 0.05)
	_check("缺少兵种不影响基础转身", not is_equal_approx(enemy.rotation.y, rotation_before))
	unit.free()
	_finish()


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("BASIC CAPABILITIES: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
