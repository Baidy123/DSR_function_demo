extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for enabled in [false, true]: await _check_solo(enabled)
	print("ENEMY COOPERATION SOLO: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _check_solo(enabled: bool) -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	player.health.debug_invincible = true
	Fixture.configure_timing(actor)
	ai.training.profile.selected_tactics.clear()
	if enabled: ai.training.profile.selected_tactics.append(&"cooperate")
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	ai.refresh_configuration(true)
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	actor.debug_shooting = false
	actor.weapon.magazine_capacity = 6
	actor.weapon.reload_seconds = 1.2
	actor.ammo.magazine_rounds = 2
	actor.global_position = Vector3(18, 0, 0)
	player.global_position = Vector3(23, 0, 1)
	actor.look_at(player.global_position)
	for frame in 8: await physics_frame
	var label := "合作已训练" if enabled else "合作未训练"
	check(ai.context.cooperation_enabled() == enabled, label + "：本轮装配与预期一致")
	var shots_before: int = actor.shot_count
	var saw_reload := false
	var reloaded := false
	var previous_reloading := false
	var only_empty_reload := true
	var no_proactive := true
	var no_waiting := true
	var no_invented_ally := true
	for frame in 360:
		await physics_frame
		ai._physics_process(STEP)
		var context = ai.context
		if actor.ammo.is_reloading and not previous_reloading:
			only_empty_reload = only_empty_reload and actor.ammo.magazine_rounds == 0
			saw_reload = true
		if saw_reload and not actor.ammo.is_reloading and actor.ammo.magazine_rounds > 2: reloaded = true
		previous_reloading = actor.ammo.is_reloading
		no_proactive = no_proactive and not context.cooperation_reload_opportunity().get("allowed", false)
		for candidate: Dictionary in ai.actions[&"reload"].collect_candidates(context.sees_player):
			no_proactive = no_proactive and not candidate.get("proactive_reload", false)
		no_waiting = no_waiting and ai.utility_current.get("id") != &"cooperate"
		if enabled:
			no_waiting = no_waiting and ai.actions[&"cooperate"].collect_candidates(context.sees_player).is_empty()
		no_invented_ally = no_invented_ally and not context.team_visual_contact
	check(actor.shot_count > shots_before + 2 and saw_reload and reloaded and only_empty_reload, label + "：单人自主射击、空匣换弹并恢复射击")
	check(no_proactive, label + "：低余弹无人掩护时没有主动补弹机会或候选")
	check(no_waiting and no_invented_ally, label + "：不选择等队友的协作任务，也不把自己当成团队目击来源")

	# 真实遮挡后仍由原有个人调查推进；不指定动作、不注入友军ready。
	var barrier := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.2, 3, 20)
	collision.shape = shape
	barrier.add_child(collision)
	scene.add_child(barrier)
	barrier.global_position = Vector3(24, 1.5, 0)
	player.global_position = Vector3(27, 0, 1)
	for frame in 3: await physics_frame
	var lost_at: Vector3 = actor.global_position
	var lost := false
	var investigated := false
	var moved := 0.0
	for frame in 300:
		await physics_frame
		ai._physics_process(STEP)
		lost = lost or (ai.context.has_visual_memory and not ai.context.sees_player)
		investigated = investigated or (lost and ai.utility_current.get("id") == &"search")
		moved = maxf(moved, actor.global_position.distance_to(lost_at))
		no_waiting = no_waiting and ai.utility_current.get("id") != &"cooperate"
	check(lost and investigated and moved > 0.4 and no_waiting, label + "：失视后独自实际移动调查，不等待未来队友")
	print("SOLO enabled=%s shots=%d reload=%s search=%s max_loss_move=%.3f" % [enabled, actor.shot_count - shots_before, saw_reload, investigated, moved])
	scene.queue_free()
	await process_frame
	await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
