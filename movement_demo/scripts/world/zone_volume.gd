class_name ZoneVolume
extends Area3D

## 区域标识节点：只提供稳定 zone_id 并加入 zone_volume 组，供任务条件等订阅方使用。
## 它不判定任何玩法，也不认识任何控制器；阶段控制器仍可按自己的 node_paths 绑定同一批区域。

## 稳定标识，例如 tavern / arena；留空时回退到节点名。
@export var zone_id: StringName = &""


func _ready() -> void:
	add_to_group(&"zone_volume")
	if zone_id == &"":
		zone_id = StringName(name)
