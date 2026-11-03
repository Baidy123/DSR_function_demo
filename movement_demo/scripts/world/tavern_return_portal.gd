extends Interactable

## 通用关卡返程门：记录本关完成与玩家状态，再执行场景切换效果。

@export_range(1, 5) var level_number: int = 1


func _ready() -> void:
	super()
	interact_id = StringName("tavern_return_level_%d" % level_number)
	display_name = "酒馆"
	verb = "返回"


func interact(player: Node3D) -> bool:
	if not can_interact(player):
		return super.interact(player)
	var state_node := state()
	if state_node == null:
		push_error("TavernReturnPortal: GameState is missing")
		return false
	state_node.completed_level = level_number
	state_node.set_pending_player_state(PlayerCampaignState.capture(player))
	if level_number == 1:
		state_node.task_a_returned = "returned"
	return super.interact(player)
