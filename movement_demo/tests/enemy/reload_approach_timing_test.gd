extends SceneTree

var checks := 0
var failures := 0
const STEP := 1.0 / 60.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"attack_position", true)
	actor.weapon.reload_seconds = 3.5
	player.get_node("Health").debug_invincible = true
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	actor.debug_shooting = false
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(20, 0, -2)
	actor.face_direction(player.global_position - actor.global_position, 10.0)
	for frame in range(60):
		await physics_frame
		ai.context.update_evidence(STEP, true)
		ai.context.spatial.advance_evaluation()
	actor.ammo.magazine_rounds = 0
	ai._start_utility_option(ai.actions[&"reload"].collect_candidates(true)[0], true)
	player.get_node("Health").debug_invincible = false
	check(actor.get_node("Label").visible and actor.get_node("Label").text.contains("换弹 0%") and not actor.get_node("Label").text.contains("生命"),
		"关闭Debug仍显示真实换弹进度，不显示调试生命和动作信息")
	player.get_node("Health").debug_invincible = true
	var timing_ok := true
	var display_ok := true
	var switched_while_reloading := false
	var completion_frame := -1
	var shots_before: int = actor.shot_count
	for frame in range(210):
		await physics_frame
		if frame == 30: player.global_position = actor.global_position + Vector3.LEFT * 1.2
		ai._physics_process(STEP)
		var elapsed := (frame + 1) * STEP
		if actor.ammo.is_reloading:
			timing_ok = timing_ok and absf(actor.ammo.reload_progress - elapsed / 3.5) < 0.0001
			timing_ok = timing_ok and actor.ammo.magazine_rounds == 0 and actor.shot_count == shots_before
			display_ok = display_ok and actor.get_node("Label").text.contains("剩余")
			switched_while_reloading = switched_while_reloading or ai.utility_current.get("id") != &"reload"
		elif completion_frame < 0:
			completion_frame = frame + 1
	check(timing_ok and completion_frame == 210, "玩家靠近和动作接管不能加速换弹，满3.5秒才完成")
	check(switched_while_reloading, "实际发生换弹过程中切换到其他动作")
	check(display_ok, "动作切换后仍显示真实换弹进度与剩余时间")
	check(actor.ammo.magazine_rounds == actor.weapon.magazine_capacity, "完成计时后正常补满弹匣")
	player.get_node("Health").debug_invincible = false
	check(not actor.get_node("Label").visible, "非Debug模式完成换弹后隐藏头顶进度")
	player.get_node("Health").debug_invincible = true
	# 在实际合法的长路线执行边走边换，验证完成与到达是两个不同事件。
	ai.reset_actions()
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(20, 0, -2)
	ai.context.update_evidence(STEP, true)
	for frame in range(3): await physics_frame
	var reload_action = ai.actions[&"reload"]
	var destination: Dictionary = {}
	var longest := 0.0
	for candidate in ai.context.spatial.cover_points():
		if not ai.context.spatial.cover_valid(candidate): continue
		var length: float = ai.cover_selection._path_length(actor.global_position, candidate.hide)
		if length > longest:
			longest = length
			destination = candidate
	check(longest > actor.move_speed * 3.5 + 1.0, "实际地图提供换弹完成前无法抵达的合法掩体路线")
	if destination.is_empty():
		_finish()
		return
	actor.ammo.magazine_rounds = 1
	ai._start_utility_option(reload_action.option(destination, 3.5, 0.0, 0.0, &"on_way"), true)
	var premature_fire := false
	var overwritten_ammo := false
	for frame in range(210):
		await physics_frame
		var output: Dictionary = reload_action.tick(STEP, true)
		actor.move_character(output.direction, STEP, output.multiplier)
		ai.context.fire.update(STEP, true, not output.direction.is_zero_approx(), output.fire)
		ai._update_label()
		if frame < 209:
			premature_fire = premature_fire or actor.try_fire()
			overwritten_ammo = overwritten_ammo or not actor.ammo.is_reloading or actor.ammo.magazine_rounds != 1
	check(not premature_fire and not overwritten_ammo, "边走边换即使匣内有余弹也不能提前开火或补满")
	check(not actor.ammo.is_reloading and reload_action._running and reload_action.transfer.phase == reload_action.transfer.Phase.RUN_TO_COVER,
		"可以先换完弹、再继续前往掩体")
	check(actor.get_node("Label").text.contains("换弹完成，继续前往掩体") and not actor.get_node("Label").text.contains("剩余"),
		"已补满但尚未抵达时不再误显示正在换弹")
	# 将进行中的换弹交给真实合格的攻击站位，直接检查计时所有权。
	ai.reset_actions()
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(20, 0, -2)
	actor.face_direction(player.global_position - actor.global_position, 10.0)
	for frame in range(3): await physics_frame
	ai.context.update_evidence(STEP, true)
	var attack = ai.actions[&"attack_position"]
	var assessment: Dictionary = {}
	for point in attack.evaluation_points():
		assessment = attack.evaluate_point(point)
		if not assessment.is_empty(): break
	check(not assessment.is_empty(), "存在可实际接管的合格攻击站位")
	if not assessment.is_empty():
		actor.ammo.magazine_rounds = 1
		actor.request_reload()
		actor.update_weapon(0.5)
		var progress: float = actor.ammo.reload_progress
		ai._start_utility_option(attack.option(assessment.destination, assessment.unavailable, assessment.exposed), true)
		check(ai.current_action == attack and actor.ammo.is_reloading and actor.ammo.reload_progress == progress and actor.ammo.magazine_rounds == 1,
			"攻击站位接管不会补弹、重置或加速已有换弹")
		var attack_timing_ok := true
		for frame in range(180):
			await physics_frame
			var output: Dictionary = attack.tick(STEP, true)
			actor.move_character(output.direction, STEP, output.multiplier)
			ai.context.fire.update(STEP, true, not output.direction.is_zero_approx(), output.fire)
			ai._update_label()
			if frame < 179:
				attack_timing_ok = attack_timing_ok and actor.ammo.is_reloading and actor.ammo.magazine_rounds == 1
				attack_timing_ok = attack_timing_ok and absf(actor.ammo.reload_progress - (0.5 + (frame + 1) * STEP) / 3.5) < 0.0001
				attack_timing_ok = attack_timing_ok and actor.get_node("Label").text.contains("剩余")
		check(attack_timing_ok and not actor.ammo.is_reloading and actor.ammo.magazine_rounds == actor.weapon.magazine_capacity,
			"攻击站位执行期间仍在累计3.5秒后补满，过程中持续显示换弹")
	# 先去掩体再换弹尚未启动计时，必须明确显示准备阶段。
	ai.reset_actions()
	actor.ammo.magazine_rounds = 0
	reload_action.begin(reload_action.option(destination, 3.5, 0.0, 0.0, &"after_cover"), true)
	check(not actor.ammo.is_reloading and reload_action.state_label() == "前往掩体，准备换弹", "先躲后换的准备阶段不冒充正在换弹")
	ai.reset_actions()
	_finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)

func _finish() -> void:
	print("RELOAD APPROACH TIMING: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)
