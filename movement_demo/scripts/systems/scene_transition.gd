extends RefCounted

## 所有正式场景切换的统一入口。场景节点会被引擎释放，但 GL Compatibility
## 可能保留上一场景的 World3D 环境参数；切换前显式恢复中性环境。


static func change_scene(tree: SceneTree, scene_path: String, guard: Callable = Callable(), accepted: Callable = Callable()) -> Error:
	return await _load_scene(tree, scene_path, false, guard, accepted)

static func reload_scene(tree: SceneTree, guard: Callable = Callable(), accepted: Callable = Callable()) -> Error:
	return await _load_scene(tree, "", true, guard, accepted)

static func _load_scene(tree: SceneTree, scene_path: String, reload_current: bool, guard: Callable, accepted: Callable) -> Error:
	if tree == null:
		return ERR_UNAVAILABLE
	var original_scene := tree.current_scene
	var world := tree.root.get_world_3d()
	var environment: Environment = world.environment if world != null else null
	var fallback: Environment = world.fallback_environment if world != null else null
	_restore_neutral_environment(tree)
	# 让中性环境先提交到当前 World3D，再释放旧场景。
	await tree.process_frame
	var result: Error = ERR_SKIP
	if not guard.is_valid() or guard.call():
		result = tree.reload_current_scene() if reload_current else tree.change_scene_to_file(scene_path)
	if result == OK:
		if accepted.is_valid(): accepted.call()
	elif world != null and tree.current_scene == original_scene:
		world.environment = environment
		world.fallback_environment = fallback
	return result


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
