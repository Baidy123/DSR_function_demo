extends CanvasLayer

## 任务面板：Tab 显示／隐藏，展示任务状态。
## 只读任务控制器的查询接口与状态信号，不写游戏状态。

const TOGGLE_ACTION: StringName = &"toggle_quest_panel"

@onready var panel: PanelContainer = $Panel
@onready var quest_list: Label = $Panel/Margin/Content/QuestList

var _quests
var _toggle_was_down := false


func _ready() -> void:
	add_to_group(&"quest_panel")
	_ensure_toggle_action()
	set_open(false)
	_bind()
	# 控制器可能晚一步绑定配置表，下一帧再刷一次。
	call_deferred("_refresh")


func _process(_delta: float) -> void:
	var toggle_down := Input.is_action_pressed(TOGGLE_ACTION)
	if toggle_down and not _toggle_was_down:
		toggle()
	_toggle_was_down = toggle_down


func toggle() -> void:
	set_open(not panel.visible)


func _ensure_toggle_action() -> void:
	if not InputMap.has_action(TOGGLE_ACTION):
		InputMap.add_action(TOGGLE_ACTION)
	var tab_event := InputEventKey.new()
	tab_event.physical_keycode = KEY_TAB
	for existing in InputMap.action_get_events(TOGGLE_ACTION):
		if existing.is_match(tab_event):
			return
	InputMap.action_add_event(TOGGLE_ACTION, tab_event)


func set_open(value: bool) -> void:
	if panel != null:
		panel.visible = value


func _bind() -> void:
	var controller := _find_quests()
	if controller == null or controller == _quests:
		return
	_quests = controller
	if _quests.has_signal(&"quest_changed") and not _quests.quest_changed.is_connected(_on_quest_changed):
		_quests.quest_changed.connect(_on_quest_changed)


func _on_quest_changed(_quest_id: StringName, _previous: int, _current: int) -> void:
	_refresh()


func _refresh() -> void:
	_bind()
	if quest_list == null:
		return
	var lines: Array[String] = []
	var entries := _entries()
	if entries.is_empty():
		lines.append("暂无任务")
	else:
		for entry in entries:
			lines.append(_line_text(entry))
	quest_list.text = "\n".join(lines)


func _entries() -> Array:
	if _quests == null or not _quests.has_method(&"get_quest_entries"):
		return []
	return _quests.get_quest_entries()


func _line_text(entry: Dictionary) -> String:
	var status := "未解锁" if bool(entry.get("locked", false)) else str(entry.get("status_name", "未接"))
	var text := "%s：%s" % [str(entry.get("name", "")), status]
	var area := str(entry.get("target_area", ""))
	if not area.is_empty():
		text += "（场地 %s）" % area
	return text


func _find_quests() -> Node:
	var tree := get_tree()
	return tree.get_first_node_in_group(&"quest_controller") if tree != null else null
