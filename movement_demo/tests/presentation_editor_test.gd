extends SceneTree

var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1


func run() -> void:
	for i in 8: await process_frame
	var original = load("res://scenes/world/cover.tscn").instantiate(PackedScene.GEN_EDIT_STATE_MAIN)
	root.add_child(original)
	var view = original.get_node("Presentation")
	view.model_scene = load("res://scenes/presentation/example_model.tscn")
	view.animation_profile = load("res://resources/animations/example_actor.tres")
	view.position = Vector3(0.2, -1.1, 0)
	for i in 4: await process_frame
	check(view.has_model(), "编辑器显示模型预览")
	check(original.get_node("Mesh").visible, "预览不污染原占位外观的保存状态")
	var packed := PackedScene.new()
	check(packed.pack(original) == OK, "带接口的掩体可保存")
	check(ResourceSaver.save(packed, "res://logs/presentation_cover_saved.tscn") == OK, "掩体配置资源落盘")
	var content := FileAccess.get_file_as_string("res://logs/presentation_cover_saved.tscn")
	check(not content.contains("_ModelPivot"), "内部预览实例不写入场景")
	var copy = load("res://logs/presentation_cover_saved.tscn").instantiate()
	check(copy.get_node("Presentation").position.is_equal_approx(view.position), "模型偏移保存重载")
	check(copy.get_node("Presentation").model_scene != null, "模型资源引用保存重载")
	check(copy.get_node("CollisionShape3D").shape.size.is_equal_approx(original.get_node("CollisionShape3D").shape.size), "模型不改变碰撞尺寸")
	copy.free()
	original.queue_free()
	var old_suite = load("res://tests/test_cover_instance_save.gd").new()
	old_suite.test_cover_instance_save()
	check(not old_suite._failed, "原掩体实例保存专项7项断言")
	for i in 4: await process_frame
	print("Presentation editor failures: ", failures)
	quit(1 if failures else 0)
