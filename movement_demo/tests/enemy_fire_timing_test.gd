extends SceneTree

const Fixture = preload("res://tests/enemy_fire_fixture.gd")
var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var e = scene.get_node("Arena/Enemy")
	var ai = e.get_node("AI")
	Fixture.configure_timing(e)
	# 本测试验证固定交战位置的射击节奏；主动占位的移动与开火由独立行为测试覆盖。
	var p = scene.get_node("Player")
	var cover = e.get_node("AI").cover
	ai.set_physics_process(false)
	p.set_physics_process(false)
	p.get_node("Health").debug_invincible = true
	ai.search.debug_tracking_cheat = false
	cover.selection.debug_cover_selection = false
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	for frame in range(5):
		await physics_frame
	ai.state = ai.State.HOLD_POSITION
	_check("测试场景真正看见玩家", ai.perception.can_see_player())
	ai.tactics.update_shooting(0.01, true, false)
	_check("已经朝向玩家也不能发现即开枪", e.shot_count == 0)
	if ai.tactics.get("fire_reaction_seconds") == null:
		_finish()
		return
	_check("测试配置为半秒反应三枪停一秒", ai.tactics.fire_reaction_seconds == 0.5 and ai.tactics.burst_shot_count == 3 and ai.tactics.burst_pause_seconds == 1.0)
	ai.tactics.update_shooting(0.48, true, false)
	_check("反应时间未满不射击", e.shot_count == 0)
	_check("反应期间仍然跟枪", e.has_aim and e.aim_acquired)
	ai.tactics.update_shooting(0.02, true, false)
	_check("反应结束首枪正常命中", e.shot_count == 1 and e.last_shot_collider == p)
	ai.tactics.update_shooting(0.79, true, false)
	_check("连续射击仍受枪械射速限制", e.shot_count == 1)
	ai.tactics.update_shooting(0.02, true, false)
	_check("第二枪按原间隔开火", e.shot_count == 2)
	ai.tactics.update_shooting(0.81, true, false)
	_check("第三枪后进入停顿", e.shot_count == 3 and is_equal_approx(ai.tactics.fire_pause_remaining, 1.0))
	ai.tactics.update_shooting(0.81, true, false)
	_check("枪械已冷却但AI停顿未结束仍不射击", e.shot_cooldown == 0.0 and e.shot_count == 3)
	_check("停顿期间继续跟枪", e.has_aim and e.aim_acquired)
	ai.tactics.update_shooting(0.20, true, false)
	_check("停顿结束开启下一轮", e.shot_count == 4)
	# 丢失视野重做反应，但不清除本轮枪数，也不能偷清射击冷却。
	ai.tactics.update_shooting(0.1, false, false)
	_check("丢失视野清空反应进度", ai.tactics.fire_reaction_elapsed == 0.0 and not e.has_aim)
	_check("丢失视野保留本轮枪数", ai.tactics.fire_burst_shots == 1)
	ai.tactics.update_shooting(0.3, true, false)
	_check("再次出现需要重新反应", e.shot_count == 4)
	ai.tactics.update_shooting(0.21, true, false)
	_check("再次反应结束也不能绕过枪械冷却", e.shot_count == 4)
	ai.tactics.update_shooting(0.20, true, false)
	_check("反应与冷却都结束后恢复射击", e.shot_count == 5)
	ai.tactics.update_shooting(0.81, true, false)
	_check("遮挡没有重置第三枪停顿", e.shot_count == 6 and ai.tactics.fire_pause_remaining > 0.99)
	ai.tactics.update_shooting(0.3, false, false)
	ai.tactics.update_shooting(0.51, true, false)
	_check("消失再出现不绕过剩余停顿", e.shot_count == 6)
	ai.tactics.update_shooting(0.20, true, false)
	_check("重现反应和停顿可并行结束", e.shot_count == 7)
	# 即使请求被身体朝向拒绝，也不能虚增枪数。
	var count: int = e.shot_count
	var burst_before: int = ai.tactics.fire_burst_shots
	e.rotation.y += deg_to_rad(45.0)
	ai.tactics.update_shooting(1.0, true, false)
	_check("拒绝射击场景仍可见且已经瞄准", ai.perception.can_see_player() and e.has_aim and e.aim_acquired and e.shot_cooldown == 0.0)
	_check("执行失败不计入已发射枪数", e.shot_count == count and ai.tactics.fire_burst_shots == burst_before)
	e.look_at(p.global_position)
	# 掩体切换不能清掉未完成的一组，原禁射规则继续生效。
	cover.phase = cover.Phase.RUN_TO_COVER
	ai.tactics.update_shooting(1.0, true, true)
	_check("跑掩体仍然停火且保留计数", e.shot_count == count and ai.tactics.fire_burst_shots == burst_before)
	cover.reset()
	# 修改参数做低速枪验证：AI停顿结束不能缩短枪械自己的冷却。
	e.reset_target()
	e.look_at(p.global_position)
	ai.state = ai.State.HOLD_POSITION
	ai.tactics.fire_reaction_seconds = 0.0
	ai.tactics.burst_shot_count = 1
	ai.tactics.burst_pause_seconds = 0.2
	e.weapon.shot_interval = 2.0
	ai.tactics.update_shooting(0.0, true, false)
	ai.tactics.update_shooting(0.3, true, false)
	_check("停顿结束不会缩短慢枪冷却", e.shot_count == 1)
	ai.tactics.update_shooting(1.71, true, false)
	_check("慢枪实际冷却结束才能继续", e.shot_count == 2)
	# 可分别关闭两项新增时序；一次大delta也只补发一枪。
	e.reset_target()
	e.look_at(p.global_position)
	ai.state = ai.State.HOLD_POSITION
	ai.tactics.burst_pause_seconds = 0.0
	e.weapon.shot_interval = 0.8
	ai.tactics.update_shooting(0.0, true, false)
	_check("零反应可恢复立即开枪", e.shot_count == 1)
	ai.tactics.update_shooting(0.81, true, false)
	_check("零停顿仍遵循原枪械间隔", e.shot_count == 2)
	ai.tactics.update_shooting(10.0, true, false)
	_check("长帧不补发多枪", e.shot_count == 3)
	e.receive_hit(e.max_health)
	_check("敌人死亡清除射击决策时序", ai.tactics.fire_reaction_elapsed == 0.0 and ai.tactics.fire_burst_shots == 0 and ai.tactics.fire_pause_remaining == 0.0)
	e.reset_target()
	_check("复位清除反应计数停顿及身体状态", ai.tactics.fire_reaction_elapsed == 0.0 and ai.tactics.fire_burst_shots == 0 and ai.tactics.fire_pause_remaining == 0.0 and e.shot_count == 0)
	await _check_real_frames()
	_finish()


func _check_real_frames() -> void:
	current_scene.free()
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var e = scene.get_node("Arena/Enemy")
	var ai = e.get_node("AI")
	Fixture.configure_timing(e)
	# 本组固定射击位验证节奏；专项选位与失视压制由各自的实走／射击测试覆盖。
	var p = scene.get_node("Player")
	p.set_physics_process(false)
	p.get_node("Health").debug_invincible = true
	ai.search.debug_tracking_cheat = false
	e.get_node("AI").cover.selection.debug_cover_selection = false
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	# 留在有效射击位，真实AI每个物理帧仍处理感知、移动、跟枪和开火。
	ai.state = ai.State.HOLD_POSITION
	var first_seen_frame: int = -1
	var shot_frames: Array[int] = []
	for frame in range(350):
		var count: int = e.shot_count
		await physics_frame
		if first_seen_frame < 0 and ai.perception.can_see_player():
			first_seen_frame = frame
		if e.shot_count > count:
			shot_frames.append(frame)
		if shot_frames.size() >= 4:
			break
	_check("真实AI能够完成两轮射击", shot_frames.size() >= 4)
	if shot_frames.size() >= 4:
		_check("真实首枪等待至少半秒", shot_frames[0] - first_seen_frame >= 29)
		_check("真实前三枪保持枪械间隔", shot_frames[1] - shot_frames[0] >= 47 and shot_frames[2] - shot_frames[1] >= 47)
		_check("真实第三枪后停顿至少一秒", shot_frames[3] - shot_frames[2] >= 59)
	# 真实离场刷新后，下次进入仍重新反应。
	p.global_position = Vector3.ZERO
	for frame in range(5):
		await physics_frame
	_check("离场实际清除枪数及所有射击时序", e.shot_count == 0 and ai.tactics.fire_reaction_elapsed == 0.0 and ai.tactics.fire_burst_shots == 0 and ai.tactics.fire_pause_remaining == 0.0)
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	ai.state = ai.State.HOLD_POSITION
	for frame in range(15):
		await physics_frame
	_check("重新入场仍需反应时间", e.shot_count == 0)


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("FIRE TIMING: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
