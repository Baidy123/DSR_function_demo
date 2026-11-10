class_name QuestPortal
extends Interactable

## 酒馆关卡门：读取任务与 A 解锁的关卡，切换前携带当前玩家状态。
const QuestControllerScript := preload("res://scripts/systems/stage/quest_controller.gd")

const LEVELS: Array[String] = [
	"res://scenes/world/levels/lvl_1.tscn",
	"res://scenes/world/levels/lvl_2.tscn",
	"res://scenes/world/levels/lvl_3.tscn",
	"res://scenes/world/levels/lvl_4.tscn",
	"res://scenes/world/levels/lvl_5.tscn",
]

@export var quest_id: StringName = &"task_a"

var _quests: Node
var _game_state: Node
var _synced_level := -1


func _ready() -> void:
	super()
	call_deferred(&"_bind_sources")


func interact(player: Node3D) -> bool:
	if not can_interact(player):
		return super.interact(player)
	if _game_state != null:
		var snapshot: Dictionary = PlayerCampaignState.capture(player)
		_game_state.set_pending_player_state(snapshot)
		if _game_state.has_method(&"set_level_entry_player_state"):
			_game_state.set_level_entry_player_state(snapshot)
	return super.interact(player)


func conditions_met() -> bool:
	return super() and _level_available()


func _refresh_prompt() -> void:
	_sync_target()
	var completed := _completed_level()
	var available := _available_level()
	if completed >= LEVELS.size():
		blocked_hint = "五关挑战已完成"
	elif available <= completed:
		blocked_hint = "需要再次与 A 交互以解锁下一关"
	elif available == 1 and not _quest_in_progress():
		blocked_hint = "需要先接取 A 的任务"
	else:
		blocked_hint = "下一关尚未解锁"
	super()


func _bind_sources() -> void:
	if not is_inside_tree():
		return
	_quests = _find_quests()
	_game_state = get_node_or_null("/root/GameState")
	if _quests != null and _quests.has_signal(&"quest_changed") \
			and not _quests.quest_changed.is_connected(_on_quest_changed):
		_quests.quest_changed.connect(_on_quest_changed)
	if _game_state != null and _game_state.has_signal(&"value_changed") \
			and not _game_state.value_changed.is_connected(_on_state_changed):
		_game_state.value_changed.connect(_on_state_changed)
	_refresh_prompt()


func _on_quest_changed(_quest_id: StringName, _previous: int, _current: int) -> void:
	_refresh_prompt()


func _on_state_changed(key: StringName, _value: Variant) -> void:
	if key == &"completed_level" or key == &"available_level":
		_refresh_prompt()


func _sync_target() -> void:
	var level := _available_level()
	if level == _synced_level:
		return
	_synced_level = level
	display_name = "关卡%d" % level
	if name_label != null:
		name_label.text = display_name
	var target := LEVELS[level - 1]
	for effect in effects:
		if effect is ChangeSceneEffect:
			effect.scene_path = target


func _level_available() -> bool:
	var completed := _completed_level()
	var available := _available_level()
	if available <= completed:
		return false
	if available == 1:
		return _quest_in_progress()
	return true


func _available_level() -> int:
	if _game_state == null:
		_game_state = get_node_or_null("/root/GameState")
	if _game_state == null:
		return 1
	return clampi(int(_game_state.get(&"available_level")), 1, LEVELS.size())


func _completed_level() -> int:
	if _game_state == null:
		_game_state = get_node_or_null("/root/GameState")
	if _game_state == null:
		return 0
	return clampi(int(_game_state.get(&"completed_level")), 0, LEVELS.size())


func _quest_in_progress() -> bool:
	if _quests == null or not is_instance_valid(_quests):
		_quests = _find_quests()
	if _quests == null or not _quests.has_method(&"status_of"):
		return false
	return int(_quests.status_of(quest_id)) == QuestControllerScript.Status.IN_PROGRESS


func _find_quests() -> Node:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"quest_controller") if tree != null else null
