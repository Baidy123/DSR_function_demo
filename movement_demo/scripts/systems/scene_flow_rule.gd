class_name SceneFlowRule
extends Resource

enum Scope { SCENE, REGION }
enum Combination { ANY, ALL }
## 给规则起可辨认的名字，例如“打开终端后叫增援”；只用于诊断，不是事件ID。
@export var label := ""
## SCENE：本场一次，离区不重播；REGION：每轮区域战斗一次，离区复位后可再次触发。
@export var scope: Scope = Scope.SCENE
## 推荐的简单接法：选择场景中 SceneEvent 节点，相对 SceneDirector 填路径。
## 例 ../SceneEvents/CallReinforcements；监听其标准 triggered 信号。也可选自带此信号的节点。
## 多个节点按 Combination 组合；可与下方高级 Triggers 一起使用。
@export_node_path("Node") var event_nodes: Array[NodePath] = []
## 添加元素→新建 SceneEventTrigger。路径相对 SceneDirector，不相对资源文件。
## 留空：场景准备好后自动执行一次；有事件：记住本轮收到的事实，再在调度边界开始动作。
@export var triggers: Array[SceneEventTrigger] = []
## ANY 等任意一个事件，ALL 等所有事件都发生；不是每帧轮询信号。
@export var combination: Combination = Combination.ANY
## 按数组顺序执行；添加元素→新建 SceneFlowAction。不同规则可以各自等待，不互相阻塞。
@export var actions: Array[SceneFlowAction] = []
@export_group("可选当前状态复核")
## 可选查询对象，相对 SceneDirector；下面的 Condition Method 留空时不检查。
@export var condition_target: NodePath
## 返回 bool 的公开查询方法。事件已满足但返回 false 时继续等待，例如检查旗标仍有效。
@export var condition_method: StringName
## 按查询方法签名填写；例如 has_flag(flag: StringName) 的第0项填写 StringName 旗标ID。
@export var condition_arguments: Array = []

func event_configuration() -> Array[SceneEventTrigger]:
	var result: Array[SceneEventTrigger] = []
	for path in event_nodes:
		var event := SceneEventTrigger.new()
		event.source_path = path
		event.signal_name = &"triggered"
		result.append(event)
	result.append_array(triggers)
	return result
