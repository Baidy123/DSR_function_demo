extends Node

## 仅负责调试总开关；视图和生命组件各自响应，不介入 AI 决策。
signal changed(enabled: bool)

var _navigation_requested: bool = false

var enabled: bool = false:
	set(value):
		var allowed := value and OS.is_debug_build()
		if enabled == allowed:
			return
		enabled = allowed
		if is_inside_tree():
			get_tree().debug_navigation_hint = enabled and _navigation_requested
		changed.emit(enabled)


func _ready() -> void:
	# 保留编辑器“可见导航”的选择，但总开关关闭时也必须隐藏。
	_navigation_requested = get_tree().debug_navigation_hint
	get_tree().debug_navigation_hint = enabled and _navigation_requested


func set_enabled(value: bool) -> void:
	enabled = value
