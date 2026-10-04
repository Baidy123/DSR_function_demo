extends InteractionEffect
class_name GiveItemEffect

## 写入 GameState 物品栏；拾取型交互使用。
@export var item_id: StringName = &""
## 提示文本使用的名字，例如 门禁卡。
@export var display_name: String = ""
@export_range(1, 99, 1) var count: int = 1


func apply(context: InteractionContext) -> void:
	if item_id == &"" or not context.state_supports(&"add_item"):
		push_warning("GiveItemEffect 缺少物品 ID 或可写状态，已跳过")
		return
	context.state.add_item(item_id, display_name, count)
