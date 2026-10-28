@tool
class_name SceneFlowAction
extends Resource

## 场景规则依次执行的动作类型。各动作需要的参数会随 Kind 自动显示。
enum Kind {
	## 等待 Seconds 秒后继续。普通暂停及演出镜头期间不累计等待时间。
	WAIT,
	## 请求 Target Path 指定的 Wave 出场，等真实生成成功后继续；可用 Present Spawn 展示增援。
	REQUEST_WAVE,
	## 等待 Target Path 指定的 Wave 全灭后继续；本动作不会请求该波出场。
	WAIT_WAVE_CLEARED,
	## 展示 Target Path 指定的 Marker3D/Node3D，暂停战斗，镜头返回后继续；不生成敌人。
	PRESENT_TARGET,
	## 启动 Target Path 指定的引导，调用 begin() 并等待 finished；Guide Pauses World 控制是否暂停。
	GUIDE,
	## 请求当前场景完成；必要镜头结束后显示已绑定的结果界面，同帧死亡优先，不自动切关。
	COMPLETE_SCENE,
	## 重载当前场景，从该场景的保存配置重新开始；加载失败保留暂停并允许重试。
	RESTART,
	## 切换到 Scene Path 指定的场景；加载失败重试原目标，不改用五关的下一关路径。
	CHANGE_SCENE,
	## 调用 Target Path 对象的公开 Method，传入 Arguments；可用 Completed Trigger 等待异步完成。
	CALL_METHOD,
	## 等待 Completed Trigger 指定的信号及过滤条件满足后继续；只等待，不主动调用目标方法。
	WAIT_SIGNAL
}
## 选择本步骤要做什么；下面只显示该类型需要填写的参数。[br]
## [b]WAIT（等待时间）[/b]：填写 Seconds，等待结束后执行下一步。[br]
## [b]REQUEST_WAVE（请求出场）[/b]：Target Path 选 Wave，等实际生成；Present Spawn 可附带出场镜头。[br]
## [b]WAIT_WAVE_CLEARED（等待清空）[/b]：Target Path 选 Wave，等它全灭；不会主动刷出这一波。[br]
## [b]PRESENT_TARGET（展示目标）[/b]：Target Path 选 Marker3D/Node3D，配置移动、停留、返回时间，返回后继续。[br]
## [b]GUIDE（启动引导）[/b]：Target Path 选引导节点，等待 finished；可选择是否暂停世界。[br]
## [b]COMPLETE_SCENE（完成场景）[/b]：请求通关结果，等待必要镜头收尾，不自动切换关卡。[br]
## [b]RESTART（重开当前场景）[/b]：重新加载当前场景，无需填写目标路径。[br]
## [b]CHANGE_SCENE（切换场景）[/b]：Scene Path 选择要加载的 .tscn 文件。[br]
## [b]CALL_METHOD（调用方法）[/b]：填写目标、公开方法名和参数；异步完成通知填 Completed Trigger。[br]
## [b]WAIT_SIGNAL（等待信号）[/b]：填写 Completed Trigger，等待其来源信号与过滤结果。[br]
## 所有 Target Path 相对 SceneDirector。普通等待遇暂停会冻结；详细接线见 docs/gameplay/SCENE_DIRECTOR.md。
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
