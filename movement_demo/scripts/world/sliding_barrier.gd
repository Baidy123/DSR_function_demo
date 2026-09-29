extends Node3D

## 纯位移屏障：只提供 open/close，不处理输入，也不读取任何游戏状态。
## 门禁、机关等由外部交互物通过 CallMethodEffect 驱动，因此屏障不认识玩家与物品。

## 打开时相对于根节点的 X 坐标；关闭回到 0。正负值决定滑动方向。
@export var slide_distance: float = 2.4
@export var animation_seconds: float = 0.4
var is_open: bool = false
var barrier_tween: Tween


func open() -> void:
	set_open(true)


func close() -> void:
	set_open(false)


func set_open(value: bool) -> void:
	if is_open == value:
		return
	is_open = value
	if barrier_tween != null and barrier_tween.is_valid():
		barrier_tween.kill()
	barrier_tween = create_tween().set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	barrier_tween.tween_property($Panel, "position:x", slide_distance if is_open else 0.0, animation_seconds)
