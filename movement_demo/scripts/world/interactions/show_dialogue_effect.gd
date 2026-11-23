extends InteractionEffect
class_name ShowDialogueEffect

## 复用现有 DialogueUI 打开对话；查看/使用类交互用它显示信息。
@export var dialogue_resource: DialogueResource
@export var dialogue_start: String = "start"
## 界面节点加入的组名；效果只按组查找，不引用具体界面类型或路径。
@export var ui_group: StringName = &"dialogue_ui"


func apply(context: InteractionContext) -> void:
	execute(context)

func execute(context: InteractionContext) -> Dictionary:
	if dialogue_resource == null or context.player == null:
		return {"status": &"failed", "reason": &"missing_dialogue_resource_or_player"}
	var tree := context.tree()
	var ui: Node
	var director = load("res://scripts/systems/scene_director.gd").for_node(context.host)
	if tree != null and director != null:
		for candidate in tree.get_nodes_in_group(ui_group):
			if load("res://scripts/systems/scene_director.gd").for_node(candidate) == director:
				ui = candidate
				break
	if ui == null: return {"status": &"failed", "reason": &"missing_dialogue_ui"}
	var request = context.request_action(&"dialogue", {"target": ui,
		"parameters": {"resource": dialogue_resource, "start": dialogue_start}})
	if request == null: return {"status": &"failed", "reason": &"missing_director"}
	return await request.wait_result()
