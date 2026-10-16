extends InteractionEffect
class_name ToggleFlagEffect

## 翻转一个布尔旗标：第一次使用打开，第二次回到关闭。
## 只读状态节点当前值，再写回相反值；状态节点缺少接口时跳过。

@export var flag: StringName = &""


func apply(context: InteractionContext) -> void:
	if flag == &"" or not context.state_supports(&"set_flag") or not context.state_supports(&"is_flag_set"):
		push_warning("ToggleFlagEffect 缺少旗标名或可读写状态，已跳过")
		return
	context.state.set_flag(flag, not bool(context.state.is_flag_set(flag)))
