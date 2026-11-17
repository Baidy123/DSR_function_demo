extends InteractionEffect
class_name ChangeSceneEffect

## 通用场景切换效果：具体目标场景由交互物资源配置，不硬编码剧情或关卡编号。
@export_file("*.tscn") var scene_path: String = ""


func apply(context: InteractionContext) -> void:
	execute(context)

func execute(context: InteractionContext) -> Dictionary:
	if scene_path.is_empty(): return {"status": &"failed", "reason": &"missing_scene_path"}
	var parameters := {"mode": &"plain"}
	if is_instance_valid(context.host) and context.host.has_method("transition_parameters"):
		parameters = context.host.transition_parameters(context.player)
	parameters["path"] = scene_path
	parameters["return_control_on_failure"] = true
	var request = context.request_action(&"transition", {"parameters": parameters})
	if request == null: return {"status": &"failed", "reason": &"missing_director"}
	return await request.wait_result()
