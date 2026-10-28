@tool
extends Node3D

## 场景总调度入口。现有 Wave/Squad 部署保持；没有 Wave 也可处理引导、死亡和场景动作。
## 新场景拖入 scenes/world/scene_director.tscn。旧 enemy_waves.tscn 保留兼容。
## 入门：事件节点放在 SceneEvents，Wave 的 Event Nodes 选择它；出场镜头手动选择 Marker3D。
## 完整步骤：docs/gameplay/SCENE_DIRECTOR.md。不要将本节点或整个区域设为 Always。
const Runtime = preload("res://scripts/world/enemy_wave_runtime.gd")
const Director = preload("res://scripts/systems/scene_director.gd")
signal wave_started(index: int)
signal wave_cleared(index: int)
signal encounter_completed

@export_group("区域与波次")
## 玩家进入所属 CombatZone 自动请求开始。关闭后由 start_encounter 或 REQUEST_WAVE 动作启动。
## 无论怎样请求，刷新仍检查区域、暂停、玩家状态和出生点，不会绕过区域资格。
@export var auto_start_on_enter := true
## 出生点被玩家/敌人占住时的原地重试间隔，不会自行改刷新位置。
@export_range(0.01, 10.0, 0.01) var spawn_retry_seconds := 0.25
## 有结果UI时，所有配置波次都出场并清空后显示通关。无Wave不自动通关。
## 关闭可由场景规则的 COMPLETE_SCENE 决定完成；不会改变敌人实际清空统计。
@export var complete_when_all_waves_cleared := true
@export_group("场景绑定")
## 当前玩家Health，相对SceneDirector。收到died后由调度器显示原死亡UI并处理重开。
@export_node_path("Node") var health_path: NodePath = ^"../Player/Health"
## 当前关结果界面，默认同级LevelFlow；其关卡编号和五关路径表保持原配置。
## 留空不启用默认全波通关界面；独立玩法可另接自定义结果。
@export_node_path("CanvasLayer") var result_view_path: NodePath = ^"../LevelFlow"
## 可选开场提供者，默认临时PlayGuide。清空即可跳过，删除PlayGuide也不会永久等待。
## 替换教程时选择有begin()/cancel()/finished信号的适配节点，不要求固定脚本类型。
@export_node_path("Node") var guide_path: NodePath = ^"../LevelFlow/PlayGuide"
## 开启后指定的引导缺失会报告配置错误；默认关闭，便于移除临时说明。
@export var guide_required := false
## 临时说明开启；未来互动教程允许玩家行动时关闭。仅影响开场引导，不改变死亡暂停。
@export var guide_pauses_world := true
## 可选的专用PresentationCamera节点。留空时首次需要镜头会创建同级内部实例。
## 不要选玩家Camera3D；它继续由原Phantom跟随，演出使用第二台相机。
@export_node_path("Camera3D") var presentation_camera_path: NodePath
@export_group("场景规则")
## 添加元素→新建SceneFlowRule。Event Nodes选事件节点，Actions按顺序放动作。
## 只想事件刷怪可直接配Wave.Event Nodes，不必先写规则。无Wave也可使用提示/镜头等动作。
@export var scene_rules: Array[SceneFlowRule] = []
@export_group("统一出场镜头（可选）")
## 可选整场默认：每波出场都展示统一目标。通常在各Wave的“出场镜头”单独配置更直观。
## 默认关闭，保留当前关卡节奏；每波/场景动作的专属镜头优先。
@export var present_spawned_waves := false
## 可选的整场统一镜头目标，相对本调度节点。每波或动作的专属目标优先。
## 必须手动选择 Marker3D/Node3D；不自动猜测敌人位置。
@export_node_path("Node3D") var presentation_target_path: NodePath
## 统一镜头移动时间；每波单独开启的镜头使用其自己的时间。
@export_range(0.0, 10.0, 0.05) var camera_move_seconds := 0.6
## 统一镜头到达后停留时间。
@export_range(0.0, 30.0, 0.05) var camera_hold_seconds := 1.2
## 统一镜头返回玩家最新视野的时间，返回完成才恢复战斗。
@export_range(0.0, 10.0, 0.05) var camera_return_seconds := 0.6

var _runtime
var director: Node
var _corpse_root: Node3D:
	get: return _runtime._corpse_root if _runtime != null else null
var _pending: Array[Dictionary]:
	get: return _runtime._pending if _runtime != null else []

func _ensure_runtime() -> void:
	if _runtime != null: return
	_runtime = Runtime.new(self)
	_runtime.wave_started.connect(func(index: int): wave_started.emit(index))
	_runtime.wave_cleared.connect(func(index: int): wave_cleared.emit(index))
	_runtime.encounter_completed.connect(func(): encounter_completed.emit())

func capture_templates(region: Node3D) -> void:
	if Engine.is_editor_hint(): return
	_ensure_runtime()
	_runtime.capture_templates(region)

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_ensure_runtime()
	director = Director.new()
	director.name = "SceneDirector"
	director.configure(self, {
		"health": get_node_or_null(health_path) if not health_path.is_empty() else null,
		"level_flow": get_node_or_null(result_view_path) if not result_view_path.is_empty() else null,
		"guide": get_node_or_null(guide_path) if not guide_path.is_empty() else null,
		"guide_required": guide_required, "guide_pauses_world": guide_pauses_world,
		"camera": get_node_or_null(presentation_camera_path) if not presentation_camera_path.is_empty() else null,
		"rules": scene_rules, "wave_runtime": _runtime,
		"auto_complete_waves": complete_when_all_waves_cleared and not result_view_path.is_empty() and get_node_or_null(result_view_path) != null,
		"present_spawned_waves": present_spawned_waves,
		"presentation_target_path": presentation_target_path,
		"presentation_options": {"move_seconds": camera_move_seconds, "hold_seconds": camera_hold_seconds, "return_seconds": camera_return_seconds}})
	# Never make the host Always: enemy descendants must remain pausable.
	add_child(director, false, Node.INTERNAL_MODE_BACK)

func start_encounter() -> void:
	_ensure_runtime()
	_runtime.start_encounter()

func advance_from_region(delta: float) -> void:
	if _runtime != null: _runtime.advance_from_region(delta)

func reset_encounter() -> void:
	if is_instance_valid(director): director.reset_region()
	if _runtime != null: _runtime.reset_encounter()

func request_wave(wave: Node) -> bool:
	_ensure_runtime()
	return _runtime.request_wave(wave)

func wave_status(wave: Node) -> StringName:
	return _runtime.wave_status(wave) if _runtime != null else &"unknown"

func wave_focus(wave: Node) -> Variant:
	return _runtime.wave_focus(wave) if _runtime != null else null

func owns_runtime_enemy(enemy: Node) -> bool:
	return _runtime != null and _runtime.owns_runtime_enemy(enemy)

func debug_snapshot() -> Dictionary:
	_ensure_runtime()
	var snapshot: Dictionary = _runtime.debug_snapshot()
	snapshot["scene"] = director.debug_snapshot() if is_instance_valid(director) else {}
	return snapshot

func _instantiate_wave(index: int) -> Array[Dictionary]:
	return _runtime._instantiate_wave(index)

func _get_configuration_warnings() -> PackedStringArray:
	var runtime = Runtime.new(self)
	return runtime.configuration_warnings(get_parent())

func _exit_tree() -> void:
	if _runtime != null:
		_runtime.release()
		_runtime = null
