extends SceneTree

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
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(actor)
	ai.cover_selection.debug_cover_selection = false
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(25, 0, -2)
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	var threat := Vector3(26, 0, -2)
	var crossing := PackedVector3Array([actor.global_position, Vector3(28, 0, -2)])
	check(not ai.context.spatial.cover_route_safe(crossing, threat), "掩体路径穿过已知玩家近身区域时淘汰")
	var away := PackedVector3Array([actor.global_position, Vector3(22, 0, -2)])
	check(ai.context.spatial.cover_route_safe(away, threat), "远离威胁的退路仍可用")
	check(ai.context.spatial.cover_route_safe(away, Vector3(24.8, 0, -2)), "已经被贴近时允许向外脱离")
	for frame in range(5): await physics_frame
	check(ai.context.is_position_free(player.global_position), "远程候选查询不借碰撞探测隐藏玩家")
	check(not ai.context.is_position_free(player.global_position, true), "执行时短距离避障识别真实玩家身体")
	# 临时狭道迫使真实胶囊碰撞，不能从两侧绕过；不修改场景或导航资源。
	for side in [-1.0, 1.0]:
		var wall := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(3.0, 2.0, 0.1)
		wall.add_child(shape)
		scene.add_child(wall)
		wall.global_position = Vector3(25, 1, -2 + side * 0.65)
	var shelter = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(shelter)
	shelter.global_position = Vector3(26.5, 1.1, -2)
	var collision = shelter.get_node("CollisionShape3D")
	collision.shape = collision.shape.duplicate()
	collision.shape.size = Vector3(0.2, 2.2, 4.0)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_known_position = Vector3(28, 0, -2)
	ai.last_seen_position = ai.last_known_position
	var destination := {"hide": Vector3(25.85, 0, -2), "body": shelter}
	for frame in range(5): await physics_frame
	check(ai.context.spatial.cover_valid(destination), "阻挡测试的掩体和导航目的地真实有效")
	ai.actions[&"cover"].transfer.cover_max_detour_retries = 1
	ai._start_utility_option({"id": &"cover", "destination": destination, "cost": 0.0}, false)
	var collided := false
	for frame in range(480):
		await physics_frame
		if ai.current_action == null: break
		var output: Dictionary = ai.current_action.tick(1.0 / 60.0, false)
		actor.move_character(output.direction, 1.0 / 60.0, output.multiplier)
		for index in actor.get_slide_collision_count():
			collided = collided or actor.get_slide_collision(index).get_collider() == player
		if not output.running: ai._cancel_utility_execution(&"finished")
	check(collided, "玩家真实身体阻挡跑向掩体")
	check(ai.current_action == null, "持续受阻后在有限时间内退出转移")
	check(ai.context.is_utility_destination_blocked(destination.hide), "失败掩体暂时排除，避免重选并清空卡住进度")
	for frame in range(20):
		await physics_frame
		preload("res://tests/enemy/enemy_fire_fixture.gd").advance_evaluation(ai, false)
	var options: Array = ai.action_selector.assess_options(ai, false)
	check(not options.any(func(o): return o.destination.get("hide", Vector3.INF).distance_to(destination.hide) < 0.75), "所有掩体和换弹方案都遵守失败位置排除")
	var peek := Vector3(24, 0, -4)
	var transfer = ai.actions[&"cover"].transfer
	transfer.start_utility_peek({"hide": destination.hide, "position": peek, "body": shelter}, ai.last_known_position)
	transfer.step(0.01, true)
	check(not transfer.is_active() and not ai.context.is_utility_destination_blocked(peek), "探头重新发现玩家属于成功，不错误封禁可用点")
	# 调查观察段结束仍不能被同一份旧威胁拉回躲藏；新受击可以打断。
	var search = ai.actions[&"search"]
	search._begin_segment()
	search._segment_boundary_pending = true
	check(not search.can_interrupt({"conceals": true}, false), "没有新危险时搜索段边界不折返躲藏")
	check(search.can_interrupt({"conceals": true, "urgent": true}, false), "换弹仍可中断调查")
	search.on_event(&"damage", {})
	check(search.can_interrupt({"conceals": true}, false), "新受击允许重新选择掩体")
	print("COVER TACTICAL SAFETY: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
