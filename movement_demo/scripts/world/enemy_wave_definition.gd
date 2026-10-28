@tool
extends Node3D

## 一波的部署容器。把 squad.tscn 拖到下面，再在小队里摆敌人；复制本节点即可增加一波。
const Squad = preload("res://scripts/world/squad_controller.gd")
const EventTrigger = preload("res://scripts/systems/scene_event_trigger.gd")

signal spawned
signal cleared

enum StartMode { SEQUENCE, EVENTS, REQUEST }
enum TriggerCombination { ANY, ALL }

@export_group("出场条件")
## SEQUENCE：按相邻上一波出场；EVENTS：监听下面的事件；REQUEST：由场景动作请求。
## 简单接法：选EVENTS，Event Nodes选择SceneEvent；要顺序动作时选REQUEST，再配SceneDirector规则。
@export var start_mode: StartMode = StartMode.SEQUENCE
## EVENTS 模式的快捷入口：从场景树选择带无参 triggered 信号的事件节点，无需填写信号名。
## 路径相对此 Wave；与下面的 Triggers 一起按 ANY／ALL 组合。事件节点放在部署层之外。
@export_node_path("Node") var event_nodes: Array[NodePath] = []
## EVENTS 模式使用。添加元素→新建 SceneEventTrigger；Source Path 相对此 Wave 节点填写。
## 例如 ../../CombatZone 的 body_entered，配参数0的 NODE_IN_GROUP=player 过滤。
@export var triggers: Array[EventTrigger] = []
## ANY：任一事件发生即可；ALL：本轮每个事件都发生过。离开战斗区复位后重新等待。
@export var trigger_combination: TriggerCombination = TriggerCombination.ANY

## 开启：上一波全灭后开始等待；关闭：上一波实际出场后开始等待，允许多波同时作战。
## 第一波没有上一波，始终从本轮战斗开始计时。
@export var wait_for_previous_clear: bool = true
## 按上面的条件开始计时，经过这些秒数后本波加入。0表示条件满足后尽快加入。
## 暂停、对话或玩家死亡时不扣时间；刷新点被占用时仍需等待原位置空出。
@export_range(0.0, 120.0, 0.1, "or_greater", "suffix:s") var start_delay_seconds: float = 0.0
@export_group("出场镜头")
## 开启后，本波真正生成成功时暂停战斗并展示下面绑定的目标，返回玩家视野后恢复。
## 必须手动指定 Presentation Target Path；出生点受阻时不提前播放。无需修改玩家相机。
@export var show_spawn_presentation := false
## 选择一个 Marker3D 或已有 Node3D 作为画面中心；路径相对此 Wave。
## 将标记放在场景根的 CameraPoints 等独立容器下，不要直接塞进 Wave 的小队部署层。
## 标记表示“看哪里”，不是相机的位置；保留玩家相机倾角。未绑定或目标消失则诊断并跳过镜头。
@export_node_path("Node3D") var presentation_target_path: NodePath
## 从玩家视野移动到指定目标的秒数；0立即到达。
@export_range(0.0, 10.0, 0.05, "suffix:s") var presentation_move_seconds := 0.6
## 到达目标后停留秒数；期间战斗冻结。
@export_range(0.0, 30.0, 0.05, "suffix:s") var presentation_hold_seconds := 1.2
## 返回玩家最新视野的秒数；完成后才释放本次演出暂停。
@export_range(0.0, 10.0, 0.05, "suffix:s") var presentation_return_seconds := 0.6
## 正交相机展示范围；0复制玩家当前 Size。不会改写玩家武器视野。
@export_range(0.0, 100.0, 0.1) var presentation_size := 0.0
@export_group("出生搜索")
## 仅后续波生效：实际生成时获得一次玩家大概位置，先快速追查提示区域，再持续警戒搜索。
## 场景树最前的初始波（第0波）始终忽略；真实视野、声音和接敌仍按原规则运行。
@export var search_on_spawn: bool = true
## 出生位置提示的最大水平误差，单位米；默认3米，0为精确的单次位置提示。
## 控制情报误差，不改变原搜索范围，不构成目击或开火许可；隐蔽移动不会自动刷新它。
@export_range(0.0, 30.0, 0.25, "or_greater", "suffix:m") var spawn_search_error_radius: float = 3.0
@export_group("兼容已有场景")
## 可选：相对此波节点的已有小队路径。仅用于保留原地图路径；普通新波次直接放子小队即可。
## 一个小队只能属于一波；留空不额外引用任何小队，不需要逐个登记敌人。
@export var existing_squads: Array[NodePath] = []:
	set(value):
		existing_squads = value
		update_configuration_warnings()

func deployment_configuration() -> Dictionary:
	var squads: Array[Node3D] = []
	var errors: PackedStringArray = []
	for child in get_children():
		if child is Squad: squads.append(child)
		else: errors.append("%s：波次下面请放 Squad 小队，敌人放到小队下面。" % child.name)
	for path in existing_squads:
		var squad = get_node_or_null(path) if not path.is_empty() else null
		if not squad is Squad:
			errors.append("已有小队路径无效：%s" % path)
		elif squads.has(squad):
			errors.append("重复引用小队：%s" % path)
		else:
			squads.append(squad)
	if squads.is_empty(): errors.append("本波还没有小队：拖入 squad.tscn，再把敌人放到小队下。")
	if start_mode not in [StartMode.SEQUENCE, StartMode.EVENTS, StartMode.REQUEST]:
		errors.append("未知出场方式。")
	if trigger_combination not in [TriggerCombination.ANY, TriggerCombination.ALL]:
		errors.append("未知事件组合方式。")
	var event_triggers := configured_triggers()
	if start_mode == StartMode.EVENTS and event_triggers.is_empty():
		errors.append("事件波至少需要一个事件节点或 SceneEventTrigger。")
	if not is_finite(start_delay_seconds) or start_delay_seconds < 0.0:
		errors.append("波前等待必须是大于或等于0的秒数。")
	if not is_finite(spawn_search_error_radius) or spawn_search_error_radius < 0.0:
		errors.append("出生搜索的位置误差必须是有限且大于或等于0的米数。")
	return {"squads": squads, "errors": errors, "triggers": event_triggers, "event_node_start": triggers.size()}

func configured_triggers() -> Array[EventTrigger]:
	# Compile a fresh list; never append runtime/configuration data to shared resources.
	var result: Array[EventTrigger] = []
	result.assign(triggers)
	for path in event_nodes:
		var trigger := EventTrigger.new()
		trigger.source_path = path
		trigger.signal_name = &"triggered"
		result.append(trigger)
	return result

func event_node_diagnostic(path: NodePath) -> String:
	if path.is_empty(): return "事件节点路径不能为空。"
	var source := get_node_or_null(path)
	if source == null: return "事件节点不存在：%s。" % path
	if not source.has_signal(&"triggered"): return "事件节点 %s 必须提供无参 triggered 信号。" % path
	for metadata in source.get_signal_list():
		if metadata.name == &"triggered":
			return "" if metadata.args.is_empty() else "事件节点 %s 的 triggered 信号必须无参数。" % path
	return "无法读取事件节点 %s 的 triggered 信号定义。" % path

func _get_configuration_warnings() -> PackedStringArray:
	var errors: PackedStringArray = deployment_configuration().errors
	if show_spawn_presentation:
		var target := get_node_or_null(presentation_target_path) if not presentation_target_path.is_empty() else null
		if not target is Node3D: errors.append("出场镜头请手动绑定Marker3D/Node3D目标；未绑定时跳过表现。")
	if start_mode == StartMode.EVENTS:
		for path in event_nodes:
			var diagnostic := event_node_diagnostic(path)
			if not diagnostic.is_empty(): errors.append(diagnostic)
	if get_parent() == null or not get_parent().has_method("capture_templates"):
		errors.append("请把本波放在 SceneDirector 控制器下面；按场景树顺序出场。")
	return errors
