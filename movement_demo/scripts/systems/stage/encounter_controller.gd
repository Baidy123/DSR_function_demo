class_name EncounterController
extends Node

## 关卡奖励控制器：每关返回酒馆后由奖励 NPC 打开该关独立的三选一配置。

@export var reward_table: RewardTable
@export var reward_board_path: NodePath

@onready var reward_board: CanvasLayer = get_node_or_null(reward_board_path)

var _reward_open := false
var _pause_owned := false
var _reward_level := 0
var _options: Array[RewardOption] = []


func _ready() -> void:
	if reward_board != null and reward_board.has_signal(&"reward_selected") \
			and not reward_board.reward_selected.is_connected(_on_reward_selected):
		reward_board.reward_selected.connect(_on_reward_selected)


## NPC 在玩家靠近并按下交互键时调用；当前已完成关卡尚未领取时接管输入。
func open_reward_for_player(player: Node3D) -> bool:
	if player == null or not is_instance_valid(player) or not player.is_in_group(&"player"):
		return false
	if not can_offer_reward():
		return false
	if reward_board == null or not reward_board.has_method(&"show_board") \
			or not reward_board.has_method(&"configure"):
		push_error("EncounterController: reward board is missing or incomplete")
		return false
	var options := _options_for_level(_completed_level())
	if options.size() != 3 or not reward_board.configure(options):
		push_error("EncounterController: level reward config must provide exactly three options")
		return false
	_reward_level = _completed_level()
	_options = options
	var tree := get_tree()
	_reward_open = true
	_pause_owned = not tree.paused
	if _pause_owned:
		tree.paused = true
	reward_board.show_board()
	return true


func can_offer_reward() -> bool:
	if _reward_open:
		return true
	var level := _completed_level()
	return level >= 1 and level <= 5 \
		and not _reward_claimed(level) \
		and _options_for_level(level).size() == 3 \
		and _player_alive()


func _on_reward_selected(reward_id: StringName) -> void:
	select_reward(reward_id)


## 每个已完成关卡只能提交一次。
func select_reward(reward_id: StringName) -> bool:
	if not _reward_open or _reward_claimed(_reward_level):
		return false
	if not _player_alive():
		return false
	var option: RewardOption = null
	for candidate in _options:
		if candidate != null and candidate.id == reward_id:
			option = candidate
			break
	if option == null:
		return false
	match option.effect:
		RewardOption.Effect.HEAL:
			_heal_player(float(option.amount))
		RewardOption.Effect.REFILL_AMMO:
			_refill_ammo()
		RewardOption.Effect.SYSTEM_PROGRESS:
			_add_progress(option.amount)
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
		state.mark_reward_claimed(_reward_level)
	if owned_pause:
		tree.paused = false
	return true


func _options_for_level(level_number: int) -> Array[RewardOption]:
	if reward_table == null:
		return []
	var level := reward_table.for_level(level_number)
	return [] if level == null else level.options


func _heal_player(amount: float) -> void:
	var player := _player()
	if player == null:
		return
	var health := player.get_node_or_null("Health")
	if health != null and health.has_method(&"heal"):
		health.heal(amount)


func _refill_ammo() -> void:
	var player := _player()
	if player == null:
		return
	var slots := player.get_node_or_null("Equipment")
	if slots != null and slots.has_method(&"refill_all_ammo"):
		slots.refill_all_ammo()


func _add_progress(amount: int) -> void:
	var state := _state()
	if state != null and state.has_method(&"add_system_progress"):
		state.add_system_progress(amount)


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


func _reward_claimed(level_number: int) -> bool:
	var state := _state()
	return state != null and state.has_claimed_reward(level_number)


func _completed_level() -> int:
	var state := _state()
	return int(state.get(&"completed_level")) if state != null else 0
