extends Node3D

## 只提供相机跟随位置，过滤翻越抬升；不修改玩家或第三方相机插件。
@export var player_path: NodePath = ^"../Player"
@onready var actor: Node3D = get_node_or_null(player_path)

func _ready() -> void:
	_update_anchor()

func _physics_process(_delta: float) -> void:
	_update_anchor()

func _update_anchor() -> void:
	if not is_instance_valid(actor): return
	global_position = actor.global_position
	if actor.has_method("get_camera_ground_height"):
		global_position.y = actor.get_camera_ground_height()
