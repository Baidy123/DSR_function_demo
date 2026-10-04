extends StaticBody3D

## 该 NPC 使用的 Dialogue Manager 对话资源；留空时按 E 不启动对话。
@export var dialogue_resource: DialogueResource
## 对话资源中的起始标题，例如 start；应与该资源中的标题一致。
@export var dialogue_start: String = "start"

var pending_player = null

@onready var interaction_area: Area3D = $InteractionArea


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if is_instance_valid(pending_player):
		get_viewport().set_input_as_handled()
		return

	# 未指定对话文件时，不锁住玩家。
	if dialogue_resource == null:
		return

	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("player"):
			body.set_dialogue_active(true)
			body.face_npc(global_position)
			pending_player = body
			get_viewport().set_input_as_handled()
			return


func _physics_process(_delta: float) -> void:
	if not is_instance_valid(pending_player):
		return
	# 等待 Player 完成转身，这期间已经锁住移动。
	if pending_player.is_facing_npc:
		return
	$"../DialogueUI".open_dialogue(pending_player, dialogue_resource, dialogue_start, self)
	pending_player = null
