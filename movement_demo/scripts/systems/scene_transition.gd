extends RefCounted

## 所有正式场景切换的统一入口。场景节点会被引擎释放，但 GL Compatibility
## 可能保留上一场景的 World3D 环境参数；切换前显式恢复中性环境。


static func change_scene(tree: SceneTree, scene_path: String) -> Error:
	if tree == null:
		return ERR_UNAVAILABLE
	_restore_neutral_environment(tree)
	# 让中性环境先提交到当前 World3D，再释放旧场景。
	await tree.process_frame
	return tree.change_scene_to_file(scene_path)


static func reload_scene(tree: SceneTree) -> Error:
	if tree == null:
		return ERR_UNAVAILABLE
	_restore_neutral_environment(tree)
	await tree.process_frame
	return tree.reload_current_scene()


static func _restore_neutral_environment(tree: SceneTree) -> void:
	var world := tree.root.get_world_3d()
	if world == null:
		return
	var neutral := Environment.new()
	neutral.background_mode = Environment.BG_CLEAR_COLOR
	neutral.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	neutral.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	world.environment = neutral
	world.fallback_environment = neutral
