extends SceneTree

var checks := 0
var failures := 0

class Recorder extends Node:
	var events: Array[Dictionary] = []
	func receive_noise(source: Node3D, position: Vector3, radius: float, multiplier: float) -> void:
		events.append({"source": source, "position": position, "radius": radius, "multiplier": multiplier})

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var enemy = scene.get_node("Arena/Enemy")
	player.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	check(player.get("movement_noise_radius") != null, "玩家节点直接导出移动声半径")
	check(enemy.get("movement_noise_radius") != null, "敌人节点直接导出移动声半径")
	check(enemy.weapon.get("shot_noise_radius") != null, "武器直接导出枪声半径")
	check(player.has_node("Health/Debug/Controls/NoiseRanges"), "调试面板提供声音范围开关")
	if failures > 0:
		finish()
		return
	var ai = enemy.get_node("AI")
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	player.get_node("Health").debug_mode = false
	player.global_position = enemy.global_position + Vector3(0, 0, 4.8)
	await settle()
	# 在加入树前选合法出生点，让环境登记拿到最终位置；不与原敌人重叠。
	var peer_position := Vector3.INF
	var navigation: NavigationRegion3D = ai.context.navigation_region
	for offset in [Vector3.LEFT * 2.0, Vector3.RIGHT * 2.0, Vector3.FORWARD * 2.0, Vector3.BACK * 2.0]:
		var point := NavigationServer3D.region_get_closest_point(navigation.get_rid(), enemy.global_position + offset)
		if point.distance_to(enemy.global_position) > 1.0 and ai.context.is_position_free(point):
			peer_position = point
			break
	check(peer_position.is_finite(), "同伴在合法导航地面生成")
	if not peer_position.is_finite():
		finish()
		return
	var peer = enemy.duplicate()
	peer.position = enemy.get_parent().to_local(peer_position)
	enemy.get_parent().add_child(peer)
	peer.get_node("AI").set_physics_process(false)
	var recorder := Recorder.new()
	root.add_child(recorder)
	recorder.add_to_group("hearing_listener")
	await settle()
	check(ai.is_arena_active(), "实际进入竞技场后测试敌我声源")
	var debug = player.get_node("Health/NoiseRanges")
	var toggle = player.get_node("Health/Debug/Controls/NoiseRanges")
	player.movement_noise.emit_from(player, 7.25)
	await settle()
	check(debug.get_child_count() == 0, "关闭调试显示时仍有声音事件但无图形")
	check(recorder.events.size() == 1 and ai.is_alerted, "调试开关不影响玩家声源感知")
	enemy.reset_target()
	peer.reset_target()
	player.get_node("Health").debug_mode = true
	toggle.button_pressed = true
	debug.set_process(false) # 手动推进寿命，使图形断言不依赖机器速度。
	enemy.movement_noise.emit_from(enemy, 6.5)
	await settle()
	check(not ai.is_alerted and not peer.get_node("AI").is_alerted, "自己和队友的声音均不会触发调查")
	check(debug.get_child_count() == 1, "敌人声音仍能显示调试范围")
	var pulse = debug.get_child(0)
	check(pulse.material_override.albedo_color.is_equal_approx(debug.ENEMY_COLOR), "敌人圆环为橙色")
	check(is_equal_approx(pulse.mesh.get_aabb().size.x, 13.0), "调试外圈读取实际事件半径")
	var vertices = pulse.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var has_inner := false
	for vertex in vertices:
		if is_equal_approx(Vector2(vertex.x, vertex.z).length(), 6.5 * 0.4):
			has_inner = true
	check(has_inner, "内虚线圈读取隔墙倍率")
	var origin: Vector3 = pulse.global_position
	enemy.global_position += Vector3.RIGHT
	check(pulse.global_position == origin, "声圈留在发声位置而非跟着角色移动")
	player.movement_noise.emit_from(player, 7.25)
	await settle()
	check(debug.get_child(1).material_override.albedo_color.is_equal_approx(debug.PLAYER_COLOR), "玩家圆环为蓝色")
	debug._process(debug.LIFETIME + 0.01)
	check(debug.get_child_count() == 0, "声音范围到时自动清除")
	# 使用同一个声音资源和武器，阵营仍取自实际发声者。
	enemy.reset_target()
	peer.reset_target()
	enemy.movement_noise = player.movement_noise
	enemy.movement_noise_radius = 3.25
	enemy.movement_noise_interval = 0.4
	recorder.events.clear()
	for frame in range(12):
		await physics_frame
		enemy.move_character(Vector3.RIGHT, 1.0 / 60.0)
	await settle()
	check(recorder.events.size() == 1 and recorder.events[0].source == enemy and recorder.events[0].radius == 3.25, "敌人实际移动按节点半径和间隔发声")
	check(not ai.is_alerted and not peer.get_node("AI").is_alerted, "真实敌人移动不会唤醒同伴")
	recorder.events.clear()
	enemy.move_character(Vector3.ZERO, 0.1)
	enemy.face_direction(Vector3.FORWARD, 0.1)
	await settle()
	check(recorder.events.is_empty(), "敌人站立和转身无脚步声")
	var combat = player.get_node("Combat")
	var weapon = combat.weapon.duplicate()
	weapon.shot_noise_radius = 21.5
	enemy.equip_weapon(weapon)
	combat.equip_weapon(weapon)
	enemy.look_at(player.global_position)
	# 真正从当前枪口向玩家身体点完成瞄准；不能依赖旧0.8米枪口恰好水平。
	enemy.update_weapon(1.0, player.get_torso_position())
	enemy.shot_cooldown = 0.0
	check(enemy.try_fire(), "敌人确实成功开枪")
	await settle()
	check(recorder.events.size() == 1 and recorder.events[0].source == enemy and recorder.events[0].radius == 21.5, "敌人枪声使用所持武器半径并保留敌人身份")
	check(not ai.is_alerted and not peer.get_node("AI").is_alerted, "真实敌人枪声不会唤醒同伴")
	enemy.try_fire()
	await settle()
	check(recorder.events.size() == 1, "射击冷却拒绝时不产生敌人枪声")
	recorder.events.clear()
	combat.is_aiming = true
	combat.locked_target = null
	combat.shot_cooldown = 0.0
	player.rotation.y = -PI / 2.0
	combat.shoot()
	await settle()
	check(recorder.events.size() == 1 and recorder.events[0].source == player and recorder.events[0].radius == 21.5, "玩家共用同一武器仍以玩家身份发出枪声")
	check(ai.is_alerted and peer.get_node("AI").is_alerted, "相同武器的玩家枪声可引发敌人调查")
	combat.cancel_aim()
	recorder.events.clear()
	player.movement_noise_radius = 8.25
	player._movement_noise_timer = 0.0
	for frame in range(8):
		await physics_frame
		player._move_while_locked(1.0 / 60.0, Vector3.RIGHT)
	await settle()
	check(not recorder.events.is_empty() and recorder.events[0].source == player and recorder.events[0].radius == 8.25, "玩家实际移动读取节点导出的半径")
	check(enemy.movement_noise_radius == 3.25, "玩家调参不会修改敌人移动范围")
	toggle.button_pressed = false
	check(not debug.enabled and debug.get_child_count() == 0, "关闭开关立即清理全部残留声圈")
	recorder.events.clear()
	enemy.movement_noise_radius = 0.0
	enemy._movement_noise_timer = 0.0
	await physics_frame
	enemy.move_character(Vector3.RIGHT, 0.1)
	weapon.shot_noise_radius = 0.0
	enemy.shot_cooldown = 0.0
	enemy.try_fire()
	await settle()
	check(recorder.events.is_empty(), "零半径关闭移动和枪声事件")
	enemy.movement_noise_radius = 5.0
	enemy.receive_hit(enemy.health)
	enemy.move_character(Vector3.RIGHT, 0.1)
	check(not enemy.try_fire(), "死亡敌人不能继续发声开枪")
	await settle()
	check(recorder.events.is_empty(), "死亡敌人不产生移动声")
	weapon.shot_noise_radius = 23.5
	var path := "user://noise-weapon-test.tres"
	check(ResourceSaver.save(weapon, path) == OK, "武器声音半径可保存到tres")
	var restored = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	check(restored.shot_noise_radius == 23.5, "重新读取武器保留独立枪声半径")
	DirAccess.remove_absolute(path)
	peer.free()
	recorder.free()
	finish()

func settle() -> void:
	for frame in range(3):
		await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("NOISE DEBUG: ", checks - failures, "/", checks)
	quit(0 if failures == 0 else 1)
