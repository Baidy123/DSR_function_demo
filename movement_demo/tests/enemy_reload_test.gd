extends SceneTree

const Fixture = preload("res://tests/enemy_fire_fixture.gd")
var checks := 0
var failed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var unit = enemy.get_node("UnitType")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(enemy)
	ai.search.debug_tracking_cheat = false
	ai.cover_selection.debug_cover_selection = false
	enemy.debug_shooting = false
	player.get_node("Health").debug_invincible = true
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	check(enemy.has_method("request_reload"), "敌人提供基础换弹请求")
	if failed > 0:
		finish()
		return
	var weapon: WeaponData = enemy.weapon.duplicate()
	weapon.magazine_capacity = 2
	weapon.reload_seconds = 2.0
	weapon.shot_interval = 0.1
	weapon.shot_noise = null
	enemy.equip_weapon(weapon)
	for frame in range(5):
		await physics_frame
	var target: Vector3 = player.global_position + Vector3.UP * 0.8
	enemy.update_weapon(1.0, target)
	check(enemy.try_fire() and enemy.ammo.magazine_rounds == 1, "敌人实际射击扣弹")
	enemy.update_weapon(1.0, target)
	check(enemy.try_fire() and enemy.ammo.magazine_rounds == 0, "敌人弹匣可以打空")
	enemy.update_weapon(1.0, target)
	check(not enemy.try_fire() and not enemy.ammo.is_reloading, "基础射击不自行决定换弹")
	check(enemy.request_reload(), "远程身体接受换弹请求")
	var count: int = enemy.shot_count
	enemy.update_weapon(0.5, target)
	check(not enemy.try_fire() and enemy.shot_count == count, "敌人换弹期间不射击")
	check(is_equal_approx(enemy.ammo.reload_progress, 0.25), "敌人固定速度推进换弹")
	var position_before: Vector3 = enemy.global_position
	enemy.move_character(Vector3.RIGHT, 1.0 / 60.0, 2.0)
	enemy.face_direction(Vector3.RIGHT, 0.01)
	enemy.update_weapon(0.5, target)
	check(enemy.global_position.x > position_before.x and is_equal_approx(enemy.ammo.reload_progress, 0.5), "敌人可移动转向且换弹进度不减速")
	enemy.receive_hit(1.0)
	check(enemy.ammo.is_reloading and is_equal_approx(enemy.ammo.reload_progress, 0.5), "敌人普通受击不取消基础换弹")
	enemy.update_weapon(1.0, target)
	check(enemy.ammo.magazine_rounds == 2 and not enemy.ammo.is_reloading, "无限备弹完成补满")
	enemy.ammo.magazine_rounds = 0
	enemy.request_reload()
	unit.combat_type = unit.CombatType.MELEE
	check(not enemy.request_reload() and not enemy.try_fire(), "近战禁止请求换弹与开火")
	enemy.update_weapon(2.0, target)
	check(not enemy.ammo.is_reloading and enemy.ammo.magazine_rounds == 0, "中途切近战取消进度且不补弹")
	unit.combat_type = unit.CombatType.RANGED
	enemy.request_reload()
	enemy.receive_hit(enemy.health)
	check(not enemy.ammo.is_reloading and not enemy.request_reload(), "死亡取消并拒绝换弹")
	enemy.reset_target()
	check(enemy.ammo.magazine_rounds == 2 and not enemy.ammo.is_reloading, "刷新恢复满弹匣及干净进度")
	enemy.ammo.magazine_rounds = 0
	enemy.request_reload()
	enemy.equip_weapon(null)
	check(not enemy.ammo.is_reloading and not enemy.request_reload(), "卸下武器取消换弹")

	# 真实AI由空弹匣触发，不通过测试直接请求。
	enemy.equip_weapon(weapon)
	enemy.look_at(player.global_position)
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	for frame in range(5):
		await physics_frame
	enemy.ammo.magazine_rounds = 0
	ai._physics_process(0.1)
	check(enemy.ammo.is_reloading and enemy.ammo.reload_progress > 0.0, "激活AI发现空匣自动开始并推进换弹")
	ai._update_label()
	check(enemy.get_node("Label").text.contains("换弹中"), "敌人状态文字显示换弹")
	player.is_in_dialogue = true
	ai._physics_process(0.1)
	check(not enemy.ammo.is_reloading and enemy.ammo.magazine_rounds == 0, "对话期间AI取消且不自动重启换弹")
	player.is_in_dialogue = false
	ai._physics_process(0.1)
	check(enemy.ammo.is_reloading, "对话结束空匣恢复换弹请求")
	player.global_position = Vector3(0, 0, 100)
	for frame in range(5):
		await physics_frame
	ai._physics_process(0.1)
	check(not ai.is_arena_active() and not enemy.ammo.is_reloading and enemy.ammo.magazine_rounds == 2, "离场刷新满弹并保持未激活")
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	enemy.look_at(player.global_position)
	weapon.reload_seconds = 0.4
	ai.tactics.fire_reaction_seconds = 0.0
	ai.tactics.burst_pause_seconds = 0.0
	for frame in range(5):
		await physics_frame
	var saw_reload := false
	count = enemy.shot_count
	for frame in range(180):
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		saw_reload = saw_reload or enemy.ammo.is_reloading
	check(saw_reload and enemy.shot_count >= count + 4, "真实AI持续交战完成打空换弹再开火循环")
	finish()


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)


func finish() -> void:
	print("ENEMY RELOAD: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
