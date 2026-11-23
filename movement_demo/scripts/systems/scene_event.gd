@tool
class_name SceneEvent
extends Node

## 可复用的场景事件节点。Wave/规则直接选本节点，统一监听 triggered，无需重复填信号名。
## 用法一：绑定来源节点和信号；用法二：来源留空，其他脚本调用 trigger() 或编辑器连接无参信号。
## 教程：docs/gameplay/SCENE_DIRECTOR.md。请把事件放在独立 SceneEvents 容器，不改 Wave/Squad 部署层。
signal triggered

const Subscription = preload("res://scripts/systems/scene_event_subscription.gd")
const Trigger = preload("res://scripts/systems/scene_event_trigger.gd")

@export_group("事件来源（可选）")
## 相对本事件节点选来源。例：SceneEvents/EnterZone 的来源为 ../../CombatZone。
## 留空时是手动事件，外部调用此节点.trigger() 即通知监听它的 Wave 或场景规则。
@export_node_path("Node") var source_path: NodePath:
	set(value):
		source_path = value
		notify_property_list_changed()
		if is_inside_tree(): update_configuration_warnings()
## 选择来源信号；绑定来源后，检查器下拉列出其信号。例：Area3D 用 body_entered，Timer 用 timeout。
## 参数由本节点过滤后统一转成无参 triggered，Wave 无需处理来源的参数。
@export var signal_name: StringName:
	set(value):
		signal_name = value
		if is_inside_tree(): update_configuration_warnings()
## 可选：同一信号的过滤项必须全部满足。body_entered 建参数0/NODE_IN_GROUP/player，排除敌人。
## flag_changed 建参数0/STRING_NAME/旗标名和参数1/BOOL/true。没有参数的 timeout 留空。
@export var filters: Array[SceneEventFilter] = []

var _subscription = Subscription.new()
var _last_error := ""
var _emitting := false
var _diagnosing := false

func _ready() -> void:
	if Engine.is_editor_hint(): return
	bind_source.call_deferred()

## 手动触发；普通暂停中也可记录事实，实际动作仍受总调度的暂停与生命周期约束。
func trigger() -> void:
	if Engine.is_editor_hint() or not is_inside_tree() or is_queued_for_deletion(): return
	if _emitting:
		_last_error = "场景事件循环连接，已停止本次递归通知。"
		return
	_emitting = true
	triggered.emit()
	_emitting = false

## 脚本改变来源配置后可显式重绑；先解除旧连接，返回空字符串表示成功或手动模式。
func bind_source() -> String:
	clear_source()
	if Engine.is_editor_hint() or not is_inside_tree(): return ""
	if source_path.is_empty(): return ""
	var warnings := _get_configuration_warnings()
	if not warnings.is_empty():
		_last_error = "; ".join(warnings)
		return _last_error
	var event := Trigger.new()
	event.source_path = source_path
	event.signal_name = signal_name
	event.filters = filters
	_last_error = _subscription.connect_trigger(self, event, trigger)
	return _last_error

func clear_source() -> void:
	_subscription.clear()
	_last_error = ""

func diagnostics() -> PackedStringArray:
	return scene_event_diagnostics()

func scene_event_diagnostics() -> PackedStringArray:
	if _diagnosing: return ["场景事件来源存在循环引用。"]
	_diagnosing = true
	var errors: PackedStringArray = _subscription.diagnostics()
	_diagnosing = false
	if not _last_error.is_empty(): errors.append(_last_error)
	return errors

func _validate_property(property: Dictionary) -> void:
	if property.name != "signal_name" or source_path.is_empty(): return
	var source := get_node_or_null(source_path)
	if source == null: return
	var names: PackedStringArray = []
	for metadata in source.get_signal_list(): names.append(metadata.name)
	names.sort()
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = ",".join(names)

func _get_configuration_warnings() -> PackedStringArray:
	if source_path.is_empty(): return []
	var source := get_node_or_null(source_path)
	if source == null: return ["事件来源不存在，请重新选择 Source Path。"]
	if source == self: return ["事件来源不能是自己，避免 triggered 递归通知。"]
	if signal_name.is_empty() or not source.has_signal(signal_name): return ["请从 Signal Name 选择来源节点的有效信号。"]
	for metadata in source.get_signal_list():
		if metadata.name != signal_name: continue
		if metadata.args.size() > Subscription.MAX_ARGUMENTS: return ["来源信号只支持0～8个参数。"]
		for filter in filters:
			if filter == null: return ["Filters中存在空项，请新建SceneEventFilter或移除该项。"]
			var error: String = filter.validate(metadata.args)
			if not error.is_empty(): return [error]
	return []

func _exit_tree() -> void:
	clear_source()
