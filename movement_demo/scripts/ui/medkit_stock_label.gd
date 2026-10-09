extends Label

## 武器栏只展示医疗库存；数量和使用逻辑仍属于 Health/Medkit。
@export var medkit_path: NodePath = ^"../../../../Health/Medkit"
@onready var medkit = get_node(medkit_path)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	medkit.state_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	text = "医疗包 [H]  × %d" % medkit.remaining_count
