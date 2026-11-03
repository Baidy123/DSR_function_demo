extends InteractionEffect
class_name ChangeSceneEffect

const SceneTransition = preload("res://scripts/systems/scene_transition.gd")

## 通用场景切换效果：具体目标场景由交互物资源配置，不硬编码剧情或关卡编号。
@export_file("*.tscn") var scene_path: String = ""


func apply(context: InteractionContext) -> void:
	var tree := context.tree()
	if scene_path.is_empty() or tree == null:
		push_warning("ChangeSceneEffect 缺少目标场景或有效场景树，已跳过")
		return
	_change_scene.call_deferred(tree, scene_path)


func _change_scene(tree: SceneTree, path: String) -> void:
	var result: Error = await SceneTransition.change_scene(tree, path)
	if result != OK:
		push_error("无法切换到 %s：%s" % [path, error_string(result)])
