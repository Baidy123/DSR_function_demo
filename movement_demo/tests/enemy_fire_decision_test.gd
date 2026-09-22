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
	Fixture.configure_decision(e)
	var ai = e.get_node("AI")
	var t = ai.tactics
	var p = scene.get_node("Player")
	ai.set_physics_process(false)
	p.set_physics_process(false)
	p.get_node("Health").debug_invincible = true
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	for frame in range(5):
		await physics_frame
	ai.state = ai.State.HOLD_POSITION
	# 先复现实际问题：真实物理移动的玩家一直可见，但目标移动惩罚令稳定度低于70%。
	var moving_fire := false
	var low_stability_fire := false
	var direction := 1.0
	var center: float = p.global_position.x
	var travelled := 0.0
	for frame in range(480):
		await physics_frame
		if absf(p.global_position.x - center) > 0.55:
			direction *= -1.0
		p.velocity = Vector3(direction * 2.0, 0.0, 0.0)
		var before: Vector3 = p.global_position
		p.move_and_slide()
		travelled += p.global_position.distance_to(before)
		var shots: int = e.shot_count
		var stability: float = e.weapon_stability
		t.update_shooting(1.0 / 60.0, true, false)
		if e.shot_count > shots:
			moving_fire = moving_fire or p.global_position.distance_to(before) > 0.01
			low_stability_fire = low_stability_fire or stability < 0.7
	_check("玩家持续实际移动时敌人仍会重复开火", travelled > 10.0 and moving_fire and e.shot_count >= 2)
	_check("低于70%也能选择开火", low_stability_fire)
	_check("战术挂载独立射击动作评分", t.fire_decision != null)
	if t.fire_decision == null:
		_finish()
		return
	var decision = t.fire_decision
	decision.reset()
	var chosen = decision.choose_action(0.0, 0.5, 0.7, 0.5, 0.0)
	_check("刚接敌且精度可恢复时优先稳枪", chosen == decision.Action.STEADY and decision.steady_score > decision.fire_score)
	chosen = decision.choose_action(0.0, 0.7, 0.7, 0.5, 0.0)
	_check("达70%时开火分不低于稳枪分", chosen == decision.Action.FIRE and decision.fire_score >= decision.steady_score)
	decision.reset()
	decision.choose_action(0.0, 0.5, 0.7, 0.0, 0.0)
	var no_gain_score: float = decision.steady_score
	decision.choose_action(0.0, 0.5, 0.7, 0.5, 0.0)
	_check("有恢复收益会提高稳枪分", decision.steady_score > no_gain_score)
	var far_score: float = decision.fire_score
	decision.choose_action(0.0, 0.5, 0.7, 0.5, 1.0)
	_check("近距离压力提高开火分", decision.fire_score > far_score)
	decision.reset()
	decision.choose_action(0.2, 0.0, 0.7, 0.0, 0.0)
	var early_score: float = decision.fire_score
	chosen = decision.choose_action(3.0, 0.0, 0.7, 0.0, 0.0)
	_check("等待提高开火分而非永久卡在低精度", chosen == decision.Action.FIRE and decision.fire_score > early_score)
	decision.on_shot_fired()
	_check("成功开火后清理等待压力", decision.wait_seconds == 0.0)
	decision.reset()
	_check("目标为零直接偏向开火", decision.choose_action(0.0, 0.0, 0.0, 0.0, 0.0) == decision.Action.FIRE)
	# 安全条件先过滤：不能靠积累分数绕过视野、动作、冷却或首枪跟准。
	e.reset_target()
	e.look_at(p.global_position)
	ai.state = ai.State.HOLD_POSITION
	e.weapon_stability = 0.0
	decision.wait_seconds = 10.0
	t.update_shooting(0.1, false, false)
	_check("丢失目标清理压力且不盲射", decision.wait_seconds == 0.0 and e.shot_count == 0)
	e.weapon_stability = 1.0
	var w = e.weapon.duplicate()
	w.initial_accuracy = 1.0 # 敌人使用概率模式；初始100%使恢复速率为0。
	e.equip_weapon(w)
	e.shot_cooldown = 5.0
	t.update_shooting(0.5, true, false)
	_check("冷却期间不积累等待压力", decision.wait_seconds == 0.0 and e.shot_count == 0)
	e.shot_cooldown = 0.0
	ai.state = ai.State.SEARCH
	decision.wait_seconds = 10.0
	t.update_shooting(1.0, true, false)
	_check("搜索记忆不能靠高分请求开火", decision.wait_seconds == 0.0 and e.shot_count == 0)
	ai.state = ai.State.HOLD_POSITION
	t.fire_while_moving = false
	decision.wait_seconds = 10.0
	t.update_shooting(1.0, true, true)
	_check("禁跑打时高分也不开火", decision.wait_seconds == 0.0 and e.shot_count == 0)
	t.fire_while_moving = true
	p.is_in_dialogue = true
	t.update_shooting(1.0, true, false)
	_check("对话时不能因评分开火", e.shot_count == 0)
	p.is_in_dialogue = false
	e.reset_target()
	_check("战斗刷新清除评分状态", decision.wait_seconds == 0.0 and decision.selected_action == decision.Action.NONE)
	await _check_live_moving_target()
	_finish()

func _check_live_moving_target() -> void:
	current_scene.free()
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var e = scene.get_node("Arena/Enemy")
	Fixture.configure_decision(e)
	var p = scene.get_node("Player")
	p.set_physics_process(false)
	p.get_node("Health").debug_invincible = true
	p.global_position = e.global_position + Vector3(0, 0, 4.8)
	e.look_at(p.global_position)
	var direction := 1.0
	var center: float = p.global_position.x
	var travelled := 0.0
	for frame in range(600):
		await physics_frame
		if absf(p.global_position.x - center) > 0.55:
			direction *= -1.0
		p.velocity = Vector3(direction * 2.0, 0.0, 0.0)
		var before: Vector3 = p.global_position
		p.move_and_slide()
		travelled += before.distance_to(p.global_position)
	_check("完整AI自主走位时也向持续移动玩家重复开火", travelled > 15.0 and e.shot_count >= 2)

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)

func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("FIRE DECISION: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
