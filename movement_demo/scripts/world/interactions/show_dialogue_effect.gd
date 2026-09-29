extends InteractionEffect
class_name ShowDialogueEffect

## 复用现有 DialogueUI 打开对话；查看/使用类交互用它显示信息。
@export var dialogue_resource: DialogueResource
@export var dialogue_start: String = "start"
## 界面节点加入的组名；效果只按组查找，不引用具体界面类型或路径。
@export var ui_group: StringName = &"dialogue_ui"


func apply(context: InteractionContext) -> void:
	if dialogue_resource == null or context.player == null:
		push_warning("ShowDialogueEffect 缺少对话资源或玩家，已跳过")
		return
	var tree := context.tree()
	var ui: Node = tree.get_first_node_in_group(ui_group) if tree != null else null
	if ui == null or not ui.has_method(&"open_dialogue"):
		push_warning("场景中没有可用的对话界面（组：%s）" % ui_group)
		return
	ui.open_dialogue(context.player, dialogue_resource, dialogue_start)
