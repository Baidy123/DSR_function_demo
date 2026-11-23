extends RefCounted

## 波次回收前只保留静态外观快照，没有身体、脚本、导航、动画播放器或信号。
static func create(actor: Node3D, parent: Node3D) -> Node3D:
	var corpse := Node3D.new()
	corpse.name = "Corpse"
	corpse.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	parent.add_child(corpse)
	corpse.global_transform = actor.global_transform
	var presentation = actor.get_node_or_null("Presentation")
	if presentation != null and presentation.has_model():
		_copy_meshes(presentation, corpse)
	else:
		var body := actor.get_node_or_null("Body") as MeshInstance3D
		if body != null:
			var visual := _copy_mesh(body, corpse)
			# 最后一人的倒地往往还没结束。接续当前位置和剩余时间，不能直接跳到终点。
			visual.transform = body.transform
			if actor.death_tween != null and actor.death_tween.is_valid() and actor.death_tween.is_running():
				var remaining: float = maxf(0.001, 0.3 - actor.death_tween.get_total_elapsed_time())
				var fall := visual.create_tween().set_parallel(true)
				fall.tween_property(visual, "rotation:x", PI * 0.5, remaining)
				fall.tween_property(visual, "position:y", 0.35, remaining)
	if corpse.get_child_count() == 0:
		corpse.queue_free()
		return null
	return corpse

static func _copy_meshes(source: Node, corpse: Node3D) -> void:
	if source is MeshInstance3D and source.is_visible_in_tree() and source.mesh != null:
		_copy_mesh(source, corpse)
	for child in source.get_children(true): _copy_meshes(child, corpse)

static func _copy_mesh(source: MeshInstance3D, corpse: Node3D) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = source.mesh
	# 真正的蒙皮模型才读取当前姿态；普通占位胶囊直接复用几何资源。
	if source.get_skin_reference() != null:
		var baked := source.bake_mesh_from_current_skeleton_pose()
		if baked != null: visual.mesh = baked
	elif source.get_blend_shape_count() > 0:
		var baked := source.bake_mesh_from_current_blend_shape_mix()
		if baked != null: visual.mesh = baked
	visual.material_override = source.material_override
	visual.material_overlay = source.material_overlay
	visual.layers = source.layers
	visual.cast_shadow = source.cast_shadow
	for surface in source.mesh.get_surface_count():
		visual.set_surface_override_material(surface, source.get_active_material(surface))
	corpse.add_child(visual)
	visual.global_transform = source.global_transform
	return visual
