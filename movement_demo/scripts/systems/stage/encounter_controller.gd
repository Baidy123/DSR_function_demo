class_name EncounterController
extends Node

## 任务奖励控制器：第一关返回酒馆后由奖励 NPC 请求打开三选一面板。
## 只管理奖励展示、暂停和结算；任务完成状态仍由 QuestController 权威判定。

@export var quest_id: StringName = &"task_a"
@export var heal_amount: float = 35.0
@export var system_progress_amount: int = 20
@export var reward_board_path: NodePath

@onready var reward_board: CanvasLayer = get_node_or_null(reward_board_path)

var _reward_open := false
var _pause_owned := false


func _ready() -> void:
	if reward_board != null and reward_board.has_signal(&"reward_selected") \
			and not reward_board.reward_selected.is_connected(_on_reward_selected):
		reward_board.reward_selected.connect(_on_reward_selected)


## NPC 在玩家靠近并按下交互键时调用；只有已完成且未领取时接管输入。
func open_reward_for_player(player: Node3D) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_in_group(&"player"):
		return false
	if not can_offer_reward():
		return false
	if reward_board == null or not reward_board.has_method(&"show_board"):
		push_error("EncounterController: reward board is missing or does not implement show_board()")
		return false
	var tree := get_tree()
	_reward_open = true
	_pause_owned = not tree.paused
	if _pause_owned:
		tree.paused = true
	reward_board.show_board()
	return true


func can_offer_reward() -> bool:
	return _reward_open or (
		_completed_level() == 1
		and _quest_status() == QuestController.Status.COMPLETED
		and not _reward_claimed()
		and _player_alive()
	)


func _on_reward_selected(reward_id: StringName) -> void:
	select_reward(reward_id)


## 奖励只能提交一次；成功后在共享运行态记录领取结果。
func select_reward(reward_id: StringName) -> bool:
	if not _reward_open or _reward_claimed():
		return false
	if not _player_alive():
		return false
	match reward_id:
		&"first_aid":
			_heal_player()
		&"ammo":
			_refill_ammo()
		&"system_progress":
			_add_progress()
		_:
			return false
	var tree := get_tree()
	var owned_pause := _pause_owned
	_reward_open = false
	_pause_owned = false
	if reward_board != null:
		reward_board.visible = false
	var state := _state()
	if state != null:
		state.set(&"task_a_reward_claimed", true)
	if owned_pause:
		tree.paused = false
	return true


func _heal_player() -> void:
	var player := _player()
	if player == null:
		return
	var health := player.get_node_or_null("Health")
	if health != null and health.has_method(&"heal"):
		health.heal(heal_amount)


func _refill_ammo() -> void:
	var player := _player()
	if player == null:
		return
	var slots := player.get_node_or_null("Equipment")
	if slots != null and slots.has_method(&"refill_all_ammo"):
		slots.refill_all_ammo()


func _add_progress() -> void:
	var state := _state()
	if state != null and state.has_method(&"add_system_progress"):
		state.add_system_progress(system_progress_amount)


func _player() -> Node3D:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"player") if tree != null else null


func _player_alive() -> bool:
	var player := _player()
	if player == null:
		return false
	if player.has_method(&"is_dead"):
		return not player.is_dead()
	var health := player.get_node_or_null("Health")
	return health == null or not bool(health.get("is_dead"))


func _state() -> Node:
	return get_node_or_null("/root/GameState")


func _quests() -> Node:
	var tree := get_tree() if is_inside_tree() else null
	return tree.get_first_node_in_group(&"quest_controller") if tree != null else null


func _quest_status() -> int:
	var quests := _quests()
	if quests == null or not quests.has_method(&"status_of"):
		return QuestController.Status.NOT_STARTED
	return int(quests.status_of(quest_id))


func _reward_claimed() -> bool:
	var state := _state()
	return state != null and bool(state.get(&"task_a_reward_claimed"))


func _completed_level() -> int:
	var state := _state()
	return int(state.get(&"completed_level")) if state != null else 0
