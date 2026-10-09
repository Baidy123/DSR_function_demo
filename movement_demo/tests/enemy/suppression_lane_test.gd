extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var ai = scene.get_node("Arena/Enemy/AI")
	var enemy = ai.actor
	var player = ai.player
	ai.set_physics_process(false)
	player.set_physics_process(false)
	preload("res://tests/enemy/enemy_fire_fixture.gd").configure_timing(enemy)
	player.get_node("Health").debug_invincible = true
	ai.actions[&"search"].tracking_cheat_enabled = false
	ai.cover_selection.debug_cover_selection = false
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai,&"suppression",true)
	enemy.global_position = Vector3(24,0,-2)
	player.global_position = Vector3(21,0,-2)
	enemy.look_at(player.global_position)
	ai.is_alerted = true
	ai.has_visual_memory = true
	ai.last_seen_position = player.global_position
	ai.last_known_position = player.global_position
	var action = ai.actions[&"suppression"]
	var wall := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.2,4,10)
	collision.shape = box
	wall.add_child(collision)
	scene.add_child(wall)
	wall.global_position = Vector3(22,1,-2)
	for f in range(10): await physics_frame
	check(not ai.cover_selection.has_clear_line(enemy.get_shot_origin(),ai.last_seen_position+Vector3.UP*0.8), "目标区域被远处掩体挡住")
	check(not action.utility_available(), "枪口通畅但完整枪线被硬墙挡住仍拒绝压制")
	ai.was_seeing_player = true
	ai._physics_process(1.0/60.0)
	check(ai.utility_current.get("id") != &"suppression", "远处硬墙阻止Utility选择无效压制")
	var shots: int = enemy.shot_count
	var wall_hits := 0
	for f in range(150):
		await physics_frame
		var before: int = enemy.shot_count
		ai._physics_process(1.0/60.0)
		if enemy.shot_count > before and enemy.last_shot_collider == wall: wall_hits += 1
	check(enemy.shot_count == shots and wall_hits == 0, "正常Utility不浪费子弹向完整硬墙盲射")
	enemy.global_position = Vector3(24,0,-2)
	wall.global_position = Vector3(23.75,1,-2)
	for f in range(3): await physics_frame
	check(not action.utility_available(), "枪口前近墙堵住时拒绝压制候选")
	shots = enemy.shot_count
	for f in range(15):
		await physics_frame
		ai._physics_process(1.0/60.0)
	check(enemy.shot_count == shots and not action.is_active(), "枪口后来被堵也停止实际压制")
	wall.queue_free()
	for f in range(3): await physics_frame
	# 用户现场：20度最大散布碰墙，但中心射线仍有空隙。
	ai.reset_actions()
	enemy.global_position = Vector3(15.281994,0.0009416,1.8143523)
	ai.last_seen_position = Vector3(15.788537,0.0008406,4.672626)
	ai.last_known_position = ai.last_seen_position
	ai.context.last_seen_aim_position = ai.last_seen_position + Vector3.UP * 0.8 # Explicit geometry fixture sample.
	ai.context.publish_suppression_evidence(&"visual_loss", ai.last_seen_position)
	ai.is_alerted = true
	ai.has_visual_memory = true
	enemy.cancel_reload()
	enemy.ammo.magazine_rounds = enemy.weapon.magazine_capacity
	for f in range(3): await physics_frame
	check(action.utility_available(), "用户现场普通压制不再被最大散布整体否决")
	preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai,&"suppression",true)
	var exits = ai.actions[&"suppression"]
	check(exits.preview_candidate(&"exit_sweep").is_empty(), "现场线索仅在墙端附近且无可靠遮挡归属时不误压出口")
	# 单端执行仍在同一原场景验证，但新线索必须真实处于 CoverA 背侧。
	var actual_cover = ai.navigation_region.get_node("Environment/CoverA")
	var actual_box: CollisionShape3D = actual_cover.get_node("CollisionShape3D")
	var half: Vector3 = actual_box.shape.size * 0.5
	ai.last_seen_position = actual_box.to_global(Vector3(half.x + 0.6, -half.y, 0.0))
	ai.last_known_position = ai.last_seen_position
	ai.context.publish_suppression_evidence(&"visual_loss", ai.last_seen_position)
	check(ai.cover_selection.confirmed_suppression_cover(ai.last_seen_position) == actual_cover and exits.preview_candidate(&"exit_sweep").is_empty(), "明确遮挡归属也不能恢复已移除的出口方案")
	# 横墙只隔住负Z端；通过真实碰撞制造单端，而非只清空候选数组。
	var end_wall := StaticBody3D.new()
	var end_collision := CollisionShape3D.new()
	var end_box := BoxShape3D.new()
	end_box.size = Vector3(20,4,0.2)
	end_collision.shape = end_box
	end_wall.add_child(end_collision)
	scene.add_child(end_wall)
	end_wall.global_position = Vector3(15,1,0)
	for f in range(3): await physics_frame
	var geometry: Dictionary = ai.cover_selection.suppression_geometry(ai.last_seen_position)
	check(not geometry.is_empty() and geometry.first.is_empty() and not geometry.second.is_empty(), "实体墙挡住一端，共享几何保留另一端真实通路")
	check(not exits.begin({"plan": &"exit_sweep"}, false) and not exits.is_active(), "单端通路不能启动已移除的出口压制")
	check(exits.preview_candidate(&"exit_left").is_empty() and exits.preview_candidate(&"exit_right").is_empty(), "多人单侧出口变体也保持停用")
	print("SUPPRESSION LANE: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ",label)
