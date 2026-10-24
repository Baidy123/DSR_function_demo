extends Label

## 装备栏只展示医疗库存；数量属于 Equipment，使用由其 Medkit 组件执行。
@export var medkit_path: NodePath = ^"../../../Medkit"
@onready var medkit = get_node(medkit_path)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	medkit.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	text = "医疗包 [H]  × %d" % medkit.remaining_count
