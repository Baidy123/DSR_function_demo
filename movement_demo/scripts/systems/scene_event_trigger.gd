@tool
class_name SceneEventTrigger
extends Resource

const EventFilter = preload("res://scripts/systems/scene_event_filter.gd")

## 高级直连方式：Wave中相对该Wave，SceneFlowRule中相对SceneDirector；也可填/root/GameState。
## 简单配置优先使用SceneEvent节点+Event Nodes，这里用于不建立中间节点的原信号接线。
@export_node_path("Node") var source_path: NodePath
## 来源节点声明的信号名，不带括号，例如body_entered、interacted、flag_changed。
## 支持0～8个参数；名称、参数数目和过滤类型不合法会诊断，不静默忽略。
@export var signal_name: StringName = &""
## 所有过滤都必须满足；空数组接受该信号的所有通知。无参信号不要添加参数过滤。
@export var filters: Array[EventFilter] = []
