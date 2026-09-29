extends InteractionEffect
class_name SetFlagEffect

## 写入 GameState 旗标；对话与调试面板可读取。
@export var flag: StringName = &""
@export var value: bool = true


func apply(context: InteractionContext) -> void:
	if flag == &"" or not context.state_supports(&"set_flag"):
		push_warning("SetFlagEffect 缺少旗标名或可写状态，已跳过")
		return
	context.state.set_flag(flag, value)
