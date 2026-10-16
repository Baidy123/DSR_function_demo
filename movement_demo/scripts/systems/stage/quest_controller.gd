class_name QuestController
extends Node

## 任务控制器：任务状态的唯一权威。按配置表里的条件判定接取、拒绝、完成与失效，
## 只读阶段序号判断解锁／失效窗口与重算时机，不监听阶段行为、不触发阶段逻辑。

signal quest_changed(quest_id: StringName, previous: int, current: int)

enum Status {
	NOT_STARTED, ## 未接（含尚未解锁）
	IN_PROGRESS, ## 进行中
	REFUSED, ## 已拒绝
	COMPLETED, ## 已完成
	MISSED, ## 已失效：过了失效阶段仍未完成
}

const STATUS_NAMES: Dictionary = {
	Status.NOT_STARTED: "未接",
	Status.IN_PROGRESS: "进行中",
	Status.REFUSED: "已拒绝",
	Status.COMPLETED: "已完成",
	Status.MISSED: "已失效",
}

const STATUS_KEYS: Dictionary = {
	&"not_started": Status.NOT_STARTED,
	&"in_progress": Status.IN_PROGRESS,
	&"refused": Status.REFUSED,
	&"completed": Status.COMPLETED,
	&"missed": Status.MISSED,
}

## 读取状态字段、旗标与物品的状态节点；默认 GameState。
@export var state_path: NodePath = ^"/root/GameState"

var _table: StageTable
## 阶段控制器：任务侧只调用 get_stage_index()，并只订阅 stage_changed 广播。
var _stage
var _state
var _statuses: Dictionary = {}
## 「曾经」类条件的记忆：交互、区域进出。
var _interacted: Dictionary = {}
var _zones_entered: Dictionary = {}
var _zones_left: Dictionary = {}
var _bound_interactables: Dictionary = {}
var _bound_zones: Dictionary = {}
var _evaluating: bool = false


func _ready() -> void:
	add_to_group(&"quest_controller")
	_bind_state()
	_bind_stage(_find(&"stage_controller"))
	_bind_events()
	# 场景里节点顺序变化时兜底：控制器还没进树就下一帧再绑定一次。
	call_deferred("_bind_late")


func set_table(table: StageTable) -> void:
	_table = table
	_evaluate_all()


## 配置分发方或测试显式接线；绑定后立刻按当前窗口与条件评估一次。
func bind_stage(stage: Node) -> void:
	_bind_stage(stage)
	_evaluate_all()


func status_of(quest_id: StringName) -> int:
	return int(_statuses.get(quest_id, Status.NOT_STARTED))


func status_name(quest_id: StringName) -> String:
	return str(STATUS_NAMES.get(status_of(quest_id), "未接"))


## 未到解锁阶段的任务不参与条件评估；表中没有该任务时按锁定处理。
func is_locked(quest_id: StringName) -> bool:
	var quest := quest_definition(quest_id)
	if quest == null:
		return true
	return quest.unlock_stage > 0 and get_stage_index() < quest.unlock_stage


func quest_definition(quest_id: StringName) -> QuestDefinition:
	return _table.quest_by_id(quest_id) if _table != null else null


## 面板与测试使用的只读列表；按阶段升序，同阶段保持表内顺序。
func get_quest_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if _table == null:
		return entries
	var indexed: Array = []
	for order in _table.quests.size():
		indexed.append({"order": order, "quest": _table.quests[order]})
	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var left: QuestDefinition = a["quest"]
		var right: QuestDefinition = b["quest"]
		if left.stage_index != right.stage_index:
			return left.stage_index < right.stage_index
		return int(a["order"]) < int(b["order"])
	)
	for item in indexed:
		var quest: QuestDefinition = item["quest"]
		entries.append({
			"id": quest.id,
			"name": quest.display_name,
			"status": status_of(quest.id),
			"status_name": status_name(quest.id),
			"stage_index": quest.stage_index,
			"target_area": quest.target_area,
			"locked": is_locked(quest.id),
		})
	return entries


## 配置表用字符串写状态，这里换成枚举；未知字符串按「未接」处理。
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


func fail(quest_id: StringName) -> void:
	set_status(quest_id, Status.MISSED)


## 重开或换表时清空进度与「曾经」记忆，回到未接。
func reset_progress() -> void:
	for quest_id in _statuses.keys():
		set_status(quest_id, Status.NOT_STARTED)
	_statuses.clear()
	_interacted.clear()
	_zones_entered.clear()
	_zones_left.clear()


func get_stage_index() -> int:
	if _stage != null and _stage.has_method(&"get_stage_index"):
		return int(_stage.get_stage_index())
	return 1


func _bind_stage(stage: Node) -> void:
	if _stage == stage:
		return
	if _stage != null and _stage.has_signal(&"stage_changed") and _stage.stage_changed.is_connected(_on_stage_changed):
		_stage.stage_changed.disconnect(_on_stage_changed)
	_stage = stage
	if _stage != null and _stage.has_signal(&"stage_changed") and not _stage.stage_changed.is_connected(_on_stage_changed):
		_stage.stage_changed.connect(_on_stage_changed)


func _bind_state() -> void:
	_state = get_node_or_null(state_path)
	if _state == null:
		return
	if _state.has_signal(&"value_changed") and not _state.value_changed.is_connected(_on_state_value_changed):
		_state.value_changed.connect(_on_state_value_changed)
	if _state.has_signal(&"item_gained") and not _state.item_gained.is_connected(_on_item_gained):
		_state.item_gained.connect(_on_item_gained)
	if _state.has_signal(&"flag_changed") and not _state.flag_changed.is_connected(_on_flag_changed):
		_state.flag_changed.connect(_on_flag_changed)


## 按 group 绑定交互物与区域；绑定表去重，重复调用只补新节点。
func _bind_events() -> void:
	var tree := get_tree() if is_inside_tree() else null
	if tree == null:
		return
	if _state == null:
		_bind_state()
	for node in tree.get_nodes_in_group(&"interactable"):
		if _bound_interactables.has(node) or not node.has_signal(&"interacted"):
			continue
		node.interacted.connect(_on_interacted)
		_bound_interactables[node] = true
	for node in tree.get_nodes_in_group(&"zone_volume"):
		if _bound_zones.has(node) or not (node is Area3D):
			continue
		var zone_id := _zone_id(node)
		if zone_id == &"":
			continue
		(node as Area3D).body_entered.connect(_on_zone_body_entered.bind(zone_id))
		(node as Area3D).body_exited.connect(_on_zone_body_exited.bind(zone_id))
		_bound_zones[node] = true


func _bind_late() -> void:
	if _stage == null:
		_bind_stage(_find(&"stage_controller"))
	_bind_events()
	_evaluate_all()


func _on_state_value_changed(_key: StringName, _value: Variant) -> void:
	_evaluate_all()


func _on_item_gained(_item_id: StringName, _display_name: String, _total: int) -> void:
	_evaluate_all()


func _on_flag_changed(_flag: StringName, _value: bool) -> void:
	_evaluate_all()


func _on_interacted(interactable: Node, _player: Node3D) -> void:
	var interact_id := _interact_id(interactable)
	if interact_id == &"":
		return
	_interacted[interact_id] = true
	_evaluate_all()


func _on_zone_body_entered(body: Node3D, zone_id: StringName) -> void:
	if not body.is_in_group(&"player"):
		return
	_zones_entered[zone_id] = true
	_evaluate_all()


func _on_zone_body_exited(body: Node3D, zone_id: StringName) -> void:
	if not body.is_in_group(&"player"):
		return
	_zones_left[zone_id] = true
	_evaluate_all()


func _on_stage_changed(_index: int, _phase: int) -> void:
	_evaluate_all()


## 先算窗口再算条件；任务状态变化可能让阶段推进，阶段已同步更新后补跑一轮，避免解锁滞后。
func _evaluate_all() -> void:
	if _table == null or _evaluating:
		return
	_evaluating = true
	var stage_index := get_stage_index()
	_apply_expiry(stage_index)
	_apply_conditions()
	_evaluating = false
	if get_stage_index() != stage_index:
		_evaluate_all()


func _apply_expiry(stage_index: int) -> void:
	for quest in _table.quests:
		if quest.expire_stage <= 0 or stage_index < quest.expire_stage:
			continue
		var status := status_of(quest.id)
		if status == Status.COMPLETED or status == Status.MISSED:
			continue
		set_status(quest.id, Status.MISSED)


func _apply_conditions() -> void:
	for quest in _table.quests:
		if is_locked(quest.id):
			continue
		match status_of(quest.id):
			Status.NOT_STARTED, Status.REFUSED:
				if _conditions_met(quest.refuse_conditions):
					set_status(quest.id, Status.REFUSED)
				elif _conditions_met(quest.accept_conditions):
					set_status(quest.id, Status.IN_PROGRESS)
			Status.IN_PROGRESS:
				if _conditions_met(quest.complete_conditions):
					set_status(quest.id, Status.COMPLETED)


## 空数组表示该判定不生效，避免没配条件的任务被自动推进。
func _conditions_met(conditions: Array[QuestCondition]) -> bool:
	if conditions.is_empty():
		return false
	for condition in conditions:
		if condition != null and condition.enabled and not _condition_met(condition):
			return false
	return true


func _condition_met(condition: QuestCondition) -> bool:
	if condition.key == &"":
		return false
	match condition.source:
		QuestCondition.Source.STATE_FIELD:
			return _state_has(condition.key) and str(_state.get(condition.key)) == condition.state_value
		QuestCondition.Source.FLAG:
			return _flag_value(condition.key) == condition.flag_value
		QuestCondition.Source.ITEM:
			return _item_count(condition.key) >= condition.min_count
		QuestCondition.Source.INTERACTED:
			return _interacted.has(condition.key)
		QuestCondition.Source.ZONE_ENTERED:
			return _zones_entered.has(condition.key)
		QuestCondition.Source.ZONE_LEFT:
			return _zones_left.has(condition.key)
	return false


func _flag_value(flag: StringName) -> bool:
	if _state == null or not _state.has_method(&"is_flag_set"):
		return false
	return bool(_state.is_flag_set(flag))


func _item_count(item_id: StringName) -> int:
	if _state == null or not _state.has_method(&"get_item_count"):
		return 0
	return int(_state.get_item_count(item_id))


func _state_has(property_name: StringName) -> bool:
	if _state == null:
		return false
	for entry in _state.get_property_list():
		if entry.get("name", "") == str(property_name):
			return true
	return false


func _interact_id(interactable: Node) -> StringName:
	var id = interactable.get(&"interact_id")
	if id != null and str(id) != "":
		return StringName(id)
	return StringName(interactable.name)


func _zone_id(zone: Node) -> StringName:
	var id = zone.get(&"zone_id")
	if id != null and str(id) != "":
		return StringName(id)
	return StringName(zone.name)


func _find(group: StringName) -> Node:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(group) if tree != null else null
