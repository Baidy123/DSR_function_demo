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
	player.combat.set_physics_process(false)
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	var action = ai.actions[&"melee_cover"]
	check(action.has_method("_exit_options"), "升级动作提供基于已有掩体出口的只读接敌评估")
	if not action.has_method("_exit_options"):
		quit(1)
		return
	var cover = ai.navigation_region.get_node("Environment/CoverA")
	var box = cover.get_node("CollisionShape3D")
	var center: Vector3 = box.global_position
	center.y = 0.0
	enemy.global_position = center + Vector3(-1.45, 0, 0)
	player.global_position = center + Vector3(4.0, 0, 1.8)
	for frame in 5: await physics_frame
	enemy.set_physics_process(false)
	ai.context.is_alerted = true
	ai.context.has_visual_memory = true
	ai.context.last_known_position = player.global_position
	var destination := {"body": cover, "hide": enemy.global_position}
	var incoming := PackedVector3Array([enemy.global_position])
	var south: Vector3 = center + Vector3(0, 0, box.shape.size.z * 0.5 + cover.peek_outset)
	var north: Vector3 = center - Vector3(0, 0, box.shape.size.z * 0.5 + cover.peek_outset)
	var options: Array[Dictionary] = action._exit_options(destination, incoming, south)
	check(options.size() == 2 and options.all(func(candidate): return candidate.contact), "斜向目标只使用当前躲藏面的两个可通行端点，不混入其他面的探头点")
	var chosen: Dictionary = action._choose_exit(options)
	check(not chosen.is_empty() and chosen.position.distance_to(south) < 0.05, "同侧明显更快接近目标时选择近侧出口，不为换侧绕远")
	var nav_target: Vector3 = ai.agent.target_position
	var timer: float = action.transfer.timer
	var before: Array[Dictionary] = options.duplicate(true)
	player.global_position = center + Vector3(3.0, 0, -1.0)
	await physics_frame
	var after: Array[Dictionary] = action._exit_options(destination, incoming, south)
	check(not ai.perception.can_see_player() and before == after, "移动隐藏玩家不改变出口路线或接敌评分")
	check(ai.agent.target_position == nav_target and action.transfer.timer == timer and action._entry_position == Vector3.INF, "出口比较不修改导航、计时或实际入口记录")
	# 对称目标只改变已知证据，出口距离接近时分别检查两个入口方向。
	ai.context.last_known_position = center + Vector3(4.0, 0, 0)
	await physics_frame
	options = action._exit_options(destination, incoming, south)
	chosen = action._choose_exit(options)
	check(options.size() == 2 and not chosen.is_empty() and chosen.position.distance_to(north) < 0.05, "路线相近时从南侧进入优先北侧绕出")
	options = action._exit_options(destination, incoming, north)
	chosen = action._choose_exit(options)
	check(not chosen.is_empty() and chosen.position.distance_to(south) < 0.05, "交换实际入口方向后换侧偏好也随之交换")
	var blocker := _block(south)
	await physics_frame
	options = action._exit_options(destination, incoming, north)
	chosen = action._choose_exit(options)
	check(options.size() == 1 and not chosen.is_empty() and chosen.position.distance_to(north) < 0.05, "一侧动态封堵时使用剩余出口，即使它与入口同侧")
	var second := _block(north)
	await physics_frame
	check(action._exit_options(destination, incoming, south).is_empty(), "两个出口都不能站立时不生成虚假的绕出路线")
	blocker.queue_free()
	second.queue_free()
	await physics_frame
	options = action._exit_options(destination, incoming, south)
	check(options.size() == 2, "动态障碍移除后两侧出口恢复")
	var base = ai.actions[&"cover"]
	var peek := {"body": cover, "hide": enemy.global_position, "position": north}
	action.transfer.start_utility_peek(peek, ai.context.last_known_position, action._exit_speed())
	base.transfer.start_utility_peek(peek, ai.context.last_known_position)
	check(action.transfer.movement_multiplier() > 1.0 and is_equal_approx(base.transfer.movement_multiplier(), base.transfer.peek_speed_multiplier), "近战奔跑绕出与基础慢速探头各用自己的移动速度")
	action.cancel(&"test")
	check(not action.transfer.is_active() and action._charge_remaining == 0.0 and action._entry_position == Vector3.INF, "取消清理绕出、奔跑和入口状态")
	base.cancel(&"test")
	var peak_usec := 0
	for frame in 60:
		await physics_frame
		var started := Time.get_ticks_usec()
		action._choose_exit(action._exit_options(destination, incoming, south))
		peak_usec = maxi(peak_usec, Time.get_ticks_usec() - started)
	check(peak_usec < 20000, "双出口实际导航和风险比较保留20毫秒门槛")
	var preset = ai.training.profile.duplicate(true)
	preset.set_setting(&"melee_tactics", &"cover_exit_speed_multiplier", 1.8)
	preset.set_setting(&"melee_tactics", &"cover_charge_seconds", 1.4)
	preset.set_setting(&"melee_tactics", &"cover_exit_side_tolerance_seconds", 0.15)
	DirAccess.make_dir_recursive_absolute("res://logs")
	var saved: Error = ResourceSaver.save(preset, "res://logs/melee_cover_exit_training.tres")
	var restored = load("res://logs/melee_cover_exit_training.tres")
	check(saved == OK and is_equal_approx(restored.setting(&"melee_tactics", &"cover_exit_speed_multiplier"), 1.8) and is_equal_approx(restored.setting(&"melee_tactics", &"cover_charge_seconds"), 1.4) and is_equal_approx(restored.setting(&"melee_tactics", &"cover_exit_side_tolerance_seconds"), 0.15), "出口速度、奔跑时限和换侧容差保存重载后保留")
	scene.queue_free()
	for frame in 3: await physics_frame
	for mode in [&"timeout", &"lost_sight", &"revoke"]:
		await _check_charge_case(mode)
	print("MELEE COVER EXITS: %d/%d passed; peak %d us" % [checks - failures, checks, peak_usec])
	quit(1 if failures else 0)

func _check_charge_case(mode: StringName) -> void:
	# 每个边界从独立真实场景自主进入奔跑，避免前一轮击退或导航缓存影响起点。
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	enemy.global_position = Vector3(28, 0, 1)
	player.global_position = Vector3(24, 0, -2.5)
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	enemy.receive_hit(5.0, player.global_position)
	var gun := WeaponData.new()
	gun.reload_seconds = 4.0
	player.combat.equip_weapon(gun)
	player.combat.ammo.infinite_reserve = true
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	for frame in 12:
		await physics_frame
		ai.context.update_evidence(1.0 / 60.0, ai.perception.can_see_player())
	var action = ai.actions[&"melee_cover"]
	var entered := false
	# 边界用例先让原预算完成一轮候选准备，避免首帧资源扫描耗时决定测试前提。
	# 完整从空缓存接敌仍由 enemy_melee_cover_test 验证。
	var pass_count: int = ai.context.spatial.completed_passes
	for frame in 180:
		await physics_frame
		ai.context.update_evidence(0.0, ai.perception.can_see_player())
		ai.context.spatial.advance_evaluation()
		if ai.context.spatial.completed_passes > pass_count: break
	var previous := ""
	for frame in 240:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		var state := str(ai.utility_current.get("id"), "/", action.transfer.phase, "/", ai.context.sees_player)
		if state != previous:
			print("CHARGE CASE ", mode, " frame=", frame, " state=", state, " position=", enemy.global_position, " speed=", action._exit_speed())
			previous = state
		if ai.current_action == action and action._charge_remaining > 0.0:
			entered = true
			break
	check(entered, "边界场景由原Utility自主进入出掩体奔跑：" + String(mode))
	if entered:
		if mode == &"timeout":
			var elapsed := 0.0
			var ran := false
			while elapsed < 3.0 and ai.current_action == action:
				await physics_frame
				player.velocity = Vector3(-3.5, 0, 0)
				player.move_and_slide()
				ai._physics_process(1.0 / 60.0)
				elapsed += 1.0 / 60.0
				ran = ran or Vector2(enemy.velocity.x, enemy.velocity.z).length() > enemy.move_speed * 1.1
			check(ran and elapsed <= action._charge_seconds() + 0.1 and ai.current_action != action and action._charge_remaining == 0.0, "目标持续移动时奔跑仍按时限或合法中断结束，不无限续期")
		elif mode == &"lost_sight":
			var remembered: Vector3 = ai.context.last_known_position
			player.global_position = Vector3(12, 0, 8)
			await physics_frame
			ai._physics_process(1.0 / 60.0)
			check(not ai.context.sees_player and ai.context.last_known_position == remembered and ai.current_action != action and action._charge_remaining == 0.0, "奔跑中真正失视立即释放接敌，不更新隐藏玩家位置")
		else:
			ai.training.profile.selected_tactics.clear()
			ai.refresh_configuration(true)
			check(not ai.actions.has(&"melee_cover") and not ai.actions.has(&"cover") and not action._running and action._charge_remaining == 0.0 and not action.transfer.is_active(), "奔跑中撤销升级同时清理执行和仅由升级包含的基础权限")
	scene.queue_free()
	for frame in 3: await physics_frame

func _block(point: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.2, 1.2)
	collision.shape = box
	body.add_child(collision)
	root.add_child(body)
	body.global_position = point + Vector3.UP * 1.1
	return body

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
