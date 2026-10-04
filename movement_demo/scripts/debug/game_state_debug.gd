extends CanvasLayer

## 调试面板：显示交互产生的物品与旗标；只在 DebugSettings 总开关打开时可见。

@onready var debug_settings = get_node("/root/DebugSettings")
@onready var lines: Label = $Panel/Margin/Content


func _ready() -> void:
	debug_settings.changed.connect(_on_debug_changed)
	var state := get_node("/root/GameState")
	state.item_gained.connect(_on_item_gained)
	state.flag_changed.connect(_on_flag_changed)
	_refresh()


func _on_debug_changed(_enabled: bool) -> void:
	_refresh()


func _on_item_gained(_item_id: StringName, _display_name: String, _total: int) -> void:
	_refresh()


func _on_flag_changed(_flag: StringName, _value: bool) -> void:
	_refresh()


func _refresh() -> void:
	visible = debug_settings.enabled
	if not visible:
		return
	lines.text = "[交互状态]\n物品：%s\n旗标：%s" % [_item_text(), _flag_text()]


func _item_text() -> String:
	var state := get_node("/root/GameState")
	if state.items.is_empty():
		return "—"
	var parts: Array[String] = []
	for item_id in _sorted_keys(state.items):
		parts.append("%s×%d" % [state.item_display_name(item_id), state.get_item_count(item_id)])
	return "，".join(parts)


func _flag_text() -> String:
	var state := get_node("/root/GameState")
	if state.flags.is_empty():
		return "—"
	var parts: Array[String] = []
	for flag in _sorted_keys(state.flags):
		parts.append("%s=%s" % [flag, "开" if state.is_flag_set(flag) else "关"])
	return "  ".join(parts)


func _sorted_keys(source: Dictionary) -> Array:
	var keys: Array = source.keys()
	keys.sort_custom(func(a, b): return str(a) < str(b))
	return keys
