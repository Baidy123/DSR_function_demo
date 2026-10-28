@tool
class_name SceneFlowAction
extends Resource

enum Kind { WAIT, REQUEST_WAVE, WAIT_WAVE_CLEARED, PRESENT_TARGET, GUIDE, COMPLETE_SCENE, RESTART, CHANGE_SCENE, CALL_METHOD, WAIT_SIGNAL }
## 先选动作类型，再填出现的参数。配置教程：docs/gameplay/SCENE_DIRECTOR.md。
## REQUEST_WAVE 等真实生成才继续；PRESENT_TARGET 只看指定节点；CALL_METHOD 调用已有公开接口。
@export var kind: Kind = Kind.WAIT:
	set(value):
		kind = value
		notify_property_list_changed()
## 路径相对 SceneDirector。Wave2 写 Wave2；关卡根的标记写 ../CameraPoints/Reinforcement。
## 请求/等待波次选 Wave 节点；镜头选 Marker3D/Node3D；引导和公开动作选对应提供者。
@export_node_path("Node") var target_path: NodePath
## WAIT 动作的等待秒数。普通暂停、镜头和结果界面期间不累计。
@export_range(0.0, 3600.0, 0.05) var seconds := 0.0
## REQUEST_WAVE 专用：先申请出场，真实生成后才冻结并展示，不会先看空出生点。
@export var present_spawn := false
## REQUEST_WAVE 镜头的手动目标，相对 SceneDirector；留空则使用该 Wave 自己绑定的目标。
## 绑定 Marker3D 或已有 Node3D，表示画面中心。两处均未绑定时跳过镜头并报告原因。
@export_node_path("Node3D") var presentation_target_path: NodePath
## 移动到所选目标的秒数。
@export_range(0.0, 10.0, 0.05) var move_seconds := 0.6
## 在目标处停留的秒数。
@export_range(0.0, 30.0, 0.05) var hold_seconds := 1.2
## 返回玩家最新视野的秒数。
@export_range(0.0, 10.0, 0.05) var return_seconds := 0.6
## 正交展示范围，0保留玩家当前 Size；不改变原玩家相机。
@export_range(0.0, 100.0, 0.1) var camera_size := 0.0
## 临时说明开启；未来允许走动的互动教程可关闭。提供者须有 begin/cancel 和无参 finished。
@export var guide_pauses_world := true
## CHANGE_SCENE 的目标场景。加载失败保留暂停与重试界面，不自动跳到下一关。
@export_file("*.tscn") var scene_path := ""
## CALL_METHOD 的公开方法名，例如 open；不用括号，不允许以下划线开头的私有方法。
@export var method: StringName
## 按方法声明顺序填写参数；数量和类型会检查。无参数的方法留空。
@export var arguments: Array = []
## WAIT_SIGNAL 必填；CALL_METHOD 可选。先接完成通知再调用，不会漏掉同步发出的信号。
## 没有完成信号时 CALL_METHOD 只表示调用返回，不表示门的动画或其他异步任务已经结束。
@export var completed_trigger: SceneEventTrigger

func camera_options() -> Dictionary:
	return {"move_seconds": move_seconds, "hold_seconds": hold_seconds, "return_seconds": return_seconds, "size": camera_size}

func _validate_property(property: Dictionary) -> void:
	var relevant: Array[String] = ["kind"]
	match kind:
		Kind.WAIT: relevant.append("seconds")
		Kind.REQUEST_WAVE: relevant.append_array(["target_path", "present_spawn", "presentation_target_path", "move_seconds", "hold_seconds", "return_seconds", "camera_size"])
		Kind.WAIT_WAVE_CLEARED: relevant.append("target_path")
		Kind.PRESENT_TARGET: relevant.append_array(["target_path", "move_seconds", "hold_seconds", "return_seconds", "camera_size"])
		Kind.GUIDE: relevant.append_array(["target_path", "guide_pauses_world"])
		Kind.CHANGE_SCENE: relevant.append("scene_path")
		Kind.CALL_METHOD: relevant.append_array(["target_path", "method", "arguments", "completed_trigger"])
		Kind.WAIT_SIGNAL: relevant.append("completed_trigger")
	var fields := ["target_path", "seconds", "present_spawn", "presentation_target_path", "move_seconds", "hold_seconds", "return_seconds", "camera_size", "guide_pauses_world", "scene_path", "method", "arguments", "completed_trigger"]
	if property.name in fields and property.name not in relevant: property.usage &= ~PROPERTY_USAGE_EDITOR
