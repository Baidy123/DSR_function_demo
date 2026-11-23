extends InteractionEffect
class_name CallMethodEffect

## 通用出口：对场景里指定节点调用一个方法。
## 交互物因此不需要知道门、生成器或机关的存在，具体目标由场景配置决定。
@export var target_path: NodePath
## 目标方法名，例如 open / set_open / set_active。
@export var method: StringName = &""
## 是否带一个布尔参数；关掉则调用无参方法。
@export var use_argument: bool = true
@export var bool_argument: bool = true


func apply(context: InteractionContext) -> void:
	execute(context)

func execute(context: InteractionContext) -> Dictionary:
	var target := context.host.get_node_or_null(target_path) if is_instance_valid(context.host) else null
	var args: Array = [bool_argument] if use_argument else []
	var request = context.request_action(&"script", {"target": target,
		"parameters": {"mode": &"method", "method": method, "arguments": args}})
	if request == null: return {"status": &"failed", "reason": &"missing_director"}
	return await request.wait_result()
