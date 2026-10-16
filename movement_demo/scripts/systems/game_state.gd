extends Node

## 对话字段被写入时通知监听者（例如任务控制器按表同步任务状态）；
## 值没有变化时不发信号，避免同一结果反复刷新。旗标与物品另有专用信号。
signal value_changed(key: StringName, value: Variant)

# 本次运行共享的对话状态；重新运行游戏会重置。
var talked_to_a: bool = false:
	set(value):
		if talked_to_a == value:
			return
		talked_to_a = value
		value_changed.emit(&"talked_to_a", value)
# 空字符串：尚未选择；accepted：答应；refused：拒绝。
var help_choice: String = "":
	set(value):
		if help_choice == value:
			return
		help_choice = value
		value_changed.emit(&"help_choice", value)
# 唱片机支线：空字符串＝尚未选择；accepted＝已接取；refused＝已拒绝。
var music_quest_choice: String = "":
	set(value):
		if music_quest_choice == value:
			return
		music_quest_choice = value
		value_changed.emit(&"music_quest_choice", value)
# 唱片机支线交差提交：done＝已提交（是否完成由任务条件按音乐旗标判定）。
var music_quest_turnin: String = "":
	set(value):
		if music_quest_turnin == value:
			return
		music_quest_turnin = value
		value_changed.emit(&"music_quest_turnin", value)
## 只读镜像：对话剧本按属性名读取唱片机旗标；旗标本身仍是唯一来源，由交互物写入。
var music_playing: bool:
	get:
		return get_flag(&"music_playing")
## 唱片机门禁：接取任务时由对话置位，交互物用 required_flags 读同一个旗标。
var music_quest_open: bool:
	get:
		return get_flag(&"music_quest_open")
	set(value):
		set_flag(&"music_quest_open", value)

## 交互产生的物品与旗标；与对话状态一样，重新运行游戏才重置，死亡重开场景保留。
signal item_gained(item_id: StringName, display_name: String, total: int)
signal flag_changed(flag: StringName, value: bool)

## item_id -> {"display_name": String, "count": int}
var items: Dictionary = {}
## flag -> bool
var flags: Dictionary = {}


## 拾取或获得物品；display_name 留空时保留已有名字。
func add_item(item_id: StringName, display_name: String = "", count: int = 1) -> void:
	if item_id == &"" or count <= 0:
		return
	var entry: Dictionary = items.get(item_id, {"display_name": "", "count": 0})
	if not display_name.is_empty():
		entry["display_name"] = display_name
	entry["count"] = int(entry["count"]) + count
	items[item_id] = entry
	item_gained.emit(item_id, entry["display_name"], entry["count"])


func has_item(item_id: StringName) -> bool:
	return get_item_count(item_id) > 0


func get_item_count(item_id: StringName) -> int:
	var entry: Dictionary = items.get(item_id, {})
	return int(entry.get("count", 0))


## 提示文本使用；未登记过该物品时回退到内部 ID。
func item_display_name(item_id: StringName) -> String:
	var entry: Dictionary = items.get(item_id, {})
	var name_text: String = entry.get("display_name", "")
	return name_text if not name_text.is_empty() else str(item_id)


## 置位旗标；值没有变化时不重复发信号，避免调试面板反复刷新。
func set_flag(flag: StringName, value: bool = true) -> void:
	if flag == &"":
		return
	if flags.get(flag, null) == value:
		return
	flags[flag] = value
	flag_changed.emit(flag, value)


func get_flag(flag: StringName, fallback: bool = false) -> bool:
	return bool(flags.get(flag, fallback))


func is_flag_set(flag: StringName) -> bool:
	return get_flag(flag)


## 供测试与重开流程使用；正常死亡重开不清空。
func clear_interaction_state() -> void:
	items.clear()
	flags.clear()
