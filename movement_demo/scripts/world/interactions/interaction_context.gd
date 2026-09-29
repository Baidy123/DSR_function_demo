extends RefCounted
class_name InteractionContext

## 一次交互的上下文。效果只使用这里注入的引用，不自己去查找全局节点，
## 因此交互物与效果都不依赖 GameState、DialogueUI 或任何具体系统。
## state 由 Interactable 通过可配置的 state_path 解析，可以是任意鸭子类型节点。

var host: Node
var player: Node3D
var state: Node


func _init(host_node: Node = null, player_node: Node3D = null, state_node: Node = null) -> void:
	host = host_node
	player = player_node
	state = state_node


func tree() -> SceneTree:
	return host.get_tree() if host != null and host.is_inside_tree() else null


## 鸭子类型检查，避免效果脚本引用具体状态类。
func state_supports(method: StringName) -> bool:
	return state != null and state.has_method(method)
