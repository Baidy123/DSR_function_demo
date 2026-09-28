extends SceneTree

var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var e = scene.get_node("Arena/Enemy")
	var ai = e.get_node("AI")
	var t = ai.tactics
	var cover = t.cover
	var p = scene.get_node("Player")
	ai.set_physics_process(false)
	p.set_physics_process(false)
	p.get_node("Health").debug_invincible = true
	# 固定本组时序，避免用户场景调参改变决策回归的前提。
	t.fire_reaction_seconds = 0.3
	t.burst_pause_seconds = 2.1
	t.fire_stability_target = 0.7
	_check("普通交火提供稳定度目标", t.get("fire_stability_target") != null)
	if checks.values().has(false):
		_finish()
		return
	_check("场景反应0.3秒且保留2.1秒停顿", is_equal_approx(t.fire_reaction_seconds, 0.3) and is_equal_approx(t.burst_pause_seconds, 2.1))
	_check("普通交火默认目标70%", is_equal_approx(t.fire_stability_target, 0.7))
	_check("当前武器初始50%需要稳枪", is_equal_approx(e.weapon_stability, 0.5))
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	for frame in range(5):
		await physics_frame
	ai.state = ai.State.HOLD_POSITION
	t.update_shooting(0.3, true, false)
	_check("反应结束但未稳到70%不射击", e.shot_count == 0 and e.weapon_stability < 0.7)
	t.update_shooting(0.25, true, false)
	_check("反应与稳枪并行而非串联等待", e.shot_count == 1)
	var w = e.weapon.duplicate()
	w.initial_accuracy = 0.5
	w.accuracy_recovery_delay = 10.0
	w.shot_accuracy_penalty = 0.2
	w.minimum_accuracy = 0.0
	e.equip_weapon(w)
	e.weapon_recovery_timer = 10.0
	e.shot_cooldown = 0.0
	t.reset_fire_timing()
	e.weapon_stability = 0.5
	var count: int = e.shot_count
	t.update_shooting(0.3, true, false)
	_check("短暂等待时优先稳枪且不计入本轮枪数", e.shot_count == count and t.fire_burst_shots == 0)
	e.weapon_stability = 0.7
	t.update_shooting(0.0, true, false)
	_check("达到目标允许普通开火", e.shot_count == count + 1)
	e.shot_cooldown = 0.0
	t.update_shooting(0.1, true, false)
	_check("连射惩罚后短时间仍偏好稳枪", e.shot_count == count + 1)
	e.weapon_stability = 0.7
	t.update_shooting(0.0, true, false)
	_check("恢复到目标后继续本轮射击", e.shot_count == count + 2 and t.fire_burst_shots == 2)
	e.weapon_stability = 0.2
	e.shot_cooldown = 0.0
	ai.state = ai.State.REPOSITION
	t.update_shooting(1.0, true, true)
	_check("普通跑打精度低且等待不久时仍偏好稳枪", e.shot_count == count + 2)
	cover.phase = cover.Phase.RUN_TO_COVER
	cover.covering_retreat = true
	ai.state = ai.State.TRACK
	t.update_shooting(0.0, true, true)
	_check("掩护撤退允许低稳定度开火", e.shot_count == count + 3)
	_check("撤退仍计入三枪停顿", is_equal_approx(t.fire_pause_remaining, 2.1))
	e.shot_cooldown = 0.0
	t.update_shooting(1.0, true, true)
	_check("低稳定度例外不绕过轮后停顿", e.shot_count == count + 3)
	t.reset_fire_timing()
	t.update_shooting(0.1, true, true)
	_check("撤退仍需短反应时间", e.shot_count == count + 3)
	t.update_shooting(0.2, true, true)
	_check("短反应结束后可继续撤退射击", e.shot_count == count + 4)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(t.ai, &"covering_retreat", false)
	t.update_shooting(1.0, true, true)
	_check("低稳定度例外不绕过动作能力", e.shot_count == count + 4)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(t.ai, &"covering_retreat", true)
	cover.phase = cover.Phase.HIDE
	t.update_shooting(1.0, true, false)
	_check("躲藏阶段仍不射击", e.shot_count == count + 4)
	cover.reset()
	ai.state = ai.State.HOLD_POSITION
	e.weapon_stability = 1.0
	t.update_shooting(1.0, false, false)
	_check("高稳定度也不能向隐藏目标射击", e.shot_count == count + 4 and not e.has_aim)
	t.fire_stability_target = 0.0
	e.weapon_stability = 0.2
	t.update_shooting(1.0, true, false)
	_check("目标设为零可以关闭稳枪限制", e.shot_count == count + 5)
	t.fire_stability_target = 0.7
	w.initial_accuracy = 1.0
	e.equip_weapon(w)
	e.shot_cooldown = 0.0
	t.update_shooting(1.0, true, false)
	_check("中心概率100%时无需继续等待稳枪", e.shot_count == count + 6)
	e.reset_target()
	_check("刷新清理反应与枪数并恢复初始精度", t.fire_reaction_elapsed == 0.0 and t.fire_burst_shots == 0 and e.shot_count == 0)
	_finish()

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)

func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("STABILITY FIRE: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
