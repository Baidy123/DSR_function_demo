extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	seed(28)
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var ai = scene.get_node("Arena/Enemy/AI")
	var enemy = ai.actor
	var player = ai.player
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	ai.search.tracking_cheat_enabled = false
	ai.cover_selection.debug_cover_selection = false
	for id: StringName in [&"suppression", &"exit_suppression"]:
		# 保留真实场景武器/其他权限，只切换本轮待验证的压制权限。
		preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai,&"exit_suppression",id == &"exit_suppression")
		ai.reset_actions()
		enemy.cancel_reload()
		enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
		enemy.global_position = Vector3(22,0,3.7)
		ai.last_seen_position = Vector3(24.5,0,1.5)
		player.global_position = ai.last_seen_position
		ai.last_known_position = ai.last_seen_position
		ai.has_visual_memory = true
		ai.is_alerted = true
		ai.was_seeing_player = false
		enemy.look_at(ai.last_seen_position)
		for f in range(10): await physics_frame
		ai._physics_process(1.0 / 60.0)
		check(ai.was_seeing_player, "%s：先通过真实视线取得目击" % id)
		player.global_position = Vector3(26.3,0,3.7)
		for f in range(2): await physics_frame
		check(not ai.perception.can_see_player(), "%s：玩家实际被CoverF挡住" % id)
		ai._physics_process(1.0 / 60.0)
		print("DISPATCH ",id," selected=",ai.utility_current.get("id")," options=",ai.utility_options.map(func(o):return [o.id,o.cost]))
		check(ai.utility_current.get("id") == id, "%s：从真实失视事件经Utility自动选中" % id)
		var action = ai.actions[id]
		var started: bool = action.is_active()
		var duration: float = action.remaining
		var elapsed := 0.0
		var shots: int = enemy.shot_count
		var shot_sides := {}
		var memory: Vector3 = ai.last_seen_position
		var frozen_center: Vector3 = action.target_center
		for f in range(360):
			if not action.is_active(): break
			var side: int = action._next_exit if id == &"exit_suppression" else 0
			var before: int = enemy.shot_count
			await physics_frame
			# 墙后换位置不能更新压制目标；仍处于实体掩体背面。
			if f == 30: player.global_position.z += 0.2
			ai._physics_process(1.0 / 60.0)
			elapsed += 1.0 / 60.0
			if enemy.shot_count > before: shot_sides[side] = true
			if "--capture" in OS.get_cmdline_user_args() and f == 100:
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png("res://logs/%s-dispatch.png" % id)
		check(started and elapsed >= duration - 0.1, "%s：有射界有弹时完成本次压制，不被搜索提前取消" % id)
		check(enemy.shot_count - shots >= 3, "%s：失视期间实际连续射击至少三枪" % id)
		if id == &"exit_suppression": check(shot_sides.size() == 2, "出口压制实际向两端开火")
		check(ai.last_seen_position == memory and action.target_center == frozen_center, "%s：隐藏玩家移动不更新最后目击和压制中心" % id)
		for f in range(5):
			await physics_frame
			ai._physics_process(1.0 / 60.0)
		check(ai.utility_current.get("id") == &"search", "%s：正常结束后交回调查" % id)
		print("DISPATCH RESULT ",id," duration=",duration," elapsed=",elapsed," shots=",enemy.shot_count-shots," sides=",shot_sides.keys())
	# 搜索一旦接管，过期的失视机会不能等偶发提示/绕墙后再触发旧压制。
	ai.reset_actions()
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.utility_suppression_pending = true
	ai._start_utility_option({"id":&"search","destination":{},"cost":0.0},false)
	check(not ai.utility_suppression_pending, "调查接管时消费未采用的失视压制机会")
	print("SUPPRESSION DISPATCH: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
