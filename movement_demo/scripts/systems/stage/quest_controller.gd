class_name QuestController
extends Node

## 任务控制器：任务状态的唯一权威，按配置表判定接取、拒绝与完成。
## 对话与交互物仍然写自己的状态字段，由这里按表同步成任务状态；不反向改写剧本。

signal quest_changed(quest_id: StringName, previous: int, current: int)

enum Status {
	NOT_STARTED, ## 未接
	IN_PROGRESS, ## 进行中
	REFUSED, ## 已拒绝
	COMPLETED, ## 已完成
}

const STATUS_NAMES: Dictionary = {
	Status.NOT_STARTED: "未接",
	Status.IN_PROGRESS: "进行中",
	Status.REFUSED: "已拒绝",
	Status.COMPLETED: "已完成",
}

const STATUS_KEYS: Dictionary = {
	&"not_started": Status.NOT_STARTED,
	&"in_progress": Status.IN_PROGRESS,
	&"refused": Status.REFUSED,
	&"completed": Status.COMPLETED,
}

## 读取旗标、物品与对话写入字段的状态节点；默认 GameState，可换成实现同类接口的节点。
@export var state_path: NodePath = ^"/root/GameState"

var _table: StageTable
## 阶段控制器与状态节点都按鸭子类型调用，避免互相依赖具体脚本。
var _stage
var _state
var _statuses: Dictionary = {}


func _ready() -> void:
	add_to_group(&"quest_controller")
	_bind_state()


func set_table(table: StageTable) -> void:
	_table = table
	_sync_from_state()


## 由状态控制器接线；离开场地返回时用于自动完成。
func bind_stage(stage: Node) -> void:
	if _stage == stage:
		return
	if _stage != null and _stage.has_signal(&"phase_changed"):
		_stage.phase_changed.disconnect(_on_phase_changed)
	_stage = stage
	if _stage != null and _stage.has_signal(&"phase_changed"):
		_stage.phase_changed.connect(_on_phase_changed)


func status_of(quest_id: StringName) -> int:
	return int(_statuses.get(quest_id, Status.NOT_STARTED))


func status_name(quest_id: StringName) -> String:
	return str(STATUS_NAMES.get(status_of(quest_id), "未接"))


## 配置表里用字符串写状态，这里换成枚举；未知字符串按“未接”处理。
static func status_from_key(key: StringName) -> int:
	return int(STATUS_KEYS.get(key, Status.NOT_STARTED))


func set_status(quest_id: StringName, status: int) -> void:
	if quest_id == &"" or status_of(quest_id) == status:
		return
	var previous := status_of(quest_id)
	_statuses[quest_id] = status
	quest_changed.emit(quest_id, previous, status)


func accept(quest_id: StringName) -> void:
	set_status(quest_id, Status.IN_PROGRESS)


func refuse(quest_id: StringName) -> void:
	set_status(quest_id, Status.REFUSED)


func complete(quest_id: StringName) -> void:
	set_status(quest_id, Status.COMPLETED)


## 重开或换表时清空进度，回到未接。
func reset_progress() -> void:
	for quest_id in _statuses.keys():
		set_status(quest_id, Status.NOT_STARTED)
	_statuses.clear()


func _bind_state() -> void:
	_state = get_node_or_null(state_path)
	if _state != null and _state.has_signal(&"value_changed"):
		_state.value_changed.connect(_on_state_value_changed)
	_sync_from_state()


## 读取表里声明的接取来源，让换表或重开后状态与配置一致。
func _sync_from_state() -> void:
	if _table == null or _state == null:
		return
	for quest in _table.quests:
		if quest.accept_source == &"" or not _state_has(quest.accept_source):
			continue
		_apply_source_value(quest, _state.get(quest.accept_source))


func _on_state_value_changed(key: StringName, value: Variant) -> void:
	if _table == null:
		return
	for quest in _table.quests:
		if quest.accept_source == key:
			_apply_source_value(quest, value)


func _apply_source_value(quest: QuestDefinition, value: Variant) -> void:
	var text := str(value)
	if not quest.accept_value.is_empty() and text == quest.accept_value:
		set_status(quest.id, Status.IN_PROGRESS)
		return
	if quest.refuse_values.has(text):
		set_status(quest.id, Status.REFUSED)


## 从任务场地返回：按表把当前阶段的任务记为完成。
func _on_phase_changed(previous: int, current: int) -> void:
	if current != StagePhase.Id.RETURNED or previous == StagePhase.Id.RETURNED:
		return
	_complete_returned_stage_quests()


func _complete_returned_stage_quests() -> void:
	if _table == null:
		return
	var stage_index: int = _stage.get_stage_index() if _stage != null else 1
	for quest in _table.quests:
		if quest.stage_index != stage_index or not quest.complete_on_return:
			continue
		if status_of(quest.id) != Status.IN_PROGRESS:
			continue
		if not _has_required_flags(quest.required_flags):
			continue
		set_status(quest.id, Status.COMPLETED)


func _has_required_flags(required: Array[StringName]) -> bool:
	for flag in required:
		if _state == null or not _state.is_flag_set(flag):
			return false
	return true


func _state_has(property_name: StringName) -> bool:
	if _state == null:
		return false
	for entry in _state.get_property_list():
		if entry.get("name", "") == str(property_name):
			return true
	return false
