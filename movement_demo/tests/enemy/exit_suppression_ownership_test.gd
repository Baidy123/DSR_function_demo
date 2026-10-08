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
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", true)
	actor.global_position = Vector3(24, 0, -2)
	player.global_position = Vector3(18, 0, -7)
	for region in get_nodes_in_group("cover_region"):
		region.collision_layer = 0
		region.remove_from_group("cover_region")
	var cover = _cover(ai, Vector3(21, 1.1, -2), Vector3(0.6, 2.2, 3))
	var known := Vector3(20, 0, -2)
	await _settle()
	var selection = ai.cover_selection
	var geometry: Dictionary = selection.suppression_geometry(known)
	check(geometry.get("body") == cover and not geometry.get("first", []).is_empty() and not geometry.get("second", []).is_empty(), "单一真实遮挡归属仍保留两端出口")
	var near = _cover(ai, Vector3(20, 1.1, -2.6), Vector3(0.3, 2.2, 0.3))
	await _settle()
	geometry = selection.suppression_geometry(known)
	check(geometry.get("body") == cover, "更靠近记忆点的侧面邻墙不能替代实际遮挡墙")
	var snapshot: Dictionary = geometry.duplicate(true)
	player.global_position = Vector3(29, 0, 8)
	await _settle()
	geometry = selection.suppression_geometry(known)
	check(geometry == snapshot, "移动隐藏玩家不改变冻结线索的掩体归属和出口")
	near.collision_layer = 0
	var clear_memory := Vector3(21.6, 0, -4.1)
	check(selection.has_clear_line(actor.get_shot_origin(), clear_memory + Vector3.UP * 0.15), "邻墙端部案例的冻结点确实没有静态遮挡")
	check(selection.suppression_geometry(clear_memory).is_empty(), "仅靠近可绕端部而无实际遮挡证据时不认领掩体")
	var exits = ai.actions[&"exit_suppression"]
	var ordinary = ai.actions[&"suppression"]
	_memory(ai, clear_memory)
	check(exits.collect_candidates(false).is_empty() and not ordinary.collect_candidates(false).is_empty(), "归属未知时退出出口候选但保留原点压制")
	var stacked = _cover(ai, Vector3(20.55, 1.1, -2), Vector3(0.2, 2.2, 3))
	await _settle()
	check(selection.suppression_geometry(known).is_empty(), "前后两面墙同时遮挡冻结点时拒绝猜测归属")
	_memory(ai, known)
	check(exits.collect_candidates(false).is_empty(), "多墙歧义不能进入出口压制候选")
	stacked.collision_layer = 0
	await _settle()
	_memory(ai, known)
	exits.on_target_lost()
	check(exits.is_active() and exits.target_cover == cover, "消除歧义后执行锁定实际归属墙")
	stacked.collision_layer = 1
	await _settle()
	exits.step(1.0 / 60.0, false)
	check(not exits.is_active(), "执行中归属变为歧义便结束而不换压邻墙")
	stacked.collision_layer = 0
	# 同一墙两端都被实际身体障碍封死，不得从邻墙借出口。
	var first = _obstacle(ai.navigation_region, Vector3(21, 1.1, -4.1), Vector3(1.5, 2.2, 1.0))
	var second = _obstacle(ai.navigation_region, Vector3(21, 1.1, 0.1), Vector3(1.5, 2.2, 1.0))
	await _settle()
	geometry = selection.suppression_geometry(known)
	check(geometry.get("body") == cover and geometry.get("first", []).is_empty() and geometry.get("second", []).is_empty(), "已确认墙出口封堵仍保留原归属并报告零可射出口")
	_memory(ai, known)
	check(exits.collect_candidates(false).is_empty(), "原归属墙全部出口失效时不提供出口方案")
	first.collision_layer = 0
	second.collision_layer = 0
	cover.collision_layer = 0
	var low = _cover(ai, Vector3(21, 0.5, -2), Vector3(0.6, 1.0, 3))
	low.low_cover = true
	actor.global_position = Vector3(22, 0, -2)
	known = Vector3(20, 0, -2)
	await _settle()
	check(selection.has_clear_line(actor.get_eye_position(), actor.get_posture_eye_position(false, known)), "低墙案例的站立眼位射线确实越过墙顶")
	geometry = selection.suppression_geometry(known)
	check(geometry.get("body") == low and not geometry.get("first", []).is_empty() and not geometry.get("second", []).is_empty(), "脚腿遮挡可确认低墙并保留真实可射出口")
	_memory(ai, known)
	check(not exits.collect_candidates(false).is_empty(), "可靠低墙归属仍允许出口压制参与原Utility")
	check(selection.suppression_geometry(Vector3(17, 0, -2)).is_empty(), "遮挡墙离冻结点超出原推断范围时拒绝归属")
	print("Exit suppression ownership: %d/%d passed" % [checks - failures, checks])
	scene.queue_free()
	await process_frame
	quit(1 if failures else 0)

func _memory(ai, point: Vector3) -> void:
	ai.context.sees_player = false
	ai.context.is_alerted = true
	ai.context.has_visual_memory = true
	ai.context.last_known_position = point
	ai.context.last_seen_position = point
	ai.context.publish_suppression_evidence(&"visual_loss", point)

func _cover(ai, position: Vector3, size: Vector3):
	var cover = load("res://scenes/world/cover.tscn").instantiate()
	ai.navigation_region.add_child(cover)
	cover.global_position = position
	var shape: CollisionShape3D = cover.get_node("CollisionShape3D")
	shape.shape = shape.shape.duplicate()
	shape.shape.size = size
	return cover

func _obstacle(parent: Node3D, position: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collision.shape = box
	body.add_child(collision)
	parent.add_child(body)
	body.global_position = position
	return body

func _settle() -> void:
	for frame in 3: await physics_frame

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
