extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var profile := EnemyTrainingProfile.new()
	var properties: Array = profile.selection.get_property_list().map(func(item): return item.name)
	check(properties.has("cover_inference_distance"), "掩体推断距离属于共享选位配置")
	if properties.has("cover_inference_distance"):
		profile.set_setting(&"selection", &"cover_inference_distance", 2.35)
		check(ResourceSaver.save(profile, "res://logs/shared_geometry_training.tres") == OK, "共享几何参数可保存")
		var saved = ResourceLoader.load("res://logs/shared_geometry_training.tres", "", ResourceLoader.CACHE_MODE_IGNORE)
		check(is_equal_approx(saved.setting(&"selection", &"cover_inference_distance"), 2.35) and saved.selection.overridden.has("cover_inference_distance"), "共享参数重载保留数值及显式覆盖")
		check(not saved.exit_suppression.get_property_list().any(func(item): return item.name == "cover_inference_distance"), "出口配置不再提供重复调参入口")
		var scene = load("res://scenes/main.tscn").instantiate()
		root.add_child(scene)
		current_scene = scene
		var actor = scene.get_node("Arena/Enemy")
		var ai = actor.get_node("AI")
		var player = scene.get_node("Player")
		ai.set_physics_process(false)
		player.set_physics_process(false)
		preload("res://tests/enemy/enemy_fire_fixture.gd").set_training_action(ai, &"exit_suppression", true)
		for body in ai.navigation_region.get_node("Environment").get_children():
			if body is StaticBody3D and body.name != "Floor": body.collision_layer = 0
		for old in get_nodes_in_group("cover_region"):
			old.collision_layer = 0
			old.remove_from_group("cover_region")
		var cover = load("res://scenes/world/cover.tscn").instantiate()
		ai.navigation_region.add_child(cover)
		cover.global_position = Vector3(22, 1.1, -2)
		cover.get_node("CollisionShape3D").shape = BoxShape3D.new()
		cover.get_node("CollisionShape3D").shape.size = Vector3(0.8, 2.2, 6)
		actor.global_position = Vector3(23.2, 0, -4.7)
		player.global_position = Vector3(20.8, 0, -2)
		ai.has_visual_memory = true
		ai.is_alerted = true
		ai.last_seen_position = Vector3(22.8, 0, -5.5)
		ai.last_known_position = ai.last_seen_position
		for index in 4:
			await physics_frame
			await process_frame
		ai.training.profile.set_setting(&"selection", &"cover_inference_distance", 0.1)
		var ordinary = ai.actions[&"suppression"]
		var exits = ai.actions[&"exit_suppression"]
		check(is_zero_approx(ordinary.information_retention()) and not exits.utility_available(), "较小共享半径同时排除两种压制的远处掩体推断")
		ai.training.profile.set_setting(&"selection", &"cover_inference_distance", 2.35)
		var retained: float = ordinary.information_retention()
		check(retained > 0.0 and exits.utility_available(), "调大共享半径同时恢复两种压制的几何收益")
		ai.training.profile.selected_tactics.assign([&"suppression"])
		ai.training.profile.exit_suppression = null
		ai.refresh_configuration(true)
		check(not ai.actions.has(&"exit_suppression") and is_equal_approx(ordinary.information_retention(), retained), "删除出口动作及其参数资源不影响普通压制几何评分")
		scene.queue_free()
		await process_frame
		await process_frame
	print("Shared geometry settings: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
