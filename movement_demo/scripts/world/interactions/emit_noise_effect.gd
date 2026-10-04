extends InteractionEffect
class_name EmitNoiseEffect

## 触发一次逻辑声音事件，走既有听觉系统，不需要改动敌人节点。
@export var noise: NoiseData
## 声源半径（米）；遮挡衰减由 NoiseData 自己决定。
@export_range(0.0, 100.0, 0.5) var radius: float = 8.0
## 声音位置用玩家还是物体本身；敌人听觉当前只调查玩家来源，需要吸引敌人时打开。
@export var from_player: bool = false


func apply(context: InteractionContext) -> void:
	var source: Node3D = null
	if from_player and context.player != null:
		source = context.player
	elif context.host is Node3D:
		source = context.host as Node3D
	if noise == null or source == null:
		push_warning("EmitNoiseEffect 缺少声音资源或 3D 宿主，已跳过")
		return
	noise.emit_from(source, radius)
