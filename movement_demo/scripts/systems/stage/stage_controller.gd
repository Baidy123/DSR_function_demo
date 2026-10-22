class_name StageController
extends Node

## 阶段控制器：判定“现在处于第几阶段（第几个任务 + 哪个环节）”，并在变化时广播。
## 它只读取场景与任务状态，不接管对话、移动或战斗；场景状态内容由 StageStateController 负责。

## 组合值（阶段序号或环节）变化时发出；首次解析与换表也会发出一次。
signal stage_changed(index: int, phase: int)
## 仅环节变化时发出，previous / current 取值见 StagePhase.Id。
signal phase_changed(previous: int, current: int)

## 酒馆范围；玩家离开它即视为出发。
@export var tavern_zone: Area3D
## 任务场地范围；玩家进入它即视为到达场地。
@export var site_zone: Area3D

var _table: StageTable
## 任务控制器按鸭子类型调用（status_of / quest_changed），不直接依赖具体脚本。
var _quests
var _index: int = 1
var _phase: int = StagePhase.Id.TAVERN_IDLE
var _in_tavern: bool = false
var _in_site: bool = false
var _left_tavern: bool = false
var _reached_site: bool = false


func _ready() -> void:
	add_to_group(&"stage_controller")
	_bind_zone(tavern_zone, &"tavern")
	_bind_zone(site_zone, &"site")
	_refresh(true)


func set_table(table: StageTable) -> void:
	_table = table
	_refresh(true)


## 由状态控制器注入任务控制器；阶段判定需要任务状态。
func bind_quests(quests: Node) -> void:
	if _quests == quests:
		return
	if _quests != null and _quests.has_signal(&"quest_changed"):
		_quests.quest_changed.disconnect(_on_quest_changed)
	_quests = quests
	if _quests != null and _quests.has_signal(&"quest_changed"):
		_quests.quest_changed.connect(_on_quest_changed)
	_refresh(true)


func get_stage_index() -> int:
	return _index


func get_phase() -> int:
	return _phase


func get_phase_name() -> String:
	return StagePhase.name_of(_phase)


## 玩家当前所在区域：tavern / site / other。
func get_player_zone() -> StringName:
	if _in_site:
		return &"site"
	if _in_tavern:
		return &"tavern"
	return &"other"


## 区域进出入口；区域信号和测试都走这里，无物理环境时也能驱动。
func set_player_in_zone(zone: StringName, inside: bool) -> void:
	match zone:
		&"tavern":
			_in_tavern = inside
			if not inside:
				_left_tavern = true
		&"site":
			_in_site = inside
			if inside:
				_reached_site = true
	_refresh()


func _bind_zone(zone: Area3D, zone_id: StringName) -> void:
	if zone == null:
		return
	zone.body_entered.connect(_on_zone_body_entered.bind(zone_id))
	zone.body_exited.connect(_on_zone_body_exited.bind(zone_id))


func _on_zone_body_entered(body: Node3D, zone_id: StringName) -> void:
	if body.is_in_group(&"player"):
		set_player_in_zone(zone_id, true)


func _on_zone_body_exited(body: Node3D, zone_id: StringName) -> void:
	if body.is_in_group(&"player"):
		set_player_in_zone(zone_id, false)


func _on_quest_changed(_quest_id: StringName, _previous: int, _current: int) -> void:
	_refresh()


func _refresh(force: bool = false) -> void:
	var index := _resolve_index()
	var phase := _resolve_phase(index)
	var index_changed := index != _index
	var phase_changed_now := phase != _phase
	var previous := _phase
	_index = index
	_phase = phase
	if force or index_changed or phase_changed_now:
		stage_changed.emit(_index, _phase)
	if phase_changed_now:
		phase_changed.emit(previous, _phase)


## 当前阶段是表中第一个尚未完成的任务所在阶段；全部完成时停在最后一个阶段。
func _resolve_index() -> int:
	if _table == null:
		return 1
	var ordered := _table.sorted_stages()
	if ordered.is_empty():
		return 1
	for stage in ordered:
		if stage.quest_id == &"":
			return stage.index
		var status := _quest_status(stage.quest_id)
		# 已完成与已失效都表示本阶段已经结束，阶段不会因为失效卡在原处。
		if status != QuestController.Status.COMPLETED and status != QuestController.Status.MISSED:
			return stage.index
	return ordered[ordered.size() - 1].index


func _resolve_phase(index: int) -> int:
	var quest_id: StringName = &""
	if _table != null:
		var stage := _table.stage_for_index(index)
		if stage != null:
			quest_id = stage.quest_id
	var status := _quest_status(quest_id) if quest_id != &"" else QuestController.Status.NOT_STARTED
	match status:
		QuestController.Status.IN_PROGRESS:
			if _in_site:
				return StagePhase.Id.IN_SITE
			if _reached_site:
				return StagePhase.Id.RETURNED
			if _left_tavern:
				return StagePhase.Id.TRAVELING
			return StagePhase.Id.QUEST_TAKEN
		QuestController.Status.COMPLETED:
			return StagePhase.Id.RETURNED
		QuestController.Status.MISSED:
			return StagePhase.Id.RETURNED
	return StagePhase.Id.TAVERN_IDLE


func _quest_status(quest_id: StringName) -> int:
	if _quests == null or quest_id == &"":
		return QuestController.Status.NOT_STARTED
	return _quests.status_of(quest_id)
