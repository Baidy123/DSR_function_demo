extends Interactable

## 通用关卡返程门：记录本关完成与玩家状态，再执行场景切换效果。

@export_range(1, 5) var level_number: int = 1


func _ready() -> void:
	super()
	interact_id = StringName("tavern_return_level_%d" % level_number)
	display_name = "酒馆"
	verb = "返回"


func transition_parameters(player: Node3D) -> Dictionary:
	return {"mode": &"return_tavern", "level_number": level_number,
		"player_snapshot": PlayerCampaignState.capture(player)}
