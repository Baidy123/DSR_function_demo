class_name StageStateController
extends Node

## 状态控制器：阶段状态的权威。按配置表解析当前阶段应有的 NPC／任务／对话／位置，
## 负责记录快照，并在开关打开时把结果下发给场景里的 NPC。
## 它不判定阶段（那是 StageController 的职责），也不改对话剧本与任务定义。

## 每次重新解析并记录后发出，内容与 get_snapshot() 相同。
signal snapshot_changed(snapshot: Dictionary)

## 配置表；阶段、任务与 NPC 规则都从这里读取。可以换成按阶段拆分的多份表。
@export var stage_table: StageTable
## 是否把解析结果真正下发到场景。默认关闭：只检测、只记录，表现与接入前一致。
@export var apply_enabled: bool = false
## 是否把记录追加写入文件。
@export var log_to_file: bool = true
## 记录文件路径；默认落在已忽略的 logs 目录下。
@export var log_path: String = "res://logs/stage_state.log"
## 是否同时打印到控制台，便于运行时直接观察。
@export var print_log: bool = true
## 读取旗标与物品的状态节点；默认 GameState。
@export var state_path: NodePath = ^"/root/GameState"

## 三个注入点都是鸭子类型接口，按组查找后动态调用，避免互相依赖具体脚本。
var _stage
var _quests
var _state


func _ready() -> void:
	add_to_group(&"stage_state_controller")
	reload_table()
	# 场景里节点顺序变化时兜底：控制器还没进树就下一帧再接线。
	if _stage == null or _quests == null:
		call_deferred("reload_table")


## 重新绑定控制器与配置表，并记录一次当前状态；换表后调用即可。
func reload_table() -> void:
	_stage = _find(&"stage_controller")
	_quests = _find(&"quest_controller")
	if _stage != null:
		_stage.set_table(stage_table)
		if _stage.has_signal(&"stage_changed") and not _stage.stage_changed.is_connected(_on_stage_changed):
			_stage.stage_changed.connect(_on_stage_changed)
	if _quests != null:
		_quests.set_table(stage_table)
		if not _quests.quest_changed.is_connected(_on_quest_changed):
			_quests.quest_changed.connect(_on_quest_changed)
		_quests.bind_stage(_stage)
	if _stage != null:
		_stage.bind_quests(_quests)
	_on_changed("初始化")


## 当前阶段的完整状态快照：阶段、环节、任务、对话、玩家位置与每个 NPC 的应收状态。
func get_snapshot() -> Dictionary:
	var stage_definition: StageDefinition = null
	if stage_table != null:
		stage_definition = stage_table.stage_for_index(get_stage_index())
	var quest: QuestDefinition = null
	if stage_table != null:
		quest = stage_table.quest_for_stage(get_stage_index())
	var quest_id: StringName = quest.id if quest != null else &""
	# 目标地点优先取任务定义，任务没写时回退到阶段定义。
	var target_area: StringName = &""
	if quest != null:
		target_area = quest.target_area
	if target_area == &"" and stage_definition != null:
		target_area = stage_definition.target_area
	return {
		"stage": {
			"index": get_stage_index(),
			"name": stage_definition.display_name if stage_definition != null else "",
			"quest_id": str(stage_definition.quest_id) if stage_definition != null else "",
			"target_area": str(stage_definition.target_area) if stage_definition != null else "",
		},
		"phase": {"id": get_phase(), "name": get_phase_name()},
		"quest": {
			"id": str(quest_id),
			"name": quest.display_name if quest != null else "",
			"status": get_quest_status(quest_id),
			"status_name": get_quest_status_name(quest_id),
			"target_area": str(target_area),
		},
		"dialogue": _dialogue_state(),
		"player": {"position": _player_position(), "zone": str(_player_zone())},
		"npcs": resolve_npc_states(),
	}


## 按配置表解析每个 NPC 当前应有的状态；后面的规则覆盖前面的，未命中的字段保留上一结果。
func resolve_npc_states() -> Dictionary:
	var resolved: Dictionary = {}
	for npc in _npcs():
		var npc_id := _npc_id(npc)
		if npc_id == &"":
			continue
		resolved[npc_id] = {
			"present": bool(npc.visible),
			"position": _npc_position(npc),
			"facing": Vector3.ZERO,
			"dialogue": _npc_dialogue_path(npc),
			"rule": &"",
			"rules": [],
		}
	if stage_table == null:
		return resolved
	for rule in stage_table.rules:
		if not _rule_matches(rule):
			continue
		for npc_id in resolved.keys():
			if rule.target_npc != &"" and rule.target_npc != npc_id:
				continue
			var entry: Dictionary = resolved[npc_id]
			entry["present"] = rule.present
			if rule.position_set:
				entry["position"] = rule.position
			if rule.facing_set:
				entry["facing"] = rule.facing
			if rule.dialogue != null:
				entry["dialogue"] = rule.dialogue.resource_path
			entry["rule"] = rule.id if rule.id != &"" else &"未命名规则"
			entry["rules"].append(entry["rule"])
	return resolved


## 把解析结果下发给场景里的 NPC；开关关闭时不改动任何表现。
func apply_states() -> void:
	if not apply_enabled:
		return
	var resolved := resolve_npc_states()
	for npc in _npcs():
		var npc_id := _npc_id(npc)
		if not resolved.has(npc_id):
			continue
		if npc.has_method(&"apply_stage_state"):
			npc.apply_stage_state(resolved[npc_id])


func get_stage_index() -> int:
	return _stage.get_stage_index() if _stage != null else 1


func get_phase() -> int:
	return _stage.get_phase() if _stage != null else StagePhase.Id.TAVERN_IDLE


func get_phase_name() -> String:
	return StagePhase.name_of(get_phase())


func get_quest_status(quest_id: StringName) -> int:
	if _quests == null:
		return QuestController.Status.NOT_STARTED
	return _quests.status_of(quest_id)


func get_quest_status_name(quest_id: StringName) -> String:
	return str(QuestController.STATUS_NAMES.get(get_quest_status(quest_id), "未接"))


## 记录一次当前状态；reason 写进日志，便于对照是哪个变化触发的。
func log_snapshot(reason: String = "") -> void:
	var line := _format_line(get_snapshot(), reason)
	if print_log:
		print(line)
	if log_to_file:
		_append_line(line)


func _on_stage_changed(index: int, phase: int) -> void:
	_on_changed("阶段变化 阶段%d/环节%s" % [index, StagePhase.name_of(phase)])


func _on_quest_changed(quest_id: StringName, previous: int, current: int) -> void:
	_on_changed("任务变化 %s %s→%s" % [quest_id, _status_name(previous), _status_name(current)])


func _on_changed(reason: String) -> void:
	# 场景卸载时区域与任务信号仍可能触发，此时不再解析与记录。
	if not is_inside_tree():
		return
	var snapshot := get_snapshot()
	apply_states()
	var line := _format_line(snapshot, reason)
	if print_log:
		print(line)
	if log_to_file:
		_append_line(line)
	snapshot_changed.emit(snapshot)


func _format_line(snapshot: Dictionary, reason: String) -> String:
	var parts: Array[String] = []
	parts.append("[阶段记录] %s" % Time.get_datetime_string_from_system())
	parts.append("阶段%d(%s)" % [int(snapshot["stage"]["index"]), str(snapshot["stage"]["name"])])
	parts.append("环节=%s" % str(snapshot["phase"]["name"]))
	parts.append("任务=%s/%s" % [str(snapshot["quest"]["id"]), str(snapshot["quest"]["status_name"])])
	parts.append("玩家=%s%s" % [str(snapshot["player"]["zone"]), str(snapshot["player"]["position"])])
	if bool(snapshot["dialogue"]["active"]):
		parts.append("对话中=%s" % str(snapshot["dialogue"]["source"]))
	for npc_id in snapshot["npcs"].keys():
		var entry: Dictionary = snapshot["npcs"][npc_id]
		parts.append(
			"%s{在场=%s,位置=%s,对话=%s,规则=%s}" % [
				str(npc_id),
				"是" if bool(entry["present"]) else "否",
				str(entry["position"]),
				str(entry["dialogue"]),
				str(entry["rule"]),
			]
		)
	parts.append("原因=%s" % reason)
	return " ".join(parts)


func _append_line(line: String) -> void:
	if log_path.is_empty():
		return
	var file := FileAccess.open(log_path, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		push_warning("阶段记录无法写入 %s" % log_path)
		return
	file.seek_end()
	file.store_line(line)
	file.close()


func _rule_matches(rule: StateRule) -> bool:
	if not rule.enabled:
		return false
	if rule.stage_index != 0 and rule.stage_index != get_stage_index():
		return false
	if rule.phase != StateRule.ANY_PHASE and rule.phase != get_phase():
		return false
	if rule.quest_id != &"" and rule.quest_status != &"":
		if get_quest_status(rule.quest_id) != QuestController.status_from_key(rule.quest_status):
			return false
	return _has_flags(rule.required_flags) and _has_items(rule.required_items)


func _has_flags(flags: Array[StringName]) -> bool:
	for flag in flags:
		if _state_node() == null or not _state_node().is_flag_set(flag):
			return false
	return true


func _has_items(items: Array[StringName]) -> bool:
	for item in items:
		if _state_node() == null or not _state_node().has_item(item):
			return false
	return true


func _state_node():
	if _state == null or not is_instance_valid(_state):
		_state = get_node_or_null(state_path)
	return _state


func _npcs() -> Array:
	var tree := active_tree()
	return tree.get_nodes_in_group(&"npc") if tree != null else []


func _npc_id(npc: Node) -> StringName:
	var id = npc.get(&"npc_id")
	if id != null and str(id) != "":
		return StringName(id)
	return StringName(npc.name)


func _npc_position(npc) -> Vector3:
	if npc is Node3D:
		return npc.global_position
	return Vector3.ZERO


func _npc_dialogue_path(npc: Node) -> String:
	var dialogue = npc.get(&"dialogue_resource")
	if dialogue is Resource:
		return dialogue.resource_path
	return ""


func _player_zone() -> StringName:
	return _stage.get_player_zone() if _stage != null else &"other"


func _player_position() -> Vector3:
	var tree := active_tree()
	if tree == null:
		return Vector3.ZERO
	var player = tree.get_first_node_in_group(&"player")
	if player is Node3D:
		return (player as Node3D).global_position
	return Vector3.ZERO


## 对话面板只暴露“当前玩家 / 来源 / 资源”，这里按组查找，不硬编码界面节点路径。
func _dialogue_state() -> Dictionary:
	var tree := active_tree()
	if tree == null:
		return {"active": false, "source": "", "resource": ""}
	var ui = tree.get_first_node_in_group(&"dialogue_ui")
	if ui == null or ui.get(&"dialogue_player") == null:
		return {"active": false, "source": "", "resource": ""}
	var source = ui.get(&"dialogue_source")
	var resource = ui.get(&"dialogue_resource")
	return {
		"active": true,
		"source": str(source.name) if source is Node else "",
		"resource": resource.resource_path if resource is Resource else "",
	}


func _status_name(status: int) -> String:
	return str(QuestController.STATUS_NAMES.get(status, "未知"))


func _find(group: StringName) -> Node:
	var tree := active_tree()
	return tree.get_first_node_in_group(group) if tree != null else null


## 节点离开场景树后 get_tree() 仍会返回已清空的树，这里统一挡掉。
func active_tree() -> SceneTree:
	return get_tree() if is_inside_tree() else null
