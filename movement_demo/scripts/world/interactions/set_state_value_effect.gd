extends InteractionEffect
class_name SetStateValueEffect

## 写入状态节点已有的字段；缺少字段时不创建动态属性。
@export var key: StringName = &""
@export var value: Variant = ""


func apply(context: InteractionContext) -> void:
	if key == &"" or context.state == null:
		push_warning("SetStateValueEffect 缺少字段名或状态节点，已跳过")
		return
	var exists := false
	for property in context.state.get_property_list():
		if StringName(property.name) == key:
			exists = true
			break
	if not exists:
		push_warning("SetStateValueEffect 状态节点缺少字段：%s" % key)
		return
	context.state.set(key, value)
