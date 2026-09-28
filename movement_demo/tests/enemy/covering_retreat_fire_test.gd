extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var e = scene.get_node("Arena/Enemy")
	var ai = e.get_node("AI")
	Fixture.configure_timing(e)
	var cover = e.get_node("AI").cover
	var p = scene.get_node("Player")
	ai.set_physics_process(false)
	p.set_physics_process(false)
	p.get_node("Health").debug_invincible = true
	cover.selection.debug_cover_selection = false
	ai.search.debug_tracking_cheat = false
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	for frame in range(5):
		await physics_frame
	# Cover优先控制移动时，主状态可能仍是其他状态，不能要求先回REPOSITION。
	ai.state = ai.State.TRACK
	cover.phase = cover.Phase.RUN_TO_COVER
	cover.covering_retreat = true
	ai.tactics.update_shooting(0.49, true, true)
	_check("掩护撤退仍需反应时间", e.shot_count == 0)
	ai.tactics.update_shooting(0.02, true, true)
	_check("掩护撤退可以真实开火命中玩家", e.shot_count == 1 and e.last_shot_collider == p)
	_check("开枪不会退出掩护撤退", cover.phase == cover.Phase.RUN_TO_COVER and cover.covering_retreat)
	ai.tactics.update_shooting(0.81, true, true)
	ai.tactics.update_shooting(0.81, true, true)
	_check("掩护撤退累计三枪", e.shot_count == 3)
	ai.tactics.update_shooting(0.81, true, true)
	_check("撤退中三枪后仍需停顿", e.shot_count == 3)
	ai.tactics.update_shooting(0.20, true, true)
	_check("停顿结束继续掩护射击", e.shot_count == 4)
	var count: int = e.shot_count
	ai.tactics.fire_while_moving = false
	ai.tactics.update_shooting(1.0, true, true)
	_check("关闭移动射击同样限制掩护撤退", e.shot_count == count)
	ai.tactics.fire_while_moving = true
	cover.covering_retreat = false
	ai.tactics.update_shooting(1.0, true, true)
	_check("普通转身跑掩体仍不射击", e.shot_count == count)
	cover.covering_retreat = true
	ai.tactics.update_shooting(1.0, false, true)
	_check("失去视线时掩护撤退不盲射", e.shot_count == count and not e.has_aim)
	cover.phase = cover.Phase.HIDE
	ai.tactics.update_shooting(1.0, true, false)
	_check("躲藏阶段不因残留撤退标记开火", e.shot_count == count)
	cover.phase = cover.Phase.PEEK_OUT
	ai.tactics.update_shooting(1.0, true, true)
	_check("有效探头阶段仍不射击", e.shot_count == count)
	cover.phase = cover.Phase.RUN_TO_COVER
	cover.damage_force_sprint_chance = 1.0
	cover.hide_position = e.global_position + Vector3(0, 0, -3)
	cover.timer = 10.0
	cover.on_damage_received()
	ai.tactics.update_shooting(1.0, true, true)
	_check("受伤切为冲刺后立即停止掩护射击", not cover.covering_retreat and e.shot_count == count)
	# 用实际AI物理循环沿可达路线撤退，确认cover优先分支也接上了射击。
	e.reset_target()
	e.look_at(p.global_position)
	ai.state = ai.State.TRACK
	cover.phase = cover.Phase.RUN_TO_COVER
	cover.covering_retreat = true
	cover.hide_position = e.global_position + Vector3(0, 0, -3)
	cover.look_position = p.global_position
	cover.threat_origin = p.global_position + Vector3.UP * 0.8
	cover.timer = 10.0
	e.agent.target_position = cover.hide_position
	var walked: float = 0.0
	var retreat_shot := false
	var before: Vector3 = e.global_position
	for frame in range(100):
		await physics_frame
		count = e.shot_count
		ai._physics_process(1.0 / 60.0)
		var movement: float = e.global_position.distance_to(before)
		walked += movement
		before = e.global_position
		retreat_shot = retreat_shot or (movement > 0.001 and e.shot_count > count and cover.phase == cover.Phase.RUN_TO_COVER and cover.covering_retreat)
	_check("真实Cover移动分支边撤退边开火", walked > 0.3 and retreat_shot)
	print("RETREAT WALK distance=", walked, " shots=", e.shot_count, " phase=", cover.phase)
	var failed: int = checks.values().count(false)
	print("RETREAT FIRE: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)
