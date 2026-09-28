extends SceneTree

const Fixture = preload("res://tests/enemy_fire_fixture.gd")
const IDS = [&"patrol", &"search", &"engage", &"cover", &"attack_position", &"suppression", &"exit_suppression", &"covering_retreat"]
var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(28)
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	Fixture.configure_timing(actor)
	player.get_node("Health").debug_invincible = true
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	ai.unit_type.available_actions.clear()
	for id in IDS:
		ai.unit_type.available_actions.append(load("res://enemy_actions/%s.tres" % id))
	for id in IDS:
		_allow(ai, [id])
		check(ai.can_use_action(id), "列表单独授权即可使用：%s" % id)
		check(IDS.all(func(other): return other == id or not ai.can_use_action(other)), "单独授权不连带开放：%s" % id)
	for id in IDS:
		_allow(ai, IDS.filter(func(other): return other != id))
		check(not ai.can_use_action(id) and IDS.all(func(other): return other == id or ai.can_use_action(other)), "移除只影响自身：%s" % id)
	_allow(ai, IDS)
	var definition = ai.unit_type.available_actions.pop_back()
	check(not ai.can_use_action(definition.action_id), "Training不能赋予兵种没有的能力")
	ai.unit_type.available_actions.append(definition)
	# 真实地图的开阔射线；不改写用户资源。
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(22, 0, -2)
	actor.look_at(player.global_position)
	ai.last_seen_position = player.global_position
	ai.last_known_position = player.global_position
	ai.has_visual_memory = true
	ai.is_alerted = true
	for frame in range(5): await physics_frame
	check(ai.is_arena_active() and ai.perception.can_see_player(), "实际入场且可见玩家")
	_allow(ai, [&"engage"])
	ai.state = ai.State.HOLD_POSITION
	var shots: int = actor.shot_count
	await _fire_frames(ai, 100, true)
	check(actor.shot_count > shots, "没有两种压制权限时普通交战仍实际射击")
	ai.state = ai.State.SEARCH
	ai.tactics.fire_pause_remaining = 1.0
	ai.tactics.fire_reaction_elapsed = ai.tactics.fire_reaction_seconds
	ai.tactics.update_shooting(0.4, false, false)
	check(is_equal_approx(ai.tactics.fire_pause_remaining, 0.6), "搜索中仍按自然时间消耗连射停顿")
	check(ai.tactics.fire_reaction_elapsed == 0.0, "搜索失视清除旧反应进度")
	_allow(ai, [&"attack_position"])
	ai.tactics.reset_fire_timing()
	var attack = ai.actions[&"attack_position"]
	check(attack.start(ai.last_known_position), "攻击占位可独立启动")
	attack.phase = attack.Phase.HOLD
	ai.state = ai.State.HOLD_POSITION
	shots = actor.shot_count
	await _fire_frames(ai, 100, true)
	check(actor.shot_count > shots, "只有攻击占位权限也能使用公共射击")
	attack.reset()
	_allow(ai, [&"suppression"])
	ai.tactics.reset_fire_timing()
	var area = ai.actions[&"suppression"]
	check(area.utility_available(), "普通压制无需接敌或出口压制权限即可参选")
	area.on_target_lost()
	check(area.is_active(), "普通压制独立启动")
	shots = actor.shot_count
	await _fire_frames(ai, 90, false)
	check(actor.shot_count > shots, "普通压制独立实际开火")
	# 撤销一个未执行的动作，不触碰当前压制和基础换弹。
	_allow(ai, [&"suppression", &"exit_suppression"])
	actor.ammo.magazine_rounds = 0
	actor.request_reload()
	actor.ammo.advance_reload(0.1)
	var progress: float = actor.ammo.reload_progress
	var remaining: float = area.remaining
	_allow(ai, [&"suppression"])
	ai._enforce_action_permissions()
	check(area.is_active() and area.remaining == remaining, "移除出口压制不重置正在执行的普通压制")
	check(actor.ammo.is_reloading and actor.ammo.reload_progress == progress, "移除无关权限保留换弹进度")
	_allow(ai, [])
	ai._enforce_action_permissions()
	check(not area.is_active(), "撤销正在执行的普通压制立即停止")
	check(actor.ammo.is_reloading and actor.ammo.reload_progress == progress, "撤销当前动作仍保留基础换弹")
	actor.ammo.advance_reload(100.0)
	# 已无动作授权但状态残留HOLD，公共射击不能自行开枪。
	ai.state = ai.State.HOLD_POSITION
	shots = actor.shot_count
	await _fire_frames(ai, 100, true)
	check(actor.shot_count == shots, "无授权动作时残留主状态不能开枪")
	# 使用真实掩体的两端目标，验证出口压制不依赖普通压制。
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	var cover = load("res://cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = Vector3(22, 1.1, -2)
	var collision = cover.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	collision.shape.size = Vector3(0.8, 2.2, 3)
	actor.global_position = Vector3(24.5, 0, -2)
	ai.last_seen_position = Vector3(22.8, 0, -4.05)
	_allow(ai, [&"exit_suppression"])
	ai.tactics.reset_fire_timing()
	for frame in range(3): await physics_frame
	var exits = ai.actions[&"exit_suppression"]
	check(exits.utility_available(), "只有出口压制权限也能参选")
	ai._start_utility_option({"id": &"exit_suppression", "destination": {}}, false)
	check(exits.is_active(), "出口压制无需普通压制权限即可启动")
	shots = actor.shot_count
	await _fire_frames(ai, 120, false)
	check(actor.shot_count > shots, "出口压制独立实际开火")
	_allow(ai, [])
	ai._enforce_action_permissions()
	check(not exits.is_active(), "撤销出口压制停止自身")
	for plan in [&"cover", &"reload"]:
		for previous in [ai.State.SEARCH, ai.State.TRACK, ai.State.PATROL]:
			_allow(ai, IDS)
			ai.state = previous
			var destination := {"hide": actor.global_position, "body": cover}
			ai.cover.start_reload_transfer(destination, ai.last_known_position)
			ai.utility_current = {"id": plan, "destination": destination}
			ai.cover.cover_stuck_timer = 0.25
			Fixture.set_training_action(ai, &"patrol" if previous == ai.State.PATROL else &"search", false)
			ai._enforce_action_permissions()
			check(ai.utility_current.get("id") == plan and ai.cover.is_active() and ai.cover.cover_stuck_timer == 0.25,
				"撤销残留状态权限不打断当前计划：%s/%s" % [plan, previous])
			ai.cover.reset()
	print("ACTION PERMISSION ISOLATION: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func _allow(ai: Node, ids: Array) -> void:
	ai.training.allowed_actions.clear()
	for id in ids:
		ai.training.allowed_actions.append(load("res://enemy_actions/%s.tres" % id))

func _fire_frames(ai: Node, frames: int, visible: bool) -> void:
	for frame in range(frames):
		await physics_frame
		if ai.current_suppression.is_active():
			ai.current_suppression.step(1.0 / 60.0, visible)
			ai.actor.face_direction(ai.current_suppression.aim_point - ai.actor.global_position, 1.0 / 60.0)
		ai.tactics.update_shooting(1.0 / 60.0, visible, false)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
