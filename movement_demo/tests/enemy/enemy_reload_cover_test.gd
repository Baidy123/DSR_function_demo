extends SceneTree

const Fixture = preload("res://tests/enemy/enemy_fire_fixture.gd")
const STEP := 1.0 / 60.0
var checks := 0
var failures := 0

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
	actor.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(actor)
	Fixture.set_training_action(ai, &"cover", true)
	ai.cover_selection.debug_attack_points = false
	ai.cover_selection.debug_cover_selection = false
	ai.actions[&"search"].tracking_cheat_enabled = false
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	actor.debug_shooting = false
	player.health.debug_invincible = true
	var wall = scene.get_node("Arena/NavigationRegion3D/Environment/LowCover")
	var center: Vector3 = wall.global_position
	center.y = 0.0
	player.global_position = center + Vector3.FORWARD * 4.0
	var action = ai.actions[&"reload"]
	check(action.config_section == &"cover" and action._setting(&"reload_cover_preference", -1.0) == 6.0 and action._setting(&"reload_cover_preference_distance", -1.0) == 4.0, "换弹偏好归原Cover参数段且默认值可查询")
	await _reset(ai, actor, center + Vector3.BACK * 1.1)
	var starting_position: Vector3 = actor.global_position
	var selected_here := false
	var actual_crouch := false
	var safe_timing := true
	var no_fire := true
	var complete := false
	var elapsed := 0.0
	var shots: int = actor.shot_count
	for frame in 240:
		await physics_frame
		ai._physics_process(STEP)
		actor._physics_process(STEP)
		elapsed += STEP
		selected_here = selected_here or (ai.utility_current.get("id") == &"reload" and ai.utility_current.get("plan") == &"here")
		if actor.ammo.is_reloading:
			actual_crouch = actual_crouch or actor.is_crouching()
			safe_timing = safe_timing and absf(actor.ammo.reload_progress - elapsed / actor.weapon.reload_seconds) < 0.0001
			no_fire = no_fire and actor.shot_count == shots and not actor.try_fire()
		elif actor.ammo.magazine_rounds > 0:
			complete = true
			break
	check(selected_here and actual_crouch, "实际低墙后站姿空匣由完整AI自主选择原地换弹并真正蹲下")
	check(actor.global_position.distance_to(starting_position) < 0.12, "已在低墙后原地换弹不绕行或跳到相邻网格中心")
	check(safe_timing and complete and absf(elapsed - actor.weapon.reload_seconds) <= STEP + 0.0001, "蹲姿过渡没有暂停重置或加速真实换弹进度")
	check(no_fire and actor.ammo.magazine_rounds == actor.weapon.magazine_capacity, "蹲姿换弹完成前不射击且正常补满")

	# 保留完整候选池和空缓存，依靠已有Utility选择附近安全掩体。
	await _reset(ai, actor, center + Vector3.BACK * 2.8)
	starting_position = actor.global_position
	var chose_cover := false
	var reload_crouched := false
	var walked := false
	var progress_monotonic := true
	var previous_progress := 0.0
	for frame in 300:
		await physics_frame
		ai._physics_process(STEP)
		actor._physics_process(STEP)
		var selected: Dictionary = ai.utility_current
		if selected.get("id") == &"reload" and selected.get("destination", {}).get("body") == wall:
			chose_cover = true
		walked = walked or actor.global_position.distance_to(starting_position) > 0.3
		if actor.ammo.is_reloading:
			reload_crouched = reload_crouched or actor.is_crouching()
			progress_monotonic = progress_monotonic and actor.ammo.reload_progress + 0.0001 >= previous_progress
			previous_progress = actor.ammo.reload_progress
		elif actor.ammo.magazine_rounds > 0 and chose_cover:
			break
	check(chose_cover and walked and reload_crouched, "实际空匣冷启动由Utility走到附近低墙并在换弹中蹲好")
	check(progress_monotonic and actor.ammo.magazine_rounds > 0, "原地与途中方案重评不丢弃基础换弹进度")

	# 用户实况：低墙短边已在交战，弹匣自然打空后原攻击占位仍有效。
	# 从实际完整AI与满匣开始，不手工选换弹或修改共同切换优势。
	Fixture.set_training_action(ai, &"attack_position", true)
	action = ai.actions[&"reload"]
	player.global_position = center + Vector3(-0.41789, 0, -0.818408)
	await _reset(ai, actor, center + Vector3(2.21207, 0, 0.404255))
	actor.ammo.magazine_rounds = actor.weapon.magazine_capacity
	shots = actor.shot_count
	var fired_empty := false
	var saw_reload := false
	var crouched_reload := false
	var resumed_fire := false
	var empty_at := -1
	var reload_at := -1
	var resumed_at := -1
	# 打空前的实际蹲起轮次保留900帧上限；换弹接续从打空事件计时。
	# 预算仅由已有换弹、恢复、火控暂停、有限蹲起及一次重评/保持组成。
	var resume_seconds: float = actor.weapon.reload_seconds + actor.weapon.stabilize_seconds + actor.weapon.accuracy_recovery_delay
	resume_seconds += ai.context.fire.fire_reaction_seconds + ai.context.fire.burst_pause_seconds + actor.weapon.shot_interval
	resume_seconds += float(ai.training.profile.setting(&"cover", &"low_cover_hide_seconds", 0.6)) + actor.posture_seconds * 3.0
	resume_seconds += ai.utility_recheck_seconds + ai.utility_hold_seconds
	var resume_frames := ceili(resume_seconds / STEP)
	for frame in 900 + resume_frames:
		if (empty_at < 0 and frame >= 900) or (empty_at >= 0 and frame - empty_at > resume_frames): break
		await physics_frame
		ai._physics_process(STEP)
		actor._physics_process(STEP)
		if actor.shot_count >= shots + actor.weapon.magazine_capacity and actor.ammo.magazine_rounds == 0:
			fired_empty = true
			if empty_at < 0: empty_at = frame
		if fired_empty and actor.ammo.is_reloading:
			saw_reload = true
			if reload_at < 0: reload_at = frame
			crouched_reload = crouched_reload or actor.is_crouching()
		if saw_reload and actor.shot_count > shots + actor.weapon.magazine_capacity:
			resumed_fire = true
			resumed_at = frame
			break
	check(fired_empty and saw_reload and reload_at - empty_at <= 90, "实况低墙短边完整交战自然打空后及时自主换弹，不停在旧架枪方案")
	check(crouched_reload and resumed_fire and resumed_at - empty_at <= resume_frames, "实况空匣接续真正蹲姿换弹并恢复实际射击")
	print("RELOAD LIVE CYCLE: empty frame=%d, reload frame=%d, resumed frame=%d, post-empty budget=%d" % [empty_at, reload_at, resumed_at, resume_frames])
	player.global_position = center + Vector3.FORWARD * 4.0

	# 参数只改变显式信用，候选的真实时间、暴露和信息代价不能跟着变。
	await _reset(ai, actor, center + Vector3.BACK * 2.8)
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	for frame in 80:
		await physics_frame
		ai.context.spatial.advance_evaluation()
	var weighted: Array = action.collect_candidates(true)
	ai.training.profile.set_setting(&"cover", &"reload_cover_preference", 0.0)
	var plain: Array = action.collect_candidates(true)
	var same_estimates := weighted.size() == plain.size()
	var positive_credit := false
	var useful: Dictionary = {}
	for index in mini(weighted.size(), plain.size()):
		var a: Dictionary = weighted[index]
		var b: Dictionary = plain[index]
		same_estimates = same_estimates and a.destination == b.destination and a.outcome.unavailable_seconds == b.outcome.unavailable_seconds and a.outcome.exposed_seconds == b.outcome.exposed_seconds and a.outcome.information_loss == b.outcome.information_loss
		positive_credit = positive_credit or a.outcome.preference_credit > 0.0
		if a.outcome.preference_credit > 0.0: useful = a
	check(positive_credit and same_estimates and plain.all(func(candidate): return candidate.outcome.preference_credit == 0.0), "0关闭偏好保留真实候选、时间、曝露和信息代价")
	check(not useful.is_empty() and useful.outcome.exposed_seconds < weighted[0].outcome.exposed_seconds, "附近掩体信用必须对应同一窗口内实际遮蔽收益")
	check(_winner(ai, plain).get("plan") == &"here" and not _winner(ai, weighted).get("destination", {}).is_empty(), "软加权明确提升安全掩体相对站空地换弹的选择")
	ai.training.profile.set_setting(&"cover", &"reload_cover_preference", 6.0)
	var threat: Vector3 = ai.context._known_reload_threat()
	var far: Dictionary = {}
	for destination in ai.context.spatial.cover_points():
		if not ai.context.spatial.cover_valid(destination): continue
		destination.path = ai.context.routes.planning_path(actor.global_position, destination.hide)
		var length := 0.0
		var previous: Vector3 = actor.global_position
		for point: Vector3 in destination.path:
			length += ai.context._horizontal_distance_between(previous, point)
			previous = point
		if length <= 5.0: continue
		var travel: Dictionary = ai.context.spatial.assess_cover_route(destination.path, threat, action.transfer.run_speed_multiplier, actor.weapon.reload_seconds)
		var remaining: float = maxf(0.0, ai.utility_horizon_seconds - travel.seconds)
		var exposure: float = travel.exposure + action._stationary_exposure(destination.hide, threat, remaining, destination.get("crouch", false))
		far = action.option(destination, maxf(travel.seconds, actor.weapon.reload_seconds), exposure, remaining, &"on_way")
		far.outcome.preference_credit = action._cover_credit(far, weighted[0].outcome.exposed_seconds, threat)
		break
	check(not far.is_empty() and far.outcome.preference_credit == 0.0, "真实超过偏好距离的长路线没有信用")
	check(not far.is_empty() and _winner(ai, [weighted[0], far]).plan == &"here", "真实远路不会因掩体偏好强抢可及时完成的原地换弹")
	if not useful.is_empty():
		var no_gain: Dictionary = useful.duplicate(true)
		no_gain.outcome.exposed_seconds = weighted[0].outcome.exposed_seconds
		check(action._cover_credit(no_gain, weighted[0].outcome.exposed_seconds, threat) == 0.0, "没有减少曝露的目的地不能领取偏好")
		var unsafe: Dictionary = useful.duplicate(true)
		unsafe.destination.path = PackedVector3Array([actor.global_position, threat, unsafe.destination.hide])
		check(not ai.context.spatial.cover_route_safe(unsafe.destination.path, threat) and action._cover_credit(unsafe, weighted[0].outcome.exposed_seconds, threat) == 0.0, "穿过已知威胁近身范围的路线不领取偏好")
		var best: Dictionary = _winner(ai, weighted)
		check(ai.action_selector.choose_option([best, {"id": &"better", "cost": best.cost - 0.1}]).id == &"better", "其他更低共同代价仍能胜过掩体换弹")

	await _reset(ai, actor, center + Vector3.BACK * 1.1)
	ai.context.update_evidence(0.0, ai.perception.can_see_player())
	ai.training.profile.set_setting(&"cover", &"reload_cover_preference", 0.0)
	var here: Dictionary = action.collect_candidates(true)[0]
	check(here.crouch and here.outcome.preference_credit == 0.0 and here.outcome.exposed_seconds < ai.context._reload_exposure(actor.global_position, player.global_position) * ai.utility_horizon_seconds, "0偏好仍保留低墙原地蹲姿及真实防护")
	action.begin(here, true)
	actor.update_weapon(0.5)
	var progress: float = actor.ammo.reload_progress
	action.cancel()
	check(actor.ammo.is_reloading and actor.ammo.reload_progress == progress, "取消换弹安排不取消身体已开始的换弹")
	actor.ammo.magazine_rounds = 1
	check(not actor.try_fire(), "取消动作但尚在基础换弹时余弹也不能射击")
	actor.cancel_reload()
	actor.ammo.magazine_rounds = actor.weapon.magazine_capacity
	check(action.collect_candidates(true).is_empty(), "满匣不因掩体偏好新增换弹候选")
	ai.training.profile.set_setting(&"cover", &"reload_cover_preference", 7.25)
	ai.training.profile.set_setting(&"cover", &"reload_cover_preference_distance", 3.5)
	var path := "user://reload_cover_training.tres"
	var saved := ResourceSaver.save(ai.training.profile, path) == OK
	var loaded = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) if saved else null
	check(loaded != null and loaded.setting(&"cover", &"reload_cover_preference", -1) == 7.25 and loaded.setting(&"cover", &"reload_cover_preference_distance", -1) == 3.5, "独立换弹偏好与距离可以保存重载")
	scene.queue_free()
	await process_frame
	print("RELOAD COVER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _reset(ai, actor, position: Vector3) -> void:
	ai.reset_actions()
	ai.context.reset_memory()
	ai.context.spatial.reset_evaluation()
	actor.cancel_reload()
	actor.body_motion.reset()
	actor.global_position = position
	actor.velocity = Vector3.ZERO
	actor.ammo.magazine_rounds = 0
	actor.look_at(ai.context.player.global_position)
	for frame in 6: await physics_frame

func _winner(ai, options: Array) -> Dictionary:
	var scored: Array = []
	for original: Dictionary in options:
		var candidate := original.duplicate(true)
		var outcome: Dictionary = candidate.outcome
		candidate.cost = ai.action_selector.score_outcome(ai.context, outcome.unavailable_seconds, outcome.exposed_seconds, outcome.information_loss, outcome.get("preference_credit", 0.0)).cost
		scored.append(candidate)
	return ai.action_selector.choose_option(scored)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
